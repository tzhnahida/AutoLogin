#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="autologin.conf"
RUN_ONCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    -1)
      RUN_ONCE=1
      shift
      ;;
    -once)
      RUN_ONCE=1
      shift
      ;;
    --once)
      RUN_ONCE=1
      shift
      ;;
    --run-once)
      RUN_ONCE=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

[[ -f "$CONFIG_FILE" ]] || { echo "Config file not found: $CONFIG_FILE" >&2; exit 1; }

USER_ID=""
PASSWORD=""
SERVICE=""
BASE_URL="http://210.27.177.172"
LOGIN_URL="http://210.27.177.172/eportal/InterFace.do?method=login"
TEST_URL="https://www.baidu.com"
PING_ENABLE=true
PING_TARGET="223.5.5.5 114.114.114.114"
POLL_INTERVAL=3600
RETRY_INTERVAL=60

strip_quotes() {
  local value="$1"
  value="${value%$'\r'}"
  if [[ "${#value}" -ge 2 ]]; then
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s' "$value"
}

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  [[ "$line" == *=* ]] || continue
  key="${line%%=*}"
  value="$(strip_quotes "${line#*=}")"
  [[ -n "$key" && -n "$value" ]] || continue

  case "$key" in
    USER_ID) USER_ID="$value" ;;
    PASSWORD) PASSWORD="$value" ;;
    SERVICE) SERVICE="$value" ;;
    BASE_URL) BASE_URL="$value" ;;
    LOGIN_URL) LOGIN_URL="$value" ;;
    TEST_URL) TEST_URL="$value" ;;
    PING_ENABLE) PING_ENABLE="$value" ;;
    PING_TARGET) PING_TARGET="$value" ;;
    POLL_INTERVAL) POLL_INTERVAL="$value" ;;
    RETRY_INTERVAL) RETRY_INTERVAL="$value" ;;
  esac
done < "$CONFIG_FILE"

[[ -n "$USER_ID" ]] || { echo "Missing USER_ID" >&2; exit 1; }
[[ -n "$PASSWORD" ]] || { echo "Missing PASSWORD" >&2; exit 1; }

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

WORK_DIR="$(mktemp -d -t autologin.XXXXXX)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

COOKIE_JAR="$WORK_DIR/cookies.txt"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

check_network() {
  log "Checking network connectivity..."
  check_ping || return 1

  local status
  status="$(curl -ksS -L --max-time 15 -o /dev/null -w '%{http_code}' "$TEST_URL")"
  if [[ "$status" == "200" ]]; then
    log "Network reachable."
    return 0
  fi
  log "Network check failed. HTTP status: $status"
  return 1
}

check_ping() {
  [[ "$PING_ENABLE" != "false" ]] || return 0
  command -v ping >/dev/null || { echo "ping is required when PING_ENABLE=true" >&2; return 1; }

  local target
  for target in ${PING_TARGET}; do
    log "Pinging $target..."
    ping -c 2 -W 2 "$target" >/dev/null 2>&1 && return 0
  done

  log "Ping check failed for: $PING_TARGET"
  return 1
}

fetch_query_string() {
  local html redirect_url query_string
  log "Fetching authentication redirect URL..."
  html="$(curl -ksS -L --max-time 20 -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$BASE_URL")"
  redirect_url="$(printf '%s' "$html" | sed -n "s/.*location\.href='\([^']*\)'.*/\1/p" | head -n 1)"
  [[ -n "$redirect_url" ]] || { echo "Redirect URL not found" >&2; return 1; }

  log "Fetching query string..."
  query_string="$(curl -ksS -L --max-time 20 -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o /dev/null -w '%{url_effective}' "$redirect_url")"
  query_string="${query_string#*\?}"
  [[ -n "$query_string" ]] || { echo "Query string not found" >&2; return 1; }
  printf '%s' "$query_string"
}

authenticate_with_service() {
  local service_name="$1"
  local query_string response result
  query_string="$(fetch_query_string)" || return 1

  log "Trying service: $service_name"
  response="$(curl -ksS --max-time 20 -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-urlencode "userId=${USER_ID}" \
    --data-urlencode "password=${PASSWORD}" \
    --data-urlencode "service=${service_name}" \
    --data-urlencode "queryString=${query_string}" \
    --data-urlencode "operatorPwd=" \
    --data-urlencode "operatorUserId=" \
    --data-urlencode "validcode=" \
    --data-urlencode "passwordEncrypt=false" \
    "$LOGIN_URL")"

  result="$(printf '%s' "$response" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  [[ "$result" == "success" ]] || { log "Service failed: $service_name"; return 1; }
  log "Authentication succeeded with service: $service_name"
}

authenticate_any() {
  if [[ -n "$SERVICE" ]]; then
    authenticate_with_service "$SERVICE"
    return $?
  fi

  local services=("校园联通" "校园电信" "校园移动" "校园无线")
  for service_name in "${services[@]}"; do
    if authenticate_with_service "$service_name"; then
      return 0
    fi
  done

  log "All configured services failed."
  return 1
}

login_once() {
  if check_network; then
    log "Network is reachable. No authentication needed."
    return 0
  fi

  authenticate_any || return 1

  local attempts=0
  while true; do
    if check_network; then
      log "Network is reachable after authentication."
      return 0
    fi
    attempts=$((attempts + 1))
    log "Network is still unreachable. Retry $attempts."
    sleep "$RETRY_INTERVAL"
    authenticate_any || return 1
  done
}

log "AutoLogin started. Config: $CONFIG_FILE"
while true; do
  login_once || log "Login cycle failed."
  [[ "$RUN_ONCE" -eq 1 ]] && break
  sleep "$POLL_INTERVAL"
done
