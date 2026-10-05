#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/usr/local/bin"
CONFIG_FILE="/etc/autologin.conf"
SERVICE_NAME="autologin"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_NAME=""
SOURCE_CONFIG=""
ENABLE_SERVICE=1

usage() {
  cat <<'EOF'
Usage:
  sudo ./install-service.sh
  sudo ./install-service.sh -c /path/to/autologin.conf
  sudo ./install-service.sh --script /path/to/autologin.sh --config /path/to/autologin.conf --no-enable

Installs the shell script into /usr/local/bin/autologin.sh, installs the config
into /etc/autologin.conf, creates /etc/systemd/system/autologin.service, and
enables the service for boot startup.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      [[ $# -ge 2 ]] || { echo "Option $1 requires a path" >&2; exit 1; }
      SOURCE_CONFIG="$2"
      shift 2
      ;;
    --script)
      [[ $# -ge 2 ]] || { echo "Option $1 requires a path" >&2; exit 1; }
      SCRIPT_NAME="$2"
      shift 2
      ;;
    --no-enable)
      ENABLE_SERVICE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ $(id -u) -ne 0 ]]; then
  echo "Run this script with sudo, for example: sudo ./install-service.sh" >&2
  exit 1
fi

if [[ -z "$SCRIPT_NAME" ]]; then
  SCRIPT_NAME="$(pwd)/autologin.sh"
fi

if [[ ! -f "$SCRIPT_NAME" ]]; then
  echo "Script not found: $SCRIPT_NAME" >&2
  exit 1
fi

if [[ -z "$SOURCE_CONFIG" && -f "$(pwd)/autologin.conf" ]]; then
  SOURCE_CONFIG="$(pwd)/autologin.conf"
elif [[ -z "$SOURCE_CONFIG" && -f "$(dirname "$SCRIPT_NAME")/autologin.conf" ]]; then
  SOURCE_CONFIG="$(dirname "$SCRIPT_NAME")/autologin.conf"
elif [[ -z "$SOURCE_CONFIG" ]]; then
  echo "Config not found. Create autologin.conf or pass: -c /path/to/autologin.conf" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_CONFIG" ]]; then
  echo "Config not found: $SOURCE_CONFIG" >&2
  exit 1
fi

command -v systemctl >/dev/null || { echo "systemctl is required" >&2; exit 1; }

install -m 0755 "$SCRIPT_NAME" "${INSTALL_DIR}/autologin.sh"
install -m 0600 "$SOURCE_CONFIG" "$CONFIG_FILE"

cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Qinghai University campus network auto login
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/usr/local/bin
ExecStart=/usr/bin/env bash /usr/local/bin/autologin.sh -c /etc/autologin.conf
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

if [[ "$ENABLE_SERVICE" -eq 1 ]]; then
  systemctl enable --now "${SERVICE_NAME}.service"
fi

echo "Installed ${INSTALL_DIR}/autologin.sh"
echo "Installed ${CONFIG_FILE}"
echo "Installed ${SERVICE_FILE}"

if [[ "$ENABLE_SERVICE" -eq 1 ]]; then
  echo "Service enabled and started: ${SERVICE_NAME}.service"
else
  echo "Service not enabled because --no-enable was passed."
fi

echo "Check status: systemctl status ${SERVICE_NAME}.service"
echo "View logs: journalctl -u ${SERVICE_NAME}.service -f"
