#!/usr/bin/env bash
# install.sh — Installs the church camera control suite (single-camera control +
# multi-camera dashboard) onto an Apache/PHP host.
#
# Idempotent and re-runnable. Installs dependencies, deploys the web apps to
# /var/www/html, then configures site-specific camera IPs / encoder / switcher by
# rendering the Apache vhost and writing the local JSON configs.
#
# Interactive by default. When stdin is not a TTY (e.g. driven by a restore
# script) it runs non-interactively, reusing any existing/seeded config values.
#
# Usage:
#   sudo ./install.sh
#
# Environment overrides (skip the matching prompt):
#   ENCODER_HOSTNAME   Hostname/IP of the HLS encoder
#   SWITCHER_IP        IP of the video switcher (blank to omit)
#   CAMERA_1_IP .. CAMERA_4_IP   Panasonic camera IPs
#   CAMERA_COUNT       Number of Panasonic cameras (1-4, default 4)
#   WEB_ROOT           Deploy directory (default /var/www/html)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEB_ROOT="${WEB_ROOT:-/var/www/html}"
VHOST_EXAMPLE="$SCRIPT_DIR/sites-enabled/000-default.conf.example"
VHOST_TARGET="/etc/apache2/sites-available/000-default.conf"

if [[ $EUID -ne 0 ]]; then
    echo "Error: this installer must be run as root (use sudo)." >&2
    exit 1
fi

INTERACTIVE=0
[[ -t 0 ]] && INTERACTIVE=1

# ask <var_name> <prompt> <default>
# Sets the named variable from an env override, an interactive prompt, or the
# provided default (in that order).
ask() {
    local __var="$1" __prompt="$2" __default="$3" __cur __reply
    __cur="${!__var:-}"
    if [[ -n "$__cur" ]]; then
        printf -v "$__var" '%s' "$__cur"
        return
    fi
    if [[ $INTERACTIVE -eq 1 ]]; then
        read -r -p "$__prompt [$__default]: " __reply
        [[ -z "$__reply" ]] && __reply="$__default"
        # Strip any embedded newlines to prevent config injection.
        __reply="${__reply//$'\n'/}"
        printf -v "$__var" '%s' "$__reply"
    else
        printf -v "$__var" '%s' "$__default"
    fi
}

# ── Step 1: Dependencies ─────────────────────────────────────────────
echo "==> Installing system dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2 php php-zip php-curl php-xml ffmpeg rsync jq libapache2-mod-php

echo "==> Enabling Apache modules"
a2enmod proxy proxy_http rewrite headers >/dev/null 2>&1 || true

# ── Step 2: Deploy web applications ──────────────────────────────────
echo "==> Deploying web apps to $WEB_ROOT"
install -d "$WEB_ROOT"

# Site-specific files are deployed/seeded separately below, so exclude them here
# to avoid clobbering live configs, secrets, presets, and captured images.
DEPLOY_EXCLUDES=(
    --exclude='.git'
    --exclude='config.json'
    --exclude='presets.json'
    --exclude='sequences.json'
    --exclude='cameras.json'
    --exclude='onvif-credentials.php'
    --exclude='images/'
    --exclude='captures/'
    --exclude='thumbnails/'
)
rsync -a "${DEPLOY_EXCLUDES[@]}" "$SCRIPT_DIR/cameracontrol/" "$WEB_ROOT/cameracontrol/"
rsync -a "${DEPLOY_EXCLUDES[@]}" "$SCRIPT_DIR/multicamera/" "$WEB_ROOT/multicamera/"

# Seed user-data files from their examples if they don't exist yet.
seed_from_example() {
    local target="$1" example="$2"
    if [[ ! -f "$target" && -f "$example" ]]; then
        cp "$example" "$target"
        echo "    Seeded $(basename "$target") from example."
    fi
}
seed_from_example "$WEB_ROOT/cameracontrol/presets.json"   "$SCRIPT_DIR/cameracontrol/presets.example.json"
seed_from_example "$WEB_ROOT/cameracontrol/sequences.json" "$SCRIPT_DIR/cameracontrol/sequences.example.json"
install -d "$WEB_ROOT/cameracontrol/images" "$WEB_ROOT/cameracontrol/captures" \
           "$WEB_ROOT/multicamera/thumbnails" "$WEB_ROOT/multicamera/config"

