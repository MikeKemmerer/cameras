# PTZOptics VISCA-over-IP API Reference

PTZOptics cameras are controlled with **VISCA**, a protocol originally created by Sony and adopted (with vendor-specific extensions) by most PTZ camera manufacturers. Unlike the Panasonic AW-HE40's plain-text CGI commands (`#PTS5050` sent as an HTTP query string), VISCA commands are raw **binary byte sequences** sent over a socket connection — there is no HTTP request/response involved at all.

This document was compiled from the [Bitfocus Companion PTZOptics module](https://github.com/bitfocus/companion-module-ptzoptics-visca) source (TypeScript, actively maintained), which is the most complete open-source implementation of the PTZOptics VISCA command set.

---

## Transport

| Property | Value |
|----------|-------|
| Protocol | Raw VISCA over **TCP** (no extra IP packet header) |
| Default port | **5678** |
| Camera address byte | `1` (PTZOptics forces this; multi-camera daisy-chain addressing via RS-422 is not used over IP) |
| Auth | None |

This is simpler than Sony/AVer/Marshall's "VISCA-over-IP" framing (see those docs) — you open a TCP socket to port 5678 and write the raw VISCA bytes directly. The camera replies with `ACK` (`90 4y FF`) then `Completion` (`90 5y FF`) messages, or a `90 60 02 FF` syntax error.

> Some older PTZOptics models (pre-G3) also expose a Panasonic-style CGI interface. This document covers the current VISCA-over-IP interface used by all modern PTZOptics models.

---

## Command Envelope

Every command/inquiry:
- Starts with `81` (`8x`, x=camera address, always `1` over IP)
- Ends with `FF`
- Contains no embedded `FF` bytes

Example: `81 01 06 04 FF` (Pan/Tilt Home)

---

## Pan/Tilt

**Continuous drive** — `81 01 06 01 <panSpeed> <tiltSpeed> <panDir> <tiltDir> FF`
- `panSpeed`/`tiltSpeed`: `01`-`18` (1-24 decimal); tilt is capped at `14` (20) even though pan can go to `18` (24)
- Direction bytes (pan, tilt):

| Direction | panDir | tiltDir |
|-----------|--------|---------|
| Up | `03` | `01` |
| Down | `03` | `02` |
| Left | `01` | `03` |
| Right | `02` | `03` |
| Up-Left | `01` | `01` |
| Up-Right | `02` | `01` |
| Down-Left | `01` | `02` |
| Down-Right | `02` | `02` |
| Stop | `03` | `03` |

Example — pan right + tilt up at speed 12: `81 01 06 01 0C 0C 02 01 FF`

**Home**: `81 01 06 04 FF`
**Reset**: `81 01 06 05 FF`

**Absolute position**: `81 01 06 02 <panSpeed> <tiltSpeed> 0p 0p 0p 0p 0t 0t 0t 0t FF` (16-bit signed pan/tilt position, model-dependent range)

---

## Zoom

| Command | Bytes |
|---------|-------|
| Stop | `81 01 04 07 00 FF` |
| Tele (standard speed) | `81 01 04 07 02 FF` |
| Wide (standard speed) | `81 01 04 07 03 FF` |
| Tele (variable speed `p`=0-7) | `81 01 04 07 2p FF` |
| Wide (variable speed `p`=0-7) | `81 01 04 07 3p FF` |
| Direct position (16-bit `0-65535`) | `81 01 04 47 0p 0p 0p 0p FF` |

---

## Focus

| Command | Bytes |
|---------|-------|
| Stop | `81 01 04 08 00 FF` |
| Far (standard speed) | `81 01 04 08 02 FF` |
| Near (standard speed) | `81 01 04 08 03 FF` |
| Auto Focus | `81 01 04 38 02 FF` |
| Manual Focus | `81 01 04 38 03 FF` |
| One-Push AF trigger | `81 01 04 18 01 FF` |
| Direct position (16-bit) | `81 01 04 48 0p 0p 0p 0p FF` |

---

## Exposure / Iris

| Command | Bytes |
|---------|-------|
| Exposure mode | `81 01 04 39 0m FF` — `00`=Full Auto, `03`=Manual, `0A`=Shutter Priority, `0B`=Iris Priority, `0D`=Bright |
| Iris direct (hex `00`-`11`, see F-stop table in [AW-HE40 doc](AW-HE40-API-REFERENCE.md) for a similar iris concept — values differ per brand) | `81 01 04 4B 00 00 0h 0h FF` |
| Backlight compensation on/off | `81 01 04 33 02/03 FF` |

---

## Presets

Presets are **0-indexed**, range `0`-`255`, but PTZOptics reserves preset numbers **90-99** and **255** for internal use — avoid saving to those slots.

| Command | Bytes |
|---------|-------|
| Set (save) | `81 01 04 3F 01 pp FF` |
| Recall | `81 01 04 3F 02 pp FF` |
| Reset | `81 01 04 3F 00 pp FF` |

Example — recall preset 5 (0-indexed, so this is the UI's "preset 6" if you 1-index like the AW-HE40 doc does): `81 01 04 3F 02 05 FF`

---

## Power / Tally

PTZOptics VISCA models generally do **not** expose a VISCA power command over IP (some models are inquiry-only for power state). There is also no standardized tally command across all PTZOptics models — check your specific model's manual. This is a notable feature gap versus the AW-HE40, which has explicit `#O1`/`#O0` power and `#DA1`/`#DA0` tally commands.

---

## Implementation Notes

### This is a socket protocol, not HTTP

The single biggest integration difference from the current AW-HE40 setup: **there is no `fetch()`-friendly HTTP endpoint**. To control a PTZOptics camera from PHP (e.g., in `multicamera/`), you must open a raw TCP socket (`fsockopen()` or `stream_socket_client()`), write the VISCA byte string, and read back the ACK/Completion response. Apache's `ProxyPass`/`mod_proxy_http` (used for the AW-HE40's `/cam/ptz` routes) **cannot** proxy this — it's not HTTP.

### Byte construction example (conceptual, PHP)

```php
$bytes = pack('C*', 0x81, 0x01, 0x06, 0x01, $panSpeed, $tiltSpeed, $panDir, $tiltDir, 0xFF);
$socket = fsockopen($cameraIp, 5678, $errno, $errstr, 2);
fwrite($socket, $bytes);
$reply = fread($socket, 32); // ACK (90 4y FF) then Completion (90 5y FF)
fclose($socket);
```

### Custom command escape hatch

If a specific PTZOptics firmware supports a command not listed here, any raw VISCA byte sequence can be sent as long as it starts with `81`, ends with `FF`, and contains no embedded `FF`.

---

## Sources

- [Bitfocus Companion Module — companion-module-ptzoptics-visca](https://github.com/bitfocus/companion-module-ptzoptics-visca) — `src/camera/*.ts` (command byte tables), `src/config.ts` (default port 5678, TCP transport), `src/visca/*.ts` (envelope/framing rules)
