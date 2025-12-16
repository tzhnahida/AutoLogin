#!/bin/bash

# Always run from project root
cd "$(dirname "$0")"

echo "=================================="
echo "  Go Cross-Platform Build Script"
echo "=================================="
echo
echo "1) Windows x64"
echo "2) Windows x86"
echo "3) Windows ARM64"
echo "4) Linux x64"
echo "5) Linux x86"
echo "6) Linux ARM"
echo "7) Linux ARM64"
echo "8) All platforms"
echo

read -p "Select target platform (1-8): " choice

build() {
  echo "Building $1 $2 ..."
  CGO_ENABLED=0 GOOS=$1 GOARCH=$2 GOARM=$3 \
  go build -o "$4" ./cmd
}

case $choice in
  1) build windows amd64 "" AutoLogin_win_x64.exe ;;
  2) build windows 386 "" AutoLogin_win_x86.exe ;;
  3) build windows arm64 "" AutoLogin_win_arm64.exe ;;
  4) build linux amd64 "" AutoLogin_linux_x64 ;;
  5) build linux 386 "" AutoLogin_linux_x86 ;;
  6) build linux arm 7 AutoLogin_linux_arm ;;
  7) build linux arm64 "" AutoLogin_linux_arm64 ;;
  8)
    echo "Building all platforms..."
    echo
    build windows amd64 "" AutoLogin_win_x64.exe
    build windows 386 "" AutoLogin_win_x86.exe
    build windows arm64 "" AutoLogin_win_arm64.exe
    build linux amd64 "" AutoLogin_linux_x64
    build linux 386 "" AutoLogin_linux_x86
    build linux arm 7 AutoLogin_linux_arm
    build linux arm64 "" AutoLogin_linux_arm64
    echo
    echo "All builds completed."
    ;;
  *)
    echo "Invalid selection."
    exit 1
    ;;
esac
