#!/bin/sh

TOR_CONFIG=${TOR_CONFIG:-/etc/tor/torrc}
TOR_DATA_DIR=${TOR_DATA_DIR:-/var/lib/tor}
TOR_LOG_DIR=${TOR_LOG_DIR:-/var/log/tor}
RELAY_STATE=${RELAY_STATE:-/run/tor/relay.state}
PROC_ROOT=${PROC_ROOT:-/proc}

json_string() {
  printf '%s' "$1" | awk 'BEGIN {printf "\""} {if (NR>1) printf "\\n"; for (i=1;i<=length($0);i++) {c=substr($0,i,1); if(c=="\\") printf "\\\\"; else if(c=="\"") printf "\\\""; else if(c=="\t") printf "\\t"; else if(c=="\r") printf "\\r"; else printf "%s",c}} END {printf "\""}'
}
process_start() {
  [ -r "$PROC_ROOT/$1/stat" ] || return 1
  sed 's/.*) //' "$PROC_ROOT/$1/stat" | awk '{print $20}'
}
inspect_process() {
  TOR_PID=0; PROCESS_REASON=process_missing
  pids=$(for file in "$PROC_ROOT"/[0-9]*/comm; do
    [ -r "$file" ] || continue
    name=''; IFS= read -r name < "$file" || true
    if [ "$name" = tor ]; then
      directory=${file%/comm}
      command_line=$(tr '\000' '\n' 2>/dev/null < "$directory/cmdline") || continue
      [ -n "$command_line" ] || continue
      if printf '%s\n' "$command_line" | grep -qE '^--(verify-config|dump-config|version|hash-password|keygen)$'; then continue; fi
      printf '%s\n' "${directory##*/}"
    fi
  done)
  set -- $pids
  [ "$#" -gt 0 ] || return 1
  [ "$#" -eq 1 ] || { PROCESS_REASON=process_ambiguous; return 1; }
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  TOR_PID=$1
  START_TIME=$(process_start "$TOR_PID") || return 1
  [ -n "$START_TIME" ] || return 1
  active=$(tr '\000' '\n' < "$PROC_ROOT/$TOR_PID/cmdline" | awk 'next_arg {print; exit} $0=="-f" || $0=="--torrc-file" {next_arg=1}')
  [ -z "$active" ] || TOR_CONFIG=$active
  PROCESS_REASON=running
}
config_is_mounted() {
  awk -v config="$TOR_CONFIG" '$5==config || (index(config,$5 "/")==1 && $5 != "/") {found=1} END {exit !found}' /proc/self/mountinfo
}
config_source() {
  CONFIG_SOURCE=unknown
  if [ -s "$TOR_CONFIG" ]; then
    if config_is_mounted; then CONFIG_SOURCE=mounted
    elif head -n 1 "$TOR_CONFIG" | grep -q '^# Generated Tor configuration'; then CONFIG_SOURCE=environment
    else CONFIG_SOURCE=mounted; fi
  fi
}
config_valid() {
  [ -r "$TOR_CONFIG" ] && [ -s "$TOR_CONFIG" ] && tor --verify-config -f "$TOR_CONFIG" >/dev/null 2>&1
}
inspect_config_paths() {
  effective_data=$(tor --dump-config short -f "$TOR_CONFIG" 2>/dev/null | awk '$1=="DataDirectory" {sub(/^DataDirectory[[:space:]]+/,""); gsub(/^"|"$/,""); print; exit}')
  [ -z "$effective_data" ] || TOR_DATA_DIR=$effective_data
}
inspect_health() {
  LIVE=false; READY=false; CONFIG_VALID=false; FRESH=false
  BOOTSTRAP=0; REACHABLE=unknown; ERRORS=0; UPTIME=unknown
  REASON=process_missing; TOR_PID=0
  if inspect_process; then
    LIVE=true; REASON=bootstrap_pending
    UPTIME=$(ps -o pid=,etime= | awk -v p="$TOR_PID" '$1==p {print $2; exit}')
    [ -n "$UPTIME" ] || UPTIME=unknown
  else REASON=$PROCESS_REASON; fi
  config_source
  if config_valid; then CONFIG_VALID=true; else REASON=config_invalid; fi
  RELAY_MODE=${TOR_RELAY_MODE:-unknown}
  if [ -r "$TOR_CONFIG" ]; then
    if grep -qi '^BridgeRelay[[:space:]]\+1' "$TOR_CONFIG"; then RELAY_MODE=bridge
    elif grep -qi '^ExitRelay[[:space:]]\+1' "$TOR_CONFIG"; then RELAY_MODE='exit'; fi
  fi
  inspect_config_paths
  TOR_LOG=$TOR_LOG_DIR/notices.log
  if [ "$LIVE" = true ] && [ -r "$RELAY_STATE" ] && [ -r "$TOR_LOG" ]; then
    saved_pid=$(awk -F= '$1=="pid" {print $2}' "$RELAY_STATE")
    saved_start=$(awk -F= '$1=="start" {print $2}' "$RELAY_STATE")
    saved_inode=$(awk -F= '$1=="inode" {print $2}' "$RELAY_STATE")
    offset=$(awk -F= '$1=="offset" {print $2}' "$RELAY_STATE")
    case "$offset" in ''|*[!0-9]*) offset=0; saved_start=invalid ;; esac
    if [ "$saved_pid" = "$TOR_PID" ] && [ "$saved_start" = "$START_TIME" ] &&
       [ "$saved_inode" = "$(stat -c %i "$TOR_LOG")" ] && [ "$(stat -c %s "$TOR_LOG")" -ge "$offset" ]; then
      FRESH=true
      observation=$(tail -c "+$((offset + 1))" "$TOR_LOG" | awk '
        /Bootstrapped [0-9]+%/ {line=$0; sub(/.*Bootstrapped /,"",line); sub(/%.*/,"",line); bootstrap=line+0}
        /Self-testing indicates your ORPort.*is reachable from the outside/ {reach="true"}
        /ORPort not reachable|not managed to confirm reachability for its ORPort/ {reach="false"}
        /\[err\]/ {errors++}
        END {printf "%d %s %d",bootstrap,reach==""?"unknown":reach,errors}')
      set -- $observation; BOOTSTRAP=$1; REACHABLE=$2; ERRORS=$3
      if [ "$BOOTSTRAP" -eq 100 ] && [ "$CONFIG_VALID" = true ]; then READY=true; REASON=ready; fi
    else [ "$CONFIG_VALID" != true ] || REASON=observation_stale; fi
  elif [ "$LIVE" = true ] && [ "$CONFIG_VALID" = true ]; then REASON=observation_missing; fi
  [ "$LIVE" = true ] || REASON=$PROCESS_REASON
  NICKNAME=unknown; FINGERPRINT=unknown
  if [ -r "$TOR_DATA_DIR/fingerprint" ]; then
    NICKNAME=$(awk 'NR==1 {print $1}' "$TOR_DATA_DIR/fingerprint")
    FINGERPRINT=$(awk 'NR==1 {print $2}' "$TOR_DATA_DIR/fingerprint")
  fi
  TOR_VERSION=$(tor --version 2>/dev/null | head -n 1 | sed 's/^Tor version //;s/\.$//')
  BUILD_VERSION=$(awk -F': ' '/^Version:/ {print $2; exit}' "${BUILD_INFO:-/build-info.txt}" 2>/dev/null || true)
  [ -n "$BUILD_VERSION" ] || BUILD_VERSION=unknown
}
health_json() {
  status=down; [ "$LIVE" != true ] || status=up
  printf '{"status":"%s","pid":%s,"bootstrap":%s,"reachable":"%s","errors":%s,"liveness":%s,"readiness":%s,"config_valid":%s,"fresh":%s,"reason":"%s"' "$status" "$TOR_PID" "$BOOTSTRAP" "$REACHABLE" "$ERRORS" "$LIVE" "$READY" "$CONFIG_VALID" "$FRESH" "$REASON"
  for key in uptime nickname fingerprint tor_version relay_mode build_version config_source; do
    case "$key" in uptime) value=$UPTIME ;; nickname) value=$NICKNAME ;; fingerprint) value=$FINGERPRINT ;; tor_version) value=$TOR_VERSION ;; relay_mode) value=$RELAY_MODE ;; build_version) value=$BUILD_VERSION ;; config_source) value=$CONFIG_SOURCE ;; esac
    printf ',"%s":' "$key"; json_string "$value"
  done
  printf ',"config_path":'; json_string "$TOR_CONFIG"; printf '}\n'
}
