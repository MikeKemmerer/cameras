# Generic ONVIF PTZ API Reference

[ONVIF](https://www.onvif.org/) is a vendor-neutral standard for network video devices, widely supported by Hikvision, Dahua, Bosch, Axis, and as a **secondary** protocol on many PTZOptics/AVer/other VISCA cameras. Unlike every other document in this folder, ONVIF is **SOAP/XML over plain HTTP** — architecturally the closest thing to the AW-HE40's CGI approach, since it doesn't require a raw TCP/UDP socket bridge.

This project already has a working example of this pattern: [`multicamera/onvif-proxy.php`](../multicamera/onvif-proxy.php), which does WS-Security digest-auth SOAP calls today for the "Lobby Camera" entry in `multicamera/config/cameras.json`.

This document was compiled from the [Bitfocus Companion Generic ONVIF module](https://github.com/bitfocus/companion-module-generic-onvif) source, which wraps the `onvif` npm package (a SOAP client) rather than hand-building command bytes.

---

## Transport

| Property | Value |
|----------|-------|
| Protocol | SOAP 1.2 / XML over **HTTP** |
| Default port | `80` (vendor-dependent — often `8080`, `2020`, etc.) |
| Device service path | `/onvif/device_service` (default, configurable) |
| Auth | Username + password, WS-Security digest (`digest/wsse` mode) |

Because this rides on plain HTTP, it is the **only** brand in this comparison set that can realistically reuse the existing Apache `mod_proxy_http` + PHP pattern already used for the AW-HE40, rather than requiring a new raw-socket bridge (see the [VISCA docs](PTZOPTICS-VISCA-API-REFERENCE.md) for why those brands are different).

---

## Command Model

ONVIF PTZ is fundamentally different from VISCA's "byte string with speed+direction nibbles" model. Instead of raw commands, you call **SOAP operations** with named parameters:

| Operation | Purpose | Key Parameters |
|-----------|---------|-----------------|
| `ContinuousMove` | Start moving, like VISCA's `#PTS`/`#Z` | `x`, `y`, `zoom` velocities (each `-1.0` to `1.0`), optional `timeout` |
| `AbsoluteMove` | Move to an exact PTZ position | `x`, `y`, `zoom` position + `speed.x/y/zoom` |
| `RelativeMove` | Move relative to current position | same shape as AbsoluteMove but delta-based |
| `Stop` | Stop movement | `panTilt` (bool), `zoom` (bool) |
| `GotoHomePosition` / `SetHomePosition` | Recall/save the "home" position | `speed.x/y/zoom` |
| `GotoPreset` | Recall a preset | `presetToken` (string, not a number!) |
| `SetPreset` | Save a preset | `presetToken`, `presetName` |
| `GetPresets` | List presets (needed to populate a UI dropdown) | — |
| `GetStatus` | Poll current PTZ position + move status | — |

> **Presets are string tokens fetched from the camera**, not simple 0-indexed integers like every VISCA brand in this comparison. A UI integration must call `GetPresets` first to build the list of valid tokens — there's no way to "just recall preset 5" without knowing its token.

---

## Pan/Tilt/Zoom Velocity Convention

All movement is normalized to `-1.0`..`1.0` floating point, not the VISCA `01`-`99`/`01`-`24` integer speed scale:

- `x` (pan): negative = left, positive = right
- `y` (tilt): negative = down, positive = up
- `zoom`: negative = wide/out, positive = tele/in
- A value of `0` on any axis stops that axis

Example continuous move (pan right + tilt up at half speed): `{ x: 0.5, y: 0.5 }`

---

## Imaging Settings

ONVIF also exposes a `SetImagingSettings` operation covering settings that on VISCA cameras are separate byte commands:

| Setting | Range |
|---------|-------|
| Brightness | `0`-`100` |
| Color Saturation | `0`-`100` |
| Contrast | `0`-`100` |
| Sharpness | `0`-`100` |
| Exposure mode | `AUTO` / `MANUAL`, with `exposureTime` (ms), `gain`, `iris` sub-fields |
| Focus mode | `AUTO` / `MANUAL`, with `nearLimit`/`farLimit` |
| IR Cut Filter | `AUTO` / `ON` / `OFF` |

---

## Device Info / Status

| Operation | Returns |
|-----------|---------|
| `GetDeviceInformation` | Manufacturer, model, firmware version, serial number, hardware ID |
| `GetStatus` | Current PTZ position (`x`/`y`/`zoom`), move status (`MOVING`/`IDLE` per axis), error state |
| `GetSystemDateAndTime` | Camera's current UTC time |

---

## What's Missing vs. the AW-HE40

- **No tally light concept** — ONVIF has no standard tally operation. Some vendors expose it via a proprietary extension, but there's no cross-vendor guarantee.
- **No SD card recording control** in the base PTZ/Imaging services (a separate "Recording" or "Media" ONVIF profile may exist on NVR-style devices, but not typical single-camera PTZ units).
- **No simple integer preset numbers** — see the token caveat above; this makes porting the AW-HE40's `#R00`-`#R99` preset grid UI pattern directly to ONVIF non-trivial.

---

## Implementation Notes

Because this is HTTP+XML, a PHP bridge is much closer to what already exists in this repo than any VISCA option:

- `multicamera/onvif-proxy.php` already demonstrates WS-Security digest auth SOAP calls in this codebase's style — a `cameracontrol`-side ONVIF driver could follow the same pattern rather than inventing a new one.
- No raw socket handling, no binary byte-packing, no custom framing — just building/parsing SOAP XML envelopes over `curl`/`file_get_contents`, or using a small SOAP helper library.
- The velocity/token-based command model means the **frontend JS would need real changes** (sliders/velocities instead of `#PTS` speed strings, a preset-token dropdown instead of `#R00`-style fixed slots) — this is a UI-level difference, not just a backend translation, unlike the VISCA brands where the wire format differs but the *interaction model* (speed+direction, 0-indexed presets) stays similar to the AW-HE40.

---

## Sources

- [Bitfocus Companion Module — companion-module-generic-onvif](https://github.com/bitfocus/companion-module-generic-onvif) — `src/api.js` (SOAP calls via the `onvif` npm package), `src/actions.js` (velocity/position parameter shapes), `src/config.js` (auth fields, default device service path)
- [`multicamera/onvif-proxy.php`](../multicamera/onvif-proxy.php) — existing WS-Security digest-auth SOAP proxy already in this codebase
