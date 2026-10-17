#!/bin/bash
# Rewrite the Display panel's managed block in ~/.config/hypr/monitors.lua.
#
# Called by Panel.qml after the user keeps a confirmed change. Everything
# outside the managed block is left untouched; the block is replaced with the
# list of monitor rules built from the JSON payload on argv[1].
#
# The global `hl.monitor({ output = "" ... })` catch-all stays above the block,
# and a per-output rule takes precedence over it, so a saved line wins on the
# next reload or login.
#
# Usage: save-layout.sh '<json>'
#   json: [ { "output": "DP-2", "mode": "2560x1440@164.84", "position": "0x0",
#             "scale": 1, "transform": 0, "mirror": "", "disabled": false }, ... ]

set -euo pipefail

CONFIG="${HYPR_MONITORS_LUA:-$HOME/.config/hypr/monitors.lua}"
MARK_BEGIN='display panel'
MARK_END='-- <<< display panel'

payload="${1:-[]}"

if ! printf '%s' "$payload" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "save-layout: invalid payload" >&2
  exit 1
fi

# Build one hl.monitor line per entry. Names/modes/positions are restricted to
# characters that are safe inside a Lua string; scale/transform must be
# numbers. The panel validates too — this is defence in depth.
block=$(printf '%s' "$payload" | jq -r '
  def okstr: tostring | if test("^[A-Za-z0-9._@-]*$") then . else empty end;
  .[]
  | . as $m
  | (($m.output | okstr) // "") as $out
  | select($out != "")
  | (($m.mode | okstr) // "preferred") as $mode
  | (($m.position | okstr) // "auto") as $pos
  | (($m.scale // 1) | tonumber) as $scale
  | (if $m.transform != null then ($m.transform | tonumber) else 0 end) as $tf
  | "hl.monitor({ output = \"" + $out + "\", mode = \"" + $mode + "\", position = \"" + $pos
    + "\", scale = " + ($scale | tostring)
    + ", transform = " + ($tf | tostring)
    + (if ($m.mirror // "") != "" then ", mirror = \"" + ($m.mirror | okstr) + "\"" else "" end)
    + (if $m.disabled == true then ", disabled = true" else "" end)
    + " })"
')

mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"

tmp=$(mktemp)
tmp2=$(mktemp)
trap 'rm -f "$tmp" "$tmp2"' EXIT

# Drop any previously managed block: from a BEGIN marker line through the END
# marker. Matching the BEGIN loosely lets old blocks with different wording be
# cleaned up as well.
awk -v begin="$MARK_BEGIN" -v end="$MARK_END" '
  index($0, "-- >>>") && index($0, begin) { skip = 1; next }
  $0 == end { skip = 0; next }
  !skip { print }
' "$CONFIG" > "$tmp"

# Trim trailing blank lines so repeated saves do not grow the file.
awk 'NF { last = NR } { lines[NR] = $0 } END { for (i = 1; i <= last; i++) print lines[i] }' "$tmp" > "$tmp2"

{
  cat "$tmp2"
  printf '%s\n' "-- >>> display panel: per-monitor layout saved by the Display panel"
  if [ -n "$block" ]; then printf '%s\n' "$block"; fi
  printf '%s\n' "$MARK_END"
} > "$CONFIG"

hyprctl reload >/dev/null 2>&1 || true
