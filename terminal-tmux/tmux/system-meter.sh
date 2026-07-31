#!/usr/bin/env bash

set -u

# tmux 状态栏的跨平台进度指标：
#   - macOS 笔记本显示电量；
#   - Linux/容器没有电池，显示按 CPU 核数归一化的 1 分钟负载。
# 进度条只使用 ASCII，避免旧 tmux server 在 locale 初始化失败时
# 把 Nerd Font/Unicode 字符替换成下划线。

bar_width=${TMUX_SYSTEM_METER_WIDTH:-10}
case "$bar_width" in
  ''|*[!0-9]*) bar_width=10 ;;
esac
if ((bar_width < 5 || bar_width > 20)); then
  bar_width=10
fi

system_name=${TMUX_SYSTEM_METER_OS:-$(uname -s 2>/dev/null || printf unknown)}
label=LOAD
percentage=

battery_percentage() {
  if [[ -n ${TMUX_SYSTEM_METER_BATTERY_PERCENTAGE:-} ]]; then
    printf '%s\n' "$TMUX_SYSTEM_METER_BATTERY_PERCENTAGE"
    return
  fi

  command -v pmset >/dev/null 2>&1 || return
  pmset -g batt 2>/dev/null | grep -Eo '[0-9]{1,3}%' | head -n 1 | tr -d '%'
}

load_percentage() {
  local load_one processors
  load_one=${TMUX_SYSTEM_METER_LOAD1:-}
  processors=${TMUX_SYSTEM_METER_CPU_COUNT:-}

  if [[ -z $load_one ]]; then
    if [[ -r /proc/loadavg ]]; then
      read -r load_one _ < /proc/loadavg
    elif command -v sysctl >/dev/null 2>&1; then
      load_one=$(sysctl -n vm.loadavg 2>/dev/null | LC_ALL=C awk '
        {
          for (index = 1; index <= NF; index++) {
            if ($index ~ /^[0-9]+([.][0-9]+)?$/) {
              print $index
              exit
            }
          }
        }
      ')
    fi
  fi

  if [[ -z $processors ]]; then
    processors=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
  fi
  if [[ -z $processors && $system_name == Darwin ]]; then
    processors=$(sysctl -n hw.logicalcpu 2>/dev/null || true)
  fi

  [[ $load_one =~ ^[0-9]+([.][0-9]+)?$ ]] || load_one=0
  [[ $processors =~ ^[1-9][0-9]*$ ]] || processors=1
  LC_ALL=C awk -v load="$load_one" -v cpus="$processors" '
    BEGIN {
      percentage = int((load * 100 / cpus) + 0.5)
      if (percentage < 0) percentage = 0
      if (percentage > 100) percentage = 100
      print percentage
    }
  '
}

if [[ $system_name == Darwin ]]; then
  percentage=$(battery_percentage)
  if [[ $percentage =~ ^[0-9]+$ ]]; then
    label=BAT
  else
    percentage=$(load_percentage)
  fi
else
  percentage=$(load_percentage)
fi

[[ $percentage =~ ^[0-9]+$ ]] || percentage=0
((percentage < 0)) && percentage=0
((percentage > 100)) && percentage=100

filled=$(((percentage * bar_width + 99) / 100))
((filled > bar_width)) && filled=$bar_width
empty=$((bar_width - filled))

filled_bar=
empty_bar=
for ((index = 0; index < filled; index++)); do
  filled_bar+='='
done
for ((index = 0; index < empty; index++)); do
  empty_bar+='.'
done

printf '%-4s [%s%s] %3d%%\n' "$label" "$filled_bar" "$empty_bar" "$percentage"
