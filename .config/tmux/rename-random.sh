#!/usr/bin/env bash
# Tmux hook helper. Renames a freshly-created session (+ its initial window)
# or a freshly-created window to a random name from random-name.sh.
#
# Only renames entities whose name still looks like a tmux default — so
# explicit `tmux new-session -s NAME` / `new-window -n NAME` survive:
#   • session default = pure numeric ("0", "1", ...)
#   • window  default = basename of the shell tmux launched (zsh, bash, ...)
#
# Called from .tmux.conf:
#   rename-random.sh session <SESSION_ID>   (from session-created)
#   rename-random.sh window  <WINDOW_ID>    (from after-new-window)
# IDs come from tmux via #{q:hook_session} / #{q:window_id}; the q modifier
# shell-escapes the leading $ so bash doesn't expand $0 → "sh".

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAND="$DIR/random-name.sh"

# Candidate "default window name" set: well-known shell basenames + the user's
# own $SHELL basename, so we cover non-listed shells (e.g. nushell from brew).
shell_base="$(basename "${SHELL:-/bin/sh}")"
default_win_names="|zsh|bash|fish|sh|dash|nu|nushell|xonsh|tcsh|ksh|${shell_base}|"

is_default_sess() { [[ -z "$1" || "$1" =~ ^[0-9]+$ ]]; }
is_default_win()  { [[ -z "$1" ]] || [[ "$default_win_names" == *"|$1|"* ]]; }

# Wrap RAND so an empty/failed output never causes a blank rename.
pick() { local n; n=$("$RAND" 2>/dev/null); [ -n "$n" ] && printf '%s' "$n"; }

case "$1" in
  session)
    sid="$2"; [ -n "$sid" ] || exit 0
    sname=$(tmux display -p -t "$sid" '#{session_name}' 2>/dev/null)
    if is_default_sess "$sname"; then
      n=$(pick); [ -n "$n" ] && tmux rename-session -t "$sid" "$n"
    fi
    # after-new-window doesn't fire for the initial window in a fresh session,
    # so rename :^ (session's first window) here too — same default-name guard.
    wname=$(tmux display -p -t "$sid:^" '#{window_name}' 2>/dev/null)
    if is_default_win "$wname"; then
      n=$(pick); [ -n "$n" ] && tmux rename-window -t "$sid:^" "$n"
    fi
    ;;
  window)
    wid="$2"; [ -n "$wid" ] || exit 0
    wname=$(tmux display -p -t "$wid" '#{window_name}' 2>/dev/null)
    if is_default_win "$wname"; then
      n=$(pick); [ -n "$n" ] && tmux rename-window -t "$wid" "$n"
    fi
    ;;
esac
exit 0
