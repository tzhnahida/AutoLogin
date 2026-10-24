#!/bin/sh
# OpenWrt one-shot installer.
# Run ON the router, from the directory that holds autologin.sh,
# autologin.conf and autologin.initd:
#
#   scp -O -r openwrt/ root@<路由器IP>:/tmp/
#   ssh -o HostKeyAlgorithms=+ssh-rsa root@<路由器IP>
#   sh /tmp/openwrt/install.sh
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" -eq 0 ] || { echo "Run as root on the router." >&2; exit 1; }

for f in autologin.sh autologin.initd; do
  [ -f "$SCRIPT_DIR/$f" ] || { echo "Missing $f next to install.sh" >&2; exit 1; }
done
if [ ! -f "$SCRIPT_DIR/autologin.conf" ]; then
  if [ -f "$SCRIPT_DIR/autologin.conf.example" ]; then
    cp "$SCRIPT_DIR/autologin.conf.example" "$SCRIPT_DIR/autologin.conf"
    echo "Created autologin.conf from the example - fill in USER_ID/PASSWORD first, then re-run." >&2
  else
    echo "Missing autologin.conf (and autologin.conf.example) next to install.sh" >&2
  fi
  exit 1
fi
command -v curl >/dev/null || { echo "curl is required: opkg install curl" >&2; exit 1; }

if grep -q -e '你的学号' -e '你的密码' "$SCRIPT_DIR/autologin.conf"; then
  echo "autologin.conf still has the placeholder account/password - edit it first." >&2
  exit 1
fi

cp -f "$SCRIPT_DIR/autologin.sh" /usr/bin/autologin.sh
chmod 0755 /usr/bin/autologin.sh
cp -f "$SCRIPT_DIR/autologin.conf" /etc/autologin.conf
chmod 0600 /etc/autologin.conf
cp -f "$SCRIPT_DIR/autologin.initd" /etc/init.d/autologin
chmod 0755 /etc/init.d/autologin

/etc/init.d/autologin enable
/etc/init.d/autologin restart

echo
echo "Installed:"
echo "  /usr/bin/autologin.sh"
echo "  /etc/autologin.conf"
echo "  /etc/init.d/autologin (procd, boot-enabled)"
echo "Logs: logread | grep autologin"
