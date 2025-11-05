#!/usr/bin/env bash
set -e

BRANCH=$1
if [ -z "$BRANCH" ]; then
  echo "❌ Usage: ./deploy-cra.sh <branch-name>"
  exit 1
fi

REPO_URL="https://github.com/your-org/vidaltech-app.git"  # Change this
PORT_BASE=5000
BASE_DIR="/home/omkumar.patel/nomad-config"
TMP_DIR="/tmp/cra_$BRANCH"

# Generate deterministic port
HASH=$(echo -n "$BRANCH" | md5sum | cut -c1-3)
PORT=$((PORT_BASE + 10#$((0x$HASH % 1000)) ))

# Set base path - main gets /, others get /branch/
if [ "$BRANCH" == "main" ] || [ "$BRANCH" == "master" ]; then
  BASE_PATH="/"
  HOMEPAGE="/"
else
  BASE_PATH="/$BRANCH"
  HOMEPAGE="/$BRANCH"
fi

echo "🚀 Deploying CRA branch '$BRANCH' on port $PORT"
echo "   Base Path: $BASE_PATH"

# Clean up old container (if exists)
if docker ps -a --format '{{.Names}}' | grep -q "^cra_$BRANCH$"; then
  echo "🧹 Removing existing container for $BRANCH"
  docker stop "cra_$BRANCH" >/dev/null 2>&1 || true
  docker rm "cra_$BRANCH" >/dev/null 2>&1 || true
fi

# Clean and clone
rm -rf "$TMP_DIR"
git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR"

cd "$TMP_DIR"

# Create Dockerfile dynamically (since repo doesn't have one)
cat > Dockerfile <<'DOCKERFILE_END'
FROM node:20 AS build

WORKDIR /app

# Accept build arguments
ARG HOMEPAGE=/
ARG API_BASE_URL=http://152.67.182.12:8080/vidalhealth/
ARG BASE_PATH=/
ARG REPORTS_URL=https://global-dev.vidalhealth.com/reports

# Copy package files
COPY package*.json ./
RUN npm install

# Copy source code
COPY . .

# Create .env file
RUN echo "REACT_APP_API_BASE_URL=${API_BASE_URL}" > .env && \
    echo "DISABLE_ESLINT_PLUGIN=true" >> .env && \
    echo "REACT_APP_BASE_PATH=${BASE_PATH}" >> .env && \
    echo "REACT_APP_REPORTS_URL=${REPORTS_URL}" >> .env

# Update package.json homepage
RUN npm pkg set homepage="${HOMEPAGE}"

# Build the app
RUN npm run build:omn

# Production stage
FROM node:20-slim

WORKDIR /app

# Install serve
RUN npm install -g serve

# Copy built files
COPY --from=build /app/build ./build

EXPOSE 3000

# Serve with proper SPA routing
CMD ["serve", "-s", "build", "-l", "3000"]
DOCKERFILE_END

echo "📝 Created Dockerfile dynamically"

# Inject environment variables for build
cat > .env <<EOF
REACT_APP_API_BASE_URL=http://152.67.182.12:8080/vidalhealth/
DISABLE_ESLINT_PLUGIN=true
REACT_APP_BASE_PATH=$BASE_PATH
REACT_APP_REPORTS_URL=https://global-dev.vidalhealth.com/reports
EOF

echo "📝 Created .env with BASE_PATH=$BASE_PATH"

# Build docker image with build args
docker build \
  --build-arg HOMEPAGE="$HOMEPAGE" \
  --build-arg BASE_PATH="$BASE_PATH" \
  --build-arg API_BASE_URL="http://152.67.182.12:8080/vidalhealth/" \
  --build-arg REPORTS_URL="https://global-dev.vidalhealth.com/reports" \
  -t "cra:$BRANCH" .

# Run new container
docker run -d \
  -p $PORT:3000 \
  --name "cra_$BRANCH" \
  "cra:$BRANCH"

echo "✅ $BRANCH deployed at http://<server-ip>:$PORT"

# Register route in Caddy
bash "$BASE_DIR/caddy/update_routes.sh" "$BRANCH" "$PORT"

# Set default route if branch is main/master
if [ "$BRANCH" == "main" ] || [ "$BRANCH" == "master" ]; then
  echo "🌐 Setting '$BRANCH' as default catch-all route..."
  
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
  echo "✅ Default catch-all route now points to $BRANCH ($PORT)"
fi
