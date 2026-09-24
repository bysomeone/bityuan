#!/usr/bin/env bash
# Put the operator-facing part of a release page in place: the "Upgrade Notes" the
# authors declared, and "System Requirements".
#
# Called by release.yml in the release-linux job, right after semantic-release
# publishes -- i.e. as soon as the release exists, before any asset is uploaded.
# Deliberately *not* called from the job that uploads the Windows/macOS packages:
# a failed upload would otherwise leave the page with nothing about what an operator
# has to do.
#
#   usage: GH_TOKEN=... bash .github/scripts/add_release_footer.sh v6.9.2
#
# Safe to re-run: a release whose body already carries "System Requirements" is left
# alone, so repairing an old release cannot double-append.
set -eu

V="${1:?usage: add_release_footer.sh <tag>}"
REPO=bityuan/bityuan
HERE=$(dirname "$0")

BODY=$(gh release view "$V" --repo "$REPO" --json body -q .body)
if printf '%s' "$BODY" | grep -q "System Requirements"; then
  echo "footer already present on $V, nothing to do"
  exit 0
fi

# Upgrade notes are the text under the `Release note` heading of each pull request merged
# in this release: one note per change, written where the narrative already is (rules:
# .github/RELEASE.md). A commit that never went through a pull request -- pushed
# straight to master -- falls back to a `Release-Note:` line in its own body.
prev=$(gh api "repos/$REPO/releases?per_page=10" --jq '.[].tag_name' 2>/dev/null | grep -vx "$V" | head -1 || true)
notes=""
if [ -z "$prev" ]; then
  echo "WARNING: no previous release found, upgrade notes will be empty" >&2
else
  seen=" "
  for sha in $(gh api "repos/$REPO/compare/$prev...$V" --jq '.commits[].sha' 2>/dev/null || true); do
    pr=$(gh api "repos/$REPO/commits/$sha/pulls" --jq '.[0].number' 2>/dev/null || true)
    note=""
    if [ -n "$pr" ] && [ "$pr" != "null" ]; then
      # one note per pull request, however many commits it contributed
      case "$seen" in *" $pr "*) continue ;; esac
      seen="$seen$pr "
      note=$(gh pr view "$pr" --repo "$REPO" --json body -q .body 2>/dev/null | bash "$HERE/extract_release_note.sh" || true)
    else
      note=$(gh api "repos/$REPO/commits/$sha" --jq .commit.message 2>/dev/null | sed -n 's/^Release-Note:[[:space:]]*//p' || true)
    fi
    # a note is one bullet, so a wrapped block collapses to a single line
    note=$(printf '%s' "$note" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')
    case "$(printf '%s' "$note" | tr '[:upper:]' '[:lower:]')" in
      "" | none) continue ;;
    esac
    notes="$notes$note"$'\n'
  done
fi

upgrade=""
if [ -n "$notes" ]; then
  upgrade="\n\n### Upgrade Notes\n\n"
  while IFS= read -r note; do
    if [ -n "$note" ]; then
      upgrade="$upgrade* $note\n"
    fi
  done <<< "$notes"
fi

# The macOS line is the `minos` of the darwin binaries -- currently 14.0, from building
# on the macos-14 runner (`otool -l bityuan | grep -A4 LC_BUILD_VERSION`). Moving to a
# newer runner moves this floor.
FOOTER="$upgrade\n\n---\n\n### System Requirements\n\n**Linux** (glibc >= 2.17): Ubuntu 18.04+, Debian 10+, CentOS 7+, RHEL 7+, Rocky 8+, Alma 8+\n\n**macOS**: 14.0+\n\n**Windows**: Windows 10+, Windows Server 2016+"

printf "%b" "$BODY$FOOTER" | gh release edit "$V" --repo "$REPO" -F -
echo "footer added to $V (upgrade notes: $(printf '%s' "$notes" | grep -c . || true))"
