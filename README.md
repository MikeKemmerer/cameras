# cameras

Browser-based PTZ camera control console for Panasonic AW-series cameras, with multi-camera preset management and a video switcher integration.

## Features

- Multi-camera dashboard with per-camera preset grids
- MJPEG live preview streams
- One-click PTZ preset recall with visual feedback
- Crestron-compatible video switcher integration
- Thumbnail previews for each preset position
- Responsive grid layout adapts to screen size
- Dark broadcast-console UI theme

## Setup

### Automated install (recommended)

Run the interactive installer, which installs dependencies, deploys both web apps
to `/var/www/html`, sets up the Apache camera routes, and writes the camera configs:

```bash
sudo ./install.sh
```

It prompts for the camera IPs, encoder hostname, switcher IP, and the port for the
camera's own web admin page. The manual steps below are the equivalent if you
prefer to configure things by hand.

**Apache** — the installer doesn't rewrite your site config. All camera routes live in
`/etc/apache2/cameras/cameras.conf`, which the installer owns and regenerates on every
run. The port-80 site (`000-default.conf`) only gets one line inside its
`<VirtualHost *:80>` block, added once and checked on every run:

```apache
Include /etc/apache2/cameras/cameras.conf
```

The camera's web admin page is proxied by its own site,
`/etc/apache2/sites-available/cameras-webui.conf` (default port 8081). Every Apache
change is checked with `apache2ctl configtest`; if Apache rejects it, all of the
installer's Apache changes are rolled back. The settings behind these files are
saved in `/etc/cameras/settings.json`.

**Updating** — re-running `sudo ./install.sh` deploys the new web app files and
regenerates `cameras.conf` from the saved settings. Camera configs, presets, sequences,
per-camera preset files, captures and credentials are never overwritten.

| Command | What it changes |
|---------|-----------------|
| `sudo ./install.sh` | Code + `cameras.conf` (on an existing install, no questions asked) |
| `sudo ./install.sh --reconfigure` | Re-asks the settings, merges the camera IPs into the existing JSON configs (names, extra/ONVIF cameras and other keys are kept; backups are made) and regenerates the Apache files |

Installs made before `cameras.conf` existed are moved over by the next update: the
settings are read from the existing configs and site, `cameras.conf` is written and the
`Include` line added. Camera routes still written directly in `000-default.conf` come
before the `Include` and keep working until they are commented out; the installer
points them out.

It runs non-interactively (reusing existing values) when stdin is not a TTY.

### Prerequisites

**System packages:**

```bash
sudo apt install apache2 php php-zip php-curl php-xml ffmpeg
```

| Package | Required By | Purpose |
|---------|-------------|---------|
| `apache2` | All | Web server with reverse proxy |
| `php` | All PHP endpoints | Server-side scripting (includes `php-json` and `php-fileinfo`) |
| `php-zip` | `cameracontrol/zip-captures.php` | ZipArchive for multi-image download |
| `php-curl` | `multicamera/onvif-proxy.php`, `multicamera/capture-image.php` | HTTP requests to ONVIF cameras |
| `php-xml` | `multicamera/onvif-proxy.php` | Parsing ONVIF SOAP responses |
| `ffmpeg` | `cameracontrol/capture-image.php`, `multicamera/capture-image.php` | Extracting JPEG frames from MJPEG streams |

**Apache modules:**

```bash
sudo a2enmod proxy proxy_http rewrite
sudo systemctl restart apache2
```

**External JS (loaded via CDN, no install needed):**

- [HLS.js](https://cdn.jsdelivr.net/npm/hls.js@latest) — HLS video playback

### 1. Camera IP Configuration

Copy the example config and fill in your camera IPs:

```bash
cp multicamera/config/cameras.example.json multicamera/config/cameras.json
```

Edit `cameras.json` with your camera addresses:
```json
{
  "cameras": {
    "1": { "ip": "192.168.1.200", "type": "panasonic", "name": "Camera 1", "config": "camera1.json" },
    "2": { "ip": "192.168.1.201", "type": "panasonic", "name": "Camera 2", "config": "camera2.json" },
    "3": { "ip": "192.168.1.202", "type": "panasonic", "name": "Camera 3", "config": "camera3.json" },
    "4": { "ip": "192.168.1.203", "type": "panasonic", "name": "Camera 4", "config": "camera4.json" }
  }
}
```

### 2. Apache Reverse Proxy

Copy the routes template, replace the placeholders (`CAMERA_1_IP`, `ENCODER_HOSTNAME`,
`SWITCHER_IP`, etc.) and include it from your port-80 site:

```bash
sudo install -d /etc/apache2/cameras
sudo cp sites-enabled/cameras.conf.example /etc/apache2/cameras/cameras.conf
# then, inside <VirtualHost *:80> in /etc/apache2/sites-available/000-default.conf:
#     Include /etc/apache2/cameras/cameras.conf
```

For the camera's web admin page, do the same with `sites-enabled/cameras-webui.conf.example`
(as `/etc/apache2/sites-available/cameras-webui.conf`, then `sudo a2ensite cameras-webui`).

### 3. Preset Thumbnails

Place preset thumbnail images in `multicamera/thumbnails/<camera_number>/`. Preset definitions live in `multicamera/config/camera<N>.json`.

## Usage

- **Multi-camera view**: Open `multicamera/index.htm`
- **Single camera control**: Open `multicamera/controller.html?cam=1`
- **Legacy single-camera UI**: Open `cameracontrol/index.htm`

## Camera Documentation

- [AW-HE40-API-REFERENCE.md](cameracontrol/AW-HE40-API-REFERENCE.md) — Panasonic AW-HE40 CGI commands, including day/night (IR-cut) commands verified on the camera
- [CAMERA-BRAND-COMPARISON.md](cameracontrol/CAMERA-BRAND-COMPARISON.md) — how other PTZ brands (PTZOptics, Sony, AVer, Marshall, ONVIF) would fit this UI, with a reference page for each
- [cameracontrol/drivers/](cameracontrol/drivers/README.md) — groundwork VISCA encoder for a future second brand; not used by the UI and not deployed by `install.sh`

## Releases

`VERSION` holds the version being prepared. After a release is merged to `master`, push a
SemVer tag such as `v1.0.0`; the **Publish Release** workflow checks it matches `VERSION`
and publishes a GitHub release with a source tarball that includes `RELEASE.json`. Tags with
a suffix such as `v1.1.0-rc.1` become prereleases.

`install.sh` records the installed release, commit and time in
`/etc/cameras/installed-version.json`.

## License

MIT — see [LICENSE](LICENSE).
