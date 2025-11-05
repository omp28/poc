#!/usr/bin/env bash
set -e

BRANCH=$1
PORT=$2

if [ -z "$BRANCH" ] || [ -z "$PORT" ]; then
  echo "❌ Usage: ./update_routes.sh <branch> <port>"
  exit 1
fi

CADDY_API="http://127.0.0.1:2020/config/apps/http/servers/srv0/routes"

# 🧠 Check if route already exists for this branch
EXISTS=$(curl -s "$CADDY_API" | jq -r '.[].match[].path[]?' 2>/dev/null | grep -Fx "/$BRANCH/*" || true)

if [ -n "$EXISTS" ]; then
  echo "✅ Route for /$BRANCH/* already exists — skipping creation."
  exit 0
fi

# 🏗️ Create route JSON (path-based with stripping)
ROUTE_JSON=$(cat <<EOF
{
  "match": [
    { "path": ["/$BRANCH", "/$BRANCH/*"] }
  ],
  "handle": [
    {
      "handler": "reverse_proxy",
      "rewrite": {
        "strip_path_prefix": "/$BRANCH"
      },
      "upstreams": [ { "dial": "127.0.0.1:$PORT" } ]
    }
  ]
}
EOF
)

echo "🔁 Adding new route for /$BRANCH/* → $PORT"

# 🧩 Add route via Caddy API
curl -s -X POST "$CADDY_API" \
     -H "Content-Type: application/json" \
     -d "$ROUTE_JSON" \
  || { echo "⚠️ Failed to add route in Caddy"; exit 1; }

echo "✅ Route added: http://<server-ip>:8080/$BRANCH/"
