#!/bin/bash
set -euo pipefail

WP_ID="${1:-unknown}"
SHA=$(git rev-parse HEAD)
BRANCH=$(git branch --show-current)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p ".ai/evidence/$WP_ID"

# Requires jq; install via apt if missing
FILES_JSON=$(git diff --name-only HEAD~1..HEAD 2>/dev/null | jq -R . | jq -s . || echo "[]")

cat > ".ai/evidence/$WP_ID/manifest.json" <<EOF
{
  "work_package": "$WP_ID",
  "commit": "$SHA",
  "branch": "$BRANCH",
  "timestamp": "$TIMESTAMP",
  "model": "claude-opus-5-20251401",
  "files_changed": $FILES_JSON,
  "verification_status": "manual",
  "known_limitations": []
}
EOF

echo "Evidence manifest: .ai/evidence/$WP_ID/manifest.json"