#!/bin/bash
set -e
cd "$(dirname "$0")"
REPO_NAME="deeplink-broker"

# Create repo on GitHub
gh repo create "$REPO_NAME" --private --description "DeepLink Broker Server - agent relay & device registry" || echo "Repo may already exist, continuing..."

# Clone the bundle
TMP_DIR=$(mktemp -d)
git clone broker-repo.bundle "$TMP_DIR/push-repo"
cd "$TMP_DIR/push-repo"

# Get username
USERNAME=$(gh api user --jq .login)

# Set remote and push
git remote add origin "git@github.com:$USERNAME/$REPO_NAME.git"
git push -u origin main

# Cleanup
cd /
rm -rf "$TMP_DIR"
rm -f "$(dirname "$0")/broker-repo.bundle"

echo "Done: https://github.com/$USERNAME/$REPO_NAME"
