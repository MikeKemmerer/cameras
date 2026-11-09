# Sony VISCA-over-IP API Reference

Sony invented the **VISCA** protocol and still ships it on their BRC/SRG/FR7/AM7-series PTZ cameras. Like the [PTZOptics reference](PTZOPTICS-VISCA-API-REFERENCE.md), this is a **binary socket protocol**, not HTTP — there is no `#PTS5050`-style CGI query string like the AW-HE40 uses.

This document was compiled from the [Bitfocus Companion Sony VISCA module](https://github.com/bitfocus/companion-module-sony-visca) source and its bundled per-model Sony protocol reference sheets (`protocol/Sony_*.html`).

---

## Transport

| Property | Value |
|----------|-------|
| Protocol | **VISCA over IP** (Sony's own framing, UDP) — also available over RS-422 serial, out of scope here |
| Default port | **52381** |
| Camera address byte | First VISCA byte is `0x80 + address` (address 0-8, default address **1** → `0x81`) |
| Auth | None |

### VISCA-over-IP packet header

Unlike PTZOptics's raw-TCP approach, Sony's official "VISCA over IP" framing wraps every VISCA message in an 8-byte header before the UDP payload:

| Bytes | Meaning |
|-------|---------|
| 0-1 | Payload type — `01 00`=Command, `01 10`=Inquiry, `01 11`=Reply, `02 00`=Control Command, `02 01`=Control Reply |
| 2-3 | Payload length (big-endian, byte count of the VISCA payload that follows) |
| 4-7 | Sequence number (big-endian, increments per packet) |
| 8+ | The actual VISCA payload (e.g. `81 01 06 04 FF`) |

This same header format is reused by AVer and Marshall (see their reference docs) — it's a shared industry convention Sony originated, not something unique to Sony hardware.

> Several Sony models ship with VISCA-over-IP **disabled by default**. Check the on-screen menu or rear dip switches (documented per-model) before troubleshooting "no response" issues.

---

## Command Envelope

Every command: starts with `8x` (x = camera address byte), ends with `FF`, no embedded `FF`.

---

## Pan/Tilt

**Continuous drive** — `8x 01 06 01 <panSpeed> <tiltSpeed> <panDir> <tiltDir> FF`
- Speed range is model-dependent, typically `01`-`18` (24 max), some models support extended ranges up to `20` (32) when "Pan/Tilt Speed Type" is set to Extended.
- Direction bytes match the same table as PTZOptics (Up=`03 01`, Down=`03 02`, Left=`01 03`, Right=`02 03`, diagonals combine, Stop=`03 03`).

**Home**: `8x 01 06 04 FF`

**Absolute position**: `8x 01 06 02 <panSpeed> <tiltSpeed> 0p 0p 0p 0p 0t 0t 0t 0t FF` — pan/tilt position range and byte width (16 vs 20-bit) varies by model.

---

## Zoom / Focus

| Command | Bytes |
|---------|-------|
| Zoom stop | `8x 01 04 07 00 FF` |
| Zoom tele (standard) | `8x 01 04 07 02 FF` |
| Zoom wide (standard) | `8x 01 04 07 03 FF` |
| Zoom tele/wide (variable, `s`=0-7) | `8x 01 04 07 2s FF` / `8x 01 04 07 3s FF` |
| Focus stop | `8x 01 04 08 00 FF` |
| Focus far/near (standard) | `8x 01 04 08 02 FF` / `8x 01 04 08 03 FF` |
| Focus mode Auto/Manual | `8x 01 04 38 02 FF` / `8x 01 04 38 03 FF` |
| One-push AF | `8x 01 04 18 01 FF` |

---

## Exposure / Iris / Gain

| Command | Bytes | Notes |
|---------|-------|-------|
| Exposure mode | `8x 01 04 39 0m FF` | `0`=Full Auto, `3`=Manual, `A`=Shutter Pri, `B`=Iris Pri, `D`=Bright |
| Iris reset/up/down | `8x 01 04 0B 0p FF` | `0`=Reset, `2`=Up (open), `3`=Down (close) |
| Iris direct | `8x 01 04 4B 00 00 0p 0p FF` | Position range/max value varies by model (e.g. `00`-`19` on SRG-A40) |
| Shutter reset/up/down | `8x 01 04 0A 0p FF` | same `0`/`2`/`3` pattern |
| Gain up/down | `8x 01 04 0C 0p FF` | `2`=Up, `3`=Down |
| Backlight compensation | `8x 01 04 33 0p FF` | `2`=On, `3`=Off |
| White balance mode | `8x 01 04 35 0p FF` | Values vary by model — e.g. `0`=Auto1, `4`=ATW/Auto2, `5`=Manual, `A`=Preset |

---

## Presets

Presets are **0-indexed** in the byte stream (UI-facing "Preset 1" = wire value `00`), range depends on model (typically 64, some up to 256).

| Command | Bytes |
|---------|-------|
| Set (save) | `8x 01 04 3F 01 pp FF` |
| Recall | `8x 01 04 3F 02 pp FF` |
| Reset | `8x 01 04 3F 00 pp FF` |

---

## Power / Tally

| Command | Bytes |
|---------|-------|
| Power On | `8x 01 04 00 02 FF` |
| Power Off (standby) | `8x 01 04 00 03 FF` |
| Tally Red On/Off *(model-dependent — not all models expose this over VISCA)* | `8x 01 7E 01 0A 0p FF` (`2`=On, `3`=Off) |

> Tally support, exact byte layout for advanced features (detail, matrix, knee, gamma, etc.), and pan/tilt position ranges vary significantly by Sony model (BRC-X400/X1000/SRG-series/FR7/AM7). Always cross-reference the specific model's technical manual — the Companion module gates dozens of actions behind per-model capability flags for this reason.

---

## Implementation Notes

Same socket-protocol caveat as [PTZOptics](PTZOPTICS-VISCA-API-REFERENCE.md#implementation-notes): Apache's `mod_proxy_http` **cannot** proxy this — it's UDP, not HTTP. A PHP bridge would need `stream_socket_client("udp://...")`, prepend the 8-byte VISCA-over-IP header described above, send, and parse the ACK/Completion reply.

### Byte construction example (conceptual, PHP)

```php
$seq = 0; // must increment per packet, and be reset via a Control Command (see header table) on connect
$payload = pack('C*', 0x81, 0x01, 0x04, 0x00, 0x02, 0xFF); // Power On
$header = pack('n', 0x0100) . pack('n', strlen($payload)) . pack('N', $seq);
$socket = stream_socket_client("udp://{$cameraIp}:52381", $errno, $errstr, 2);
fwrite($socket, $header . $payload);
$reply = fread($socket, 32);
fclose($socket);
```

---

## Sources

- [Bitfocus Companion Module — companion-module-sony-visca](https://github.com/bitfocus/companion-module-sony-visca) — `src/actions.js` (command byte tables), `src/config.js` (default port 52381), `src/visca.js` (VISCA-over-IP header/payload-type constants), `protocol/Sony_*.html` (per-model official Sony VISCA command references bundled in the repo)
