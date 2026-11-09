# PTZ Camera Brand Comparison — Buying Guide

A side-by-side comparison of the AW-HE40 (current hardware) against the other brands documented in this folder, focused on **what it would actually take to integrate a second camera brand into `cameracontrol`**. See each brand's own reference doc for full command tables.

| Brand | Protocol | Transport | Default Port | Presets | Works with current Apache proxy? |
|-------|----------|-----------|---------------|---------|-----------------------------------|
| **Panasonic AW-HE40** *(current)* | Plain-text CGI | HTTP | 80 | 0-indexed int, 100 slots | ✅ Yes — this is what's already built |
| [PTZOptics](PTZOPTICS-VISCA-API-REFERENCE.md) | VISCA | Raw TCP | 5678 | 0-indexed int, 0-255 (90-99, 255 reserved) | ❌ No — needs a socket bridge |
| [Sony](SONY-VISCA-API-REFERENCE.md) | VISCA-over-IP | UDP | 52381 | 0-indexed int, model-dependent (64-256) | ❌ No — needs a socket bridge |
| [AVer](AVER-VISCA-API-REFERENCE.md) | VISCA-over-IP (optional header) | UDP | 52381 | 0-255 hex | ❌ No — needs a socket bridge |
| [Marshall](MARSHALL-VISCA-API-REFERENCE.md) | VISCA-over-IP | UDP | 52381 | Not confirmed present | ❌ No — needs a socket bridge |
| [Generic ONVIF](ONVIF-PTZ-API-REFERENCE.md) (Hikvision/Dahua/Bosch/Axis, and secondary on some PTZOptics/AVer models) | SOAP/XML | HTTP | 80 (varies) | String tokens (not integers) | ✅-ish — HTTP-based, same shape as `multicamera/onvif-proxy.php` |
| **[TONGVEO VL20N](#tongveo-vl20n-under-evaluation)** *(candidate purchase)* | VISCA-over-IP | UDP | **52381 (confirmed in manual)** | 255, 0-indexed (VISCA/Pelco-D/Pelco-P) | ❌ No — needs a socket bridge, but **matches `drivers/ViscaClient.php` defaults exactly** |

## TONGVEO VL20N (under evaluation)

The camera currently being considered for purchase. Its manual (§7.7 "VISCA over IP") confirms:

| Property | Value |
|----------|-------|
| Control port | RJ45 (same physical port as video/PoE — no separate control jack) |
| IP protocol | IPv4 |
| Transmission protocol | **UDP** |
| Port | **52381** |
| IP address | Set via the camera's web UI (default `192.168.1.205`, per its manual/Amazon listing) |
| Application range | Same network segment only (no routing across subnets) |

This is **identical** to the [Sony](SONY-VISCA-API-REFERENCE.md) and [AVer](AVER-VISCA-API-REFERENCE.md) default (UDP/52381), strongly suggesting the same shared "VISCA over IP" reference design/OEM board those docs describe. Practically, this means:

- `drivers/ViscaClient.php`'s defaults (`port = 52381`, `transport = 'udp'`, `useIpHeader = true`) require **no changes** to target this camera once purchased — construct it with just `new ViscaClient($cameraIp)`.
- The manual doesn't explicitly confirm the 8-byte VISCA-over-IP header framing (type/length/sequence) used by Sony/AVer/Marshall, but given the identical port and transport, it's a reasonable bet the camera uses the same standard framing rather than raw VISCA-over-UDP with no header. **This should be verified against real hardware** (see `drivers/README.md`) before relying on it — worth testing with `ViscaClient::send()` and checking for a valid ACK (`90 4y FF`) reply as soon as the camera arrives.
- Its RS232/RS485 serial ports remain available as a fallback/secondary control path (also VISCA/Pelco-D/Pelco-P), independent of the network path.

## The architectural fork in the road

Every brand here splits into exactly two integration paths, regardless of manufacturer:

1. **HTTP-based** (AW-HE40 today, and ONVIF): the browser's `fetch()` calls go through Apache's `mod_proxy_http` straight to the camera's CGI/SOAP endpoint. This is the entire reason `cameracontrol/index.htm` and `ptz-control.htm` can talk to the camera with zero PHP involvement today.
2. **Raw-socket VISCA** (PTZOptics, Sony, AVer, Marshall — i.e. every other brand in this comparison): Apache **cannot** proxy a raw TCP/UDP socket. Any of these brands requires writing and maintaining a new PHP (or other) bridge process that opens the socket, encodes/decodes VISCA bytes, and exposes an HTTP endpoint for the frontend to call instead.

This means the "best VISCA brand" question is largely a wash from an integration-effort standpoint — PTZOptics, Sony, AVer, and Marshall all require the *same category* of new infrastructure (a socket bridge) that doesn't exist in this codebase yet. Picking among them can reasonably come down to price, image quality, zoom range, and how well-documented/supported the *specific model* is, rather than "which VISCA dialect is easier to integrate."

## If integration effort matters more than brand loyalty

An ONVIF-capable camera is the lowest-new-infrastructure option, because:
- It's HTTP+XML, so it fits the same reverse-proxy-friendly shape as the AW-HE40.
- This repo already has a working ONVIF client pattern in [`multicamera/onvif-proxy.php`](../multicamera/onvif-proxy.php) (WS-Security digest auth SOAP calls) — a `cameracontrol` ONVIF driver could reuse that approach almost directly.
- Many PTZOptics/AVer models expose **both** VISCA and ONVIF — buying one of those keeps a VISCA fallback (for Companion/OBS/vMix workflows) while giving `cameracontrol` the easier HTTP path.

The trade-off: ONVIF's command model is meaningfully different from the AW-HE40's (velocity floats instead of speed integers, string preset tokens instead of `#R00`-style numbered slots), so the **frontend UI** would need real changes, not just a backend translation layer — see [ONVIF-PTZ-API-REFERENCE.md § What's Missing](ONVIF-PTZ-API-REFERENCE.md#whats-missing-vs-the-aw-he40) and § Implementation Notes.

## If a VISCA brand is preferred anyway

All four VISCA docs describe the same underlying interaction model as the AW-HE40 (speed+direction pan/tilt, 0-indexed numbered presets), which is closer to `cameracontrol`'s existing UI/UX than ONVIF is. The cost is upfront: someone has to write and test a VISCA socket bridge once, against real hardware, before any of PTZOptics/Sony/AVer/Marshall can be wired in. See [`drivers/README.md`](drivers/README.md) for a starting point — a protocol-encoding library that's ready to be plugged into a bridge endpoint once real hardware is available to validate against.

## Feature gaps to double-check before buying

Cross-referencing each brand's doc against the AW-HE40's feature set ([AW-HE40-API-REFERENCE.md](AW-HE40-API-REFERENCE.md)):

- **Tally light**: AW-HE40 has explicit `#DA1`/`#DA0`. PTZOptics has no standardized command. Sony/AVer/Marshall support varies by model. ONVIF has no standard tally operation at all. If tally-follows-switcher automation matters, verify this on the specific model before buying.
- **SD card recording**: AW-HE40 has `sdctrl?save=start/end`. Not confirmed for any of the other five options — check the specific model's manual.
- **Power on/off over the wire**: present on AW-HE40, Sony, Marshall. Not confirmed as universally supported on PTZOptics VISCA-over-IP (some models are inquiry-only).
- **Presets as simple numbered slots**: AW-HE40, PTZOptics, Sony, AVer all use this model. ONVIF uses string tokens instead — a materially different UI shape.