# ── Step 3: Gather site-specific settings ────────────────────────────
# Pre-seed defaults from any existing live configs so restores / re-runs keep
# the current values.
EXISTING_CAM_CFG="$WEB_ROOT/multicamera/config/cameras.json"
default_cam_ip() {
    local idx="$1"
    if [[ -f "$EXISTING_CAM_CFG" ]]; then
        jq -r --arg i "$idx" '.cameras[$i].ip // empty' "$EXISTING_CAM_CFG" 2>/dev/null || true
    fi
}
default_encoder() {
    if [[ -f "$VHOST_TARGET" ]]; then
        grep -oP 'ProxyPass\s+/hls/\s+http://\K[^:/]+' "$VHOST_TARGET" 2>/dev/null | head -1 || true
    fi
}
default_switcher() {
    if [[ -f "$VHOST_TARGET" ]]; then
        grep -oP 'ProxyPass\s+/multicamera/switcher\s+http://\K[^/]+' "$VHOST_TARGET" 2>/dev/null | head -1 || true
    fi
}

echo "==> Configuring cameras"
ask CAMERA_COUNT "Number of Panasonic cameras (1-4)" "4"
[[ "$CAMERA_COUNT" =~ ^[1-4]$ ]] || CAMERA_COUNT=4

declare -a CAM_IPS=()
for i in $(seq 1 "$CAMERA_COUNT"); do
    var="CAMERA_${i}_IP"
    def="$(default_cam_ip "$i")"
    [[ -z "$def" ]] && def="172.25.0.$((199 + i))"
    ask "$var" "Camera $i IP address" "$def"
    CAM_IPS[$i]="${!var}"
done
# Ensure all four placeholders have a value for vhost rendering (reuse cam 1 for
# any unconfigured slots so no placeholder leaks into the live config).
for i in 1 2 3 4; do
    var="CAMERA_${i}_IP"
    if [[ -z "${!var:-}" ]]; then
        printf -v "$var" '%s' "${CAM_IPS[1]}"
    fi
done

ask ENCODER_HOSTNAME "HLS encoder hostname/IP" "$(default_encoder)"
[[ -z "$ENCODER_HOSTNAME" ]] && ENCODER_HOSTNAME="encoder"
ask SWITCHER_IP "Video switcher IP (- to omit)" "$(default_switcher)"
[[ "$SWITCHER_IP" == "-" ]] && SWITCHER_IP=""

# ── Step 4: Render the Apache vhost ──────────────────────────────────
echo "==> Writing Apache vhost"
if [[ ! -f "$VHOST_EXAMPLE" ]]; then
    echo "Error: missing $VHOST_EXAMPLE" >&2
    exit 1
fi
RENDERED="$(cat "$VHOST_EXAMPLE")"
RENDERED="${RENDERED//ENCODER_HOSTNAME/$ENCODER_HOSTNAME}"
RENDERED="${RENDERED//CAMERA_1_IP/$CAMERA_1_IP}"
RENDERED="${RENDERED//CAMERA_2_IP/$CAMERA_2_IP}"
RENDERED="${RENDERED//CAMERA_3_IP/$CAMERA_3_IP}"
RENDERED="${RENDERED//CAMERA_4_IP/$CAMERA_4_IP}"
if [[ -n "$SWITCHER_IP" ]]; then
    RENDERED="${RENDERED//SWITCHER_IP/$SWITCHER_IP}"
else
    # Drop the switcher proxy lines entirely when no switcher is configured.
    RENDERED="$(printf '%s\n' "$RENDERED" | grep -v 'SWITCHER_IP')"
fi
printf '%s\n' "$RENDERED" > "$VHOST_TARGET"

# ── Step 5: Write site JSON configs ──────────────────────────────────
echo "==> Writing camera configs"
printf '{\n  "camera_ip": "%s"\n}\n' "$CAMERA_1_IP" > "$WEB_ROOT/cameracontrol/config.json"

CAMERAS_JSON='{}'
for i in $(seq 1 "$CAMERA_COUNT"); do
    var="CAMERA_${i}_IP"
    CAMERAS_JSON=$(echo "$CAMERAS_JSON" | jq \
        --arg k "$i" --arg ip "${!var}" --arg name "Camera $i" --arg cfg "camera${i}.json" \
        '. + {($k): {ip: $ip, type: "panasonic", name: $name, config: $cfg}}')
done
echo "{\"cameras\": $CAMERAS_JSON}" | jq . > "$EXISTING_CAM_CFG"

# ── Step 6: Permissions + enable site ────────────────────────────────
echo "==> Setting permissions and enabling site"
chown -R www-data:www-data "$WEB_ROOT/cameracontrol" "$WEB_ROOT/multicamera"
a2ensite 000-default >/dev/null 2>&1 || true
apache2ctl configtest
systemctl reload apache2

echo ""
echo "Done. Camera control suite installed."
echo "  Single camera:  http://localhost/cameracontrol/"
echo "  Multi camera:   http://localhost/multicamera/"
echo "  Apache vhost:   $VHOST_TARGET"
