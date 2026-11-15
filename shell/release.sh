#!/usr/bin/env bash
# Tag and publish a release from the commit log:  shell/release.sh v0.2.0 ["title"]
# Runs verify.sh first, tags the current commit, pushes the tag and creates a GitHub release whose notes are the commits since
# the previous tag. Marks versions below 1.0 as pre-releases.
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/.."
V="${1:?usage: shell/release.sh vX.Y.Z [title]}"; TITLE="${2:-Beskar $V}"
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "commit or stash your changes first" >&2; exit 1; }
[ "$(git branch --show-current)" = master ] || { echo "release from master" >&2; exit 1; }
git rev-parse "$V" >/dev/null 2>&1 && { echo "$V already exists" >&2; exit 1; }
shell/verify.sh | tail -1 | grep -q 'VERIFY PASSED' || { echo "verify.sh did not pass" >&2; exit 1; }
PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
NOTES=$(mktemp)
{ echo "pleamar pinned: $(grep '^VERSION=' shell/runtime.sh | cut -d= -f2)"; echo; echo "## Changes"; echo
  git log --no-merges --pretty='- %s' ${PREV:+$PREV..}HEAD | grep -v '^- Merge'; } > "$NOTES"
PRE=""; case "$V" in v0.*) PRE="--prerelease" ;; esac
git tag -a "$V" -m "$TITLE"; git push origin "$V"
gh release create "$V" $PRE --title "$TITLE" --notes-file "$NOTES"
