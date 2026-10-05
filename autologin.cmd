@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem UTF-8 codepage: this file, autologin.conf and the service names are UTF-8.
chcp 65001 >nul

rem Batch port of the Go implementation (login.go + autodaemon.go):
rem - network check: plain HTTP GET to TEST_URL following redirects, WITHOUT -k.
rem   A hijacked DNS answer for TEST_URL serves the portal page over TLS with a
rem   wrong certificate; curl must fail there like Go does, otherwise the script
rem   mistakes the portal for the Internet and never logs in.
rem - login body: service and queryString are URL-encoded TWICE, userId and
rem   password once (login.go applies QueryEscape and then Values.Encode). The
rem   raw values travel through environment variables and are encoded by
rem   PowerShell so cmd never re-parses % and & inside them.
rem - every cycle authenticates FIRST and verifies connectivity afterwards: on
rem   networks that keep the portal reachable only for a short unauthenticated
rem   window, the login attempt must not wait behind connectivity checks
rem - failed logins are retried every RETRY_INTERVAL seconds; once the network
rem   is up the script sleeps POLL_INTERVAL seconds

set "CONFIG_FILE=autologin.conf"
set "RUN_ONCE=0"

:parse_args
if "%~1"=="" goto parse_done
if /i "%~1"=="-c" goto set_config
if /i "%~1"=="--config" goto set_config
if "%~1"=="-1" goto set_once
if "%~1"=="-once" goto set_once
if "%~1"=="--once" goto set_once
if "%~1"=="--run-once" goto set_once
echo Unknown option: %~1 1>&2
exit /b 1

:set_config
if "%~2"=="" (
  echo Option %~1 requires a path. 1>&2
  exit /b 1
)
set "CONFIG_FILE=%~2"
shift
shift
goto parse_args

:set_once
set "RUN_ONCE=1"
shift
goto parse_args

:parse_done
if not exist "%CONFIG_FILE%" (
  echo Config file not found: %CONFIG_FILE% 1>&2
  exit /b 1
)

set "USER_ID="
set "PASSWORD="
set "SERVICE="
set "BASE_URL=http://210.27.177.172"
set "LOGIN_URL=http://210.27.177.172/eportal/InterFace.do?method=login"
set "TEST_URL=https://www.baidu.com"
set "TRIGGER_URL=http://www.baidu.com"
set "PING_ENABLE=true"
set "PING_TARGET=223.5.5.5"
set "POLL_INTERVAL=3600"
set "RETRY_INTERVAL=60"

for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
  set "KEY=%%A"
  set "VALUE=%%B"
  if defined VALUE (
    set "KEY=!KEY: =!"
    set "VALUE=!VALUE:"=!"
    if /i "!KEY!"=="USER_ID" set "USER_ID=!VALUE!"
    if /i "!KEY!"=="PASSWORD" set "PASSWORD=!VALUE!"
    if /i "!KEY!"=="SERVICE" set "SERVICE=!VALUE!"
    if /i "!KEY!"=="BASE_URL" set "BASE_URL=!VALUE!"
    if /i "!KEY!"=="LOGIN_URL" set "LOGIN_URL=!VALUE!"
    if /i "!KEY!"=="TEST_URL" set "TEST_URL=!VALUE!"
    if /i "!KEY!"=="TRIGGER_URL" set "TRIGGER_URL=!VALUE!"
    if /i "!KEY!"=="PING_ENABLE" set "PING_ENABLE=!VALUE!"
    if /i "!KEY!"=="PING_TARGET" set "PING_TARGET=!VALUE!"
    if /i "!KEY!"=="POLL_INTERVAL" set "POLL_INTERVAL=!VALUE!"
    if /i "!KEY!"=="RETRY_INTERVAL" set "RETRY_INTERVAL=!VALUE!"
  )
)

if not defined USER_ID (echo Missing USER_ID 1>&2 & exit /b 1)
if not defined PASSWORD (echo Missing PASSWORD 1>&2 & exit /b 1)

