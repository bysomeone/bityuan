#!/usr/bin/env bash
# Will this commit trigger a release?
#
# The answer is read out of `.releaserc.yml` -- the file semantic-release itself
# reads -- so the check cannot drift from the real rules. If the preset is ever
# swapped for one this script does not know, it exits 2 instead of quietly applying
# the old rules.
#
# usage (commit message on stdin):
#   git log -1 --format=%B <sha> | .github/scripts/release_commit.sh
#   exit 0 = triggers a release, 1 = does not, 2 = unknown preset
#
# The rules come from @semantic-release/commit-analyzer's default releaseRules:
#   any type with BREAKING CHANGE / `!`  -> major
#   revert:                              -> patch
#   feat: / fix: / perf:                 -> minor / patch / patch
#   under the jshint preset, [[FEAT]] / [[FIX]]
set -u

PRESET=$(sed -n 's/.*"preset"[[:space:]]*:[[:space:]]*"\([a-zA-Z-]*\)".*/\1/p' .releaserc.yml | head -1)
MSG=$(cat)
SUBJECT=$(printf '%s\n' "$MSG" | head -1)

case "$PRESET" in
  angular)
    if printf '%s\n' "$SUBJECT" | grep -qE '^(feat|fix|perf|revert)(\([^)]*\))?!?:'; then
      exit 0
    fi
    # A BREAKING CHANGE in the body makes *any* type release a major, so the subject
    # alone is not enough to answer this.
    printf '%s\n' "$MSG" | grep -q 'BREAKING CHANGE:' && exit 0
    exit 1
    ;;
  jshint)
    printf '%s\n' "$SUBJECT" | grep -qE '^\[\[(FEAT|FIX)\]\]' && exit 0
    exit 1
    ;;
  *)
    echo "release_commit.sh: .releaserc.yml uses preset '$PRESET', which this script does not know -- update its release-type rules" >&2
    exit 2
    ;;
esac
