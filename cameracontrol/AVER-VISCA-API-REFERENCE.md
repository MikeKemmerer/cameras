# AVer VISCA-over-IP API Reference

AVer PTZ cameras (PTZ310/330, TR-series, etc.) use the same VISCA-family binary protocol as PTZOptics/Sony/Marshall. Like those, this is a **socket protocol** — no HTTP CGI query strings like the AW-HE40.

This document was compiled from the [Bitfocus Companion AVer PTZ module](https://github.com/bitfocus/companion-module-aver-ptz) source, which is the most complete open-source implementation of AVer's command set.

---

## Transport

| Property | Value |
|----------|-------|
| Protocol | VISCA over IP, **UDP** |
| Default port | **52381** |
| Packet header | Optional — "VISCA over IP" checkbox in the module, **checked by default** |
| Auth | None |

### VISCA-over-IP packet header (when enabled — default)

Same convention as [Sony](SONY-VISCA-API-REFERENCE.md#visca-over-ip-packet-header) and [Marshall](MARSHALL-VISCA-API-REFERENCE.md): 2-byte payload type (`01 00` for command) + 2-byte payload length + 4-byte sequence number (increments per packet), then the raw VISCA bytes.

Example — recall preset 1, full UDP payload including header:
```
01 00 00 09 00 00 00 00 81 01 04 3F 02 01 FF
└type─┘└len┘└──seq───┘ └────── VISCA command ──────┘
```
(This example is straight from AVer's own testing doc, referenced in the module's README, tested with [PacketSender](https://packetsender.com/).)

If disabled, the raw VISCA bytes (`81 01 04 3F 02 01 FF`) are sent directly with no header — useful for older firmware or manual testing.

---

## Command Envelope

Every command: starts with `81` (camera address 1), ends with `FF`.

---

## Pan/Tilt

**Continuous drive** — `81 01 06 01 <panSpeed hex> <tiltSpeed hex> <dir> FF`, speed `1`-`24` decimal.

| Direction | Bytes |
|-----------|-------|
| Up | `03 01` |
| Down | `03 02` |
| Left | `01 03` |
| Right | `02 03` |
| Up-Left / Up-Right / Down-Left / Down-Right | `01 01` / `02 01` / `01 02` / `02 02` |
| Stop | `03 03` |

**Home**: `81 01 06 04 FF` &nbsp;&nbsp; **Reset**: `81 01 06 05 FF`

---

## Zoom / Focus

| Command | Bytes |
|---------|-------|
| Zoom in/out (level `0`-`7`) | `81 01 04 07 2<level> FF` / `81 01 04 07 3<level> FF` |
| Zoom stop | `81 01 04 07 00 FF` |
| Focus stop / far / near (standard) | `81 01 04 08 00 FF` / `81 01 04 08 02 FF` / `81 01 04 08 03 FF` |
| Focus far/near (variable, level `0`-`15`) | `81 01 04 08 2<level> FF` / `81 01 04 08 3<level> FF` |
| Focus Auto / Manual / One-push | `81 01 04 38 02 FF` / `81 01 04 38 03 FF` / `81 01 04 18 01 FF` |

---

## Exposure

| Command | Bytes |
|---------|-------|
| Auto exposure mode | `81 01 04 39 <00 Full Auto\|03 Manual\|0A Shutter Pri\|0B Iris Pri\|0D Bright> FF` |
| Shutter up/down | `81 01 04 0A <02\|03> FF` |
| Iris up/down | `81 01 04 0B <02\|03> FF` |
| Gain up/down | `81 01 04 0C <02\|03> FF` |
| Bright up/down | `81 01 04 0D <02\|03> FF` |
| Exposure compensation up/down | `81 01 04 0E <02\|03> FF` |
| Backlight compensation on/off | `81 01 04 33 <02\|03> FF` |
| Red gain up/down | `81 01 04 03 <02\|03> FF` |
| Blue gain up/down | `81 01 04 04 <02\|03> FF` |
| White balance | `81 01 04 <3500 Auto\|3504 ATW\|3501 Indoor\|3502 Outdoor\|3503 One-push mode\|3505 Manual\|1005 One-push trigger> FF` |
| Wide Dynamic Range on/off | model-dependent — check camera's own control-code PDF (not confirmed in module source) |

---

## Presets

Presets are 0-255, referenced by hex byte.

| Command | Bytes |
|---------|-------|
| Recall | `81 01 04 3F 02 <NN hex> FF` |
| Set (save) | `81 01 04 3F 01 <NN hex> FF` |
| Reset | `81 01 04 3F 00 <NN hex> FF` |

---

## Tally / Menu / Freeze

| Command | Bytes |
|---------|-------|
| Tally lamp on/off | `81 01 7E 01 0A 00 <02\|03> FF` |
| Menu on/off toggle | `81 01 06 06 10 FF` |
| Freeze on/off/preset-on/preset-off | `81 01 04 62 <02\|03\|22\|23> FF` |

---

## AVer-Specific Tracking / Streaming Features

These are notably **not present** on the AW-HE40 or most other VISCA cameras — AVer's "smart tracking" and NDI/streaming feature set is a differentiator worth knowing about when comparing brands:

| Feature | Bytes |
|---------|-------|
| Auto tracking on/off | `81 01 04 7D <02\|03> FF` |
| Tracking control mode (Full Body/Upper Body/Point/Multi-presenter/Presenter/Zone/Hybrid) | `81 01 04 3F 01 <A0-A6> FF` |
| Frame tracking (start/auto/manual) | `81 01 04 7D <00\|02\|03> 00 FF` |
| Audio tracking (tracking/frame/preset) | `81 01 04 7D <04\|05\|06> 00 FF` |
| Multi-presenter on/off | `81 01 04 A9 <02\|03> FF` |
| Video mode (IP+Stream/USB/NDI/Streaming) | `81 01 04 A3 <00\|01\|02\|03> FF` |
| RTMP on/off | `81 01 04 A2 <02\|03> FF` |

---

## Implementation Notes

Same socket-protocol caveat as the other VISCA docs: this **cannot** be proxied by Apache's `mod_proxy_http`. AVer's own README recommends testing with [PacketSender](https://packetsender.com/) before writing integration code — useful for verifying a specific camera model actually implements the command you expect, since AVer's control-code PDFs vary slightly per model line (PTZ310/330 vs TR-series).

```php
// Conceptual PHP — VISCA-over-IP header + payload
$seq = 0;
$visca = pack('C*', 0x81, 0x01, 0x04, 0x3F, 0x02, 0x01, 0xFF); // recall preset 1
$header = pack('n', 0x0100) . pack('n', strlen($visca)) . pack('N', $seq);
$socket = stream_socket_client("udp://{$cameraIp}:52381", $errno, $errstr, 2);
fwrite($socket, $header . $visca);
fclose($socket);
```

---

## Sources

- [Bitfocus Companion Module — companion-module-aver-ptz](https://github.com/bitfocus/companion-module-aver-ptz) — `actions.js` (command byte tables), `main.js` (UDP transport, VISCA-over-IP header construction, default port 52381), `README.md` (PacketSender testing example, links to AVer's official control-code PDFs)
