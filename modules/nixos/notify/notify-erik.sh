# notify-erik: send a push notification to Erik's phone through ntfy
# (homelab repo, docs/notifications.md). The `notify` skill says when to use it.
# Same policy as the Executor app `notify`; the limits below keep agents from
# spamming him. Rate-limited or duplicate sends exit 3: do not retry them.

server="https://ntfy.erikfrankling.duckdns.org"
topic="erik"
state="${XDG_STATE_HOME:-$HOME/.local/state}/notify-erik"
token_file="${NOTIFY_ERIK_TOKEN_FILE:-/run/secrets/ntfy-agents-token}"

usage() {
  cat <<'EOF'
usage: notify-erik [options] MESSAGE
       notify-erik --code CODE [options] [MESSAGE]
       notify-erik status

  -t, --title TEXT      short title (default: "Agent on <host>")
  -p, --priority P      urgent | high | normal (default) | low
      --code CODE       one-time code: pops up, "Copy" button, own budget
      --thread ID       tap opens this T3 thread (from t3_thread_list currentThreadId)
      --env ID          T3 environment of --thread (default: this machine's)
      --link URL        tap opens URL instead
      --tags a,b        ntfy tags/emoji shortcodes (e.g. warning,robot)
      --markdown        render MESSAGE as Markdown
      --test            label as a test ("[TEST]" title prefix)
      --dry-run         print the request instead of sending

Limits (per machine; the Executor app has the same): urgent 4/h,
everything but codes 12/h and 40/day, codes 6 per 10 min and 30/day,
an identical notification within 15 min is dropped. Exit 3 = not sent because of a limit.
EOF
}

title="" priority="normal" code="" thread="" env="" link="" tags="" markdown=false test=false dry=false
if [ "${1:-}" = status ]; then
  mkdir -p "$state"; touch "$state/sent"
  now=$(date +%s)
  echo "sent in the last hour: $(awk -v t=$((now - 3600)) '$1 >= t && $2 != "code"' "$state/sent" | wc -l)/12, today: $(awk -v t=$((now - 86400)) '$1 >= t && $2 != "code"' "$state/sent" | wc -l)/40"
  echo "last 5:"; tail -n 5 "$state/log" 2>/dev/null || true
  exit 0
fi
while [ $# -gt 0 ]; do
  case "$1" in
    -t | --title) title="$2"; shift 2 ;;
    -p | --priority) priority="$2"; shift 2 ;;
    --code) code="$2"; shift 2 ;;
    --thread) thread="$2"; shift 2 ;;
    --env) env="$2"; shift 2 ;;
    --link) link="$2"; shift 2 ;;
    --tags) tags="$2"; shift 2 ;;
    --markdown) markdown=true; shift ;;
    --test) test=true; shift ;;
    --dry-run) dry=true; shift ;;
    -h | --help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "notify-erik: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done
message="$*"

case "$priority" in
  urgent) prio=5 ;; high) prio=4 ;; normal) prio=3 ;; low) prio=2 ;;
  *) echo "notify-erik: priority must be urgent, high, normal or low" >&2; exit 2 ;;
esac
class="$priority"
if [ -n "$code" ]; then
  class=code prio=4
  [ -n "$title" ] || title="Code: $code"
  [ -n "$message" ] || message="One-time code $code (tap Copy)"
fi
if [ -z "$message" ]; then usage >&2; exit 2; fi
[ -n "$title" ] || title="Agent on $(hostname)"
if $test; then title="[TEST] $title"; fi
if [ ${#title} -gt 120 ] || [ ${#message} -gt 3000 ]; then
  echo "notify-erik: keep the title under 120 and the message under 3000 characters" >&2; exit 2
fi

click=""
if [ -n "$thread" ]; then
  [ -n "$env" ] || env=$(cat "$HOME/.t3/userdata/environment-id" 2>/dev/null || true)
  if [ -z "$env" ]; then echo "notify-erik: no T3 environment id; pass --env" >&2; exit 2; fi
  click="t3code-preview://threads/$(jq -rn --arg s "$env" '$s|@uri')/$(jq -rn --arg s "$thread" '$s|@uri')"
elif [ -n "$link" ]; then
  click="$link"
fi

body=$(jq -n --arg topic "$topic" --arg title "$title" --arg message "$message" \
  --argjson priority "$prio" --arg tags "$tags" --arg click "$click" --arg code "$code" \
  --argjson markdown "$markdown" --arg host "$(hostname)" '
  {topic: $topic, title: $title, message: $message, priority: $priority,
   tags: ([$tags | split(",")[] | select(. != "")] + [$host]), markdown: $markdown}
  + (if $click != "" then {click: $click} else {} end)
  + (if $code != "" then {actions: [{action: "copy", label: "Copy code", value: $code, clear: false}]} else {} end)')

if $dry; then echo "$body"; exit 0; fi

mkdir -p "$state"
exec 9>"$state/lock"
flock 9
touch "$state/sent"
now=$(date +%s)
count() { awk -v t=$((now - $1)) -v c="$2" '$1 >= t && (c == "" ? $2 != "code" : $2 == c)' "$state/sent" | wc -l; }
digest=$(printf '%s\n%s' "$title" "$message" | sha256sum | cut -c1-16)
refuse() {
  echo "notify-erik: NOT SENT: $1. Do not retry; put it in your final report instead." >&2
  echo "$(date -Iseconds) refused ($1): $title" >>"$state/log"
  exit 3
}
if awk -v t=$((now - 900)) -v d="$digest" '$1 >= t && $3 == d' "$state/sent" | grep -q .; then
  refuse "the same notification was sent in the last 15 minutes"
fi
case "$class" in
  urgent) [ "$(count 3600 urgent)" -lt 4 ] || refuse "4 urgent notifications in the last hour" ;;
  code)
    [ "$(count 600 code)" -lt 6 ] || refuse "6 codes in the last 10 minutes"
    [ "$(count 86400 code)" -lt 30 ] || refuse "30 codes in the last 24 hours"
    ;;
esac
# Codes have their own budget: Erik is waiting for them.
if [ "$class" != code ]; then
  [ "$(count 3600 "")" -lt 12 ] || refuse "12 notifications in the last hour"
  [ "$(count 86400 "")" -lt 40 ] || refuse "40 notifications in the last 24 hours"
fi

if [ ! -r "$token_file" ]; then echo "notify-erik: cannot read $token_file" >&2; exit 1; fi
response=$(curl -sS --max-time 20 -H "Authorization: Bearer $(cat "$token_file")" \
  -H "Content-Type: application/json" -d "$body" -w '\n%{http_code}' "$server/") || {
  echo "notify-erik: ntfy unreachable ($server)" >&2; exit 1
}
status=$(tail -n 1 <<<"$response")
if [ "$status" != 200 ]; then
  echo "notify-erik: ntfy answered $status: $(head -n 1 <<<"$response")" >&2; exit 1
fi
echo "$now $class $digest" >>"$state/sent"
awk -v t=$((now - 172800)) '$1 >= t' "$state/sent" >"$state/sent.new" && mv "$state/sent.new" "$state/sent"
echo "$(date -Iseconds) sent ($class): $title" >>"$state/log"
echo "sent: $(head -n 1 <<<"$response" | jq -r '.id // empty')"
