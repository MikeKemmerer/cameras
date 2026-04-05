# Panasonic AW-HE40 CGI API Reference

Quick reference for HTTP CGI commands supported by the AW-HE40 (and related HE-series cameras). All commands discovered from Panasonic's protocol specification and the [bitfocus companion module](https://github.com/bitfocus/companion-module-panasonic-ptz).

## Endpoints

| Endpoint | Purpose | Auth Required |
|----------|---------|---------------|
| `/cgi-bin/aw_ptz` | PTZ, zoom, focus, iris, presets, power, tally | No |
| `/cgi-bin/aw_cam` | Camera settings (gain, shutter, OSD, scene, white balance) | No |
| `/cgi-bin/mjpeg` | MJPEG live stream | No |
| `/cgi-bin/sdctrl` | SD card recording control | No |

### Request Format

**aw_ptz** commands use `#` prefix (URL-encoded as `%23`):
```
GET /cgi-bin/aw_ptz?cmd=%23<COMMAND>&res=1
```

**aw_cam** commands use plain text (no `#`):
```
GET /cgi-bin/aw_cam?cmd=<COMMAND>&res=1
```

### Proxy Paths (our Apache config)

| Proxy Path | Target |
|------------|--------|
| `/cam/ptz` | `http://172.25.0.200/cgi-bin/aw_ptz` |
| `/cam/cam` | `http://172.25.0.200/cgi-bin/aw_cam` |
| `/mjpeg` | `http://172.25.0.200/cgi-bin/mjpeg` |

---

## Pan/Tilt — Continuous Movement

Command: `#PTS<PP><TT>` via **aw_ptz**

Combined pan+tilt speed command. Each axis is a 2-digit value (01–99) where **50 = stopped**.

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

**Shorthand aliases** (single-axis):
```
#P<SS>       → Pan only (tilt stays at 50)
#T<SS>       → Tilt only (pan stays at 50)
```

### Absolute Position

Command: `#APC<PPPP><TTTT>` via **aw_ptz**

Move to an absolute pan/tilt position. Each value is 4-digit hex (0000–FFFF).

```
#APC7FFF7FFF → Home position (center)
```

---

## Zoom

Command: `#Z<SS>` via **aw_ptz**

Continuous zoom. SS is a 2-digit value (01–99), 50 = stop.

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

**UI speed mapping** (companion module uses speed 1–49 offset from center):
- Zoom in at speed N: `#Z` + (50 + N) → e.g. speed 25 = `#Z75`
- Zoom out at speed N: `#Z` + (50 - N) → e.g. speed 25 = `#Z25`

---

## Focus

### Continuous Focus

Command: `#F<SS>` via **aw_ptz**

Manual focus drive. SS is a 2-digit value (01–99), 50 = stop.

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

Command via **aw_ptz**:
```
#D11         → Auto Focus ON
#D10         → Manual Focus (Auto Focus OFF)
```

### One Touch Auto Focus (OTAF)

Command via **aw_cam**:
```
OSE:69:1     → Trigger one-time auto focus
```
Camera auto-focuses once then returns to manual mode.

---

## Iris

### Manual Iris Control

Command: `#I<HH>` via **aw_ptz**

Set iris position. HH is a 2-digit value (00–99, decimal string representation).

```
#I00         → Iris fully closed
#I99         → Iris fully open
#I50         → Iris at midpoint
```

### Auto/Manual Iris Mode

Command via **aw_ptz**:
```
#D30         → Auto Iris ON
#D31         → Manual Iris (Auto Iris OFF)
```

---

## Presets

### Recall Preset

Command: `#R<NN>` via **aw_ptz**

NN is 2-digit zero-padded, **0-indexed** (preset 1 = 00, preset 2 = 01, ..., preset 100 = 99).

```
#R00         → Recall preset 1
#R03         → Recall preset 4
#R21         → Recall preset 22
```

### Save Preset

Command: `#M<NN>` via **aw_ptz**

Same indexing as recall (0-indexed).

```
#M00         → Save current position as preset 1
#M03         → Save current position as preset 4
```

### Preset Recall Speed

Command: `#UPVS<NNN>` via **aw_ptz**

