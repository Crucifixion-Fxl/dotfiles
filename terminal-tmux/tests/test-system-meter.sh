#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
METER="$ROOT/tmux/system-meter.sh"

bash -n "$METER"

mac_output=$(
  TMUX_SYSTEM_METER_OS=Darwin \
    TMUX_SYSTEM_METER_BATTERY_PERCENTAGE=75 \
    "$METER"
)
[[ $mac_output == 'BAT  [========..]  75%' ]]

linux_output=$(
  TMUX_SYSTEM_METER_OS=Linux \
    TMUX_SYSTEM_METER_LOAD1=4 \
    TMUX_SYSTEM_METER_CPU_COUNT=8 \
    "$METER"
)
[[ $linux_output == 'LOAD [=====.....]  50%' ]]

capped_output=$(
  TMUX_SYSTEM_METER_OS=Linux \
    TMUX_SYSTEM_METER_LOAD1=20 \
    TMUX_SYSTEM_METER_CPU_COUNT=4 \
    "$METER"
)
[[ $capped_output == 'LOAD [==========] 100%' ]]

custom_width_output=$(
  TMUX_SYSTEM_METER_OS=Linux \
    TMUX_SYSTEM_METER_LOAD1=0 \
    TMUX_SYSTEM_METER_CPU_COUNT=8 \
    TMUX_SYSTEM_METER_WIDTH=5 \
    "$METER"
)
[[ $custom_width_output == 'LOAD [.....]   0%' ]]
