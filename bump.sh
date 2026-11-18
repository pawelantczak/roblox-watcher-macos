#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

if [ ! -f "$DIR/VERSION" ]; then
    echo "1.0.0" > "$DIR/VERSION"
fi

CURRENT_VERSION=$(cat "$DIR/VERSION" | tr -d '[:space:]')
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

BUMP_TYPE="${1:-patch}"

case "$BUMP_TYPE" in
    patch)
        PATCH=$((PATCH + 1))
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    [0-9]*.[0-9]*.[0-9]*)
        # Custom version string provided directly (e.g. ./bump.sh 1.2.0)
        NEW_VERSION="$BUMP_TYPE"
        ;;
    *)
        echo "Usage: ./bump.sh [patch | minor | major | <version>]"
        exit 1
        ;;
esac

if [ -z "$NEW_VERSION" ]; then
    NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
fi

echo "Bumping version: $CURRENT_VERSION -> $NEW_VERSION"
echo "$NEW_VERSION" > "$DIR/VERSION"

# Synchronize CHANGELOG.md: move [Unreleased] content under [NEW_VERSION] header
TODAY=$(date +"%Y-%m-%d")
if [ -f "$DIR/CHANGELOG.md" ]; then
    python3 -c "
import sys, re
changelog_path = '$DIR/CHANGELOG.md'
new_ver = sys.argv[1]
today = sys.argv[2]

with open(changelog_path, 'r') as f:
    content = f.read()

if f'## [{new_ver}]' not in content:
    pattern = r'## \[Unreleased\]\s*\n(.*?)(?=\n---\s*\n## \[|\n## \[|\Z)'
    m = re.search(pattern, content, re.DOTALL)
    if m and m.group(1).strip():
        body = m.group(1).strip()
        replacement = f'## [Unreleased]\n\n---\n\n## [{new_ver}] - {today}\n\n{body}\n'
        content = content[:m.start()] + replacement + content[m.end():]
        with open(changelog_path, 'w') as f:
            f.write(content)
        print(f'==> Updated CHANGELOG.md with release header for v{new_ver}')
" "$NEW_VERSION" "$TODAY"
fi

# Run build to stamp plist and verify
./build.sh

echo ""
echo "=========================================="
echo "Version bumped to v$NEW_VERSION successfully!"
echo "To publish this release to GitHub, run:"
echo "  git commit -am \"chore: release v$NEW_VERSION\""
echo "  git tag v$NEW_VERSION"
echo "  git push origin main --tags"
echo "=========================================="
