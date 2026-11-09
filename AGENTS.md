# AI Agent Instructions — cameras

## Project Overview

Browser-based PTZ control for Panasonic AW-series cameras. Includes single-camera control, multi-camera dashboard, ONVIF proxy, image capture gallery, and programmable preset sequences.

## Architecture

| Directory | Purpose |
|-----------|---------|
| `cameracontrol/` | Single-camera UI: presets, sequences, captures, PTZ |
| `multicamera/` | Multi-camera dashboard with per-camera controller iframes |
| `sites-enabled/` | Apache templates: `cameras.conf.example` (routes, included from the port-80 site) and `cameras-webui.conf.example` |

## Key Conventions

- **No build tools** — plain HTML/CSS/JS served directly by Apache + PHP
- **Config files**: JSON in `config/` or root (e.g., `presets.json`, `cameras.json`)
- **Camera API**: Panasonic CGI commands — see [AW-HE40-API-REFERENCE.md](cameracontrol/AW-HE40-API-REFERENCE.md); other brands in [CAMERA-BRAND-COMPARISON.md](cameracontrol/CAMERA-BRAND-COMPARISON.md)
- **Releases**: `VERSION` + `v*` tags; `.github/workflows/release.yml` publishes; `install.sh` writes `/etc/cameras/installed-version.json`
- **Docs**: no real IPs or host names — use `192.168.1.x` / `<control-server>` placeholders
- **PHP**: Minimal endpoints, no frameworks, server-side validation only
- **Apache**: Requires `mod_proxy`, `mod_rewrite`, `php-zip`, `ffmpeg`

## Setup

Recommended — run the interactive installer (deps, deploy, vhost, configs):

```bash
sudo ./install.sh
```

It is idempotent and prompts for the camera IPs, encoder hostname, and switcher IP
on a first install. On an existing install it deploys code and regenerates
`/etc/apache2/cameras/cameras.conf`; site configs are kept (`--reconfigure` merges new
settings into the JSON configs). Apache: the installer owns `cameras.conf` and
`cameras-webui.conf` and only adds one `Include` line to `000-default.conf`; any
change is rolled back if `apache2ctl configtest` fails. When stdin is
not a TTY it runs non-interactively, reusing existing/seeded configs — this is how the
church-monitoring restore flow drives it.

Manual equivalent:

```bash
sudo apt install apache2 php php-zip php-curl php-xml ffmpeg
sudo a2enmod proxy proxy_http rewrite
# Copy sites-enabled/cameras.conf.example → /etc/apache2/cameras/cameras.conf, fill in, and
#   add "Include /etc/apache2/cameras/cameras.conf" inside <VirtualHost *:80>
# Copy cameracontrol/presets.example.json → presets.json
# Copy multicamera/config/cameras.example.json → cameras.json
```

## Key Files

- `cameracontrol/index.htm` — Main single-camera UI (large all-in-one HTML/CSS/JS)
- `cameracontrol/ptz-control.htm` — Manual PTZ and preset creation
- `multicamera/controller.html` — Per-camera controller (embedded in dashboard)
- `multicamera/onvif-proxy.php` — ONVIF SOAP with WS-Security digest auth

## Terminal Notes

- `rm`, `git branch -D`, `curl` blocked by policy
- WSL path: `/mnt/c/Users/michael.kemmerer/Desktop/cameras/`
