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
    "1": "192.168.1.200",
    "2": "192.168.1.201",
    "3": "192.168.1.202",
    "4": "192.168.1.203"
  }
}
```

### 2. Apache Reverse Proxy

Copy and edit the example Apache config:

```bash
cp sites-enabled/000-default.conf.example sites-enabled/000-default.conf
```

Replace all placeholder IPs (`CAMERA_1_IP`, `ENCODER_HOSTNAME`, `SWITCHER_IP`, etc.) with your real infrastructure addresses.

### 3. Preset Thumbnails

Place preset thumbnail images in `multicamera/thumbnails/<camera_number>/`. Preset definitions live in `multicamera/config/camera<N>.json`.

## Usage

- **Multi-camera view**: Open `multicamera/index.htm`
- **Single camera control**: Open `multicamera/controller.html?cam=1`
- **Legacy single-camera UI**: Open `cameracontrol/index.htm`

## License

MIT — see [LICENSE](LICENSE).
