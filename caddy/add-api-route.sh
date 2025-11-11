#!/usr/bin/env bash
set -e

CADDY_API="http://127.0.0.1:2020/config/apps/http/servers/srv0/routes"

# Check if /api route exists
EXISTS=$(curl -s "$CADDY_API" | jq -r '.[].match[].path[]?' 2>/dev/null | grep -Fx "/api" || true)

if [ -n "$EXISTS" ]; then
  echo "✅ /api route already exists"
  exit 0
fi

echo "🔁 Adding /api route..."

# Add at position 0 (highest priority)
curl -s -X POST "$CADDY_API/0" \
     -H "Content-Type: application/json" \
     -d '{
  "match": [{"path": ["/api", "/api/*"]}],
  "handle": [{
    "handler": "reverse_proxy",
    "rewrite": {"strip_path_prefix": "/api"},
    "upstreams": [{"dial": "127.0.0.1:3002"}]
  }]
}' > /dev/null

echo "✅ API route added"
