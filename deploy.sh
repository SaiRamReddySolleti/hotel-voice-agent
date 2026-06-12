#!/bin/bash
# ============================================================
# Hotel Voice Agent — Deployment Script
# ============================================================
# Pull latest code from GitHub and redeploy containers.
# Usage: bash deploy.sh
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✔]${NC} $1"; }
warn()  { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✖]${NC} $1"; exit 1; }

# Navigate to project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "============================================================"
echo "  Hotel Voice Agent — Deploying Latest Changes"
echo "============================================================"
echo ""

# -------------------------------------------------------
# 1. Pull latest code from GitHub
# -------------------------------------------------------
echo "--- Step 1: Pulling latest code from GitHub ---"
CURRENT_COMMIT=$(git rev-parse --short HEAD)
git pull origin main
NEW_COMMIT=$(git rev-parse --short HEAD)

if [ "$CURRENT_COMMIT" = "$NEW_COMMIT" ]; then
    log "Already up to date (commit: $CURRENT_COMMIT)"
else
    log "Updated from $CURRENT_COMMIT → $NEW_COMMIT"
fi

# -------------------------------------------------------
# 2. Rebuild containers (only if Dockerfile changed)
# -------------------------------------------------------
echo ""
echo "--- Step 2: Rebuilding and restarting containers ---"

# Check if any Dockerfile or requirements changed
CHANGED_FILES=$(git diff --name-only "$CURRENT_COMMIT" "$NEW_COMMIT" 2>/dev/null || echo "")

if echo "$CHANGED_FILES" | grep -qE "(Dockerfile|requirements\.txt|docker-compose)"; then
    warn "Build files changed — performing full rebuild..."
    docker compose down
    docker compose build --no-cache
    docker compose up -d
    log "Full rebuild and restart complete"
else
    # Just restart with the new code (volume-mounted files update automatically)
    docker compose down
    docker compose up -d
    log "Containers restarted with latest code"
fi

# -------------------------------------------------------
# 3. Wait for health checks
# -------------------------------------------------------
echo ""
echo "--- Step 3: Waiting for services to become healthy ---"
echo -n "  Waiting"

MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    # Check if booking_api is healthy
    if docker compose ps --format json 2>/dev/null | grep -q '"Health":"healthy"' || \
       curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        break
    fi
    echo -n "."
    sleep 5
    WAITED=$((WAITED + 5))
done
echo ""

if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    log "Booking API is healthy ✓"
else
    warn "Booking API health check timed out (may still be starting)"
fi

# -------------------------------------------------------
# 4. Show status
# -------------------------------------------------------
echo ""
echo "--- Service Status ---"
docker compose ps
echo ""

# -------------------------------------------------------
# 5. Show tunnel URLs
# -------------------------------------------------------
echo ""
echo "--- Cloudflare Tunnel URLs ---"
API_URL=$(docker logs cloudflared_api 2>&1 | grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' | tail -1 || echo "Not available yet")
N8N_URL=$(docker logs cloudflared_n8n 2>&1 | grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' | tail -1 || echo "Not available yet")

echo "  Hotel Website / API: $API_URL"
echo "  n8n Dashboard:       $N8N_URL"
echo ""

# -------------------------------------------------------
# Done
# -------------------------------------------------------
echo "============================================================"
echo -e "  ${GREEN}Deployment Complete!${NC}"
echo "============================================================"
echo ""
echo "  Deployed commit: $NEW_COMMIT"
echo "  Time: $(date)"
echo ""
