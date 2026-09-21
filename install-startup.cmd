@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_FILE=autologin.cmd"
set "CONFIG_FILE=autologin.conf"
set "STARTUP_FILE=StartupPath.txt"

powershell -NoProfile -Command "Write-Output $([Environment]::GetFolderPath('Startup'))" > "%STARTUP_FILE%"
set /p STARTUP_DIR=<"%STARTUP_FILE%"
del "%STARTUP_FILE%"

if "%STARTUP_DIR%"=="" (
  echo Startup directory not found.
  pause
  exit /b 1
)

if not exist "%STARTUP_DIR%" (
  echo Startup directory does not exist: %STARTUP_DIR%
  pause
  exit /b 1
)

if not exist "%SCRIPT_FILE%" (
  echo Script not found: %SCRIPT_FILE%
  pause
  exit /b 1
)

if not exist "%CONFIG_FILE%" (
  echo Config not found: %CONFIG_FILE%
  pause
  exit /b 1
)

copy /y "%SCRIPT_FILE%" "%STARTUP_DIR%\autologin.cmd" || exit /b 1
copy /y "%CONFIG_FILE%" "%STARTUP_DIR%\autologin.conf" || exit /b 1

echo Done.
echo Installed:
echo   %STARTUP_DIR%\autologin.cmd
echo   %STARTUP_DIR%\autologin.conf

pause
