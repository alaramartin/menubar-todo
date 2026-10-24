#!/bin/bash
# Publishes a new GitHub release: bumps the version from the newest tag, builds the zip, tags and uploads it.
#   scripts/release.sh patch|minor|major|<x.y.z> [notes.md]
# Without a notes file, GitHub writes the notes from the commits since the last release.
set -euo pipefail
cd "$(dirname "$0")/.."

BUMP="${1:?usage: scripts/release.sh patch|minor|major|<x.y.z> [notes.md]}"
NOTES="${2:-}"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Commit your changes first." >&2; exit 1
fi
git fetch --tags -q

LATEST="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)"
IFS=. read -r MAJOR MINOR PATCH <<< "${LATEST#v}"
case "$BUMP" in
    patch) VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    minor) VERSION="$MAJOR.$((MINOR + 1)).0" ;;
    major) VERSION="$((MAJOR + 1)).0.0" ;;
    [0-9]*.[0-9]*.[0-9]*) VERSION="$BUMP" ;;
    *) echo "Unknown version: $BUMP" >&2; exit 1 ;;
esac
echo "Releasing $VERSION (previous: ${LATEST#v})"
git push -q

VERSION="$VERSION" ./build.sh --zip
rm -rf "build/Menubar Todo.app" # only the zip is needed; a stray copy shows up twice in Spotlight

if [[ -n "$NOTES" ]]; then
    gh release create "v$VERSION" build/MenubarTodo.zip --title "Menubar Todo $VERSION" --target main --notes-file "$NOTES"
else
    gh release create "v$VERSION" build/MenubarTodo.zip --title "Menubar Todo $VERSION" --target main --generate-notes
fi
git fetch --tags -q
