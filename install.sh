#!/usr/bin/env bash
# install.sh — Installs the church camera control suite (single-camera control +
# multi-camera dashboard) onto an Apache/PHP host.
#
# Apache: all camera routes live in /etc/apache2/cameras/cameras.conf, which this
# installer owns and regenerates on every run. The port-80 site gets a single
# "Include" line for it (added once, verified every run); nothing else in that site
# is changed. The camera's own web admin page can be proxied on a separate port
# (sites-available/cameras-webui.conf). Every Apache change is checked with
# apache2ctl configtest and rolled back if Apache rejects it.
#
# First install: installs dependencies, deploys the web apps, asks for the camera
# IPs / encoder / switcher / web-admin port and writes the configs.
#
# Update (re-run on an existing install): deploys the web apps and regenerates
# cameras.conf from the saved settings. Site configs (camera IPs, presets,
# sequences, per-camera preset files, credentials) are left exactly as they are.
#
# Interactive by default. When stdin is not a TTY (e.g. driven by a restore
# script) it runs non-interactively, reusing any existing/seeded config values.
#
# Usage:
#   sudo ./install.sh                first install, or update an existing one
#   sudo ./install.sh --reconfigure  re-ask the settings and merge them into the
#                                    existing JSON configs (other entries are kept)
#
# Environment overrides (skip the matching prompt):
#   ENCODER_HOSTNAME   Hostname/IP of the HLS encoder
#   SWITCHER_IP        IP of the video switcher (- to omit)
#   CAMERA_1_IP .. CAMERA_4_IP   Panasonic camera IPs
#   CAMERA_COUNT       Number of Panasonic cameras (1-4, default 4)
#   CAMERA_WEBUI_PORT  Port that proxies camera 1's web admin page (- to omit)
#   WEB_ROOT           Deploy directory (default /var/www/html)
#
# Records the installed release in /etc/cameras/installed-version.json and the
# Apache settings in /etc/cameras/settings.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEB_ROOT="${WEB_ROOT:-/var/www/html}"
APACHE_DIR="${APACHE_DIR:-/etc/apache2}"
VHOST_TARGET="${VHOST_TARGET:-$APACHE_DIR/sites-available/000-default.conf}"
CAMERAS_CONF="$APACHE_DIR/cameras/cameras.conf"
WEBUI_SITE="$APACHE_DIR/sites-available/cameras-webui.conf"
ROUTES_TEMPLATE="$SCRIPT_DIR/sites-enabled/cameras.conf.example"
WEBUI_TEMPLATE="$SCRIPT_DIR/sites-enabled/cameras-webui.conf.example"
ETC_DIR="${CAMERAS_ETC:-/etc/cameras}"
VERSION_MANIFEST="$ETC_DIR/installed-version.json"
SETTINGS_FILE="$ETC_DIR/settings.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

RECONFIGURE=0
for arg in "$@"; do
    case "$arg" in
        --reconfigure)   RECONFIGURE=1 ;;
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

# Settings are only asked on a first install or with --reconfigure; otherwise the
# current values are reused silently.
ASK=0
[[ $FRESH_INSTALL -eq 1 || $RECONFIGURE -eq 1 ]] && ASK=1
[[ $ASK -eq 1 ]] || INTERACTIVE=0

