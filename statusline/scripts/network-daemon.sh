#!/usr/bin/env bash

CACHE_DIR="$HOME/.claude/cache"
STATE_FILE="$CACHE_DIR/network-status"
PID_FILE="$CACHE_DIR/network-daemon.pid"
PING_TARGET="1.1.1.1"
PING_TIMEOUT=2
INTERVAL=5
SLOW_THRESHOLD=300
OFFLINE_THRESHOLD=3
SLOW_THRESHOLD_COUNT=2
RECONNECTED_DURATION=5

mkdir -p "$CACHE_DIR"

# Exit if another instance is already running
if [ -f "$PID_FILE" ]; then
  existing_pid=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    exit 0
  fi
fi

echo $$ > "$PID_FILE"

cleanup() {
  rm -f "$PID_FILE"
  exit 0
}
trap cleanup EXIT INT TERM

fail_count=0
slow_count=0
prev_state="online"
reconnected_at=0

write_state() {
  local state="$1" latency="$2"
  local tmp="$STATE_FILE.tmp"
  cat > "$tmp" <<EOF
STATE=$state
LATENCY=$latency
TIMESTAMP=$(date +%s)
RECONNECTED_AT=$reconnected_at
EOF
  mv -f "$tmp" "$STATE_FILE"
}

while true; do
  # Run ping and capture output
  ping_output=$(ping -c1 -W "$PING_TIMEOUT" "$PING_TARGET" 2>/dev/null)
  ping_exit=$?

  latency=-1
  if [ $ping_exit -eq 0 ]; then
    # Extract avg RTT from summary line (e.g., "round-trip min/avg/max/stddev = 12.3/14.5/16.7/1.2 ms")
    latency=$(echo "$ping_output" | grep -oE 'round-trip.*= [0-9.]+/([0-9.]+)' | grep -oE '/[0-9.]+' | head -1 | tr -d '/' | cut -d. -f1)
    [ -z "$latency" ] && latency=-1
  fi

  # Determine state
  if [ $ping_exit -ne 0 ] || [ "$latency" -eq -1 ]; then
    # Ping failed
    fail_count=$((fail_count + 1))
    slow_count=0

    if [ $fail_count -ge $OFFLINE_THRESHOLD ]; then
      state="offline"
    else
      state="$prev_state"
    fi
  else
    # Ping succeeded
    fail_count=0

    # Check if reconnecting from offline
    if [ "$prev_state" = "offline" ]; then
      state="reconnected"
      reconnected_at=$(date +%s)
    elif [ "$prev_state" = "reconnected" ]; then
      now=$(date +%s)
      elapsed=$((now - reconnected_at))
      if [ $elapsed -ge $RECONNECTED_DURATION ]; then
        state="online"
        reconnected_at=0
      else
        state="reconnected"
      fi
    else
      # Check for slow connection
      if [ "$latency" -gt $SLOW_THRESHOLD ]; then
        slow_count=$((slow_count + 1))
      else
        slow_count=0
      fi

      if [ $slow_count -ge $SLOW_THRESHOLD_COUNT ]; then
        state="slow"
      else
        state="online"
      fi
    fi
  fi

  write_state "$state" "$latency"
  prev_state="$state"

  sleep "$INTERVAL"
done
