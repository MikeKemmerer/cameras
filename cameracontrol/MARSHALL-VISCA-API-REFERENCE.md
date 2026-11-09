# Marshall VISCA-over-IP API Reference

Marshall's CV-series IP PTZ cameras (e.g. CV630-IP) use the standard VISCA-over-IP framing, same family as Sony/AVer. This document was compiled from the [Bitfocus Companion Marshall VISCA module](https://github.com/bitfocus/companion-module-marshall-visca), which is unusually well-structured — it defines commands as declarative byte "patterns" rather than hand-written strings, which made this the easiest of the four VISCA modules to extract exact byte values from with high confidence.

---

## Transport

| Property | Value |
|----------|-------|
| Protocol | VISCA over IP, **UDP** |
| Default port | **52381** |
| Camera address | `1`-`7`, default `1` (embedded in the `8x` prefix byte) |
| Sockets | 2 concurrent command sockets supported |
| Auth | None |

### VISCA-over-IP packet header

Identical convention to [Sony](SONY-VISCA-API-REFERENCE.md#visca-over-ip-packet-header)/[AVer](AVER-VISCA-API-REFERENCE.md#visca-over-ip-packet-header-when-enabled--default): 2-byte payload type + 2-byte payload length + 4-byte sequence number, then the VISCA payload.

| Payload type bytes | Meaning |
|---------------------|---------|
| `01 00` | VISCA Command |
| `01 10` | VISCA Inquiry |
| `01 11` | VISCA Reply |
| `01 20` | VISCA Device Setting Command |
| `02 00` | Control Command (used for sequence-number reset) |
| `02 01` | Control Reply |

Before sending the first real command, the Marshall module resets the sequence counter with a **Control Command**: type `02 00`, sequence `00000000`, payload `01`. The camera replies with payload `01` confirming reset, and subsequent commands increment the sequence number.

---

## Command Envelope

`8x <task-family byte> ... FF` — `x` = camera address (1-7).

---

## Power

| Command | Bytes |
|---------|-------|
| Power On | `8x 01 04 00 02 FF` |
| Power Off (Standby) | `8x 01 04 00 03 FF` |

---

## Zoom

| Command | Bytes |
|---------|-------|
| Stop | `8x 01 04 07 00 FF` |
| Tele (standard) | `8x 01 04 07 02 FF` |
| Wide (standard) | `8x 01 04 07 03 FF` |
| Tele step | `8x 01 04 07 04 FF` |
| Wide step | `8x 01 04 07 05 FF` |
| Tele (variable, `p`=0-7) | `8x 01 04 07 2p FF` |
| Wide (variable, `p`=0-7) | `8x 01 04 07 3p FF` |
| Direct position (`0x0000`-`0x4000`, wide→tele) | `8x 01 04 47 0p 0p 0p 0p FF` |
| Direct position + speed | `8x 01 04 47 <4-nibble position> <1-nibble speed> FF` |
| Memory mode on/off | `8x 01 04 47 00 <02\|03> FF` |

---

## Focus

| Command | Bytes |
|---------|-------|
| Stop | `8x 01 04 08 00 FF` |
| Far / Near (standard) | `8x 01 04 08 02 FF` / `8x 01 04 08 03 FF` |
| Far step / Near step | `8x 01 04 08 04 FF` / `8x 01 04 08 05 FF` |
| Far / Near (variable, `p`=0-7) | `8x 01 04 08 2p FF` / `8x 01 04 08 3p FF` |
| Direct position (`0x0000`-`0x047A`) | `8x 01 04 48 0p 0p 0p 0p FF` |
| Mode Auto/Manual | `8x 01 04 38 02 FF` / `8x 01 04 38 03 FF` |
| Mode toggle | `8x 01 04 38 10 FF` |
| One-push trigger | `8x 01 04 18 01 FF` |
| Initialize lens | `8x 01 04 19 01 FF` |
| Combined zoom+focus direct | `8x 01 04 47 <4-nibble zoom> <4-nibble focus> <1-nibble speed> FF` |

---

## White Balance

| Command | Bytes | Values |
|---------|-------|--------|
| Mode | `8x 01 04 35 0p FF` | `00`=Auto, `01`=Indoor, `02`=Outdoor, `03`=One Push, `04`=Auto Tracing, `05`=Manual, `0C`=Sodium Lamp |
| One-push trigger | `8x 01 04 10 05 FF` | (manual mode only) |
| Red gain reset/up/down | `8x 01 04 03 <00\|02\|03> FF` | manual mode only |
| Red gain direct | `8x 01 04 43 00 00 0p 0q FF` | `0x00`-`0x80` |
| Blue gain reset/up/down | `8x 01 04 04 <00\|02\|03> FF` | manual mode only |
| Blue gain direct | `8x 01 04 44 00 00 0p 0q FF` | `0x00`-`0x80` |

---

## Autofocus Tuning

| Command | Bytes | Values |
|---------|-------|--------|
| Curve tracking | `8x 01 04 38 03 0p FF` | `02`=Curve tracking, `03`=Zoom tracking |
| Sensitivity | `8x 01 04 58 0p FF` | `01`=High, `02`=Middle, `03`=Low |
| Frame | `8x 01 04 5C 0p FF` | `01`=Auto, `02`=Full Frame, `03`=Center |
| Frame toggle | `8x 01 04 5C 10 FF` | — |

---

## Video Format

| Command | Bytes |
|---------|-------|
| Resolution | `8x 01 06 35 0p 0q FF` (lookup table — e.g. 1080p59.94=`08`, 720p29.97=`11`, 4K29.97=`05`) |
| HDMI output range | `8x 01 06 37 0p FF` (`01`=16-235, `02`=1-254) |

---

## Presets

> **Iris position values are defined in the module's lookup table (`Close`=`0F` down to `F18`=`00`) but the corresponding VISCA command to *set* iris directly is commented out in the module source** — meaning either the command code wasn't confirmed by the module author, or this camera line manages iris only via auto-exposure. Verify directly against real hardware before relying on it.

No dedicated preset save/recall command was found wired into the Marshall module (unlike Sony/AVer/PTZOptics) — Marshall's CV-series may handle presets purely through its own web UI/NDI control surface rather than VISCA. Confirm with Marshall's official VISCA command PDF for your exact model before assuming preset support.

---

## Implementation Notes

Same as the other VISCA docs — **not proxyable via Apache `mod_proxy_http`** (UDP, not HTTP). Notably, this is the one module where the sequence-number reset handshake is explicit and required (send the Control Command first) rather than just "start at 0 and increment," which is a good detail to replicate in any custom PHP bridge.

```php
// Conceptual PHP — reset sequence counter, then send Power On
$socket = stream_socket_client("udp://{$cameraIp}:52381", $errno, $errstr, 2);
fwrite($socket, pack('n', 0x0200) . pack('n', 1) . pack('N', 0) . pack('C', 0x01)); // reset
fread($socket, 32); // expect payload = 0x01

$visca = pack('C*', 0x81, 0x01, 0x04, 0x00, 0x02, 0xFF); // Power On
fwrite($socket, pack('n', 0x0100) . pack('n', strlen($visca)) . pack('N', 1) . $visca);
fclose($socket);
```

---

## Sources

- [Bitfocus Companion Module — companion-module-marshall-visca](https://github.com/bitfocus/companion-module-marshall-visca) — `visca/lib/Marshall/commands.js` (declarative command byte patterns), `visca/lib/Marshall/lookupTables.js` (enum values), `visca/lib/ViscaSocket.js` (UDP transport, payload-type header, sequence-counter reset handshake), `visca/lib/Connection.js` (default port 52381)
