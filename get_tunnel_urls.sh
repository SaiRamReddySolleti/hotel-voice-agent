#!/bin/bash
# ============================================================
# Get Cloudflare tunnel public URLs and update .env
# Run after: docker compose up -d
# Usage: bash get_tunnel_urls.sh
# ============================================================

echo "Waiting for Cloudflare tunnels to start..."
sleep 8

# Extract tunnel URLs from container logs
N8N_URL=$(docker logs cloudflared_n8n 2>&1 | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1)
API_URL=$(docker logs cloudflared_api  2>&1 | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1)

if [ -z "$N8N_URL" ] || [ -z "$API_URL" ]; then
  echo "Tunnels not ready yet, waiting 10 more seconds..."
  sleep 10
  N8N_URL=$(docker logs cloudflared_n8n 2>&1 | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1)
  API_URL=$(docker logs cloudflared_api  2>&1 | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1)
fi

if [ -z "$N8N_URL" ]; then
  echo "ERROR: Could not get n8n tunnel URL. Run: docker logs cloudflared_n8n"
  exit 1
fi

if [ -z "$API_URL" ]; then
  echo "ERROR: Could not get API tunnel URL. Run: docker logs cloudflared_api"
  exit 1
fi

echo ""
echo "========================================="
echo "  Cloudflare Tunnel URLs"
echo "========================================="
echo "  n8n (Twilio webhook base): $N8N_URL"
echo "  Booking API (audio files): $API_URL"
echo ""
echo "  Twilio webhook URL:"
echo "  $N8N_URL/webhook/voice-agent"
echo "========================================="
echo ""

# Update .env file
ENV_FILE="$(dirname "$0")/.env"

if [ -f "$ENV_FILE" ]; then
  # Update N8N_WEBHOOK_URL
  sed -i.bak "s|^N8N_WEBHOOK_URL=.*|N8N_WEBHOOK_URL=$N8N_URL|" "$ENV_FILE"
  # Update BOOKING_API_PUBLIC_URL
  sed -i.bak "s|^BOOKING_API_PUBLIC_URL=.*|BOOKING_API_PUBLIC_URL=$API_URL|" "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
  echo ".env updated with new tunnel URLs."
  echo ""
  echo "Now restart n8n and booking_api to pick up the new URLs:"
  echo "  docker compose up -d --force-recreate n8n booking_api"
  echo ""
  echo "Then in Twilio console, set webhook URL to:"
  echo "  $N8N_URL/webhook/voice-agent"
else
  echo "WARNING: .env file not found. Set these manually:"
  echo "  N8N_WEBHOOK_URL=$N8N_URL"
  echo "  BOOKING_API_PUBLIC_URL=$API_URL"
fi