echo(%POLL_INTERVAL%| findstr /r "^[0-9][0-9]*$" >nul || set "POLL_INTERVAL=3600"
echo(%RETRY_INTERVAL%| findstr /r "^[0-9][0-9]*$" >nul || set "RETRY_INTERVAL=60"

where curl.exe >nul 2>nul
if errorlevel 1 (
  echo curl.exe is required 1>&2
  exit /b 1
)

echo AutoLogin started. Config: %CONFIG_FILE%

:run_loop
call :ensure_logged_in
if "%RUN_ONCE%"=="1" exit /b 0
timeout /t !POLL_INTERVAL! /nobreak >nul
goto run_loop

:ensure_logged_in
rem Authenticate first, then verify. When the session is already valid the
rem portal simply rejects the extra login, which is harmless.
call :authenticate_any
if errorlevel 1 echo Authentication attempt failed. 1>&2
call :check_network
if not errorlevel 1 (
  echo Network is reachable.
  exit /b 0
)
echo Network still unreachable. Retrying in !RETRY_INTERVAL! seconds...
timeout /t !RETRY_INTERVAL! /nobreak >nul
goto ensure_logged_in

:check_network
echo Checking network connectivity...
rem HTTP first: offline it fails within milliseconds, while waiting for pings
rem to time out would stall every check for tens of seconds.
curl -sS --noproxy "*" -L --max-time 15 -o nul -w "%%{http_code}" "!TEST_URL!" | findstr /x "200" >nul
if errorlevel 1 (
  echo Network check failed.
  exit /b 1
)
call :check_ping
if errorlevel 1 exit /b 1
echo Network reachable.
exit /b 0

:check_ping
if /i "!PING_ENABLE!"=="false" exit /b 0

where ping >nul 2>nul
if errorlevel 1 (
  echo ping is required when PING_ENABLE=true 1>&2
  exit /b 1
)

echo Pinging !PING_TARGET!...
ping -n 3 !PING_TARGET! >nul
if errorlevel 1 (
  echo Ping check failed for: !PING_TARGET!
  exit /b 1
)

exit /b 0

:extract_redirect
set "REDIRECT_URL="
for /f "usebackq delims=" %%L in (`findstr /r "location\.href=" "%HTML_FILE%"`) do (
  if not defined REDIRECT_URL (
    set "HTML_LINE=%%L"
    set "HTML_LINE=!HTML_LINE:"=!"
    set "HTML_LINE=!HTML_LINE:*location.href=!"
    set "HTML_LINE=!HTML_LINE:~1!"
    for /f "tokens=1 delims='" %%U in ("!HTML_LINE!") do set "REDIRECT_URL=%%U"
  )
)
exit /b 0

:authenticate_any
rem Errorlevel 2 means the portal itself is unreachable; trying the remaining
rem service names cannot help then, so the caller aborts the whole attempt.
if defined SERVICE (
  set "TRY_SERVICE=!SERVICE!"
  call :authenticate
  exit /b !ERRORLEVEL!
)

set "TRY_SERVICE=校园联通"
call :authenticate
if not errorlevel 1 exit /b 0
if errorlevel 2 exit /b !ERRORLEVEL!

set "TRY_SERVICE=校园电信"
call :authenticate
if not errorlevel 1 exit /b 0
if errorlevel 2 exit /b !ERRORLEVEL!

set "TRY_SERVICE=校园移动"
call :authenticate
if not errorlevel 1 exit /b 0
if errorlevel 2 exit /b !ERRORLEVEL!

set "TRY_SERVICE=校园无线"
call :authenticate
if not errorlevel 1 exit /b 0
if errorlevel 2 exit /b !ERRORLEVEL!

echo All configured services failed. 1>&2
exit /b 1

:authenticate
set "WORK_DIR=%TEMP%\autologin-%RANDOM%-%RANDOM%"
mkdir "%WORK_DIR%" 2>nul
set "COOKIE_JAR=%WORK_DIR%\cookies.txt"
set "HTML_FILE=%WORK_DIR%\base.html"
set "EFFECTIVE_URL=%WORK_DIR%\effective_url.txt"
set "RESPONSE_FILE=%WORK_DIR%\response.txt"
set "BODY_FILE=%WORK_DIR%\body.txt"

echo Fetching authentication redirect URL...
curl -sS --noproxy "*" -L --max-time 20 -b "%COOKIE_JAR%" -c "%COOKIE_JAR%" -o "%HTML_FILE%" "!BASE_URL!"
call :extract_redirect
if not defined REDIRECT_URL (
  rem The configured portal refused or served no redirect page (e.g. after
  rem moving to another campus network); detect the active portal instead.
  echo No redirect from !BASE_URL!. Trying portal auto-detection via !TRIGGER_URL!...
  curl -sS --noproxy "*" -L --max-time 20 -b "%COOKIE_JAR%" -c "%COOKIE_JAR%" -o "%HTML_FILE%" "!TRIGGER_URL!" || goto portal_unreachable
  call :extract_redirect
  if not defined REDIRECT_URL (
    echo No portal redirect found via !TRIGGER_URL! 1>&2
    goto auth_failed
  )
  for /f "tokens=1,2 delims=/" %%A in ("!REDIRECT_URL!") do set "PORTAL_ORIGIN=%%A//%%B"
  echo Detected portal: !PORTAL_ORIGIN!
  set "BASE_URL=!PORTAL_ORIGIN!"
  set "LOGIN_URL=!PORTAL_ORIGIN!/eportal/InterFace.do?method=login"
)

echo Fetching query string...
curl -sS -L --max-time 20 -b "%COOKIE_JAR%" -c "%COOKIE_JAR%" -o nul -w "%%{url_effective}" "!REDIRECT_URL!" > "%EFFECTIVE_URL%" || goto auth_failed
set "QUERY_URL="
set /p QUERY_URL=<"%EFFECTIVE_URL%"
set "QUERY_STRING="
if defined QUERY_URL set "QUERY_STRING=!QUERY_URL:*?=!"
if not defined QUERY_STRING (
  echo Query string not found 1>&2
  goto auth_failed
)

echo Trying service: !TRY_SERVICE!
rem Values go through the environment so cmd cannot re-parse % and & in them.
set "AUTOLOGIN_UID=!USER_ID!"
set "AUTOLOGIN_PWD=!PASSWORD!"
set "AUTOLOGIN_SVC=!TRY_SERVICE!"
set "AUTOLOGIN_QS=!QUERY_STRING!"
set "AUTOLOGIN_BODY=!BODY_FILE!"
powershell -NoProfile -Command "$e=[uri]::EscapeDataString; $b='userId=' + $e($env:AUTOLOGIN_UID) + '&password=' + $e($env:AUTOLOGIN_PWD) + '&service=' + $e($e($env:AUTOLOGIN_SVC)) + '&queryString=' + $e($e($env:AUTOLOGIN_QS)) + '&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false'; [IO.File]::WriteAllText($env:AUTOLOGIN_BODY, $b)" || goto auth_failed
if not exist "%BODY_FILE%" goto auth_failed

curl -sS --noproxy "*" --max-time 20 -b "%COOKIE_JAR%" -c "%COOKIE_JAR%" ^
  -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" ^
  --data-binary "@%BODY_FILE%" ^
  "!LOGIN_URL!" > "%RESPONSE_FILE%" || goto auth_failed

findstr /c:"\"result\":\"success\"" "%RESPONSE_FILE%" >nul
if not errorlevel 1 (
  echo Authentication succeeded with service: !TRY_SERVICE!
  rmdir /s /q "%WORK_DIR%" 2>nul
  exit /b 0
)

echo Service failed: !TRY_SERVICE! 1>&2

:portal_unreachable
echo Portal unreachable: !BASE_URL! 1>&2
rmdir /s /q "%WORK_DIR%" 2>nul
exit /b 2

:auth_failed
rmdir /s /q "%WORK_DIR%" 2>nul
exit /b 1
