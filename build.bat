@echo off
chcp 65001 > nul
setlocal

REM Always run from project root
cd /d %~dp0

echo ==================================
echo   Go Cross-Platform Build Script
echo ==================================
echo.
echo 1) Windows x64
echo 2) Windows x86
echo 3) Windows ARM64
echo 4) Linux x64
echo 5) Linux x86
echo 6) Linux ARM
echo 7) Linux ARM64
echo 8) All platforms
echo.

set /p choice=Select target platform (1-8):

set CGO_ENABLED=0

if "%choice%"=="8" goto build_all

if "%choice%"=="1" (
    set GOOS=windows
    set GOARCH=amd64
    set OUTPUT=AutoLogin_win_x64.exe
) else if "%choice%"=="2" (
    set GOOS=windows
    set GOARCH=386
    set OUTPUT=AutoLogin_win_x86.exe
) else if "%choice%"=="3" (
    set GOOS=windows
    set GOARCH=arm64
    set OUTPUT=AutoLogin_win_arm64.exe
) else if "%choice%"=="4" (
    set GOOS=linux
    set GOARCH=amd64
    set OUTPUT=AutoLogin_linux_x64
) else if "%choice%"=="5" (
    set GOOS=linux
    set GOARCH=386
    set OUTPUT=AutoLogin_linux_x86
) else if "%choice%"=="6" (
    set GOOS=linux
    set GOARCH=arm
    set GOARM=7
    set OUTPUT=AutoLogin_linux_arm
) else if "%choice%"=="7" (
    set GOOS=linux
    set GOARCH=arm64
    set OUTPUT=AutoLogin_linux_arm64
) else (
    echo Invalid selection.
    goto end
)

echo Building %GOOS% %GOARCH% ...
go build -o %OUTPUT% ./cmd
goto end

:build_all
echo Building all platforms...
echo.

set GOOS=windows
set GOARCH=amd64
go build -o AutoLogin_win_x64.exe ./cmd

set GOARCH=386
go build -o AutoLogin_win_x86.exe ./cmd

set GOARCH=arm64
go build -o AutoLogin_win_arm64.exe ./cmd

set GOOS=linux
set GOARCH=amd64
go build -o AutoLogin_linux_x64 ./cmd

set GOARCH=386
go build -o AutoLogin_linux_x86 ./cmd

set GOARCH=arm
set GOARM=7
go build -o AutoLogin_linux_arm ./cmd

set GOARCH=arm64
set GOARM=
go build -o AutoLogin_linux_arm64 ./cmd

echo.
echo All builds completed.

:end
pause
