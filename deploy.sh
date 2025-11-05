#!/usr/bin/env bash
set -e

BRANCH=$1
if [ -z "$BRANCH" ]; then
  echo "❌ Usage: ./deploy.sh <branch-name>"
  exit 1
fi

REPO_URL="https://github.com/omp28/app1.git"
PORT_BASE=4000
BASE_DIR="/home/omkumar.patel/nomad-config"
TMP_DIR="/tmp/$BRANCH"

# Generate deterministic port
HASH=$(echo -n "$BRANCH" | md5sum | cut -c1-3)
PORT=$((PORT_BASE + 10#$((0x$HASH % 1000)) ))

# Set base path - main gets /, others get /branch/
if [ "$BRANCH" == "main" ]; then
  VITE_BASE="/"
else
  VITE_BASE="/$BRANCH/"
fi

echo "🚀 Deploying branch '$BRANCH' on port $PORT with base path '$VITE_BASE'"

# Clean up old container (if exists)
if docker ps -a --format '{{.Names}}' | grep -q "^app1_$BRANCH$"; then
  echo "🧹 Removing existing container for $BRANCH"
  docker stop "app1_$BRANCH" >/dev/null 2>&1 || true
  docker rm "app1_$BRANCH" >/dev/null 2>&1 || true
fi

# Clean and clone
rm -rf "$TMP_DIR"
git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR"

cd "$TMP_DIR"

# Build docker image with dynamic base path
docker build \
  --build-arg VITE_BASE_PATH="$VITE_BASE" \
  -t "app1:$BRANCH" .

# Run new container
docker run -d \
  -p $PORT:3000 \
  --name "app1_$BRANCH" \
  "app1:$BRANCH"

echo "✅ $BRANCH deployed at http://<server-ip>:$PORT"

# Register route in Caddy (path-based)
bash "$BASE_DIR/caddy/update_routes.sh" "$BRANCH" "$PORT"

# Set default route if branch is main
if [ "$BRANCH" == "main" ]; then
  echo "🌐 Setting 'main' as default catch-all route..."
  
  # Remove existing catch-all if present
  ROUTES_COUNT=$(curl -s "http://127.0.0.1:2020/config/apps/http/servers/srv0/routes" | jq 'length')
  LAST_INDEX=$((ROUTES_COUNT - 1))
  
  IS_CATCHALL=$(curl -s "http://127.0.0.1:2020/config/apps/http/servers/srv0/routes/$LAST_INDEX" | jq -r '.match[0].path[0]' 2>/dev/null || echo "")
  
  if [ "$IS_CATCHALL" == "/*" ]; then
    echo "Removing old catch-all route..."
    curl -s -X DELETE "http://127.0.0.1:2020/config/apps/http/servers/srv0/routes/$LAST_INDEX" > /dev/null
  fi
  
  curl -s -X POST "http://127.0.0.1:2020/config/apps/http/servers/srv0/routes" \
       -H "Content-Type: application/json" \
       -d "{
         \"match\": [{\"path\": [\"/*\"]}],
         \"handle\": [{
           \"handler\": \"reverse_proxy\",
           \"upstreams\": [{\"dial\": \"127.0.0.1:$PORT\"}]
         }]
       }" > /dev/null
  echo "✅ Default catch-all route now points to main ($PORT)"
fi
