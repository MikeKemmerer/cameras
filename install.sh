#!/usr/bin/env bash
# install.sh — Installs the church camera control suite (single-camera control +
# multi-camera dashboard) onto an Apache/PHP host.
#
# First install: installs dependencies, deploys the web apps to /var/www/html,
# asks for the camera IPs / encoder / switcher, renders the Apache vhost and writes
# the JSON configs.
#
# Update (re-run on an existing install): deploys the web apps only. The Apache
# vhost and every site config (camera IPs, presets, sequences, per-camera preset
# files, credentials) are left exactly as they are.
#
# Interactive by default. When stdin is not a TTY (e.g. driven by a restore
# script) it runs non-interactively, reusing any existing/seeded config values.
#
# Usage:
#   sudo ./install.sh                  first install, or update an existing one
#   sudo ./install.sh --reconfigure    also re-ask the settings and merge them into the
#                                      existing JSON configs (other entries are kept);
#                                      the vhost is written beside the live one for review
#   sudo ./install.sh --rewrite-vhost  replace the Apache vhost from the template
#                                      (the old one is backed up and restored if Apache
#                                      rejects the new one)
#
# Environment overrides (skip the matching prompt):
#   ENCODER_HOSTNAME   Hostname/IP of the HLS encoder
#   SWITCHER_IP        IP of the video switcher (- to omit)
#   CAMERA_1_IP .. CAMERA_4_IP   Panasonic camera IPs
#   CAMERA_COUNT       Number of Panasonic cameras (1-4, default 4)
#   WEB_ROOT           Deploy directory (default /var/www/html)
#
# Records the installed release in /etc/cameras/installed-version.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEB_ROOT="${WEB_ROOT:-/var/www/html}"
VHOST_EXAMPLE="$SCRIPT_DIR/sites-enabled/000-default.conf.example"
VHOST_TARGET="${VHOST_TARGET:-/etc/apache2/sites-available/000-default.conf}"
VERSION_MANIFEST="${VERSION_MANIFEST:-/etc/cameras/installed-version.json}"
STAMP="$(date +%Y%m%d-%H%M%S)"

RECONFIGURE=0
REWRITE_VHOST=0
for arg in "$@"; do
    case "$arg" in
        --reconfigure)   RECONFIGURE=1 ;;
        --rewrite-vhost) REWRITE_VHOST=1 ;;
        -h|--help)       sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
    esac
done

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
EXISTING_CAM_CFG="$WEB_ROOT/multicamera/config/cameras.json"
CAMCTL_CFG="$WEB_ROOT/cameracontrol/config.json"
# Decided before deploying, which never creates these files.
FRESH_INSTALL=1
[[ -f "$EXISTING_CAM_CFG" || -f "$CAMCTL_CFG" ]] && FRESH_INSTALL=0

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
    --exclude='camera[0-9]*.json'
    --exclude='onvif-credentials.php'
    --exclude='images/'
    --exclude='captures/'
    --exclude='thumbnails/'
    --exclude='drivers/'
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
install -d "$WEB_ROOT/cameracontrol/images" "$WEB_ROOT/cameracontrol/captures" \
           "$WEB_ROOT/multicamera/thumbnails" "$WEB_ROOT/multicamera/config"
seed_from_example "$WEB_ROOT/cameracontrol/presets.json"   "$SCRIPT_DIR/cameracontrol/presets.example.json"
seed_from_example "$WEB_ROOT/cameracontrol/sequences.json" "$SCRIPT_DIR/cameracontrol/sequences.example.json"
for f in "$SCRIPT_DIR"/multicamera/config/camera[0-9]*.json; do
    if [[ -f "$f" ]]; then
        seed_from_example "$WEB_ROOT/multicamera/config/$(basename "$f")" "$f"
    fi
done

backup() {
    if [[ -f "$1" ]]; then
        cp -p "$1" "$1.bak-$STAMP"
        echo "    Backed up $1 -> $1.bak-$STAMP"
    fi
}

