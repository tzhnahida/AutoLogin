#!/bin/sh
# busybox ash port of autologin.sh (for OpenWrt, no bash):
# - login body: service and queryString are URL-encoded TWICE, userId and
#   password once (same as the Go/bash implementations)
# - network check: plain HTTP GET to TEST_URL following redirects, WITHOUT -k;
#   a hijacked DNS answer serves the portal over TLS with a wrong certificate
#   and curl must fail there, otherwise the portal would pass as "Internet"
# - every cycle authenticates FIRST and verifies connectivity afterwards
# - failed logins are retried every RETRY_INTERVAL seconds; once the network
#   is up the script sleeps POLL_INTERVAL seconds

set -eu

CONFIG_FILE="autologin.conf"
RUN_ONCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--config)
      [ $# -ge 2 ] || { echo "Option $1 requires a path" >&2; exit 1; }
      CONFIG_FILE="$2"
      shift 2
      ;;
    -1|-once|--once|--run-once)
      RUN_ONCE=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

[ -f "$CONFIG_FILE" ] || { echo "Config file not found: $CONFIG_FILE" >&2; exit 1; }

USER_ID=""
PASSWORD=""
SERVICE=""
BASE_URL="http://210.27.177.172"
LOGIN_URL="http://210.27.177.172/eportal/InterFace.do?method=login"
TEST_URL="https://www.baidu.com"
TRIGGER_URL="http://www.baidu.com"
PING_ENABLE=true
PING_TARGET="223.5.5.5 114.114.114.114"
POLL_INTERVAL=3600
RETRY_INTERVAL=60

CR=$(printf '\r')
BOM=$(printf '\357\273\277')

strip_quotes() {
  value=$1
  value=${value%"$CR"}
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  case "$value" in
    '"'*'"')
      value=${value#?}
      printf '%s' "${value%?}"
      ;;
    "'"*"'")
      value=${value#?}
      printf '%s' "${value%?}"
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

while IFS= read -r line || [ -n "$line" ]; do
  line=${line%"$CR"}
  line=${line#"$BOM"}
  first=${line#"${line%%[![:space:]]*}"}
  case "$first" in
    '#'*) continue ;;
  esac
  [ -n "$first" ] || continue
  case "$line" in
    *=*) ;;
    *) continue ;;
  esac
  key=${line%%=*}
  key=$(printf '%s' "$key" | tr -d ' \t')
  value=$(strip_quotes "${line#*=}")
  [ -n "$key" ] || continue
  [ -n "$value" ] || continue

  case "$key" in
    USER_ID) USER_ID=$value ;;
    PASSWORD) PASSWORD=$value ;;
    SERVICE) SERVICE=$value ;;
    BASE_URL) BASE_URL=$value ;;
    LOGIN_URL) LOGIN_URL=$value ;;
    TEST_URL) TEST_URL=$value ;;
    TRIGGER_URL) TRIGGER_URL=$value ;;
    PING_ENABLE) PING_ENABLE=$value ;;
    PING_TARGET) PING_TARGET=$value ;;
    POLL_INTERVAL) POLL_INTERVAL=$value ;;
    RETRY_INTERVAL) RETRY_INTERVAL=$value ;;
  esac
done < "$CONFIG_FILE"

[ -n "$USER_ID" ] || { echo "Missing USER_ID" >&2; exit 1; }
[ -n "$PASSWORD" ] || { echo "Missing PASSWORD" >&2; exit 1; }
case "$POLL_INTERVAL" in
  ''|*[!0-9]*) POLL_INTERVAL=3600 ;;
esac
case "$RETRY_INTERVAL" in
  ''|*[!0-9]*) RETRY_INTERVAL=60 ;;
esac

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

WORK_DIR=$(mktemp -d /tmp/autologin.XXXXXX)
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

COOKIE_JAR="$WORK_DIR/cookies.txt"

# Logs go to stderr: fetch_query_string runs inside "$( )", so anything on
# stdout would end up inside the captured query string.
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# Byte-wise percent-encoding, equivalent to Go's url.QueryEscape.
# Works on bytes (OpenWrt locale is C), so UTF-8 service names encode right.
urlencode() {
  rest=$1
  encoded=''
  while [ -n "$rest" ]; do
    c=${rest%"${rest#?}"}
    rest=${rest#?}
    case "$c" in
      [a-zA-Z0-9.~_-]) encoded="$encoded$c" ;;
      *) code=$(( $(printf '%d' "'$c") & 0xFF ))
         encoded="$encoded$(printf '%%%02X' "$code")" ;;
    esac
  done
  printf '%s' "$encoded"
}