# ── Step 3: Gather site-specific settings ────────────────────────────
# Defaults come from the current setup: settings.json, then the live configs, then
# (for installs made before cameras.conf existed) the routes in the port-80 site.
# cameras.json entries may be objects or plain IP strings.
setting() {
    [[ -f "$SETTINGS_FILE" ]] && jq -r --arg k "$1" 'if has($k) then (.[$k] | if . == "" then "-" else tostring end) else empty end' \
        "$SETTINGS_FILE" 2>/dev/null || true
}
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
legacy_route() {  # legacy_route <grep -oP pattern>: first match in the port-80 site
    if [[ -f "$VHOST_TARGET" ]]; then
        grep -oP "$1" "$VHOST_TARGET" 2>/dev/null | head -1 || true
    fi
}
default_encoder() {
    local v; v="$(setting encoder)"
    [[ -n "$v" ]] || v="$(legacy_route 'ProxyPass\s+/hls/\s+http://\K[^:/]+')"
    printf '%s' "$v"
}
default_switcher() {
    local v; v="$(setting switcher)"
    [[ -n "$v" ]] || v="$(legacy_route 'ProxyPass\s+/multicamera/switcher\s+http://\K[^/]+')"
    [[ -n "$v" || $FRESH_INSTALL -eq 1 ]] || v="-"
    printf '%s' "$v"
}
default_webui_port() {
    local v; v="$(setting webui_port)"
    if [[ -z "$v" && -f "$VHOST_TARGET" ]]; then
        # A port-80 site from before cameras.conf may hold the web-admin vhost itself.
        v=$(tr -d '\r' < "$VHOST_TARGET" | awk '
            /^[[:space:]]*#/ { next }
            match($0, /<VirtualHost[^>]*:[0-9]+>/) { s = substr($0, RSTART, RLENGTH); gsub(/.*:|>/, "", s); port = s }
            port != "" && port != "80" && /ProxyPass[[:space:]]+\/[[:space:]]+http:\/\// { print port; exit }
            /<\/VirtualHost>/ { port = "" }')
    fi
    [[ -n "$v" ]] || { [[ $FRESH_INSTALL -eq 1 ]] && v="8081" || v="-"; }
    printf '%s' "$v"
}

echo "==> Camera settings$([[ $ASK -eq 1 ]] || echo " (reusing the current values)")"
ask CAMERA_COUNT "Number of Panasonic cameras (1-4)" "$(default_cam_count)"
[[ "$CAMERA_COUNT" =~ ^[1-4]$ ]] || CAMERA_COUNT=4

for i in $(seq 1 "$CAMERA_COUNT"); do
    var="CAMERA_${i}_IP"
    def="$(default_cam_ip "$i")"
    [[ -z "$def" ]] && def="192.168.1.$((199 + i))"
    ask "$var" "Camera $i IP address" "$def"
done

ask ENCODER_HOSTNAME "HLS encoder hostname/IP" "$(default_encoder)"
[[ -z "$ENCODER_HOSTNAME" ]] && ENCODER_HOSTNAME="encoder"
ask SWITCHER_IP "Video switcher IP (- to omit)" "$(default_switcher)"
[[ "$SWITCHER_IP" == "-" ]] && SWITCHER_IP=""
ask CAMERA_WEBUI_PORT "Port for camera 1's web admin page (- to omit)" "$(default_webui_port)"
[[ "$CAMERA_WEBUI_PORT" == "-" ]] && CAMERA_WEBUI_PORT=""
if [[ -n "$CAMERA_WEBUI_PORT" && ! "$CAMERA_WEBUI_PORT" =~ ^[0-9]{2,5}$ ]]; then
    echo "Error: invalid web admin port '$CAMERA_WEBUI_PORT'" >&2
    exit 1
fi

# ── Step 4: Write site JSON configs (first install / --reconfigure only) ───
# Existing files are merged: only the camera IPs change, names, extra cameras
# (e.g. ONVIF) and any other keys are kept.
if [[ $ASK -eq 1 ]]; then
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
else
    echo "==> Existing install: keeping all site configs (use --reconfigure to change camera settings)"
fi

# ── Step 5: Apache: cameras.conf, the Include line, the web-admin site ─────
render_template() {  # render_template <template>: substitute settings, drop unused cameras/switcher
    local out i
    out="# Generated by cameras/install.sh from $(basename "$1") - changes here are overwritten."$'\n'
    out+="$(tr -d '\r' < "$1")"
    out="${out//\/var\/www\/html/$WEB_ROOT}"
    out="${out//ENCODER_HOSTNAME/$ENCODER_HOSTNAME}"
    out="${out//WEBUI_PORT/$CAMERA_WEBUI_PORT}"
    for i in 1 2 3 4; do
        if (( i > CAMERA_COUNT )); then
            out="$(printf '%s\n' "$out" | grep -v "CAMERA_${i}_IP")"
        else
            local var="CAMERA_${i}_IP"
            out="${out//CAMERA_${i}_IP/${!var}}"
        fi
    done
    if [[ -n "$SWITCHER_IP" ]]; then
        out="${out//SWITCHER_IP/$SWITCHER_IP}"
    else
        out="$(printf '%s\n' "$out" | grep -v 'SWITCHER_IP')"
    fi
    printf '%s\n' "$out"
}

CHANGED=()   # files changed this run, restored from their backups if Apache rejects the result
CREATED=()   # files created this run, removed if Apache rejects the result
put_file() {  # put_file <path> <content>: write only when the content changes
    local path="$1" content="$2"
    if [[ -f "$path" ]] && [[ "$(cat "$path")" == "${content%$'\n'}" ]]; then
        return 0
    fi
    if [[ -f "$path" ]]; then backup "$path"; CHANGED+=("$path"); else CREATED+=("$path"); fi
    install -d "$(dirname "$path")"
    printf '%s\n' "${content%$'\n'}" > "$path.tmp-$STAMP"
    chmod 644 "$path.tmp-$STAMP"
    mv "$path.tmp-$STAMP" "$path"
    echo "    Wrote $path"
}
include_line_present() {
    local escaped="${CAMERAS_CONF//./\\.}"
    grep -qE "^[[:space:]]*Include[[:space:]]+${escaped}[[:space:]]*$" "$VHOST_TARGET"
}
ensure_include() {
    if [[ ! -f "$VHOST_TARGET" ]]; then
        echo "Error: $VHOST_TARGET not found; the camera routes need a port-80 site to be included in." >&2
        return 1
    fi
    include_line_present && return 0
    local tmp="$VHOST_TARGET.tmp-$STAMP"
    if ! awk -v inc="Include $CAMERAS_CONF" '
            !done && /<VirtualHost[^>]*:80>/ { invh = 1 }
            !done && invh && /^[[:space:]]*<\/VirtualHost>/ {
                print "    # Camera control routes, managed by cameras/install.sh"
                print "    " inc
                done = 1; invh = 0
            }
            { print }
            END { exit done ? 0 : 1 }' "$VHOST_TARGET" > "$tmp"; then
        rm -f "$tmp"
        echo "Error: no <VirtualHost *:80> block found in $VHOST_TARGET; add this line inside it by hand:" >&2
        echo "    Include $CAMERAS_CONF" >&2
        return 1
    fi
    backup "$VHOST_TARGET"
    CHANGED+=("$VHOST_TARGET")
    cat "$tmp" > "$VHOST_TARGET"   # keeps the file's owner and mode
    rm -f "$tmp"
    echo "    Added the Include line to $VHOST_TARGET"
}
listen_declared_elsewhere() {  # listen_declared_elsewhere <port>
    local f
    for f in "$APACHE_DIR"/ports.conf "$APACHE_DIR"/sites-available/*.conf "$APACHE_DIR"/conf-available/*.conf; do
        [[ -f "$f" && "$f" != "$WEBUI_SITE" ]] || continue
        grep -qE "^[[:space:]]*Listen[[:space:]]+([^[:space:]]+:)?$1([[:space:]]|$)" "$f" && return 0
    done
    return 1
}
rollback_apache() {
    local f
    for f in "${CHANGED[@]}"; do cp -p "$f.bak-$STAMP" "$f"; done
    for f in "${CREATED[@]}"; do rm -f "$f"; done
    [[ " ${CREATED[*]} " == *" $WEBUI_SITE "* ]] && a2dissite cameras-webui >/dev/null 2>&1 || true
    echo "Error: Apache rejected the new configuration; all Apache changes were rolled back." >&2
}

echo "==> Apache camera routes"
for t in "$ROUTES_TEMPLATE" "$WEBUI_TEMPLATE"; do
    [[ -f "$t" ]] || { echo "Error: missing $t" >&2; exit 1; }
done
put_file "$CAMERAS_CONF" "$(render_template "$ROUTES_TEMPLATE")"
ensure_include || { rollback_apache; exit 1; }

if [[ -n "$CAMERA_WEBUI_PORT" ]]; then
    WEBUI="$(render_template "$WEBUI_TEMPLATE")"
    if listen_declared_elsewhere "$CAMERA_WEBUI_PORT"; then
        WEBUI="$(printf '%s\n' "$WEBUI" | grep -v '^Listen ')"
    fi
    put_file "$WEBUI_SITE" "$WEBUI"
    a2ensite cameras-webui >/dev/null 2>&1 || true
elif [[ -f "$WEBUI_SITE" ]]; then
    a2dissite cameras-webui >/dev/null 2>&1 || true
    echo "    Disabled the camera web admin site"
fi

if ! apache2ctl configtest; then
    rollback_apache
    exit 1
fi

# Routes still defined directly in the port-80 site come before the Include and win.
if tr -d '\r' < "$VHOST_TARGET" | grep -qE '^[[:space:]]*ProxyPass(Match)?[[:space:]]+(/cam/|\^?/multicamera/cam/|/mjpeg)'; then
    echo "    Note: $VHOST_TARGET still has its own camera routes; they take precedence over"
    echo "    $CAMERAS_CONF until they are commented out."
fi

install -d -m 755 "$ETC_DIR"
jq -n --arg encoder "$ENCODER_HOSTNAME" --arg switcher "$SWITCHER_IP" --arg webui_port "$CAMERA_WEBUI_PORT" \
    '{encoder: $encoder, switcher: $switcher, webui_port: $webui_port}' > "$SETTINGS_FILE"
chmod 644 "$SETTINGS_FILE"

# ── Step 6: Permissions + reload ─────────────────────────────────────
echo "==> Setting permissions and reloading Apache"
chown -R www-data:www-data "$WEB_ROOT/cameracontrol" "$WEB_ROOT/multicamera"
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
