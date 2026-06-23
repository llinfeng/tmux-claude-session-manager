#!/usr/bin/env bash
# Open the session picker in a popup, on the client that invoked it.
#
# Arg: <invoking-client> — expanded from #{client_name} by the key binding. Used
# to host the popup on the screen you actually pressed the key on, which matters
# once several clients are attached. Falls back to a heuristic when absent.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

# session_of <client> — the session a client is attached to (empty if not live).
session_of() {
  tmux list-clients -F '#{client_name}	#{session_name}' 2>/dev/null |
    awk -F'\t' -v c="$1" '$1 == c { print $2; exit }'
}

# nested_session — any client attached to a prefixed (popup) session. Used as a
# fallback to detect "we're inside a session popup" when the invoker is unknown.
nested_session() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v p="$prefix" 'index($2, p) == 1 { print $2; exit }'
}

# host_client — first client NOT attached to a prefixed session: a safe outer
# host for the popup (used for the nested case and as a last-resort fallback).
host_client() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v p="$prefix" 'index($2, p) != 1 { print $1; exit }'
}

# Trust the invoking client only if it's still a live client.
client="${1:-}"
[ -n "$client" ] && [ -n "$(session_of "$client")" ] || client=''

# Detect whether we were invoked from inside a session popup.
nested=''
if [ -n "$client" ]; then
  csession="$(session_of "$client")"
  [ "${csession#"$prefix"}" != "$csession" ] && nested="$csession"
else
  nested="$(nested_session)"
fi

if [ -n "$nested" ]; then
  # Close the popup we're inside, then host the picker full-size on an outer
  # client. -c is required here: the invoking client is gone after the detach.
  tmux detach-client -s "$nested"
  for _ in $(seq 1 100); do
    tmux list-clients -F '#{session_name}' 2>/dev/null | grep -q "^${prefix}" || break
    sleep 0.05
  done
  host="$(host_client)"
  tmux set-option -g @claude_parent "$host"
  if [ -n "$host" ]; then
    tmux display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh"
  else
    tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
  fi
else
  # Normal invocation: open on the client that pressed the key. Omit -c so tmux
  # hosts the popup on the invoking client (like the launcher) — correct even
  # with several clients attached, where guessing a host picks the wrong screen.
  tmux set-option -g @claude_parent "${client:-$(host_client)}"
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
fi