if [[ $FRESH_INSTALL -eq 0 && $RECONFIGURE -eq 0 && $REWRITE_VHOST -eq 0 ]]; then
    echo "==> Existing install: keeping the Apache vhost and all site configs"
    echo "    (use --reconfigure to change camera settings, --rewrite-vhost to replace the vhost)"
else
# ── Step 3: Gather site-specific settings ────────────────────────────
# Pre-seed defaults from any existing live configs so restores / re-runs keep
# the current values. cameras.json entries may be objects or plain IP strings.
default_cam_ip() {
    local idx="$1" ip=""
    if [[ -f "$EXISTING_CAM_CFG" ]]; then
        ip=$(jq -r --arg i "$idx" '.cameras[$i] // empty | if type == "string" then . else (.ip // empty) end' \
            "$EXISTING_CAM_CFG" 2>/dev/null || true)
    fi
    if [[ -z "$ip" && "$idx" == 1 && -f "$CAMCTL_CFG" ]]; then
        ip=$(jq -r '.camera_ip // empty' "$CAMCTL_CFG" 2>/dev/null || true)
    fi
    printf '%s' "$ip"
}
default_cam_count() {
    local n=0
    if [[ -f "$EXISTING_CAM_CFG" ]]; then
        n=$(jq '[.cameras // {} | to_entries[] | select(.key | test("^[1-4]$"))
                 | select((.value | type) == "string" or (.value.type // "panasonic") == "panasonic")] | length' \
            "$EXISTING_CAM_CFG" 2>/dev/null || echo 0)
    fi
    [[ "$n" =~ ^[1-4]$ ]] || n=4
    printf '%s' "$n"
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
ask CAMERA_COUNT "Number of Panasonic cameras (1-4)" "$(default_cam_count)"
[[ "$CAMERA_COUNT" =~ ^[1-4]$ ]] || CAMERA_COUNT=4

declare -a CAM_IPS=()
for i in $(seq 1 "$CAMERA_COUNT"); do
    var="CAMERA_${i}_IP"
    def="$(default_cam_ip "$i")"
    [[ -z "$def" ]] && def="192.168.1.$((199 + i))"
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
if [[ ! -f "$VHOST_EXAMPLE" ]]; then
    echo "Error: missing $VHOST_EXAMPLE" >&2
    exit 1
fi
RENDERED="$(cat "$VHOST_EXAMPLE")"
RENDERED="${RENDERED//\/var\/www\/html/$WEB_ROOT}"
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

# Only Debian's stock vhost (no camera routes) is replaced without being asked.
VHOST_IS_OURS=0
[[ -f "$VHOST_TARGET" ]] && grep -q '/cam/ptz' "$VHOST_TARGET" && VHOST_IS_OURS=1
if [[ $REWRITE_VHOST -eq 1 || $VHOST_IS_OURS -eq 0 ]]; then
    echo "==> Writing Apache vhost"
    backup "$VHOST_TARGET"
    printf '%s\n' "$RENDERED" > "$VHOST_TARGET"
    if ! apache2ctl configtest; then
        if [[ -f "$VHOST_TARGET.bak-$STAMP" ]]; then
            cp -p "$VHOST_TARGET.bak-$STAMP" "$VHOST_TARGET"
            echo "Error: Apache rejected the new vhost; restored the previous one." >&2
        else
            echo "Error: Apache rejected the new vhost $VHOST_TARGET." >&2
        fi
        exit 1
    fi
else
    printf '%s\n' "$RENDERED" > "$VHOST_TARGET.cameras-new"
    echo "==> Keeping the existing Apache vhost; the template with these settings is in"
    echo "    $VHOST_TARGET.cameras-new"
    echo "    Compare: diff $VHOST_TARGET $VHOST_TARGET.cameras-new"
    echo "    Apply:   sudo ./install.sh --rewrite-vhost (or merge the changes by hand)"
fi

# ── Step 5: Write site JSON configs ──────────────────────────────────
# Existing files are merged: only the camera IPs change, names, extra cameras
# (e.g. ONVIF) and any other keys are kept.
echo "==> Writing camera configs"
TMP_JSON="$(mktemp)"
backup "$CAMCTL_CFG"
jq --arg ip "$CAMERA_1_IP" '.camera_ip = $ip' "$CAMCTL_CFG" 2>/dev/null > "$TMP_JSON" \
    || jq -n --arg ip "$CAMERA_1_IP" '{camera_ip: $ip}' > "$TMP_JSON"
install -m 644 "$TMP_JSON" "$CAMCTL_CFG"

backup "$EXISTING_CAM_CFG"
CAMERAS_JSON="$(jq -c '.' "$EXISTING_CAM_CFG" 2>/dev/null || echo '{}')"
for i in $(seq 1 "$CAMERA_COUNT"); do
    var="CAMERA_${i}_IP"
    CAMERAS_JSON=$(jq -c \
        --arg k "$i" --arg ip "${!var}" --arg name "Camera $i" --arg cfg "camera${i}.json" \
        '.cameras[$k] = ({type: "panasonic", name: $name, config: $cfg}
                         + ((.cameras[$k] // {}) | if type == "string" then {} else . end)
                         + {ip: $ip})' \
        <<<"$CAMERAS_JSON")
    # The controller loads presets from this file; start an empty one if it's missing.
    cfg_file="$(jq -r --arg k "$i" '.cameras[$k].config // empty' <<<"$CAMERAS_JSON")"
    if [[ "$cfg_file" =~ ^[A-Za-z0-9._-]+\.json$ && ! -f "$WEB_ROOT/multicamera/config/$cfg_file" ]]; then
        echo '{"presets": [], "sequences": []}' | jq . > "$WEB_ROOT/multicamera/config/$cfg_file"
        echo "    Created empty $cfg_file for camera $i."
    fi
done
jq . <<<"$CAMERAS_JSON" > "$TMP_JSON"
install -m 644 "$TMP_JSON" "$EXISTING_CAM_CFG"
rm -f "$TMP_JSON"
fi

# ── Step 6: Permissions + enable site ────────────────────────────────
echo "==> Setting permissions and reloading Apache"
chown -R www-data:www-data "$WEB_ROOT/cameracontrol" "$WEB_ROOT/multicamera"
a2ensite 000-default >/dev/null 2>&1 || true
apache2ctl configtest
systemctl reload apache2

# ── Step 7: Record the installed release ─────────────────────────────
# Release tarballs carry RELEASE.json; a git checkout falls back to VERSION + HEAD.
VERSION=$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")
TAG="v$VERSION"
COMMIT=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
if [[ -r "$SCRIPT_DIR/RELEASE.json" ]]; then
    VERSION=$(jq -r '.version // empty' "$SCRIPT_DIR/RELEASE.json")
    TAG=$(jq -r '.tag // empty' "$SCRIPT_DIR/RELEASE.json")
    COMMIT=$(jq -r '.commit // empty' "$SCRIPT_DIR/RELEASE.json")
fi
install -d -m 755 "$(dirname "$VERSION_MANIFEST")"
jq -n --arg version "${VERSION:-unknown}" --arg tag "${TAG:-unknown}" --arg commit "${COMMIT:-unknown}" \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{version: $version, tag: $tag, commit: $commit, installed_at: $installed_at}' > "$VERSION_MANIFEST"
chmod 644 "$VERSION_MANIFEST"

echo ""
echo "Done. Camera control suite installed ($TAG)."
echo "  Single camera:  http://localhost/cameracontrol/"
echo "  Multi camera:   http://localhost/multicamera/"
echo "  Apache vhost:   $VHOST_TARGET"
