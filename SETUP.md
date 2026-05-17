# Hotel Voice Agent — Setup Guide
**Grand Choice Inn & Suites**

---

## Architecture Overview

```
Caller
  │
  ▼
Twilio Phone Number  (telephony + speech-to-text)
  │  POST /webhook/voice-agent
  ▼
n8n Workflow  (orchestration + AI voice agent)
  │  tool calls
  ▼
Booking API (FastAPI)  ←→  PostgreSQL (hotel data + session memory)
  │
  ▼
ElevenLabs TTS  (natural voice responses)
```

---

## Prerequisites

- Docker + Docker Compose installed
- Twilio account (free trial works)
- AI API key (for voice agent)
- ElevenLabs API key (for text-to-speech)

---

## Step 1 — Clone & Configure

```bash
cp .env.example .env
# Edit .env and fill in your API keys
```

---

## Step 2 — Start Services

```bash
docker compose up -d

# Verify all services are healthy:
docker compose ps
```

Services started:

| Service      | Port | URL                        |
|--------------|------|----------------------------|
| PostgreSQL   | 5432 | —                          |
| Booking API  | 8000 | http://localhost:8000/docs |
| n8n          | 5678 | http://localhost:5678      |

---

## Step 3 — Get Public URLs (Cloudflare Tunnels)

The project uses Cloudflare quick tunnels automatically. After `docker compose up`, get your URLs:

```bash
# n8n tunnel URL (use for Twilio webhook)
docker logs cloudflared_n8n 2>&1 | grep trycloudflare

# Booking API tunnel URL (used internally)
docker logs cloudflared_api 2>&1 | grep trycloudflare
```

Update your `.env` with both URLs, then restart:

```bash
docker compose up -d
```

---

## Step 4 — Configure n8n

1. Open http://localhost:5678
2. **Import the workflow:**
   - Workflows → Import from File
   - Select `n8n_workflows/hotel_voice_agent.json`
3. **Activate the workflow** (toggle in top right)

The workflow reads all API keys from the environment variables already set in `docker-compose.yml`.

---

## Step 5 — Configure Twilio

1. Sign up at [twilio.com](https://twilio.com)
2. Console → Phone Numbers → Manage → Buy a Number
   - Choose a US number with **Voice** capability
3. Configure the number:
   - **Voice & Fax** section → "A call comes in" → **Webhook**
   - URL: `https://YOUR-N8N-TUNNEL.trycloudflare.com/webhook/voice-agent`
   - Method: **HTTP POST**
   - Save

---

## Step 6 — Test the System

### Quick API test (no phone needed):

```bash
# Check hotel info
curl http://localhost:8000/hotel-info \
  -H "x-api-key: demo-secret-key-2024"

# Check availability
curl "http://localhost:8000/availability?check_in=2025-06-01&check_out=2025-06-03&guests=2" \
  -H "x-api-key: demo-secret-key-2024"

# Full API docs
open http://localhost:8000/docs
```

### Phone test:
Call your Twilio number and try:
- *"I'd like to book a room for 2 nights next Friday"*
- *"What rooms do you have available?"*
- *"Can you confirm my reservation GCI-2024-001?"*
- *"What time is check-in?"*
- *"Do you have pet-friendly rooms?"*

### Website:
Open http://localhost:8000 to browse the hotel website, check rooms, and book online.

---

## How a Call Works

```
1. Call comes in → Twilio sends POST to n8n webhook
2. Parse: extract CallSid, SpeechResult, CallStatus
3. Route:
   ├─ New call   → Play greeting → Gather speech
   ├─ Ongoing    → Load history → Run AI agent → Save history → Respond
   └─ Call ended → Mark session ended
4. AI agent loop:
   a. Process conversation with full history + available tools
   b. If tool needed → execute against Booking API
   c. Feed tool results back to agent
   d. Repeat until final text response
5. Convert response to speech via ElevenLabs → return TwiML
```

---

## Demo Scenarios

| Scenario | What to say |
|---|---|
| Check availability | "Do you have any rooms available for this weekend?" |
| Get pricing | "How much is a king room per night?" |
| Make reservation | "I'd like to book a standard king for March 15th to 17th" |
| Confirm booking | "Can you confirm reservation GCI-2024-001?" |
| Hotel amenities | "Do you have a pool? What time does it open?" |
| Cancellation | "I need to cancel my reservation" |
| Pet policy | "I'm traveling with my dog, is that okay?" |

---

## File Structure

```
hotel-voice-agent/
├── docker-compose.yml          # All services
├── .env.example                # Environment template
├── setup/
│   ├── init.sql                # DB schema + seed data
│   └── create_multiple_dbs.sh  # Multi-DB init script
├── booking_system/
│   ├── main.py                 # FastAPI — all booking endpoints + hotel website
│   ├── database.py             # SQLAlchemy models
│   ├── templates/              # Hotel website HTML pages
│   ├── requirements.txt
│   └── Dockerfile
└── n8n_workflows/
    └── hotel_voice_agent.json  # Import into n8n
```

---

## Troubleshooting

**n8n can't reach booking_api:**
- Make sure the booking API service name is `booking_api` (Docker internal hostname)

**Twilio says webhook failed:**
- Check Cloudflare tunnel is running and URL in Twilio matches exactly
- Check workflow is activated in n8n

**Voice agent not responding correctly:**
- Verify `ANTHROPIC_API_KEY` is set in `.env`
- Check `docker compose logs n8n` for errors

**DB connection refused:**
- Wait ~15 seconds after `docker compose up` for PostgreSQL to initialize
- Run `docker compose logs postgres` to check

**Tunnel URLs changed (Cloudflare free tunnels reset on restart):**
```bash
# Get new URLs
docker logs cloudflared_n8n 2>&1 | grep trycloudflare
docker logs cloudflared_api 2>&1 | grep trycloudflare
# Update .env, restart services, update Twilio webhook URL
```

**Reset all data:**
```bash
docker compose down -v   # removes volumes
docker compose up -d     # re-seeds fresh data
```
