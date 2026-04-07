# Panasonic AW-HE40 CGI API Reference

This document is a comprehensive reference for controlling the Panasonic AW-HE40 PTZ camera over HTTP. The AW-HE40 exposes a set of CGI endpoints that accept simple GET requests — no SDK, no special protocol, just plain HTTP calls. This makes it straightforward to build custom web interfaces for camera control.

All commands in this document were gathered from Panasonic's official protocol specification and cross-referenced against the [Bitfocus Companion module for Panasonic PTZ cameras](https://github.com/bitfocus/companion-module-panasonic-ptz), which implements the full command set in JavaScript.

---

## HE40-Series Feature Matrix

This table summarizes every feature in this document and whether it's available on the AW-HE40 specifically. Some features (like ND filter, color temperature, and green tally) exist on other Panasonic PTZ models but are not present on the HE40 hardware. If we ever upgrade to a newer model, this table shows what additional capabilities become available.

| Feature | Supported | Endpoint | Notes |
|---------|-----------|----------|-------|
| Pan/Tilt (continuous) | ✅ | aw_ptz | `#PTS<PP><TT>` |
| Pan/Tilt (absolute) | ✅ | aw_ptz | `#APC<PPPP><TTTT>` |
| Zoom | ✅ | aw_ptz | `#Z<SS>` |
| Focus (manual drive) | ✅ | aw_ptz | `#F<SS>` |
| Auto Focus toggle | ✅ | aw_ptz | `#D11` / `#D10` |
| One Touch Auto Focus | ✅ | aw_cam | `OSE:69:1` |
| Iris (manual) | ✅ | aw_ptz | `#I<HH>` |
| Auto Iris toggle | ✅ | aw_ptz | `#D30` / `#D31` |
| Preset recall | ✅ | aw_ptz | `#R<NN>` (0-indexed) |
| Preset save | ✅ | aw_ptz | `#M<NN>` (0-indexed) |
| Preset recall speed | ✅ | aw_ptz | `#UPVS<NNN>` (275–999) |
| Preset mode (A/B/C) | ✅ | aw_cam | `OSE:71:<M>` |
| Gain | ✅ | aw_cam | `OGU:<HH>` |
| Shutter | ✅ | aw_cam | `OSH:<H>` |
| Pedestal | ✅ | aw_cam | `OTP:<HHH>` |
| Power | ✅ | aw_ptz | `#O1` / `#O0` |
| Tally (red) | ✅ | aw_ptz | `#DA1` / `#DA0` |
| Install position | ✅ | aw_ptz | `#INS0` / `#INS1` |
| SD card recording | ✅ | sdctrl | `sdctrl?save=start\|end` |
| Color bars | ✅ | aw_cam | `DCB:1` / `DCB:0` |
| ND filter | ❌ | — | Not on HE40 |
| Preset time mode | ❌ | — | Not on HE40 (speed only) |
| Green tally | ❌ | — | HE40 has red only |
| Color temperature | ❌ | — | Not on HE40 |
| Scene select | ❌ | — | Not on HE40 |
| White balance mode | ❌ | — | Not on HE40 |

---

## Table of Contents

