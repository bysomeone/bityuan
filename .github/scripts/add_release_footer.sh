#!/usr/bin/env bash
# Put the operator-facing part of a release page in place: the "Upgrade Notes" the
# authors declared, and "System Requirements".
#
# Called by release.yml right after semantic-release publishes, i.e. as soon as the
# release exists -- deliberately not from the job that uploads the Windows/macOS
# packages, because a failed upload would otherwise leave the page without either
# block (which lists nothing about what an operator has to do).
#
#   usage: GH_TOKEN=... bash .github/scripts/add_release_footer.sh v6.9.2
#
# Safe to re-run: a release whose body already carries "System Requirements" is left
# alone, so repairing an old release cannot double-append.
set -eu

V="${1:?usage: add_release_footer.sh <tag>}"

BODY=$(gh release view "$V" --repo bityuan/bityuan --json body -q .body)
if printf '%s' "$BODY" | grep -q "System Requirements"; then
  echo "footer already present on $V, nothing to do"
  exit 0
fi

# Upgrade notes are the `Release-Note:` lines written by the authors of the commits in
# this release (rules: .github/workflows/release-note.yml). The machine can only
# collect them -- what a change means for an operator is not derivable here. The range
# comes from the compare API so no git history is needed.
PREV=$(gh api "repos/bityuan/bityuan/releases?per_page=10" --jq '.[].tag_name' 2>/dev/null | grep -vx "$V" | head -1 || true)
NOTES=""
if [ -n "$PREV" ]; then
  NOTES=$(gh api "repos/bityuan/bityuan/compare/$PREV...$V" --jq '.commits[].commit.message' 2>/dev/null \
          | sed -n 's/^Release-Note:[[:space:]]*//p' | grep -vix none || true)
else
  echo "WARNING: no previous release found, upgrade notes will be empty" >&2
fi

UPGRADE=""
if [ -n "$NOTES" ]; then
  UPGRADE="\n\n### Upgrade Notes\n\n"
  while IFS= read -r note; do
    if [ -n "$note" ]; then
      UPGRADE="$UPGRADE* $note\n"
    fi
  done <<< "$NOTES"
fi

# The macOS line is the `minos` of the darwin binaries -- currently 14.0, from building
# on the macos-14 runner (`otool -l bityuan | grep -A4 LC_BUILD_VERSION`). Moving to a
# newer runner moves this floor.
FOOTER="$UPGRADE\n\n---\n\n### System Requirements\n\n**Linux** (glibc >= 2.17): Ubuntu 18.04+, Debian 10+, CentOS 7+, RHEL 7+, Rocky 8+, Alma 8+\n\n**macOS**: 14.0+\n\n**Windows**: Windows 10+, Windows Server 2016+"

printf "%b" "$BODY$FOOTER" | gh release edit "$V" --repo bityuan/bityuan -F -
echo "footer added to $V${NOTES:+ (upgrade notes: $(printf '%s' "$NOTES" | wc -l | tr -d ' '))}"
