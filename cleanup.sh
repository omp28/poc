#!/usr/bin/env bash
set -e

BRANCH=$1
if [ -z "$BRANCH" ]; then
  echo "❌ Usage: ./cleanup.sh <branch-name>"
  exit 1
fi

CADDY_API="http://127.0.0.1:2020/config/apps/http/servers/srv0/routes"

echo "🧹 Cleaning up deployment for branch '$BRANCH'..."

# 1. Stop and remove Docker container
if docker ps -a --format '{{.Names}}' | grep -q "^app1_$BRANCH$"; then
  echo "🐳 Stopping and removing container 'app1_$BRANCH'..."
  docker stop "app1_$BRANCH" >/dev/null 2>&1 || true
  docker rm "app1_$BRANCH" >/dev/null 2>&1 || true
  echo "✅ Container removed"
else
  echo "⚠️  No container found for branch '$BRANCH'"
fi

# 2. Remove Docker image
if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^app1:$BRANCH$"; then
  echo "🗑️  Removing Docker image 'app1:$BRANCH'..."
  docker rmi "app1:$BRANCH" >/dev/null 2>&1 || true
  echo "✅ Image removed"
fi

# 3. Remove Caddy route
echo "🔍 Searching for Caddy route for /$BRANCH..."

ROUTES=$(curl -s "$CADDY_API")
ROUTES_COUNT=$(echo "$ROUTES" | jq 'length')

# Find the index of the route matching this branch
for i in $(seq 0 $((ROUTES_COUNT - 1))); do
  ROUTE_PATH=$(echo "$ROUTES" | jq -r ".[$i].match[0].path[0]" 2>/dev/null || echo "")
  
  if [ "$ROUTE_PATH" == "/$BRANCH" ]; then
    echo "🗑️  Removing Caddy route at index $i: /$BRANCH/*"
    curl -s -X DELETE "$CADDY_API/$i" > /dev/null
    echo "✅ Caddy route removed"
    break
  fi
done

# 4. Check if this was a catch-all route and remove it too
ROUTES=$(curl -s "$CADDY_API")
ROUTES_COUNT=$(echo "$ROUTES" | jq 'length')

if [ "$ROUTES_COUNT" -gt 0 ]; then
  LAST_ROUTE=$(echo "$ROUTES" | jq -r '.[-1]')
  LAST_ROUTE_PATH=$(echo "$LAST_ROUTE" | jq -r '.match[0].path[0]')
  LAST_ROUTE_DIAL=$(echo "$LAST_ROUTE" | jq -r '.handle[0].upstreams[0].dial')
  
  # Generate port for this branch to check if it's the catch-all
  HASH=$(echo -n "$BRANCH" | md5sum | cut -c1-3)
  PORT=$((4000 + 10#$((0x$HASH % 1000)) ))
  
  if [ "$LAST_ROUTE_PATH" == "/*" ] && [ "$LAST_ROUTE_DIAL" == "127.0.0.1:$PORT" ]; then
    LAST_INDEX=$((ROUTES_COUNT - 1))
    echo "🗑️  Removing catch-all route at index $LAST_INDEX pointing to $PORT"
    curl -s -X DELETE "$CADDY_API/$LAST_INDEX" > /dev/null
    echo "✅ Catch-all route removed"
  fi
fi

echo ""
echo "✨ Cleanup complete for branch '$BRANCH'!"
echo ""
echo "📊 Current deployments:"
docker ps --filter "name=app1_" --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
