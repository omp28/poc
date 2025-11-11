#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/omp28/deployment-api.git"
REPO_DIR="/home/omkumar.patel/repos/deployment-api"
CONTAINER_NAME="deployment-api"
PORT=3002
SCRIPTS_DIR="/home/omkumar.patel/nomad-config"

echo "🚀 Deploying Deployment API..."

# Stop and remove existing container
if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
  echo "🧹 Removing existing container..."
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

# Clone or update repo
if [ ! -d "$REPO_DIR" ]; then
  echo "📦 Cloning repository..."
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "📦 Updating repository..."
  cd "$REPO_DIR"
  git fetch origin
  git pull origin main
fi

cd "$REPO_DIR"

# Build image
echo "🏗️  Building Docker image..."
docker build -t deployment-api:latest .

# Run container with restart policy
echo "🐳 Starting container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p $PORT:3002 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $SCRIPTS_DIR:$SCRIPTS_DIR \
  -v /home/omkumar.patel/repos:/home/omkumar.patel/repos \
  -e PORT=3002 \
  -e SCRIPTS_DIR=$SCRIPTS_DIR \
  --network host \
  deployment-api:latest

echo "✅ Deployment API is running on port $PORT"
echo "🔗 Test: curl http://localhost:$PORT/health"

# Wait for container to be ready
sleep 2

# Add Caddy route if it doesn't exist
CADDY_API="http://127.0.0.1:2020/config/apps/http/servers/srv0/routes"
EXISTS=$(curl -s "$CADDY_API" | jq -r '.[].match[].path[]?' 2>/dev/null | grep -Fx "/api" || true)

if [ -z "$EXISTS" ]; then
  echo "🔁 Adding /api route to Caddy..."
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
else
  echo "✅ /api route already exists"
fi

echo ""
echo "🎉 Deployment complete!"
echo "📡 API available at: http://135.235.193.224:3001/api/"
