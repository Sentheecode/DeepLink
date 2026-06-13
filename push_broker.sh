#!/bin/bash
# Push latest broker changes to deeplink-broker repo
# Usage: ./push_broker.sh

set -e
cd "$(dirname "$0")"
REMOTE="https://github.com/Sentheecode/deeplink-broker.git"
TMP_DIR=$(mktemp -d)

git init "$TMP_DIR/repo"
cd "$TMP_DIR/repo"
git remote add origin "$REMOTE"
git fetch origin main

# Copy broker files
rsync -a --exclude='.git' --exclude='__pycache__' --exclude='*.db' --exclude='*.db-*' --exclude='broker-repo.bundle' --exclude='push_broker.sh' /Users/zhaoyumeng/code/DeepSeekBalance/broker/ "$TMP_DIR/repo/"

git add -A
git commit -m "update: $(date '+%Y-%m-%d %H:%M')"
git push origin main

rm -rf "$TMP_DIR"
echo "Done: pushed to $REMOTE"
