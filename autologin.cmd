@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "CONFIG_FILE=autologin.conf"
set "RUN_ONCE=0"

:parse_args
if "%~1"=="" goto parse_done
if "%~1"=="-c" (
  if "%~2"=="" goto parse_failed
  set "CONFIG_FILE=%~2"
  shift
  shift
  goto parse_args
)
if "%~1"=="--config" (
  if "%~2"=="" goto parse_failed
  set "CONFIG_FILE=%~2"
  shift
  shift
  goto parse_args
)
if "%~1"=="-once" goto set_once
if "%~1"=="--once" goto set_once
if "%~1"=="-run-once" goto set_once
echo Unknown option: %~1 1>&2
exit /b 1

:set_once
set "RUN_ONCE=1"
shift
goto parse_args

:parse_failed
echo Option %~1 requires a path. 1>&2
exit /b 1

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
set "POLL_INTERVAL=3600"
set "RETRY_INTERVAL=60"

for /f "usebackq eol=# tokens=* delims=" %%L in ("%CONFIG_FILE%") do call :parse_line "%%L"

if "!USER_ID!"=="" (echo Missing USER_ID 1>&2 & exit /b 1)
if "!PASSWORD!"=="" (echo Missing PASSWORD 1>&2 & exit /b 1)

where curl.exe >nul 2>nul
if errorlevel 1 (
  echo curl.exe is required 1>&2
  exit /b 1
)

:run_loop
call :check_network
if errorlevel 1 (
  call :authenticate_any
  if errorlevel 1 goto retry_delay
  call :check_network
  if errorlevel 1 goto retry_delay
)
echo Network is reachable after authentication.
goto loop_check

:retry_delay
echo Login cycle failed.
:loop_check
if "%RUN_ONCE%"=="1" exit /b 0
timeout /t %POLL_INTERVAL% /nobreak >nul
goto run_loop

:check_network
echo Checking network connectivity...
curl -ksS -L --max-time 15 -o nul -w "%%{http_code}" !TEST_URL! | findstr /r "200" >nul
if errorlevel 1 (
  echo Network check failed.
  exit /b 1
)
echo Network reachable.
exit /b 0

:authenticate_any
if defined SERVICE (
  set "TRY_SERVICE=!SERVICE!"
  call :authenticate
  exit /b !ERRORLEVEL!
)

set "TRY_SERVICE=校园联通"
call :authenticate
if !ERRORLEVEL! equ 0 exit /b 0

set "TRY_SERVICE=校园电信"
call :authenticate
if !ERRORLEVEL! equ 0 exit /b 0

set "TRY_SERVICE=校园移动"
call :authenticate
if !ERRORLEVEL! equ 0 exit /b 0

set "TRY_SERVICE=校园无线"
call :authenticate
if !ERRORLEVEL! equ 0 exit /b 0

echo All configured services failed. 1>&2
exit /b 1

:authenticate
set "WORK_DIR=%TEMP%\autologin-%RANDOM%-%RANDOM%"
if exist "%WORK_DIR%" rmdir /s /q "%WORK_DIR%"
mkdir "%WORK_DIR%"
set "COOKIE_JAR=%WORK_DIR%\cookies.txt"
set "TMP_DIR=%WORK_DIR%"
set "RESPONSE_FILE=%WORK_DIR%\response.txt"
set "TMP_DIR=%WORK_DIR%"
set "HTML_FILE=%WORK_DIR%\base.html"
set "EFFECTIVE_URL=%WORK_DIR%\effective_url.txt"

echo Fetching authentication redirect URL...
curl -ksS -L --max-time 20 -b "%COOKIE_JAR%" -c "%COOKIE_JAR%" !BASE_URL! > "%HTML_FILE%" || goto auth_failed
for /f "tokens=1,2 delims=[]" %%A in ('findstr /r "location\.href=" "%HTML_FILE%"') do (
  set "REDIRECT_URL=%%B"
)
if "!REDIRECT_URL!"=="" (
  echo Redirect URL not found 1>&2
  goto auth_failed
)

echo Fetching query string...
curl -ksS -L --max-time 20 -b "%COOKIE_JAR%" -c "%COOKIE_JAR%" -o nul -w "%%{url_effective}" "!REDIRECT_URL!" > "%EFFECTIVE_URL%" || goto auth_failed
set /p QUERY_URL=<"%EFFECTIVE_URL%"
for /f "tokens=2 delims=?" %%Q in ("!QUERY_URL!") do set "QUERY_STRING=%%Q"
if "!QUERY_STRING!"=="" (
  echo Query string not found 1>&2
  goto auth_failed
)

echo Trying service: !TRY_SERVICE!
curl -ksS --max-time 20 -b "%COOKIE_JAR%" -c "%COOKIE_JAR%" ^
  -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" ^
  --data-urlencode "userId=!USER_ID!" ^
  --data-urlencode "password=!PASSWORD!" ^
  --data-urlencode "service=!TRY_SERVICE!" ^
  --data-urlencode "queryString=!QUERY_STRING!" ^
  --data-urlencode "operatorPwd=" ^
  --data-urlencode "operatorUserId=" ^
  --data-urlencode "validcode=" ^
  --data-urlencode "passwordEncrypt=false" ^
  "%LOGIN_URL%" > "%RESPONSE_FILE%" || goto auth_failed

for /f "tokens=1,2 delims=[[]]" %%R in ('findstr /c:""result"":""success""" "%RESPONSE_FILE%"') do (
  echo Authentication succeeded with service: !TRY_SERVICE!
  rmdir /s /q "%WORK_DIR%"
  exit /b 0
)

echo Service failed: !TRY_SERVICE! 1>&2
goto auth_failed

:auth_failed
rmdir /s /q "%WORK_DIR%" 2>nul
exit /b 1

:parse_line
set "LINE=%~1"
if not defined LINE exit /b 0
if "!LINE:~0,1!"="#" exit /b 0
set "LINE=!LINE:~0,-1!"
for /f "tokens=1,2 delims==" %%A in ("!LINE!") do (
  set "KEY=%%A"
  set "VALUE=%%B"
)
if defined KEY if defined VALUE (
  set "VALUE=!VALUE:"=!"
  if not "!VALUE:~0,1!"=="-" (
    set "VALUE=!VALUE:~1,!"
    if defined VALUE set "!KEY!=!VALUE!"
  )
)
exit /b 0
