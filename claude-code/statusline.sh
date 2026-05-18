#!/bin/bash
input=$(cat)

# ─── helpers ─────────────────────────────────────────
make_bar() {
  local pct=$1
  local width=10
  local filled=$((pct * width / 100))
  local empty=$((width - filled))
  local bar=""
  [ "$filled" -gt 0 ] && printf -v fill "%${filled}s" && bar="${fill// /▓}"
  [ "$empty" -gt 0 ] && printf -v pad "%${empty}s" && bar="${bar}${pad// /░}"
  echo "$bar"
}

fmt_tok() {
  awk -v n="$1" 'BEGIN{
    if (n>=1000000) printf "%.1fM", n/1000000;
    else if (n>=1000)    printf "%.1fk", n/1000;
    else                 printf "%d", n;
  }'
}

detect_auth_mode() {
  if   [ -n "$ANTHROPIC_FOUNDRY_RESOURCE" ];  then echo "foundry"
  elif [ "$CLAUDE_CODE_USE_BEDROCK" = "1" ];  then echo "bedrock"
  elif [ "$CLAUDE_CODE_USE_VERTEX" = "1" ];   then echo "vertex"
  elif [ -n "$ANTHROPIC_API_KEY" ];           then echo "api"
  else                                             echo "claude_ai"
  fi
}

# ─── parse input (single jq call) ────────────────────
IFS=$'\t' read -r MODEL CWD_FULL STYLE CTX_USED CTX_SIZE COST INPUT_TOK OUTPUT_TOK LIMIT_5H LIMIT_7D < <(
  echo "$input" | jq -r '[
    (.model.display_name                               // "unknown"),
    (.workspace.current_dir                            // ""),
    (.output_style.name                                // ""),
    (.context_window.total_input_tokens                // 0),
    (.context_window.context_window_size               // 200000),
    (.cost.total_cost_usd                              // 0),
    (.context_window.total_input_tokens                // 0),
    (.context_window.total_output_tokens               // 0),
    (.rate_limits.five_hour.used_percentage            // 0 | floor),
    (.rate_limits.seven_day.used_percentage            // 0 | floor)
  ] | @tsv'
)

# context window usage percentage
if [ "$CTX_SIZE" -gt 0 ] 2>/dev/null; then
  CTX=$(( CTX_USED * 100 / CTX_SIZE ))
else
  CTX=0
fi

# ─── general ─────────────────────────────────────────
GIT_ROOT=$(cd "$CWD_FULL" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
CWD=$(basename "${GIT_ROOT:-$CWD_FULL}" 2>/dev/null)

# branch from git directly
BRANCH=$(git -C "$CWD_FULL" branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] && BRANCH="no-branch"

# git dirty flag
DIRTY=""
if [ -n "$CWD_FULL" ] && [ -d "$CWD_FULL" ]; then
  if (cd "$CWD_FULL" && [ -n "$(git status --porcelain 2>/dev/null)" ]); then
    DIRTY="*"
  fi
fi

# docker environment
ENV_TAG=""
[ -f /.dockerenv ] && ENV_TAG=" 🐳"

CTX_BAR=$(make_bar "$CTX")

# ─── auth ────────────────────────────────────────────
AUTH=$(detect_auth_mode)

case "$AUTH" in
  claude_ai)
    BAR_5H=$(make_bar "$LIMIT_5H")
    BAR_7D=$(make_bar "$LIMIT_7D")
    USAGE_LINE="5h $BAR_5H ${LIMIT_5H}% │ 7d $BAR_7D ${LIMIT_7D}%"
    BADGE="🅿"
    ;;
  api|foundry|bedrock|vertex)
    USAGE_LINE="in $(fmt_tok "$INPUT_TOK") │ out $(fmt_tok "$OUTPUT_TOK") │ \$$(printf '%.3f' "$COST")"
    case "$AUTH" in
      api)     BADGE="☁API" ;;
      foundry) BADGE="☁AZR" ;;
      bedrock) BADGE="☁AWS" ;;
      vertex)  BADGE="☁GCP" ;;
    esac
    ;;
esac

# style tag
STYLE_TAG=""
[ -n "$STYLE" ] && [ "$STYLE" != "default" ] && [ "$STYLE" != "normal" ] && STYLE_TAG=" ⚙$STYLE"

# ─── output ──────────────────────────────────────────
echo "[$BADGE $MODEL]$ENV_TAG ctx $CTX_BAR ${CTX}% │ $USAGE_LINE"
echo "⎇ ${BRANCH}${DIRTY}  📁 ${CWD}${STYLE_TAG}"
