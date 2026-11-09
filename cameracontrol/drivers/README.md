# Camera Drivers — Future Multi-Brand Support

## Status: not wired into anything yet

This folder currently contains one file, `ViscaClient.php` — a standalone VISCA / VISCA-over-IP command encoder for a **future** second camera brand (PTZOptics, Sony, AVer, or Marshall — see the `*-VISCA-API-REFERENCE.md` docs one directory up).

**Nothing in `cameracontrol/` currently uses this file.** `index.htm`, `ptz-control.htm`, and the Apache `/cam/ptz` + `/cam/cam` proxy routes for the AW-HE40 are completely unmodified. This exists purely as groundwork so that whichever brand ends up getting purchased, the byte-encoding work is already done, documented, and testable — see [CAMERA-BRAND-COMPARISON.md](../CAMERA-BRAND-COMPARISON.md) for the buying-decision context.

## Why VISCA needs this at all (and the AW-HE40 didn't)

The AW-HE40 uses plain HTTP CGI (`#PTS5050` as a query string), which Apache's `mod_proxy_http` forwards transparently — no PHP involved. VISCA is a raw binary protocol over a TCP or UDP **socket**, which Apache cannot proxy. Any VISCA brand needs something on the server side that:
1. Encodes a semantic action ("pan right at speed 12") into the correct VISCA byte sequence
2. Opens a socket to the camera and sends those bytes
3. Reads back the ACK/Completion (or error) reply

`ViscaClient.php` handles steps 1 and 2. Step 3 (a lightweight HTTP endpoint the frontend can `fetch()`, analogous to today's `/cam/ptz`) does not exist yet — see "Future integration" below.

## Validating the encoding logic (no camera required)

```bash
php cameracontrol/drivers/test-encode.php
```

This checks the byte arrays `ViscaClient` produces against the literal examples quoted in the reference docs (e.g. "pan right + tilt up at speed 12 → `81 01 06 01 0C 0C 02 01 FF`"). It does **not** touch the network — pure encoding self-checks.

## Validating against real hardware (once purchased)

```php
$client = new ViscaClient($cameraIp); // defaults: port 52381, UDP, IP header enabled
// $client = new ViscaClient($cameraIp, 5678, 'tcp', useIpHeader: false); // PTZOptics
$reply = $client->send($client->panTiltHome());
var_dump($reply); // expect ACK (90 4y FF) then Completion (90 5y FF)
```

Check the relevant brand's reference doc for the correct port/transport/header combination before testing.

### Current purchase candidate: TONGVEO VL20N

Its manual (§7.7 "VISCA over IP") confirms UDP port 52381 — identical to the Sony/AVer/Marshall convention this library already defaults to. **No code changes should be needed** to target this specific camera; see [CAMERA-BRAND-COMPARISON.md § TONGVEO VL20N](../CAMERA-BRAND-COMPARISON.md#tongveo-vl20n-under-evaluation) for the confirmed spec and the one thing still unverified (whether it uses the same 8-byte header framing as Sony/AVer/Marshall). Test this first once the camera is in hand.

## Future integration (explicitly not done — requires real hardware first)

1. Add a `command.php` endpoint in `cameracontrol/` that reads the camera's `type` from `config.json`, and either passes through to the existing Panasonic proxy behavior or calls `ViscaClient` for VISCA-family types.
2. Update the specific `fetch('/cam/ptz?cmd=...')` calls in `index.htm`/`ptz-control.htm` to route through `command.php` **only** when a non-Panasonic camera type is configured — the AW-HE40's existing direct-proxy calls should remain untouched to avoid any regression risk.
3. Test against the actual purchased hardware before considering this done — VISCA command tables vary enough per model (see the per-brand docs' caveats) that this cannot be safely verified without a real camera.
