#!/bin/bash
#
# Purpose: Keep one version number for one content of the plugin. Claude Code hands people
#          who have Doorbell installed nothing new until the number in plugin.json changes,
#          so a change in the plugin that kept its number would reach nobody, and two
#          contents would carry one name.
# Inputs:  One command: check, version or notes. Run in a clone that has the release tags.
# Outputs: version: the version in plugin.json. notes: that version's section of the
#          changelog. check: nothing when all agrees; otherwise the reason on stderr and
#          exit code 1.

set -u
cd "$(dirname "$0")/../.." || exit 1

PLUGIN_DIR="plugins/doorbell"
MANIFEST="$PLUGIN_DIR/.claude-plugin/plugin.json"
CHANGELOG="CHANGELOG.md"

version=$(jq -r '.version // empty' "$MANIFEST" 2>/dev/null)

die() { printf 'release check: %s\n' "$1" >&2; exit 1; }

# A section runs from its "## <version>" heading to the next heading of that level.
notes() {
  awk -v wanted="$version" '
    /^## / { if (found) exit; found = ($2 == wanted); next }
    found  { print }' "$CHANGELOG"
}

check() {
  local newest
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "the version in $MANIFEST must be three numbers such as 1.2.3, not '${version:-nothing}'."

  newest=$(awk '/^## / { print $2; exit }' "$CHANGELOG")
  [ "$newest" = "$version" ] \
    || die "plugin.json says $version, but the newest section of $CHANGELOG is for ${newest:-nothing}. Raise both together."
  [ -n "$(notes | tr -d '[:space:]')" ] \
    || die "the section for $version in $CHANGELOG is empty."

  # Without the tags the comparison below would pass whatever the plugin holds.
  [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "false" ] \
    || die "this clone is shallow, so the released tags cannot be compared. Fetch the full history."

  # No tag yet means this version is about to be released: nothing to compare with.
  if git rev-parse -q --verify "refs/tags/v$version" >/dev/null 2>&1; then
    git diff --quiet "v$version" -- "$PLUGIN_DIR" \
      || die "$PLUGIN_DIR differs from what was released as v$version. A change in the plugin needs a new version in plugin.json and a section for it in $CHANGELOG."
  fi
}

case "${1:-}" in
  version) printf '%s\n' "$version" ;;
  notes)   notes ;;
  check)   check ;;
  *)       die "usage: release.sh check|version|notes" ;;
esac
