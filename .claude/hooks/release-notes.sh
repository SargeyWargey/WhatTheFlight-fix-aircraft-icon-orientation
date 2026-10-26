#!/bin/bash
# Release-note safety net for TestFlight builds (see CLAUDE.md, "Release notes").
#   track  PostToolUse (Edit|Write|MultiEdit|Bash): mark this session when it changes
#          app code; clear the mark when it writes a note in ReleaseNotes/unreleased/.
#   check  Stop: if the mark is set, ask Claude once to add a note (or say why the
#          change isn't user-visible), then clear it, so it reminds at most once per
#          batch of edits.
# State is one file per session in .claude/state/release-notes/ (gitignored), so
# sessions running side by side don't see each other's marks.

input=$(cat)
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
session=$(jq -r '.session_id // empty' <<<"$input")
[ -n "$session" ] || exit 0
state="$root/.claude/state/release-notes"
marker="$state/$session"

# Files that ship in the iPhone, iPad, Apple TV and Apple Watch apps.
is_app_file() {
  case "${1#"$root"/}" in
    WhatTheFlight/WhatTheFlight/Legacy/*) return 1 ;;
    WhatTheFlight/WhatTheFlight/* | WhatTheFlight/WhatTheFlightWatch/* | \
    WhatTheFlight/WhatTheFlightWidgets/* | WhatTheFlight/WhatTheFlightWatchWidgets/* | \
    WhatTheFlight/WhatTheFlightTopShelf/* | WhatTheFlight/Config/*) return 0 ;;
  esac
  return 1
}

case "${1:-}" in
track)
  cwd=$(jq -r '.cwd // empty' <<<"$input")
  wrote_note=false
  if [ "$(jq -r '.tool_name // empty' <<<"$input")" = Bash ]; then
    # Files the command changed, when Claude Code reports them alongside the output.
    files=$(jq -r '.tool_response | if type == "object" then del(.stdout, .stderr) | .. | strings else empty end' <<<"$input" 2>/dev/null)
    jq -r '.tool_input.command // ""' <<<"$input" | grep -q 'ReleaseNotes/unreleased/[^[:space:]]*\.md' && wrote_note=true
  else
    files=$(jq -r '.tool_input.file_path // empty' <<<"$input")
  fi
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$file" in /*) ;; *) file="${cwd:-$root}/$file" ;; esac
    case "${file#"$root"/}" in ReleaseNotes/unreleased/*.md) wrote_note=true; continue ;; esac
    if is_app_file "$file"; then
      mkdir -p "$state"
      echo "${file#"$root"/}" >>"$marker"
    fi
  done <<<"$files"
  if $wrote_note; then rm -f "$marker"; fi
  exit 0
  ;;
check)
  [ -s "$marker" ] || exit 0
  changed=$(sort -u "$marker" | head -10 | sed 's/^/  - /')
  rm -f "$marker"
  [ "$(jq -r '.stop_hook_active // false' <<<"$input")" = true ] && exit 0
  cat >&2 <<EOF
Release notes: this session changed app code since its last note in ReleaseNotes/unreleased/:
$changed
If a TestFlight tester would notice the change, add or update this session's note now (format in CLAUDE.md, "Release notes"). If not (refactor, tests, tooling, or already covered by a note), say so in one line; no note needed.
EOF
  exit 2
  ;;
esac
exit 0
