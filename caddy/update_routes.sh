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
EXISTS=$(curl -s "$CADDY_API" | jq -r '.[]?.match[]?.host[]?' 2>/dev/null | grep -Fx "$BRANCH.localhost" || true)

if [ -n "$EXISTS" ]; then
  echo "✅ Route for $BRANCH.localhost already exists — skipping creation."
  exit 0
fi

# 🏗️ Create route JSON
ROUTE_JSON=$(cat <<EOF
{
  "match": [
    { "host": ["$BRANCH.localhost"] }
  ],
  "handle": [
    {
      "handler": "reverse_proxy",
      "upstreams": [ { "dial": "127.0.0.1:$PORT" } ]
    }
  ]
}
EOF
)

echo "🔁 Adding new route for $BRANCH.localhost → $PORT"

# 🧩 Add route via Caddy API
curl -s -X POST "$CADDY_API" \
     -H "Content-Type: application/json" \
     -d "$ROUTE_JSON" \
  || { echo "⚠️ Failed to add route in Caddy"; exit 1; }

echo "✅ Route added: http://$BRANCH.localhost:8080"