check_network() {
  log "Checking network connectivity..."
  # HTTP first: offline it fails within milliseconds, while waiting for pings
  # to time out would stall every check for tens of seconds.
  status=$(curl -sS --noproxy '*' -L --max-time 15 -o /dev/null -w '%{http_code}' "$TEST_URL") || status=000
  if [ "$status" != "200" ]; then
    log "Network check failed. HTTP status: $status"
    return 1
  fi
  check_ping || return 1
  log "Network reachable."
  return 0
}

check_ping() {
  [ "$PING_ENABLE" != "false" ] || return 0
  command -v ping >/dev/null || { echo "ping is required when PING_ENABLE=true" >&2; return 1; }

  for target in $PING_TARGET; do
    log "Pinging $target..."
    ping -c 2 "$target" >/dev/null 2>&1 && return 0
  done

  log "Ping check failed for: $PING_TARGET"
  return 1
}

fetch_query_string() {
  html=''
  redirect_url=''
  query_string=''
  portal_origin=''
  log "Fetching authentication redirect URL..."
  html=$(curl -sS --noproxy '*' -L --max-time 20 -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$BASE_URL") || html=''
  redirect_url=$(printf '%s' "$html" | sed -n "s/.*location\.href='\([^']*\)'.*/\1/p" | head -n 1)

  if [ -z "$redirect_url" ]; then
    # The configured portal refused or served no redirect page (e.g. after
    # moving to another campus network). A plain-HTTP trigger URL gets
    # hijacked to whichever portal is active, so adopt that one.
    log "No redirect from $BASE_URL. Trying portal auto-detection via $TRIGGER_URL..."
    html=$(curl -sS --noproxy '*' -L --max-time 20 -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$TRIGGER_URL") || {
      echo "Portal unreachable: $BASE_URL" >&2
      return 2
    }
    redirect_url=$(printf '%s' "$html" | sed -n "s/.*location\.href='\([^']*\)'.*/\1/p" | head -n 1)
    if [ -z "$redirect_url" ]; then
      echo "No portal redirect found via $TRIGGER_URL" >&2
      return 1
    fi
    portal_origin=$(printf '%s' "$redirect_url" | sed -E 's#^(https?://[^/]+).*$#\1#')
    log "Detected portal: $portal_origin"
    BASE_URL=$portal_origin
    LOGIN_URL="${portal_origin}/eportal/InterFace.do?method=login"
  fi

  log "Fetching query string..."
  query_string=$(curl -sS --noproxy '*' -L --max-time 20 -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o /dev/null -w '%{url_effective}' "$redirect_url") || query_string=''
  query_string=${query_string#*\?}
  [ -n "$query_string" ] || { echo "Query string not found" >&2; return 1; }
  printf '%s' "$query_string"
}

authenticate_with_service() {
  service_name=$1
  query_string=$(fetch_query_string) || return $?

  log "Trying service: $service_name"
  body=$(printf 'userId=%s&password=%s&service=%s&queryString=%s&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false' \
    "$(urlencode "$USER_ID")" \
    "$(urlencode "$PASSWORD")" \
    "$(urlencode "$(urlencode "$service_name")")" \
    "$(urlencode "$(urlencode "$query_string")")")

  response=$(curl -sS --noproxy '*' --max-time 20 -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-binary "$body" \
    "$LOGIN_URL") || response=''

  result=$(printf '%s' "$response" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  [ "$result" = "success" ] || { log "Service failed: $service_name"; return 1; }
  log "Authentication succeeded with service: $service_name"
}

authenticate_any() {
  # Exit code 2 means the portal itself is unreachable; trying the remaining
  # service names cannot help then, so the caller aborts the whole attempt.
  if [ -n "$SERVICE" ]; then
    authenticate_with_service "$SERVICE"
    return $?
  fi

  rc=0
  for service_name in 校园联通 校园电信 校园移动 校园无线; do
    authenticate_with_service "$service_name"
    rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 2 ] && return 2
  done

  log "All configured services failed."
  return 1
}

login_once() {
  # Authenticate first, then verify. When the session is already valid the
  # portal simply rejects the extra login, which is harmless.
  while true; do
    authenticate_any || log "Authentication attempt failed."
    if check_network; then
      log "Network is reachable."
      return 0
    fi
    log "Network still unreachable. Retrying in $RETRY_INTERVAL seconds..."
    sleep "$RETRY_INTERVAL"
  done
}

log "AutoLogin started. Config: $CONFIG_FILE"
while true; do
  login_once
  [ "$RUN_ONCE" -eq 1 ] && break
  sleep "$POLL_INTERVAL"
done
