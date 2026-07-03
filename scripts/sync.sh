#!/usr/bin/env bash
# Sync with upstream, run build/deploy/clean, and push.
set -euo pipefail

# Change to project root directory
cd "$(dirname "$0")/.."

FORCE=false
PUSH=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      FORCE=true
      shift
      ;;
    --no-push)
      PUSH=false
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--force] [--no-push]" >&2
      exit 1
      ;;
  esac
done

# Define upstream
UPSTREAM_URL="https://github.com/umputun/agterm.git"
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="master"

# 1. Ensure working directory is clean
echo "Checking working directory status..."
if ! git diff-index --quiet HEAD --; then
  echo "Error: Working directory has uncommitted or staged changes." >&2
  echo "Please commit or stash your changes before syncing." >&2
  exit 1
fi

# 2. Check and configure upstream remote
if ! git remote | grep -q "^${UPSTREAM_REMOTE}$"; then
  echo "Adding remote '${UPSTREAM_REMOTE}' pointing to ${UPSTREAM_URL}..."
  git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
fi

# 3. Fetch from upstream
echo "Fetching changes from remote '${UPSTREAM_REMOTE}'..."
git fetch "$UPSTREAM_REMOTE"

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "Error: Not on any branch (detached HEAD)." >&2
  exit 1
fi

# 4. Check if there are commits to merge
FULL_UPSTREAM_BRANCH="${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"
NEW_COMMITS=$(git log HEAD.."$FULL_UPSTREAM_BRANCH" --oneline)

if [[ -z "$NEW_COMMITS" ]] && [[ "$FORCE" = "false" ]]; then
  echo "Already up to date with ${FULL_UPSTREAM_BRANCH}. No new commits to merge."
  exit 0
fi

if [[ -n "$NEW_COMMITS" ]]; then
  echo "Found new commits in ${FULL_UPSTREAM_BRANCH}:"
  echo "$NEW_COMMITS"
fi

# 5. Merge upstream branch
echo "Merging ${FULL_UPSTREAM_BRANCH} into ${CURRENT_BRANCH}..."
if ! git merge "$FULL_UPSTREAM_BRANCH" --no-edit; then
  echo "Error: Merge conflicts detected!" >&2
  echo "Aborting the merge..." >&2
  git merge --abort
  exit 1
fi

# 6. Run make commands
echo "Running 'make release'..."
if ! make release; then
  echo "Error: 'make release' failed!" >&2
  exit 1
fi

echo "Running 'make deploy'..."
if ! make deploy; then
  echo "Error: 'make deploy' failed!" >&2
  exit 1
fi

echo "Running 'make install-ctl'..."
if ! make install-ctl; then
  echo "Error: 'make install-ctl' failed!" >&2
  exit 1
fi

echo "Running 'make clean'..."
if ! make clean; then
  echo "Error: 'make clean' failed!" >&2
  exit 1
fi

# 7. Push to origin
if [[ "$PUSH" = "true" ]]; then
  echo "Pushing merged changes to origin..."
  if ! git push origin HEAD; then
    echo "Error: 'git push origin HEAD' failed!" >&2
    exit 1
  fi
  echo "Sync completed successfully!"
else
  echo "Sync completed successfully (push skipped)."
fi
