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
REPO_DIR="/home/omkumar.patel/repos/app1"  # Persistent repo location

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

# Clone repo if not exists, otherwise fetch and checkout
if [ ! -d "$REPO_DIR" ]; then
  echo "📦 Cloning repository for the first time..."
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "📦 Repository exists, fetching latest changes..."
  cd "$REPO_DIR"
  git fetch origin
fi

cd "$REPO_DIR"

# Checkout and pull the specific branch
echo "🔄 Checking out branch '$BRANCH'..."
git checkout "$BRANCH"
git pull origin "$BRANCH"

# Build docker image with dynamic base path
echo "🏗️  Building Docker image..."
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
