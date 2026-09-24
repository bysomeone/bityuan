#!/usr/bin/env bash
# Will this commit trigger a release?
#
# The answer is read out of `.releaserc.yml` -- the file semantic-release itself
# reads -- so the check cannot drift from the real rules.
#
# usage (commit message on stdin):
#   git log -1 --format=%B <sha> | .github/scripts/release_commit.sh
#   exit 0 = triggers a release, 1 = does not, 2 = cannot tell (see below)
#
# The rules come from @semantic-release/commit-analyzer's default releaseRules:
#   any type with BREAKING CHANGE / `!`  -> major
#   revert:                              -> patch
#   feat: / fix: / perf:                 -> minor / patch / patch
#   under the jshint preset, [[FEAT]] / [[FIX]]
#
# Exit 2 is deliberate and is meant to fail the check: it means someone changed
# .releaserc.yml in a way this script does not model, and silently applying the old
# rules would be worse than stopping. Two such cases:
#
#   * an unknown preset (a preset this script has no rules for);
#   * a `releaseRules` block -- rules listed per repository, which take precedence over
#     the preset defaults. Wanting one is normal: `{type: chore, scope: deps,
#     release: patch}` is how a repository makes dependency bumps cut a release, which
#     is exactly the case that surprised us when a chain33 bump released nothing.
#     Add the block if you need it, then teach this script the same rules.
set -u

if grep -q '"releaseRules"' .releaserc.yml; then
  echo "release_commit.sh: .releaserc.yml defines releaseRules, which override the preset defaults -- teach this script those rules before it can answer" >&2
  exit 2
fi

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
    echo "release_commit.sh: .releaserc.yml uses preset '$PRESET', which this script does not know -- teach it that preset's release types" >&2
    exit 2
    ;;
esac
