# Hotel Voice Agent

A full-stack voice-based hotel reservation system. Guests call a phone number, speak naturally, and the system handles availability checks, bookings, confirmations, and cancellations — all through conversation.

Built with a hotel website included so guests can also book online.

---

## Features

**Voice Agent (Phone)**
- Natural conversation over a real phone call
- Checks room availability in real time
- Creates, confirms, and cancels reservations
- Answers hotel info questions (check-in times, amenities, pet policy, etc.)
- ElevenLabs text-to-speech for natural-sounding responses
- Full conversation history preserved per call

**Hotel Website**
- Homepage with featured rooms and amenities
- Rooms & Suites page with floor map and pricing
- Online booking form with real-time availability
- My Reservation page — look up or cancel by confirmation code

**Booking API**
- RESTful API powering both voice agent and website
- Real-time availability calculation
- Confirmation codes (e.g. `GCI-2026-AB1234`)
- Guest session management

---

## Tech Stack

| Layer | Technology |
|---|---|
| Phone / STT | Twilio (speech-to-text via Deepgram Nova-2) |
| Orchestration | n8n (workflow automation) |
| Voice Intelligence | AI language model via API |
| Text-to-Speech | ElevenLabs |
| Backend API | FastAPI (Python) |
| Database | PostgreSQL |
| Hotel Website | Jinja2 templates + Tailwind CSS |
| Tunneling | Cloudflare Tunnels |
| Infrastructure | Docker Compose |

---

## Hotel: Grand Choice Inn & Suites

**42 rooms across 3 floors:**

| Floor | Rooms | Room Types |
|---|---|---|
| Floor 1 | 101–114 | Accessible Queen, Economy, Standard Queen |
| Floor 2 | 201–214 | Standard King, Double Queen |
| Floor 3 | 301–314 | Deluxe King, King Suite |

**Pricing:** $79–$239/night depending on room type and day of week.

---

## Quick Start (Local)

```bash
git clone https://github.com/SaiRamReddySolleti/hotel-voice-agent.git
cd hotel-voice-agent
cp .env.example .env
# Fill in your API keys in .env
docker compose up -d
```

See [SETUP.md](SETUP.md) for full setup instructions including Twilio and n8n configuration.

---

## Deploy to AWS EC2 (Free Tier)

Run the full stack live on AWS EC2 — free for 12 months.

### Prerequisites

- AWS account ([sign up here](https://aws.amazon.com))
- EC2 instance: **t2.micro** (free tier, 1GB RAM) or **t3.small** (2GB RAM, ~$15/mo recommended)
- Key pair (`.pem` file) for SSH access

### 1. Launch EC2 Instance

In the AWS Console → EC2 → Launch Instance:

| Setting | Value |
|---|---|
| AMI | Amazon Linux 2023 or Ubuntu 22.04 LTS |
| Instance type | t2.micro (free) or t3.small (recommended) |
| Key pair | Create new or select existing |
| Storage | 30 GB gp3 |

**Security Group — open these ports:**

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | Your IP | SSH |
| 80 | TCP | Anywhere | HTTP |
| 443 | TCP | Anywhere | HTTPS |
| 8000 | TCP | Anywhere | FastAPI / Hotel Website |
| 5678 | TCP | Anywhere | n8n Dashboard |

**Allocate an Elastic IP** and associate it with your instance (keeps IP static across restarts).

### 2. SSH into Your Instance

```bash
chmod 400 your-key.pem
ssh -i your-key.pem ec2-user@<YOUR-ELASTIC-IP>
# For Ubuntu: ssh -i your-key.pem ubuntu@<YOUR-ELASTIC-IP>
```

### 3. Run the Setup Script

```bash
# Clone and set up everything automatically
git clone https://github.com/SaiRamReddySolleti/hotel-voice-agent.git
cd hotel-voice-agent
bash ec2_setup.sh
```

This installs Docker, Docker Compose, adds 1GB swap, and configures auto-start on reboot.

### 4. Configure Environment Variables

```bash
nano .env
```

Fill in your API keys:
- `ANTHROPIC_API_KEY` — your AI API key
- `ELEVENLABS_API_KEY` — your ElevenLabs key
- `POSTGRES_PASSWORD` — change from default
- `BOOKING_API_KEY` — change from default

### 5. Start Services

```bash
docker compose up -d
```

Wait ~30 seconds for all services to start, then get your Cloudflare tunnel URLs:

```bash
bash get_tunnel_urls.sh
```

Update `.env` with the tunnel URLs (`BOOKING_API_PUBLIC_URL` and `N8N_WEBHOOK_URL`), then restart:

```bash
docker compose down && docker compose up -d
```

### 6. Access Your Live Services

| Service | URL |
|---|---|
| Hotel Website | `http://<YOUR-EC2-IP>:8000` |
| API Docs | `http://<YOUR-EC2-IP>:8000/docs` |
| n8n Dashboard | `http://<YOUR-EC2-IP>:5678` |
| Public API (via tunnel) | `https://<tunnel-url>/docs` |

### Updating from GitHub

After pushing new code to GitHub, redeploy with one command:

```bash
bash deploy.sh
```

---

## How It Works

```
Caller dials Twilio number
    → Twilio captures speech
    → n8n webhook receives transcript
    → AI agent processes request with hotel tools
    → Booking API executes (check availability, create reservation, etc.)
    → ElevenLabs converts response to speech
    → Twilio plays audio back to caller
```

Each turn of the conversation is saved so the agent remembers full context (guest name, dates already mentioned, etc.).

---

## API Endpoints

```
GET  /health                    — Service health check
GET  /hotel-info                — Hotel details and policies
GET  /rooms                     — All room types with pricing
GET  /availability              — Available rooms for date range
POST /reservations              — Create reservation
GET  /reservations/{code}       — Look up reservation
DELETE /reservations/{code}     — Cancel reservation

GET  /                          — Hotel homepage
GET  /rooms                     — Rooms & Suites page
GET  /book                      — Online booking page
GET  /my-reservation            — Manage existing reservation
```

Full interactive docs at `http://localhost:8000/docs`

---

## Project Structure

```
hotel-voice-agent/
├── docker-compose.yml
├── .env.example
├── ec2_setup.sh               # AWS EC2 server provisioning script
├── deploy.sh                  # Pull & redeploy from GitHub
├── get_tunnel_urls.sh         # Fetch Cloudflare tunnel URLs
├── setup/
│   ├── init.sql                # Schema + seed data
│   └── create_multiple_dbs.sh
├── booking_system/
│   ├── main.py                 # FastAPI app
│   ├── database.py             # SQLAlchemy models
│   ├── templates/              # HTML pages
│   │   ├── base.html
│   │   ├── index.html
│   │   ├── rooms.html
│   │   ├── book.html
│   │   └── my_reservation.html
│   ├── requirements.txt
│   └── Dockerfile
└── n8n_workflows/
    └── hotel_voice_agent.json
```

---

## Requirements

- Docker + Docker Compose
- Twilio account (phone number with Voice capability)
- ElevenLabs account (for TTS)
- AI API key (for voice agent)
- **For cloud deployment:** AWS account (EC2 free tier eligible)
