#!/bin/bash
# ============================================================
# Hotel Voice Agent — EC2 Server Setup Script
# ============================================================
# Run this script on a fresh Amazon Linux 2023 or Ubuntu 22.04 EC2 instance.
# Usage: bash ec2_setup.sh
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[✔]${NC} $1"; }
warn()  { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✖]${NC} $1"; exit 1; }

echo ""
echo "============================================================"
echo "  Hotel Voice Agent — EC2 Server Setup"
echo "============================================================"
echo ""

# -------------------------------------------------------
# Detect OS
# -------------------------------------------------------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
else
    error "Cannot detect OS. This script supports Amazon Linux 2023 and Ubuntu 22.04."
fi

log "Detected OS: $PRETTY_NAME"

# -------------------------------------------------------
# 1. Update system packages
# -------------------------------------------------------
echo ""
echo "--- Step 1: Updating system packages ---"
if [[ "$OS_ID" == "amzn" ]]; then
    sudo dnf update -y
elif [[ "$OS_ID" == "ubuntu" ]]; then
    sudo apt-get update -y && sudo apt-get upgrade -y
else
    warn "Unknown OS '$OS_ID'. Attempting to continue..."
fi
log "System packages updated"

# -------------------------------------------------------
# 2. Install Docker
# -------------------------------------------------------
echo ""
echo "--- Step 2: Installing Docker ---"
if command -v docker &> /dev/null; then
    log "Docker already installed: $(docker --version)"
else
    if [[ "$OS_ID" == "amzn" ]]; then
        sudo dnf install -y docker
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker ec2-user
    elif [[ "$OS_ID" == "ubuntu" ]]; then
        # Install Docker using official convenience script
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        sudo usermod -aG docker ubuntu
    fi
    log "Docker installed: $(docker --version)"
fi

# -------------------------------------------------------
# 3. Install Docker Compose (v2 plugin)
# -------------------------------------------------------
echo ""
echo "--- Step 3: Installing Docker Compose ---"
if docker compose version &> /dev/null; then
    log "Docker Compose already installed: $(docker compose version)"
else
    # Install Docker Compose v2 plugin
    DOCKER_COMPOSE_VERSION="v2.29.1"
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    sudo curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    log "Docker Compose installed: $(docker compose version)"
fi

# -------------------------------------------------------
# 4. Install Git (if not present)
# -------------------------------------------------------
echo ""
echo "--- Step 4: Checking Git ---"
if command -v git &> /dev/null; then
    log "Git already installed: $(git --version)"
else
    if [[ "$OS_ID" == "amzn" ]]; then
        sudo dnf install -y git
    elif [[ "$OS_ID" == "ubuntu" ]]; then
        sudo apt-get install -y git
    fi
    log "Git installed: $(git --version)"
fi

# -------------------------------------------------------
# 5. Add swap space (1GB) for t2.micro stability
# -------------------------------------------------------
echo ""
echo "--- Step 5: Configuring swap space ---"
if free | grep -q "Swap:" && [ "$(free | awk '/Swap:/ {print $2}')" -gt 0 ]; then
    log "Swap already configured: $(free -h | awk '/Swap:/ {print $2}') total"
else
    warn "No swap detected. Adding 1GB swap file..."
    sudo fallocate -l 1G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    # Make permanent
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
    log "1GB swap file created and enabled"
fi

# -------------------------------------------------------
# 6. Clone the repository (if not already cloned)
# -------------------------------------------------------
echo ""
echo "--- Step 6: Cloning repository ---"
REPO_URL="https://github.com/SaiRamReddySolleti/hotel-voice-agent.git"
APP_DIR="$HOME/hotel-voice-agent"

if [ -d "$APP_DIR" ]; then
    log "Repository already exists at $APP_DIR"
    cd "$APP_DIR"
    git pull origin main
    log "Pulled latest changes"
else
    git clone "$REPO_URL" "$APP_DIR"
    cd "$APP_DIR"
    log "Repository cloned to $APP_DIR"
fi

