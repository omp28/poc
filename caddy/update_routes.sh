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
EXISTS=$(curl -s "$CADDY_API" | jq -r '.[].match[].path[]?' 2>/dev/null | grep -Fx "/$BRANCH" || true)

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

# Get current routes
ROUTES=$(curl -s "$CADDY_API")

# Find position to insert (before any catch-all route)
ROUTES_COUNT=$(echo "$ROUTES" | jq 'length')
INSERT_POS=$ROUTES_COUNT

# Check if last route is a catch-all and insert before it
if [ "$ROUTES_COUNT" -gt 0 ]; then
  LAST_ROUTE_PATH=$(echo "$ROUTES" | jq -r '.[-1].match[0].path[0]' 2>/dev/null || echo "")
  if [ "$LAST_ROUTE_PATH" == "/*" ]; then
    INSERT_POS=$((ROUTES_COUNT - 1))
    echo "📍 Inserting at position $INSERT_POS (before catch-all route)"
  fi
fi

# Insert route at the calculated position
curl -s -X POST "$CADDY_API/$INSERT_POS" \
     -H "Content-Type: application/json" \
     -d "$ROUTE_JSON" \
  || { echo "⚠️ Failed to add route in Caddy"; exit 1; }

echo "✅ Route added at position $INSERT_POS: /$BRANCH/* → $PORT"
