#!/usr/bin/env bash
set -euo pipefail

DATA=$(cat)

# Extract fields via single jq call
IFS=$'\t' read -r MODEL MODEL_ID DIR PCT CTX_SIZE COST_RAW DURATION_MS TOK_IN TOK_OUT ADDED REMOVED < <(
    echo "$DATA" | jq -r '[
        (.model.display_name // "Claude"),
        (try (.model.id // "unknown") catch "unknown"),
        (.cwd // "~" | split("/") | last),
        (try (
    if (.context_window.remaining_percentage // null) != null then
      100 - (.context_window.remaining_percentage | floor)
    elif (.context_window.context_window_size // 0) > 0 then
      (((.context_window.current_usage.input_tokens // 0) +
        (.context_window.current_usage.cache_creation_input_tokens // 0) +
        (.context_window.current_usage.cache_read_input_tokens // 0)) * 100 /
       .context_window.context_window_size) | floor
    else 0 end
  ) catch 0),
        (.context_window.context_window_size // 200000),
        (.cost.total_cost_usd // 0),
        (.cost.total_duration_ms // 0),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_output_tokens // 0),
        (.cost.total_lines_added // 0),
        (.cost.total_lines_removed // 0)
    ] | @tsv'
)
COST=$(printf "%.2f" "$COST_RAW")
TOKENS=$((TOK_IN + TOK_OUT))
case "$MODEL_ID" in
  *opus*) TIER_ICON="◆" ;;
  *sonnet*) TIER_ICON="◇" ;;
  *haiku*) TIER_ICON="○" ;;
  *) TIER_ICON="●" ;;
esac

# Git info
BRANCH=$(git -c core.useBuiltinFSMonitor=false branch --show-current 2>/dev/null || echo "")

# Build progress bar
FILLED=$((PCT * 8 / 100))
EMPTY=$((8 - FILLED))
BAR=""
if [ "$PCT" -gt 80 ]; then BAR_CLR="\033[38;5;203m"
elif [ "$PCT" -gt 50 ]; then BAR_CLR="\033[38;5;222m"
else BAR_CLR="\033[38;5;157m"
fi
for ((i=0; i<FILLED; i++)); do
  BAR+="${BAR_CLR}█"
done
for ((i=0; i<EMPTY; i++)); do BAR+="\033[38;5;241m░"; done

# Format duration
TOTAL_SEC=$((DURATION_MS / 1000))
H=$((TOTAL_SEC / 3600))
M=$(((TOTAL_SEC % 3600) / 60))
S=$((TOTAL_SEC % 60))
if [ "$H" -gt 0 ]; then TIME="${H}h ${M}m"
elif [ "$M" -gt 0 ]; then TIME="${M}m ${S}s"
else TIME="${S}s"
fi

# Threshold colors
if [ "$PCT" -gt 80 ]; then CTX_CLR="\033[38;5;203m"
elif [ "$PCT" -gt 50 ]; then CTX_CLR="\033[38;5;222m"
else CTX_CLR="\033[38;5;157m"
fi
if (( $(echo "$COST > 10" | bc -l) )); then COST_CLR="\033[38;5;203m"
elif (( $(echo "$COST > 2" | bc -l) )); then COST_CLR="\033[38;5;222m"
else COST_CLR="\033[38;5;157m"
fi

echo -e "\033[38;5;117;1m$TIER_ICON\033[0m \033[38;5;111;1m$MODEL\033[0m\033[2m\033[38;5;241m │ \033[0m\033[38;5;111m📁 $DIR\033[0m\033[2m\033[38;5;241m │ \033[0m$([ -n "$BRANCH" ] && printf '%b' "\033[38;5;176m🌿 $BRANCH\033[0m") \033[2m\033[38;5;241m│\033[0m\033[38;5;157m+$ADDED\033[0m \033[38;5;203m-$REMOVED\033[0m\033[0m"
echo -e "$BAR\033[0m ${CTX_CLR}$PCT%\033[0m\033[2m\033[38;5;241m │ \033[0m${COST_CLR}\$$COST\033[0m\033[2m\033[38;5;241m │ \033[0m\033[38;5;176m$TOKENS tok\033[0m\033[2m\033[38;5;241m │ \033[0m\033[38;5;111m$TIME\033[0m\033[0m"
