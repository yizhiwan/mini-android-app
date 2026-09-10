#!/usr/bin/env bash
# =============================================================================
# bump-version.sh
#
# Increments VERSION_PATCH in version.properties and pushes the result
# straight back to main with "[skip ci]" so the push does not re-trigger the
# post-merge pipeline.
#
# Expects the following to already be set in the environment (populated by
# cloudbuild-postmerge.yaml from the trigger's substitution variables and the
# github-pr-token Secret Manager secret):
#   REPO_OWNER_NAME   - git author/committer name to use for the bump commit
#   REPO_OWNER_EMAIL  - git author/committer email to use for the bump commit
#   GITHUB_OWNER      - GitHub account/org that owns the repo
#   GITHUB_REPO       - repository name
#   GITHUB_TOKEN      - token with `contents: write`, injected via Secret Manager
# =============================================================================
set -euo pipefail

VERSION_FILE="version.properties"

: "${REPO_OWNER_NAME:?REPO_OWNER_NAME is not set}"
: "${REPO_OWNER_EMAIL:?REPO_OWNER_EMAIL is not set}"
: "${GITHUB_OWNER:?GITHUB_OWNER is not set}"
: "${GITHUB_REPO:?GITHUB_REPO is not set}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is not set}"

if [ ! -f "$VERSION_FILE" ]; then
  echo "ERROR: $VERSION_FILE not found in $(pwd)" >&2
  exit 1
fi

VERSION_MAJOR=$(grep '^VERSION_MAJOR=' "$VERSION_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
VERSION_MINOR=$(grep '^VERSION_MINOR=' "$VERSION_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
VERSION_PATCH=$(grep '^VERSION_PATCH=' "$VERSION_FILE" | cut -d'=' -f2 | tr -d '[:space:]')

if [ -z "$VERSION_MAJOR" ] || [ -z "$VERSION_MINOR" ] || [ -z "$VERSION_PATCH" ]; then
  echo "ERROR: could not parse VERSION_MAJOR/VERSION_MINOR/VERSION_PATCH from $VERSION_FILE" >&2
  exit 1
fi

NEW_PATCH=$((VERSION_PATCH + 1))

echo "Current version: ${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}"
echo "New version:     ${VERSION_MAJOR}.${VERSION_MINOR}.${NEW_PATCH}"

cat > "$VERSION_FILE" <<EOF
VERSION_MAJOR=${VERSION_MAJOR}
VERSION_MINOR=${VERSION_MINOR}
VERSION_PATCH=${NEW_PATCH}
EOF

git config user.name "${REPO_OWNER_NAME}"
git config user.email "${REPO_OWNER_EMAIL}"

git add "$VERSION_FILE"

if git diff --cached --quiet; then
  echo "No changes to commit — version.properties already up to date."
  exit 0
fi

git commit -m "chore: bump version to ${VERSION_MAJOR}.${VERSION_MINOR}.${NEW_PATCH} [skip ci]"

REMOTE_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git"

git push "$REMOTE_URL" HEAD:main

echo "Pushed version bump ${VERSION_MAJOR}.${VERSION_MINOR}.${NEW_PATCH} to main."
