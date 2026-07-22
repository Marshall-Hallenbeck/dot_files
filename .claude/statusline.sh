#!/usr/bin/env bash
set -euo pipefail

DATA=$(cat)

# Exit cleanly when called before session data is available (initial startup)
if [[ -z "$DATA" ]] || ! echo "$DATA" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

# Extract fields via single jq call
IFS=$'\t' read -r MODEL MODEL_ID EFFORT DIR PCT COST_RAW DURATION_MS TOK_IN TOK_OUT ADDED REMOVED THINKING FAST STYLE AGENT CTX_SIZE Q5H_PCT Q5H_RESET Q7D_PCT Q7D_RESET < <(
    echo "$DATA" | jq -r '[
        (.model.display_name // "Claude"),
        (try (.model.id // "unknown") catch "unknown"),
        (.effort.level // "none"),
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
        (.cost.total_cost_usd // 0),
        (.cost.total_duration_ms // 0),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_output_tokens // 0),
        (.cost.total_lines_added // 0),
        (.cost.total_lines_removed // 0),
        (.thinking.enabled // false),
        (.fast_mode // false),
        (.output_style.name // "default" | if . == "" then "default" else . end),
        (.agent.name // "none" | if . == "" then "none" else . end),
        (.context_window.context_window_size // 200000),
        ((.rate_limits.five_hour.used_percentage // -1) | floor),
        ((.rate_limits.five_hour.resets_at // 0) | floor),
        ((.rate_limits.seven_day.used_percentage // -1) | floor),
        ((.rate_limits.seven_day.resets_at // 0) | floor)
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

# Effort level (omitted from JSON when model has no effort parameter)
EFFORT_PART=""
if [[ "$EFFORT" != "none" ]]; then
  case "$EFFORT" in
    low) EFFORT_CLR="\033[38;5;157m" ;;
    medium) EFFORT_CLR="\033[38;5;222m" ;;
    high) EFFORT_CLR="\033[38;5;215m" ;;
    xhigh|max) EFFORT_CLR="\033[38;5;203m" ;;
    *) EFFORT_CLR="\033[38;5;241m" ;;
  esac
  EFFORT_PART=" ${EFFORT_CLR}⚡$EFFORT\033[0m"
fi

# Session-mode glyphs: thinking enabled, fast mode
THINK_PART=""
[[ "$THINKING" == "true" ]] && THINK_PART=" 💭"
FAST_PART=""
[[ "$FAST" == "true" ]] && FAST_PART=" ⏩"

# Output style and active agent (hidden when default/absent)
STYLE_PART=""
[[ "$STYLE" != "default" ]] && STYLE_PART="\033[2m\033[38;5;241m │ \033[0m\033[38;5;245m✍ $STYLE\033[0m"
AGENT_PART=""
[[ "$AGENT" != "none" ]] && AGENT_PART="\033[2m\033[38;5;241m │ \033[0m\033[38;5;117m🤖 $AGENT\033[0m"

# Human-readable context window size (200k, 1M)
if [ "$CTX_SIZE" -ge 1000000 ]; then CTX_HUMAN="$((CTX_SIZE / 1000000))M"
else CTX_HUMAN="$((CTX_SIZE / 1000))k"
fi

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
if awk "BEGIN{exit !($COST > 10)}"; then COST_CLR="\033[38;5;203m"
elif awk "BEGIN{exit !($COST > 2)}"; then COST_CLR="\033[38;5;222m"
else COST_CLR="\033[38;5;157m"
fi

# 5h/7d quota comes native from statusline stdin (.rate_limits, absent on old
# CC versions). The Hermes cache (~/.hermes/scripts/quota_scraper.py) is read
# only for the Fable 7d bucket, which the native schema doesn't break out.
# Statusline rendering must stay fast and make no network calls.
QUOTA_TXT=""
NOW=$(date +%s)
if [ "$Q5H_PCT" -ge 0 ]; then
  QUOTA_TXT="5h ${Q5H_PCT}%"
  if [ "$Q5H_RESET" -gt "$NOW" ]; then
    MIN_LEFT=$(( (Q5H_RESET - NOW) / 60 ))
    if [ "$MIN_LEFT" -ge 60 ]; then QUOTA_TXT+=" ($((MIN_LEFT / 60))h)"
    else QUOTA_TXT+=" (${MIN_LEFT}m)"
    fi
  fi
fi
if [ "$Q7D_PCT" -ge 0 ]; then
  QUOTA_TXT+="${QUOTA_TXT:+ }7d ${Q7D_PCT}%"
  [ "$Q7D_RESET" -gt "$NOW" ] && QUOTA_TXT+=" ($(date -d "@$Q7D_RESET" +%a))"
fi
QUOTA_CACHE="$HOME/.hermes/cache/provider_quota_status.json"
if [[ -r "$QUOTA_CACHE" ]]; then
  QFABLE=$(jq -r '.claude.limits["7d_fable"].used_percent // empty' "$QUOTA_CACHE" 2>/dev/null || true)
  [[ -n "$QFABLE" ]] && QUOTA_TXT+="${QUOTA_TXT:+ }Fable ${QFABLE%.*}%"
fi
QUOTA_PART=""
if [[ -n "$QUOTA_TXT" ]]; then
  QREF=$Q7D_PCT
  [ "$QREF" -lt 0 ] && QREF=$Q5H_PCT
  if [ "$QREF" -gt 80 ]; then QUOTA_CLR="\033[38;5;203m"
  elif [ "$QREF" -gt 50 ]; then QUOTA_CLR="\033[38;5;222m"
  else QUOTA_CLR="\033[38;5;157m"
  fi
  QUOTA_PART="\033[2m\033[38;5;241m │ \033[0m${QUOTA_CLR}Claude ${QUOTA_TXT}\033[0m"
fi

echo -e "\033[38;5;117;1m$TIER_ICON\033[0m \033[38;5;111;1m$MODEL\033[0m${EFFORT_PART}${THINK_PART}${FAST_PART}${STYLE_PART}${AGENT_PART}\033[2m\033[38;5;241m │ \033[0m\033[38;5;111m📁 $DIR\033[0m\033[2m\033[38;5;241m │ \033[0m$([ -n "$BRANCH" ] && printf '%b' "\033[38;5;176m🌿 $BRANCH\033[0m") \033[2m\033[38;5;241m│\033[0m\033[38;5;157m+$ADDED\033[0m \033[38;5;203m-$REMOVED\033[0m\033[0m"
echo -e "$BAR\033[0m ${CTX_CLR}$PCT%\033[0m\033[2m\033[38;5;241m/$CTX_HUMAN │ \033[0m${COST_CLR}\$$COST\033[0m\033[2m\033[38;5;241m │ \033[0m\033[38;5;176m$TOKENS tok\033[0m\033[2m\033[38;5;241m │ \033[0m\033[38;5;111m$TIME\033[0m${QUOTA_PART}\033[0m"
