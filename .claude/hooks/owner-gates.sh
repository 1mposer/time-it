#!/bin/bash
# SessionStart hook — surface stale owner gates (session retro, 2026-10-01).
# Prints every doc line still waiting on an owner action so the agent can
# report ages instead of discovering the backlog mid-task.
cd "$(dirname "$0")/../.." || exit 0
matches=$(grep -rn -iE "awaiting owner|awaiting dispatch|flagged, not decided|owner glance owed|pending the owner" docs --include="*.md" 2>/dev/null | grep -v "issues/completed/" | cut -c1-250)
if [ -n "$matches" ]; then
  echo "WAITING-ON-OWNER — doc lines still gated on an owner action (compare their dates to today and surface anything stale):"
  echo "$matches"
fi
exit 0
