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

echo "🚀 Deploying branch '$BRANCH' on port $PORT"

# Clean and clone
rm -rf "$TMP_DIR"
git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR"

cd "$TMP_DIR"

# Build docker image
docker build -t "app1:$BRANCH" .

# Stop old container if exists
if [ "$(docker ps -q -f name=app1_$BRANCH)" ]; then
  echo "🧹 Stopping old container for $BRANCH"
  docker stop "app1_$BRANCH" && docker rm "app1_$BRANCH"
fi

# Run container
docker run -d \
  -p $PORT:3000 \
  --name "app1_$BRANCH" \
  "app1:$BRANCH"

echo "✅ $BRANCH deployed at http://localhost:$PORT"

# Register route in Caddy
bash "$BASE_DIR/caddy/update_routes.sh" "$BRANCH" "$PORT"
