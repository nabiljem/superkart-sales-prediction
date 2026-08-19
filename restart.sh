#!/usr/bin/env bash

set -Eeuo pipefail

# -------------------------------------------------------
# SuperKart Docker restart script
# Expected structure:
#
# project-root/
# ├── restart.sh
# ├── backend/
# │   └── Dockerfile
# └── frontend/
#     └── Dockerfile
# -------------------------------------------------------

BACKEND_IMAGE="superkart-backend"
FRONTEND_IMAGE="superkart-frontend"

BACKEND_CONTAINER="backend"
FRONTEND_CONTAINER="frontend"

NETWORK_NAME="superkart-network"

BACKEND_PORT=7860
FRONTEND_PORT=8501

# Always work from the directory containing this script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"


pass() {
    echo "✅ PASS: $1"
}

info() {
    echo
    echo "▶ $1"
}

fail() {
    echo
    echo "❌ ERROR: $1"
    exit 1
}


# -------------------------------------------------------
# 1. Check Docker
# -------------------------------------------------------

info "Checking Docker..."

command -v docker >/dev/null 2>&1 \
    || fail "Docker is not installed."

docker info >/dev/null 2>&1 \
    || fail "Docker daemon is not running."

pass "Docker is available"


# -------------------------------------------------------
# 2. Check project files
# -------------------------------------------------------

info "Checking project structure..."

[[ -f backend/Dockerfile ]] \
    || fail "backend/Dockerfile was not found."

[[ -f frontend/Dockerfile ]] \
    || fail "frontend/Dockerfile was not found."

pass "Backend and frontend Dockerfiles found"


# -------------------------------------------------------
# 3. Stop old containers
# -------------------------------------------------------

info "Removing existing containers..."

for container in "$BACKEND_CONTAINER" "$FRONTEND_CONTAINER"; do

    if docker container inspect "$container" >/dev/null 2>&1; then
        echo "Removing existing container: $container"
        docker rm -f "$container" >/dev/null
    fi

done

pass "Old containers removed"


# -------------------------------------------------------
# 4. Create Docker network
# -------------------------------------------------------

info "Checking Docker network..."

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then

    docker network create "$NETWORK_NAME" >/dev/null

    pass "Created network: $NETWORK_NAME"

else

    pass "Network already exists: $NETWORK_NAME"

fi


# -------------------------------------------------------
# 5. Build backend
# -------------------------------------------------------

info "Building backend image..."

if docker build \
    -t "$BACKEND_IMAGE" \
    ./backend; then

    pass "Backend image built successfully"

else

    fail "Backend image build failed"

fi


# -------------------------------------------------------
# 6. Build frontend
# -------------------------------------------------------

info "Building frontend image..."

if docker build \
    -t "$FRONTEND_IMAGE" \
    ./frontend; then

    pass "Frontend image built successfully"

else

    fail "Frontend image build failed"

fi


# -------------------------------------------------------
# 7. Start backend
# -------------------------------------------------------

info "Starting backend container..."

if docker run -d \
    --name "$BACKEND_CONTAINER" \
    --network "$NETWORK_NAME" \
    -p "${BACKEND_PORT}:${BACKEND_PORT}" \
    "$BACKEND_IMAGE" >/dev/null; then

    pass "Backend container started"

else

    fail "Unable to start backend container"

fi


# -------------------------------------------------------
# 8. Start frontend
# -------------------------------------------------------

info "Starting frontend container..."

if docker run -d \
    --name "$FRONTEND_CONTAINER" \
    --network "$NETWORK_NAME" \
    -p "${FRONTEND_PORT}:${FRONTEND_PORT}" \
    "$FRONTEND_IMAGE" >/dev/null; then

    pass "Frontend container started"

else

    echo
    echo "Backend logs:"
    docker logs "$BACKEND_CONTAINER" || true

    fail "Unable to start frontend container"

fi


# -------------------------------------------------------
# 9. Give applications a moment to start
# -------------------------------------------------------

info "Waiting for services to initialize..."

sleep 4


# -------------------------------------------------------
# 10. Verify containers
# -------------------------------------------------------

for container in "$BACKEND_CONTAINER" "$FRONTEND_CONTAINER"; do

    if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" == "true" ]]; then

        pass "$container is running"

    else

        echo
        echo "Logs for $container:"
        docker logs "$container" || true

        fail "$container stopped unexpectedly"

    fi

done


# -------------------------------------------------------
# 11. Test backend connectivity
# -------------------------------------------------------

info "Testing backend..."

if command -v curl >/dev/null 2>&1; then

    if curl -fsS \
        "http://localhost:${BACKEND_PORT}/" \
        >/dev/null; then

        pass "Backend API responded on port ${BACKEND_PORT}"

    else

        echo
        echo "Backend logs:"
        docker logs "$BACKEND_CONTAINER" || true

        fail "Backend is running but did not respond on port ${BACKEND_PORT}"

    fi

else

    echo "⚠️  curl is unavailable; skipping HTTP test."

fi


# -------------------------------------------------------
# Final status
# -------------------------------------------------------

echo
echo "================================================="
echo "✅ SUPERKART DEPLOYMENT SUCCESSFUL"
echo "================================================="
echo
echo "Backend:"
echo "  Container : $BACKEND_CONTAINER"
echo "  Port      : $BACKEND_PORT"
echo
echo "Frontend:"
echo "  Container : $FRONTEND_CONTAINER"
echo "  Port      : $FRONTEND_PORT"
echo
echo "Docker network:"
echo "  $NETWORK_NAME"
echo

docker ps \
    --filter "name=$BACKEND_CONTAINER" \
    --filter "name=$FRONTEND_CONTAINER" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo
echo "================================================="
# -------------------------------------------------------
# 12. Set Codespace port visibility
# -------------------------------------------------------

info "Setting Codespace port visibility..."

if command -v gh >/dev/null 2>&1; then

    if [[ -n "${CODESPACE_NAME:-}" ]]; then

        if gh codespace ports visibility \
            -c "$CODESPACE_NAME" \
            "${BACKEND_PORT}:public"; then

            pass "Backend port ${BACKEND_PORT} set to Public"

        else
            echo "⚠️ Could not set port ${BACKEND_PORT} to Public."
        fi

    else
        echo "⚠️ CODESPACE_NAME is not available."
        echo "   Port visibility must be set manually."
    fi

else
    echo "⚠️ GitHub CLI not found; skipping port visibility setting."
fi