#!/usr/bin/env bash
set -e

BRANCH=$1
PORT=$2

if [ -z "$BRANCH" ] || [ -z "$PORT" ]; then
  echo "❌ Usage: ./update_routes.sh <branch> <port>"
  exit 1
fi

CADDY_API="http://127.0.0.1:2020/config/apps/http/servers/srv0/routes"

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

echo "🔁 Adding route for $BRANCH.localhost → $PORT"

# ✅ Correct: POST a single object (no array wrapper)
curl -s -X POST "$CADDY_API" \
     -H "Content-Type: application/json" \
     -d "$ROUTE_JSON" \
  || { echo "⚠️ Failed to add route in Caddy"; exit 1; }

echo "✅ Route added: http://$BRANCH.localhost:8080"