# -------------------------------------------------------
# 7. Create .env file from template
# -------------------------------------------------------
echo ""
echo "--- Step 7: Environment configuration ---"
if [ -f "$APP_DIR/.env" ]; then
    warn ".env file already exists. Skipping creation."
    warn "Edit it manually if needed: nano $APP_DIR/.env"
else
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
    log ".env file created from .env.example"
    echo ""
    warn "╔══════════════════════════════════════════════════════════╗"
    warn "║  ACTION REQUIRED: Edit your .env file with API keys!   ║"
    warn "║                                                         ║"
    warn "║  Run: nano $APP_DIR/.env                               ║"
    warn "║                                                         ║"
    warn "║  You need to set:                                       ║"
    warn "║    • ANTHROPIC_API_KEY                                  ║"
    warn "║    • ELEVENLABS_API_KEY                                 ║"
    warn "║    • POSTGRES_PASSWORD (change from default)            ║"
    warn "║    • BOOKING_API_KEY (change from default)              ║"
    warn "║    • N8N_ENCRYPTION_KEY (change from default)           ║"
    warn "╚══════════════════════════════════════════════════════════╝"
    echo ""
fi

# -------------------------------------------------------
# 8. Configure Docker to start on boot
# -------------------------------------------------------
echo ""
echo "--- Step 8: Configuring auto-start ---"
sudo systemctl enable docker
log "Docker configured to start on boot"

# Create a systemd service for the app
sudo tee /etc/systemd/system/hotel-voice-agent.service > /dev/null <<EOF
[Unit]
Description=Hotel Voice Agent (Docker Compose)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/local/lib/docker/cli-plugins/docker-compose -f docker-compose.yml up -d
ExecStop=/usr/local/lib/docker/cli-plugins/docker-compose -f docker-compose.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable hotel-voice-agent.service
log "Auto-start service created and enabled"

# -------------------------------------------------------
# 9. Open firewall ports (if firewall is active)
# -------------------------------------------------------
echo ""
echo "--- Step 9: Checking firewall ---"
if command -v ufw &> /dev/null && sudo ufw status | grep -q "active"; then
    sudo ufw allow 22/tcp    # SSH
    sudo ufw allow 80/tcp    # HTTP
    sudo ufw allow 443/tcp   # HTTPS
    sudo ufw allow 8000/tcp  # FastAPI
    sudo ufw allow 5678/tcp  # n8n
    log "UFW firewall rules added"
elif command -v firewall-cmd &> /dev/null; then
    sudo firewall-cmd --permanent --add-port=8000/tcp 2>/dev/null || true
    sudo firewall-cmd --permanent --add-port=5678/tcp 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
    log "Firewalld rules added"
else
    log "No active firewall detected (relying on AWS Security Group)"
fi

# -------------------------------------------------------
# Done!
# -------------------------------------------------------
echo ""
echo "============================================================"
echo -e "  ${GREEN}Setup Complete!${NC}"
echo "============================================================"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Edit your .env file:"
echo "     nano $APP_DIR/.env"
echo ""
echo "  2. Start all services:"
echo "     cd $APP_DIR"
echo "     docker compose up -d"
echo ""
echo "  3. Wait ~30 seconds, then get your Cloudflare tunnel URLs:"
echo "     bash get_tunnel_urls.sh"
echo ""
echo "  4. Update .env with the tunnel URLs (BOOKING_API_PUBLIC_URL"
echo "     and N8N_WEBHOOK_URL), then restart:"
echo "     docker compose down && docker compose up -d"
echo ""
echo "  5. Access your services:"
echo "     • Hotel Website:  http://<YOUR-EC2-IP>:8000"
echo "     • API Docs:       http://<YOUR-EC2-IP>:8000/docs"
echo "     • n8n Dashboard:  http://<YOUR-EC2-IP>:5678"
echo ""
echo "  For future updates from GitHub:"
echo "     bash deploy.sh"
echo ""
echo "============================================================"
echo ""
warn "IMPORTANT: Log out and log back in for Docker group"
warn "membership to take effect (or run: newgrp docker)"
echo ""