- [HE40-Series Feature Matrix](#he40-series-feature-matrix)
- [Endpoints](#endpoints)
- [Pan/Tilt — Continuous Movement](#pantilt--continuous-movement)
- [Zoom](#zoom)
- [Focus](#focus)
- [Iris](#iris)
- [Presets](#presets)
- [Gain](#gain)
- [Shutter](#shutter)
- [Pedestal (Black Level)](#pedestal-black-level)
- [Color Bars](#color-bars)
- [Power](#power)
- [Tally Light](#tally-light)
- [Installation Position](#installation-position)
- [SD Card Recording](#sd-card-recording)
- [Implementation Notes](#implementation-notes)
- [Status Queries and Camera State](#status-queries-and-camera-state)
- [Network Discovery and Identification](#network-discovery-and-identification)
- [Tally Integration with Video Switcher](#tally-integration-with-video-switcher)
- [Camera Web UI Proxy](#camera-web-ui-proxy)
- [Image Adjustment Commands](#image-adjustment-commands)
- [Streaming Configuration](#streaming-configuration)
- [Sources](#sources)

---

## Endpoints

The camera exposes four main CGI endpoints. None of them require authentication for basic operation — they are accessible to any device on the same network.

| Endpoint | Purpose | Auth Required |
|----------|---------|---------------|
| `/cgi-bin/aw_ptz` | PTZ movement, zoom, focus, iris, presets, power, tally | No |
| `/cgi-bin/aw_cam` | Camera settings (gain, shutter, pedestal, OSD, scene, white balance) | No |
| `/cgi-bin/mjpeg` | MJPEG live video stream | No |
| `/cgi-bin/sdctrl` | SD card recording control | No |

### Request Format

The two main control endpoints use slightly different command formats.

**aw_ptz** commands are prefixed with `#`, which must be URL-encoded as `%23` in the query string. The `&res=1` parameter tells the camera to send a response confirming receipt:
```
GET /cgi-bin/aw_ptz?cmd=%23<COMMAND>&res=1
```

**aw_cam** commands use plain text with no `#` prefix:
```
GET /cgi-bin/aw_cam?cmd=<COMMAND>&res=1
```

### Proxy Paths (Our Apache Config)

In our setup, the web server running the camera control UI proxies requests to the camera. This means the browser never talks to the camera directly — all commands go through the web server, which forwards them to the camera's IP address. See `sites-enabled/000-default.conf` for the full config.

| Proxy Path | Target |
|------------|--------|
| `/cam/ptz` | `http://172.25.0.200/cgi-bin/aw_ptz` |
| `/cam/cam` | `http://172.25.0.200/cgi-bin/aw_cam` |
| `/mjpeg` | `http://172.25.0.200/cgi-bin/mjpeg` |

---

## Pan/Tilt — Continuous Movement

The camera supports continuous pan and tilt movement at variable speeds. Rather than telling the camera "move to position X," you tell it "start moving in this direction at this speed" — exactly like holding a joystick. The camera keeps moving until you send a stop command.

The combined command `#PTS<PP><TT>` controls both axes simultaneously. Each axis is a 2-digit value from 01 to 99, where **50 means stopped**. Values below 50 move in one direction (left/down), and values above 50 move in the other (right/up). The further from 50, the faster the movement.

| Value Range | Pan Direction | Tilt Direction |
|-------------|---------------|----------------|
| 01–49 | Left (01 = fastest) | Down (01 = fastest) |
| 50 | Stopped | Stopped |
| 51–99 | Right (99 = fastest) | Up (99 = fastest) |

**Examples:**
```
#PTS5050     → Stop all movement
#PTS2050     → Pan left at moderate speed, no tilt
#PTS7050     → Pan right at moderate speed, no tilt
#PTS5070     → Tilt up at moderate speed, no pan
#PTS5020     → Tilt down at moderate speed, no pan
#PTS2070     → Pan left + tilt up simultaneously
#PTS0199     → Pan hard left + tilt hard up (max speed)
```

**Shorthand aliases** — if you only need to move on one axis, you can use the simpler single-axis commands. These behave as if the other axis is set to 50 (stopped):
```
#P<SS>       → Pan only (tilt stays at 50)
#T<SS>       → Tilt only (pan stays at 50)
```

### Absolute Position

If you know the exact pan/tilt coordinates you want (e.g., returning to a known position without using a preset), you can move directly to an absolute position. Each axis is a 4-digit hex value from 0000 to FFFF.

Command: `#APC<PPPP><TTTT>` via **aw_ptz**

```
#APC7FFF7FFF → Home position (center)
```

---

## Zoom

Zoom works exactly like pan/tilt — it's a continuous movement command, not an absolute position. You tell the camera to start zooming in or out at a given speed, and it keeps going until you send a stop command (value 50).

Command: `#Z<SS>` via **aw_ptz**

SS is a 2-digit speed value from 01 to 99. Values below 50 zoom out (wider), values above 50 zoom in (tighter), and 50 stops the zoom.

| Value Range | Direction |
|-------------|-----------|
| 01–49 | Zoom out (01 = fastest) |
| 50 | Stop |
| 51–99 | Zoom in (99 = fastest) |

**Examples:**
```
#Z50         → Stop zoom
#Z70         → Zoom in at moderate speed
#Z20         → Zoom out at moderate speed
#Z99         → Zoom in at max speed
#Z01         → Zoom out at max speed
```

**UI speed mapping** — if you're building a zoom slider or buttons with configurable speed, the Companion module maps a user-facing speed value (1–49) to the command value by offsetting from center:
- Zoom in at speed N: `#Z` + (50 + N) → e.g. speed 25 = `#Z75`
- Zoom out at speed N: `#Z` + (50 - N) → e.g. speed 25 = `#Z25`

---

## Focus

The camera supports both manual focus control (you drive the focus motor) and auto focus (the camera adjusts on its own). There's also a "one touch auto focus" mode that auto-focuses once and then stops — useful for getting a quick focus lock without leaving it in full auto mode.

### Continuous Focus

Command: `#F<SS>` via **aw_ptz**

This works the same way as zoom — it's a continuous drive command. Values below 50 focus nearer, above 50 focus farther, 50 stops.

| Value Range | Direction |
|-------------|-----------|
| 01–49 | Focus near (01 = fastest) |
| 50 | Stop |
| 51–99 | Focus far (99 = fastest) |

**Examples:**
```
#F50         → Stop focus
#F70         → Focus far at moderate speed
#F20         → Focus near at moderate speed
```

### Auto Focus Mode

Toggle between the camera managing focus automatically and you controlling it manually. When auto focus is on, the manual focus commands (`#F`) are ignored.

Command via **aw_ptz**:
```
#D11         → Auto Focus ON
#D10         → Manual Focus (Auto Focus OFF)
```

### One Touch Auto Focus (OTAF)

This is a convenience feature: it triggers a single auto-focus operation and then the camera returns to manual focus mode. Think of it as "focus on whatever is in frame right now, then let me take over again." This is especially handy when you've manually positioned the camera and just need a quick focus lock.

Command via **aw_cam**:
```
OSE:69:1     → Trigger one-time auto focus
```

---

## Iris

The iris controls how much light enters the camera. A wider iris (higher value) lets in more light but creates a shallower depth of field. The camera can manage this automatically or you can set it by hand.

### Manual Iris Control

Command: `#I<HH>` via **aw_ptz**

Sets the iris to a specific position. HH is a 2-digit decimal value from 00 (fully closed) to 99 (fully open).

```
#I00         → Iris fully closed
#I99         → Iris fully open
#I50         → Iris at midpoint
```

### Auto/Manual Iris Mode

Like focus, you can let the camera handle iris automatically or control it yourself. When auto iris is engaged, the camera adjusts exposure on its own and manual iris commands are ignored.

Command via **aw_ptz**:
```
#D30         → Auto Iris ON
#D31         → Manual Iris (Auto Iris OFF)
```

---

## Presets

Presets are saved camera positions. When you recall a preset, the camera physically moves its pan, tilt, and zoom motors to the saved position. The HE40 supports up to 100 presets. Depending on the preset mode (A/B/C), recalling a preset can also restore iris and white balance settings.

### Recall Preset

Command: `#R<NN>` via **aw_ptz**

NN is 2-digit and **0-indexed**, meaning preset 1 in the camera's menu corresponds to `00`, preset 2 is `01`, and so on. This is important to remember — our UI shows preset numbers starting from 1, but the command uses 0-indexed values.

```
#R00         → Recall preset 1
#R03         → Recall preset 4
#R21         → Recall preset 22
```

### Save Preset

Saves the camera's current pan, tilt, zoom, and (depending on mode) iris/white balance position to a preset slot. The camera stores these in non-volatile memory, so they survive power cycles.

Command: `#M<NN>` via **aw_ptz**

Same 0-indexed numbering as recall.

```
#M00         → Save current position as preset 1
#M03         → Save current position as preset 4
```

### Preset Recall Speed

This controls how fast the camera physically moves when transitioning to a recalled preset. It's a **global camera setting** — once sent, every subsequent preset recall uses this speed until you change it. Lower values produce slow, smooth, cinematic movements; higher values snap quickly to the new position.

We use this in our speed selector UI (Slow/Med/Fast/X-Fast).

Command: `#UPVS<NNN>` via **aw_ptz**

The value ranges from 275 (slowest) to 999 (fastest) in steps of 25. The table below shows the full range with our UI labels marked.

| UPVS Value | Speed Label | Notes |
|------------|------------|-------|
| 275 | Speed 01 | Slowest (cinematic) |
| 300 | Speed 02 | |
| 325 | Speed 03 | |
| 350 | Speed 04 | |
| 375 | Speed 05 | |
| 400 | Speed 06 | |
| 425 | Speed 07 | |
| **450** | **Speed 08** | **Our "Slow"** |
| 475 | Speed 09 | |
| 500 | Speed 10 | |
| 525 | Speed 11 | |
| **550** | **Speed 12** | **Our "Med" (default)** |
| 575 | Speed 13 | |
| 600 | Speed 14 | |
| 625 | Speed 15 | |
| **650** | **Speed 16** | **Our "Fast"** |
| 675 | Speed 17 | |
| 700 | Speed 18 | |
| 725 | Speed 19 | |
| **750** | **Speed 20** | **Our "X-Fast"** |
| 775 | Speed 21 | |
| ... | ... | Steps of 25 |
| 975 | Speed 29 | |
| 999 | Speed 30 | Fastest |

Formula: `UPVS_value = 275 + (speed_number - 1) * 25`  
(Exception: Speed 30 = 999, not 1000)

```
#UPVS550     → Set preset recall to Speed 12 (our "Med")
#UPVS999     → Set preset recall to Speed 30 (maximum)
#UPVS275     → Set preset recall to Speed 01 (minimum)
```

### Preset Mode (What Gets Recalled)

When you recall a preset, the camera can restore different combinations of settings depending on the active preset mode. This is controlled globally — changing the mode affects all future preset recalls.

- **Mode A** is the most complete: it restores PTZ position, iris, and white balance/color settings.
- **Mode B** restores PTZ position and iris but leaves white balance alone.
- **Mode C** restores only the PTZ position — useful if you're managing exposure and color separately.

Command via **aw_cam**:
```
OSE:71:0     → Mode A — PTZ + Iris + White Balance/Color
OSE:71:1     → Mode B — PTZ + Iris
OSE:71:2     → Mode C — PTZ only
```

---

## Gain

Gain amplifies the camera's signal to brighten the image in low-light situations. Higher gain values produce a brighter picture but also introduce more noise/grain. The auto setting lets the camera choose an appropriate gain level based on the scene.

The HE40 supports gain in 3 dB steps from 0 dB (no amplification) up to 48 dB (very high amplification, noisy). Gain values are sent as 2-digit hex codes.

Command via **aw_cam**: `OGU:<HH>`

| Value | Gain |
|-------|------|
| 80 | Auto |
| 08 | 0 dB |
| 0B | 3 dB |
| 0E | 6 dB |
| 11 | 9 dB |
| 14 | 12 dB |
| 17 | 15 dB |
| 1A | 18 dB |
| 1D | 21 dB |
| 20 | 24 dB |
| 23 | 27 dB |
| 26 | 30 dB |
| 29 | 33 dB |
| 2C | 36 dB |
| 2F | 39 dB |
| 32 | 42 dB |
| 35 | 45 dB |
| 38 | 48 dB |

```
OGU:80       → Auto gain
OGU:08       → 0 dB (no gain)
OGU:14       → 12 dB
```

---

## Shutter

The shutter speed controls how long each frame is exposed. Faster shutter speeds reduce motion blur but require more light. The "OFF" setting uses a default shutter speed that matches the frame rate (typically 1/60 for 59.94Hz). "Syncro Scan" is a special mode for shooting monitors/displays without banding.

Command via **aw_cam**: `OSH:<H>`

| Value | Shutter Speed |
|-------|---------------|
| 0 | OFF |
| 3 | 1/100 (59.94Hz) or 1/120 (50Hz) |
| 5 | 1/250 |
| 6 | 1/500 |
| 7 | 1/1000 |
| 8 | 1/2000 |
| 9 | 1/4000 |
| A | 1/10000 |
| B | Syncro Scan |

```
OSH:0        → Shutter off
OSH:6        → 1/500
```

---

## Pedestal (Black Level)

Pedestal adjusts the camera's black level — essentially how dark the darkest parts of the image appear. Raising the pedestal lifts the blacks (making shadows lighter/more washed out), while lowering it deepens the blacks (more contrast but risk of crushing detail in shadows). In most church/live production settings, the default center value works fine.

The value is a 3-digit hex number from 000 to 12C (0–300 in decimal), where the center point (0.0 on the camera's scale) is 096 (150 in decimal). Each step of 15 in the raw value equals 1.0 on the camera's pedestal scale.

Command via **aw_cam**: `OTP:<HHH>`

```
OTP:096      → Pedestal at 0.0 (center)
OTP:000      → Pedestal at minimum (-10.0)
OTP:12C      → Pedestal at maximum (+10.0)
```

---

## Color Bars

Color bars are a standard test pattern used for calibrating monitors and video equipment. The camera can output color bars instead of its live image — useful when setting up a new display, troubleshooting video routing through the Crestron switcher, or verifying that the signal path is working before a service.

The title overlay option superimposes the camera's name/identifier on the color bar output, which helps identify which camera's signal you're looking at when troubleshooting multi-camera setups.

Commands via **aw_cam**:

```
DCB:1        → Enable color bars (replaces live image)
DCB:0        → Disable color bars (return to live image)

OSD:BA:1     → Color bar Type 1 (standard SMPTE bars)
OSD:BA:0     → Color bar Type 2 (alternative pattern)

OSD:BE:1     → Title overlay ON (camera name on bars)
OSD:BE:0     → Title overlay OFF
```

---

## Power

The camera can be powered on or put into standby mode remotely. In standby, the camera stops outputting video and the motors are parked, but it stays connected to the network and can be woken up with a power-on command. This is useful for powering on all cameras before a service starts or putting them to sleep afterward — especially when the cameras are mounted in hard-to-reach locations like ceiling mounts.

Command via **aw_ptz**:
```
#O1          → Power ON (wake from standby)
#O0          → Power OFF (enter standby)
```

> Note: The camera takes several seconds to fully power on. It's ready when it starts responding to PTZ commands.

---

## Tally Light

The tally light is the small red LED on the front of the camera that indicates it's currently "on air" (its output is being sent to the program feed). In a multi-camera setup, the tally light tells both the camera operator and anyone on-camera which camera is live.

In our setup, the Crestron switcher controls which camera feeds the program output. Ideally, when you route a camera to output, you'd also send a tally-on command to that camera and tally-off to the others. This could be automated in the switcher button handler in the multicamera interface.

Command via **aw_ptz** (HE40 series — red tally only):
```
#DA1         → Red tally ON (camera is live/on-air)
#DA0         → Red tally OFF (camera is not live)
```

> Note: The HE40 only has a red tally light. Newer models (UE150, etc.) also have a green tally and use different commands: `TLR:1`/`TLR:0` (red) and `TLG:1`/`TLG:0` (green) via aw_cam.

---

## Installation Position

This tells the camera whether it's mounted upright on a surface or hanging upside-down from a ceiling mount. When set to "hanging," the camera flips the image and reverses the pan/tilt directions so everything behaves naturally. You typically set this once during installation and never touch it again.

Command via **aw_ptz**:
```
#INS0        → Desktop (upright on a shelf or tripod)
#INS1        → Hanging (inverted, ceiling-mounted)
```

---

## SD Card Recording

The HE40 has an SD card slot that can record the camera's output directly. This is useful as a backup recording or for capturing a specific camera angle independently from the main production recording. Recording uses a dedicated endpoint (not aw_ptz or aw_cam) and doesn't require the `#` prefix.

Command via dedicated endpoint:
```
GET /cgi-bin/sdctrl?save=start    → Start recording to SD card
GET /cgi-bin/sdctrl?save=end      → Stop recording
```

> Note: An SD card must be inserted and formatted by the camera before these commands will work.

---

## Implementation Notes

This section covers practical patterns for using these commands in our web-based camera control UI. All examples use the browser's `fetch()` API and our Apache reverse proxy paths, so the browser never needs direct access to the camera's IP address.

### JavaScript Examples

**Send aw_ptz command** — this is the pattern already used in index.htm for preset recall. The `%23` is the URL-encoded `#` character required by the aw_ptz endpoint:
```javascript
fetch('/cam/ptz?cmd=%23R03&res=1');           // recall preset 4
fetch('/cam/ptz?cmd=%23UPVS550&res=1');       // set speed to 12
fetch('/cam/ptz?cmd=%23PTS5050&res=1');        // stop pan/tilt
fetch('/cam/ptz?cmd=%23D11&res=1');            // auto focus on
```

**Send aw_cam command** — these go through the `/cam/cam` proxy and don't need the `#` prefix. Note the colon-separated parameter format used by aw_cam:
```javascript
fetch('/cam/cam?cmd=OSE:69:1&res=1');         // one-touch auto focus
fetch('/cam/cam?cmd=OGU:80&res=1');           // auto gain
fetch('/cam/cam?cmd=OSE:71:0&res=1');         // preset mode A
```

### Saving New Presets from the Web UI

Adding a "save preset" feature to the control page would involve several steps. The camera side is simple — you just send the save command — but the UI also needs to capture a thumbnail image and update the preset list so the new position appears as a clickable tile.

1. **Position the camera** — use PTZ joystick controls or manual pan/tilt/zoom commands to frame the shot
2. **Save to camera memory** — send `#M<NN>` (e.g., `#M15` for preset 16). The camera stores the position in non-volatile memory
3. **Capture a thumbnail** — draw the current MJPEG frame onto an HTML `<canvas>`, then export it as a JPEG using `canvas.toDataURL('image/jpeg')`. This could be saved to the `images/` directory as `preset16.jpg`
4. **Update presets.json** — add a new entry with the preset number, label, and thumbnail path. The UI reads this file on load to build the preset grid

### Pan/Tilt Joystick

A virtual joystick for manual camera control would work by mapping pointer/touch coordinates to PTS command values. The key insight is that PTS uses a "speed and direction" model — the further from center, the faster the movement.

- **X axis**: -1.0 (full left) → 01, 0.0 (center/stopped) → 50, +1.0 (full right) → 99
- **Y axis**: -1.0 (full down) → 01, 0.0 (center/stopped) → 50, +1.0 (full up) → 99
- **While dragging**: continuously send `#PTS<XX><YY>` with the mapped values
- **On release**: send `#PTS5050` to stop all movement
- **Throttle**: limit to ~10 commands per second to avoid overwhelming the camera. The camera processes commands sequentially, so flooding it causes laggy, jerky movement

### Batch Commands Across Multiple Cameras

In the multicamera setup, the same command can be sent to all four cameras by looping over their IPs using the existing dynamic proxy pattern. For example, to set all cameras to the same preset speed or power them all on before a service:

```javascript
const cameraIPs = ['172.25.0.200', '172.25.0.201', '172.25.0.202', '172.25.0.203'];

// Power on all cameras
cameraIPs.forEach(ip => {
    fetch(`/multicamera/cam/${ip}/ptz?cmd=%23O1&res=1`).catch(() => {});
});

// Set all cameras to preset speed 12
cameraIPs.forEach(ip => {
    fetch(`/multicamera/cam/${ip}/ptz?cmd=%23UPVS550&res=1`).catch(() => {});
});
```

The IP list could come from `multicamera/config/cameras.json`, which already defines camera IPs for the multi-camera interface.

---

## Status Queries and Camera State

The camera can report its current state, which is useful for building a UI that reflects what's actually happening (e.g., showing which preset is active, whether auto-focus is on, or if the camera is even powered up).

### Polling via HTTP — camdata.html

The simplest way to get the camera's current state is to fetch its status page. The camera exposes a page at `/live/camdata.html` that returns all current settings as colon-separated key-value pairs, one per line. This is the same page the Companion module uses for initial state discovery.

```
GET /live/camdata.html
```

The response is plain text with lines like:
```
OID:AW-HE40
TITLE:Camera 1
p1                    (power is ON; "p0" means OFF)
iNS0                  (desktop mount; "iNS1" means hanging)
dA0                   (tally OFF; "dA1" means ON)
d30                   (auto iris; "d31" means manual)
OAF:1                 (auto focus ON; "OAF:0" means manual)
OGU:08                (gain at 0 dB)
OSE:71:0              (preset mode A)
DCB:0                 (color bars OFF)
qSV3:x.xx             (firmware version)
```

To fetch this through our proxy, you'd need a new proxy path or fetch it directly. In our Apache config, this could be added as:
```apache
ProxyPass        /cam/status  http://172.25.0.200/live/camdata.html
ProxyPassReverse /cam/status  http://172.25.0.200/live/camdata.html
```

Then in JavaScript:
```javascript
fetch('/cam/status')
    .then(r => r.text())
    .then(text => {
        const lines = text.split('\r\n');
        lines.forEach(line => {
            const parts = line.trim().split(':');
            // parts[0] is the key, parts[1] is the value
            // e.g., ["OAF", "1"] or ["p1"]
        });
    });
```

### Event Subscription via TCP

For real-time updates (as opposed to polling), the camera supports a TCP event subscription model. You send an HTTP request to subscribe, then the camera pushes state changes to your TCP port whenever something changes (preset recalled, focus mode changed, power state, tally, etc.).

**Subscribe:**
```
GET /cgi-bin/event?connect=start&my_port=<PORT>&uid=0
```

**Unsubscribe:**
```
GET /cgi-bin/event?connect=stop&my_port=<PORT>&uid=0
```

The camera then sends newline-delimited messages to your TCP server in the same colon-separated format as camdata.html. This is how the Bitfocus Companion module stays in sync with the camera in real time.

> Note: Implementing TCP event subscription in a browser-based app would require a WebSocket bridge running server-side. For a simpler approach, polling camdata.html every few seconds is sufficient for most UI feedback needs.

### Error Codes

When a command fails, the camera responds with an error code instead of the normal acknowledgment. The response starts with `rER` followed by a 2-digit error code.

| Response | Meaning |
|----------|---------|
| `rER00` | No error (success) |
| `rER02` | Busy (camera is executing another command) |
| `rER03` | Command not supported on this model |
| `rER04` | Illegal parameter value |
| `rER10` | Camera is in standby mode (send power-on first) |

In JavaScript, you can check for errors by reading the response text:
```javascript
fetch('/cam/ptz?cmd=%23R00&res=1')
    .then(r => r.text())
    .then(text => {
        if (text.includes('rER')) {
            console.error('Camera error:', text.trim());
        }
    });
```

---

## Network Discovery and Identification

These commands help identify and monitor cameras on the network — useful for building a status dashboard or verifying that all cameras are online before a service.

### Firmware Version

The camera reports its firmware version in camdata.html as `qSV3:x.xx`. This can also be retrieved individually, though the camdata.html approach is simpler since you get everything at once.

### Model Identification

The camera reports its model via the `OID` field in camdata.html:
```
OID:AW-HE40
```

### Camera Name

Each camera can be given a name through its setup menu (or the built-in web interface). It's reported as:
```
TITLE:Camera 1
```

### Simple Health Check

The quickest way to check if a camera is online and responsive is to send any query and see if you get a response. A lightweight option:
```javascript
// Returns fast, camera responds with its power state
fetch('/cam/ptz?cmd=%23O&res=1', { signal: AbortSignal.timeout(3000) })
    .then(r => r.ok ? 'online' : 'error')
    .catch(() => 'offline');
```

For a multi-camera dashboard, run this against each camera IP:
```javascript
const cameraIPs = ['172.25.0.200', '172.25.0.201', '172.25.0.202', '172.25.0.203'];

async function checkAllCameras() {
    const results = await Promise.all(
        cameraIPs.map(ip =>
            fetch(`/multicamera/cam/${ip}/ptz?cmd=%23O&res=1`, {
                signal: AbortSignal.timeout(3000)
            })
            .then(r => ({ ip, status: r.ok ? 'online' : 'error' }))
            .catch(() => ({ ip, status: 'offline' }))
        )
    );
    return results;
}
```

---

## Tally Integration with Video Switcher

In our setup, the Crestron video switcher (proxied at `/multicamera/switcher`) routes camera inputs to the program output. By combining switcher routing with tally commands, we can automatically light up the tally LED on whichever camera is currently live.

The idea is straightforward: when you switch to camera N, send `#DA1` (tally on) to that camera and `#DA0` (tally off) to all the others. This could be added to the existing switcher button handler in the multicamera interface.

```javascript
const cameraIPs = ['172.25.0.200', '172.25.0.201', '172.25.0.202', '172.25.0.203'];

function routeAndTally(cameraIndex) {
    // Route camera to program output via Crestron switcher
    fetch(`/multicamera/switcher/route?input=${cameraIndex}&output=1`);

    // Set tally lights — ON for active camera, OFF for all others
    cameraIPs.forEach((ip, i) => {
        const tallyCmd = (i === cameraIndex - 1) ? 'DA1' : 'DA0';
        fetch(`/multicamera/cam/${ip}/ptz?cmd=%23${tallyCmd}&res=1`).catch(() => {});
    });
}

// Example: switch to camera 2 and update tally lights
routeAndTally(2);
```

---

## Camera Web UI Proxy

The AW-HE40 has a built-in web interface for advanced configuration that's normally accessed by browsing directly to the camera's IP address. In our setup, this is proxied through `liturgystream2:8081`, so the camera's control page is available at:

```
http://liturgystream2:8081/live/index.html
```

This built-in web UI provides access to settings that aren't available through the CGI commands, such as:
- Network configuration (IP address, subnet, gateway)
- Video output format (resolution, frame rate)
- Encoding settings (bitrate, compression)
- OSD (on-screen display) configuration
- Detailed image adjustments (detail level, chroma, matrix)
- User management and passwords
- Firmware updates

To link to the camera's web UI from the control page, or embed it in an iframe:
```html
<!-- Link to camera's built-in admin page -->
<a href="http://liturgystream2:8081/live/index.html" target="_blank">Camera Settings</a>

<!-- Or embed in an iframe -->
<iframe src="http://liturgystream2:8081/live/index.html" width="100%" height="600"></iframe>
```

> Note: The built-in web UI may require admin credentials for some settings. The CGI commands documented in this file do not require authentication.

---

## Image Adjustment Commands

Beyond basic exposure (gain, shutter, iris), the camera has several image quality settings that can be adjusted via CGI. These are particularly relevant for environments with changing lighting — bright Sunday mornings vs. dim evening services vs. candlelight at Christmas/Easter.

### Detail Level

Controls the sharpness/edge enhancement of the image. Higher values make the image appear sharper but can introduce artifacts.

Command via **aw_cam**:
```
OSD:48:<HH>     → Set detail level (hex value)
```

### Chroma Level

Adjusts color saturation. Lower values move toward black-and-white, higher values produce more vivid colors.

Command via **aw_cam**:
```
OSD:49:<HH>     → Set chroma level (hex value)
```

### Scene Files

The camera can store multiple "scene files" — complete image profiles that include all picture settings (detail, chroma, matrix, pedestal, gain behavior, etc.). This is useful for saving different looks for different services or lighting conditions, then switching between them with a single command.

Command via **aw_cam**:
```
XSF:1            → Load Scene File 1
XSF:2            → Load Scene File 2
XSF:3            → Load Scene File 3
XSF:4            → Load Scene File 4
```

> Note: Scene file selection is listed as unsupported on the HE40 in the companion module's feature matrix. However, it may work on HE40 firmware versions that support it — worth testing. If it doesn't work, scene-specific adjustments would need to be made via individual commands (detail, chroma, pedestal, etc.) or through the camera's built-in web UI.

### Day/Night Mode

Some Panasonic PTZ cameras support an infrared night mode that removes the IR cut filter, allowing the camera to see in very low light (image becomes black-and-white). The HE40 may support this through the OSD menu system, though it's not exposed as a dedicated CGI command in the companion module. If available, it would typically be controlled through:

```
OSE:xx:yy        → Day/night mode toggle (exact parameters model-dependent)
```

This would need to be tested on the actual hardware or verified through the camera's web UI at `liturgystream2:8081/live/index.html`.

---

## Streaming Configuration

The camera's video output settings (resolution, encoding, bitrate) can be configured through the built-in web UI. While detailed encoding parameters are typically set once during installation, here are the relevant CGI paths for querying the current configuration:

### Current Video Format

```
GET /live/camdata.html
```

The response includes video format information that can be used to verify the camera is outputting the expected resolution and frame rate.

### Streaming Endpoints

The camera outputs video in several formats simultaneously:

| Format | URL | Notes |
|--------|-----|-------|
| MJPEG | `/cgi-bin/mjpeg` | Low latency, no audio, moderate bandwidth |
| RTSP | `rtsp://<camera-ip>/MediaInput/h264/stream_1` | H.264, full quality, includes audio |
| HLS | Via external encoder | Not native to camera; our setup uses sdgocstream:8086 |

The MJPEG stream is what we use for live preview in the control UI. The RTSP stream is typically what feeds the encoder/recorder for the actual broadcast.

---

## Sources

- [Bitfocus Companion Module (panasonic-ptz)](https://github.com/bitfocus/companion-module-panasonic-ptz) — actions.js, choices.js, models.js, index.js, variables.js
- [CUE Systems AW-HE40 Module (gist)](https://gist.github.com/teemupenttinen/b141a7342361b6af68dbf739c34eddb8)
- Panasonic "HD/4K Integrated Camera Interface Specifications" v1.12 (Apr 2020) — [official docs portal](https://eww.pass.panasonic.co.jp/pro-av/support/content/guide/EN/top.html)