Controls how fast the camera moves when recalling a preset. This is a **global camera setting** — once set, all subsequent preset recalls use this speed until changed.

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

### Preset Mode (what gets recalled)

Command via **aw_cam**:
```
OSE:71:0     → Mode A — PTZ + Iris + White Balance/Color
OSE:71:1     → Mode B — PTZ + Iris
OSE:71:2     → Mode C — PTZ only
```

---

## Gain

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

Command via **aw_cam**: `OTP:<HHH>`

3-digit hex value, range 000–12C (0–300 decimal).

- Center (0.0): `096` (150 decimal)
- Each unit = 1/15 of a step
- Range: -10.0 to +10.0

```
OTP:096      → Pedestal at 0.0 (center)
OTP:000      → Pedestal at minimum (-10.0)
OTP:12C      → Pedestal at maximum (+10.0)
```

---

## Color Bars

Commands via **aw_cam**:

```
DCB:1        → Enable color bars
DCB:0        → Disable color bars

OSD:BA:1     → Color bar Type 1
OSD:BA:0     → Color bar Type 2

OSD:BE:1     → Title overlay ON
OSD:BE:0     → Title overlay OFF
```

---

## Power

Command via **aw_ptz**:
```
#O1          → Power ON
#O0          → Power OFF (standby)
```

---

## Tally Light

Command via **aw_ptz** (legacy, HE40 series):
```
#DA1         → Red tally ON
#DA0         → Red tally OFF
```

> Note: HE40 only has red tally. Newer models (UE150, etc.) use `TLR:1`/`TLR:0` (red) and `TLG:1`/`TLG:0` (green) via aw_cam.

---

## Installation Position

Command via **aw_ptz**:
```
#INS0        → Desktop (upright)
#INS1        → Hanging (inverted/ceiling mount)
```

---

## SD Card Recording

Command via dedicated endpoint (no auth, no `#` prefix):
```
GET /cgi-bin/sdctrl?save=start    → Start recording
GET /cgi-bin/sdctrl?save=end      → Stop recording
```

---

## HE40-Series Feature Matrix

Features confirmed available on the AW-HE40 (HE40 series):

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

## Implementation Notes

### JavaScript Examples

**Send aw_ptz command** (existing pattern in index.htm):
```javascript
fetch('/cam/ptz?cmd=%23R03&res=1');           // recall preset 4
fetch('/cam/ptz?cmd=%23UPVS550&res=1');       // set speed to 12
fetch('/cam/ptz?cmd=%23PTS5050&res=1');        // stop pan/tilt
fetch('/cam/ptz?cmd=%23D11&res=1');            // auto focus on
```

**Send aw_cam command** (uses `/cam/cam` proxy):
```javascript
fetch('/cam/cam?cmd=OSE:69:1&res=1');         // one-touch auto focus
fetch('/cam/cam?cmd=OGU:80&res=1');           // auto gain
fetch('/cam/cam?cmd=OSE:71:0&res=1');         // preset mode A
```

### Saving New Presets from the Web UI

To add a "save preset" feature:
1. Move camera to desired position (via PTZ joystick or manual movement)
2. Send `#M<NN>` to save the current position as preset NN
3. Capture a thumbnail (screenshot of MJPEG frame via canvas)
4. Update presets.json with the new entry

### Pan/Tilt Joystick

For a virtual joystick, map X/Y coordinates to PTS values:
- X: -1.0 (full left) → 01, 0 (center) → 50, +1.0 (full right) → 99
- Y: -1.0 (full down) → 01, 0 (center) → 50, +1.0 (full up) → 99
- Send `#PTS<XX><YY>` while dragging, `#PTS5050` on release
- Recommended: throttle to ~10 commands/sec max

---

## Sources

- [Bitfocus Companion Module (panasonic-ptz)](https://github.com/bitfocus/companion-module-panasonic-ptz) — actions.js, choices.js, models.js
- [CUE Systems AW-HE40 Module (gist)](https://gist.github.com/teemupenttinen/b141a7342361b6af68dbf739c34eddb8)
- Panasonic "HD/4K Integrated Camera Interface Specifications" v1.12 (Apr 2020) — [official docs portal](https://eww.pass.panasonic.co.jp/pro-av/support/content/guide/EN/top.html)
