"""
Grand Choice Inn & Suites — Demo Booking API
============================================
All endpoints the n8n voice agent calls as tools.
"""
import os
import re
import uuid
import random
import string
import hashlib
import pathlib
import httpx
from datetime import date, datetime
from typing import Optional, List
from decimal import Decimal

from fastapi import FastAPI, Depends, HTTPException, Header, Query, Request
from fastapi.responses import JSONResponse, FileResponse
from fastapi.openapi.docs import get_swagger_ui_html, get_redoc_html
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session
from sqlalchemy import text, func

from database import (
    get_db, HotelInfo, RoomType, Room, Customer, Reservation, CallSession
)

# Ensure audio cache directory exists
AUDIO_DIR = pathlib.Path("/tmp/audio")
AUDIO_DIR.mkdir(parents=True, exist_ok=True)

# Jinja2 templates
templates = Jinja2Templates(directory="templates")

# -------------------------------------------------------
app = FastAPI(
    title="Grand Choice Inn & Suites — Booking API",
    description="""
## Hotel Voice Agent — Demo Booking System

This API powers the AI voice agent for **Grand Choice Inn & Suites**.

### Available Operations
- **Hotel Info** — address, policies, amenities, check-in/out times
- **Rooms** — room types, pricing, availability
- **Reservations** — create, confirm, cancel bookings
- **Sessions** — call session memory for the n8n voice agent

### Authentication
All endpoints require the `x-api-key` header.
""",
    version="1.0.0",
    docs_url=None,
    redoc_url=None,
)


@app.get("/docs", include_in_schema=False)
async def custom_swagger_ui():
    return get_swagger_ui_html(
        openapi_url="/openapi.json",
        title="Grand Choice Inn — Booking API",
        swagger_css_url="https://cdn.jsdelivr.net/npm/swagger-ui-themes@3.0.1/themes/3.x/theme-flattop.css",
        swagger_ui_parameters={
            "docExpansion": "list",
            "defaultModelsExpandDepth": -1,
            "tryItOutEnabled": True,
            "persistAuthorization": True,
            "displayRequestDuration": True,
            "filter": True,
        },
    )


@app.get("/redoc", include_in_schema=False)
async def redoc_ui():
    return get_redoc_html(
        openapi_url="/openapi.json",
        title="Grand Choice Inn — API Reference",
        redoc_favicon_url="https://fastapi.tiangolo.com/img/favicon.png",
    )

API_KEY = os.getenv("API_KEY", "demo-secret-key-2024")


def verify_api_key(x_api_key: str = Header(default=None)):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")


def generate_confirmation_code() -> str:
    suffix = "".join(random.choices(string.ascii_uppercase + string.digits, k=6))
    return f"GCI-{datetime.now().year}-{suffix}"


# -------------------------------------------------------
# SCHEMAS
# -------------------------------------------------------
class AvailabilityResult(BaseModel):
    type_code: str
    room_name: str
    bed_type: Optional[str]
    max_occupancy: int
    price_per_night_weekday: float
    price_per_night_weekend: float
    available_rooms: int
    estimated_total: float
    num_nights: int


class ReservationCreate(BaseModel):
    first_name: str
    last_name: str
    phone: str
    email: Optional[str] = None
    room_type_code: str
    check_in_date: str   # YYYY-MM-DD
    check_out_date: str  # YYYY-MM-DD
    num_guests: int = 1
    special_requests: Optional[str] = None

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, v: str) -> str:
        digits = re.sub(r"\D", "", v)
        if len(digits) == 10:
            return f"+1{digits}"
        if len(digits) == 11 and digits.startswith("1"):
            return f"+{digits}"
        return v

    @field_validator("check_in_date", "check_out_date")
    @classmethod
    def validate_date_format(cls, v: str) -> str:
        try:
            datetime.strptime(v, "%Y-%m-%d")
        except ValueError:
            raise ValueError("Date must be in YYYY-MM-DD format")
        return v


class ReservationResponse(BaseModel):
    confirmation_code: str
    customer_name: str
    room_type: str
    check_in_date: str
    check_out_date: str
    num_nights: int
    num_guests: int
    total_price: float
    status: str
    special_requests: Optional[str]
    created_at: str


class CallSessionCreate(BaseModel):
    call_sid: str
    caller_phone: Optional[str] = None


class ConversationUpdate(BaseModel):
    call_sid: str
    history: Optional[list] = None
    intent: Optional[str] = None
    call_status: Optional[str] = "active"


# -------------------------------------------------------
# HEALTH
# -------------------------------------------------------
@app.get("/health", tags=["System"])
def health():
    return {"status": "ok", "service": "hotel-booking-api"}


# -------------------------------------------------------
# HOTEL INFO
# -------------------------------------------------------
@app.get("/hotel-info", tags=["Hotel"])
def get_hotel_info(
    key: Optional[str] = Query(default=None, description="Specific info key, or omit for all"),
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Return hotel details: address, policies, amenities, etc."""
    if key:
        row = db.query(HotelInfo).filter(HotelInfo.key == key).first()
        if not row:
            raise HTTPException(status_code=404, detail=f"Key '{key}' not found")
        return {key: row.value}

    rows = db.query(HotelInfo).all()
    return {r.key: r.value for r in rows}


# -------------------------------------------------------
# ROOM TYPES + PRICING
# -------------------------------------------------------
@app.get("/rooms")
async def list_room_types(
    request: Request,
    x_api_key: str = Header(default=None),
    db: Session = Depends(get_db),
):
    """Return room types as JSON (API) or the hotel rooms web page (browser)."""
    if x_api_key == API_KEY:
        rooms = db.query(RoomType).filter(RoomType.is_active == True).all()
        return [
            {
                "type_code": r.type_code,
                "name": r.name,
                "description": r.description,
                "bed_type": r.bed_type,
                "max_occupancy": r.max_occupancy,
                "price_weekday": float(r.price_weekday),
                "price_weekend": float(r.price_weekend),
                "amenities": r.amenities or [],
            }
            for r in rooms
        ]
    return templates.TemplateResponse("rooms.html", {"request": request})


# -------------------------------------------------------
# AVAILABILITY CHECK
# -------------------------------------------------------
@app.get("/availability", tags=["Rooms"], response_model=List[AvailabilityResult])
def check_availability(
    check_in: str = Query(..., description="Check-in date YYYY-MM-DD"),
    check_out: str = Query(..., description="Check-out date YYYY-MM-DD"),
    guests: int = Query(default=1, ge=1, le=8, description="Number of guests"),
    room_type: Optional[str] = Query(default=None, description="Filter by room type code"),
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Check which room types are available for given dates."""
    try:
        ci = datetime.strptime(check_in, "%Y-%m-%d").date()
        co = datetime.strptime(check_out, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Dates must be YYYY-MM-DD format")

    if ci >= co:
        raise HTTPException(status_code=400, detail="Check-out must be after check-in")
    if ci < date.today():
        raise HTTPException(status_code=400, detail="Check-in cannot be in the past")
    if (co - ci).days > 30:
        raise HTTPException(status_code=400, detail="Maximum stay is 30 nights")

    rt_filter = f"'{room_type}'" if room_type else "NULL"
    sql = text(f"""
        SELECT type_code, room_name, bed_type, max_occupancy,
               price_weekday, price_weekend, available_count, estimated_total
        FROM check_room_availability(
            CAST(:ci AS date), CAST(:co AS date), CAST({rt_filter} AS varchar)
        )
        WHERE max_occupancy >= :guests
    """)

    rows = db.execute(sql, {"ci": check_in, "co": check_out, "guests": guests}).fetchall()
    num_nights = (co - ci).days

    if not rows:
        return []

    return [
        AvailabilityResult(
            type_code=row.type_code,
            room_name=row.room_name,
            bed_type=row.bed_type,
            max_occupancy=row.max_occupancy,
            price_per_night_weekday=float(row.price_weekday),
            price_per_night_weekend=float(row.price_weekend),
            available_rooms=int(row.available_count),
            estimated_total=float(row.estimated_total),
            num_nights=num_nights,
        )
        for row in rows
    ]


# -------------------------------------------------------
# CREATE RESERVATION
# -------------------------------------------------------
@app.post("/reservations", tags=["Reservations"], response_model=ReservationResponse)
def create_reservation(
    payload: ReservationCreate,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Book a room. Returns a confirmation code."""
    ci = datetime.strptime(payload.check_in_date, "%Y-%m-%d").date()
    co = datetime.strptime(payload.check_out_date, "%Y-%m-%d").date()

    if ci >= co:
        raise HTTPException(status_code=400, detail="Check-out must be after check-in")
    if ci < date.today():
        raise HTTPException(status_code=400, detail="Check-in cannot be in the past")

    # Find room type
    rt = db.query(RoomType).filter(
        RoomType.type_code == payload.room_type_code,
        RoomType.is_active == True
    ).first()
    if not rt:
        raise HTTPException(status_code=404, detail=f"Room type '{payload.room_type_code}' not found")

    if payload.num_guests > rt.max_occupancy:
        raise HTTPException(
            status_code=400,
            detail=f"{rt.name} fits max {rt.max_occupancy} guests. You requested {payload.num_guests}."
        )

    # Verify availability
    available_check = db.execute(
        text("""
            SELECT available_count, estimated_total
            FROM check_room_availability(CAST(:ci AS date), CAST(:co AS date), CAST(:tc AS varchar))
        """),
        {"ci": payload.check_in_date, "co": payload.check_out_date, "tc": payload.room_type_code}
    ).fetchone()

    if not available_check or available_check.available_count == 0:
        raise HTTPException(
            status_code=409,
            detail=f"No {rt.name} rooms available for those dates. Try different dates or room type."
        )

    total_price = float(available_check.estimated_total)

    # Upsert customer
    customer = db.query(Customer).filter(Customer.phone == payload.phone).first()
    if customer:
        customer.first_name = payload.first_name
        customer.last_name = payload.last_name
        if payload.email:
            customer.email = payload.email
    else:
        customer = Customer(
            phone=payload.phone,
            first_name=payload.first_name,
            last_name=payload.last_name,
            email=payload.email,
        )
        db.add(customer)
        db.flush()

    # Generate unique confirmation code
    conf_code = generate_confirmation_code()
    while db.query(Reservation).filter(Reservation.confirmation_code == conf_code).first():
        conf_code = generate_confirmation_code()

    reservation = Reservation(
        confirmation_code=conf_code,
        customer_id=customer.id,
        room_type_id=rt.id,
        check_in_date=ci,
        check_out_date=co,
        num_guests=payload.num_guests,
        total_price=Decimal(str(total_price)),
        status="confirmed",
        special_requests=payload.special_requests,
    )
    db.add(reservation)
    db.commit()
    db.refresh(reservation)

    return ReservationResponse(
        confirmation_code=reservation.confirmation_code,
        customer_name=f"{customer.first_name} {customer.last_name}",
        room_type=rt.name,
        check_in_date=str(reservation.check_in_date),
        check_out_date=str(reservation.check_out_date),
        num_nights=(co - ci).days,
        num_guests=reservation.num_guests,
        total_price=float(reservation.total_price),
        status=reservation.status,
        special_requests=reservation.special_requests,
        created_at=str(reservation.created_at),
    )


# -------------------------------------------------------
# GET RESERVATION BY CONFIRMATION CODE
# -------------------------------------------------------
@app.get("/reservations/{confirmation_code}", tags=["Reservations"], response_model=ReservationResponse)
def get_reservation(
    confirmation_code: str,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Look up a reservation by confirmation code."""
    res = db.query(Reservation).filter(
        Reservation.confirmation_code == confirmation_code.upper()
    ).first()
    if not res:
        raise HTTPException(status_code=404, detail=f"Reservation '{confirmation_code}' not found")

    customer = db.query(Customer).filter(Customer.id == res.customer_id).first()
    rt = db.query(RoomType).filter(RoomType.id == res.room_type_id).first()
    num_nights = (res.check_out_date - res.check_in_date).days

    return ReservationResponse(
        confirmation_code=res.confirmation_code,
        customer_name=f"{customer.first_name} {customer.last_name}" if customer else "Unknown",
        room_type=rt.name if rt else "Unknown",
        check_in_date=str(res.check_in_date),
        check_out_date=str(res.check_out_date),
        num_nights=num_nights,
        num_guests=res.num_guests,
        total_price=float(res.total_price) if res.total_price else 0.0,
        status=res.status,
        special_requests=res.special_requests,
        created_at=str(res.created_at),
    )


# -------------------------------------------------------
# CANCEL RESERVATION
# -------------------------------------------------------
@app.delete("/reservations/{confirmation_code}", tags=["Reservations"])
def cancel_reservation(
    confirmation_code: str,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Cancel a reservation."""
    res = db.query(Reservation).filter(
        Reservation.confirmation_code == confirmation_code.upper()
    ).first()
    if not res:
        raise HTTPException(status_code=404, detail=f"Reservation '{confirmation_code}' not found")

    if res.status in ("checked_in", "checked_out"):
        raise HTTPException(status_code=400, detail="Cannot cancel a reservation that is already checked in or out")

    if res.status == "cancelled":
        return {"message": "Reservation was already cancelled", "confirmation_code": confirmation_code}

    res.status = "cancelled"
    res.updated_at = datetime.now()
    db.commit()

    return {"message": "Reservation successfully cancelled", "confirmation_code": confirmation_code.upper()}


# -------------------------------------------------------
# CALL SESSION MANAGEMENT (used by n8n voice agent)
# -------------------------------------------------------
@app.post("/sessions", tags=["Sessions"])
def create_session(
    payload: CallSessionCreate,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Create a new call session."""
    existing = db.query(CallSession).filter(CallSession.call_sid == payload.call_sid).first()
    if existing:
        return {"call_sid": existing.call_sid, "status": "already_exists"}

    session = CallSession(
        call_sid=payload.call_sid,
        caller_phone=payload.caller_phone,
        conversation_history=[],
        call_status="active",
    )
    db.add(session)
    db.commit()
    return {"call_sid": session.call_sid, "status": "created"}


@app.get("/sessions/{call_sid}", tags=["Sessions"])
def get_session(
    call_sid: str,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Load conversation history for a call."""
    session = db.query(CallSession).filter(CallSession.call_sid == call_sid).first()
    if not session:
        return {"call_sid": call_sid, "history": [], "found": False}
    return {
        "call_sid": session.call_sid,
        "caller_phone": session.caller_phone,
        "history": session.conversation_history or [],
        "call_status": session.call_status,
        "intent": session.intent,
        "found": True,
    }


@app.put("/sessions/{call_sid}", tags=["Sessions"])
def update_session(
    call_sid: str,
    payload: ConversationUpdate,
    db: Session = Depends(get_db),
    _: None = Depends(verify_api_key),
):
    """Save updated conversation history. Creates the session if it doesn't exist (upsert)."""
    session = db.query(CallSession).filter(CallSession.call_sid == call_sid).first()
    if not session:
        session = CallSession(
            call_sid=call_sid,
            caller_phone=payload.call_sid,
            conversation_history=[],
            call_status="active",
        )
        db.add(session)
        db.flush()

    if payload.history is not None:
        session.conversation_history = payload.history
    if payload.intent:
        session.intent = payload.intent
    if payload.call_status:
        session.call_status = payload.call_status
        if payload.call_status == "ended":
            session.ended_at = datetime.now()

    db.commit()
    return {"call_sid": call_sid, "status": "updated"}


# -------------------------------------------------------
# ELEVENLABS TTS — generate audio and serve as public URL
# -------------------------------------------------------
ELEVENLABS_API_KEY  = os.getenv("ELEVENLABS_API_KEY", "")
ELEVENLABS_VOICE_ID = os.getenv("ELEVENLABS_VOICE_ID", "21m00Tcm4TlvDq8ikWAM")
BOOKING_API_PUBLIC_URL = os.getenv("BOOKING_API_PUBLIC_URL", "http://localhost:8000")


class TTSRequest(BaseModel):
    text: str
    voice_id: Optional[str] = None   # override default voice


@app.post("/tts", tags=["TTS"])
async def text_to_speech(
    payload: TTSRequest,
    _: None = Depends(verify_api_key),
):
    """
    Convert text to speech via ElevenLabs.
    Returns a public audio URL Twilio can play with <Play>.
    Audio is cached by content hash so identical phrases are free.
    """
    if not ELEVENLABS_API_KEY:
        raise HTTPException(status_code=503, detail="ElevenLabs API key not configured")

    text = payload.text.strip()
    voice_id = payload.voice_id or ELEVENLABS_VOICE_ID

    # Cache by hash — same text = same file, no re-generation
    cache_key = hashlib.md5(f"{voice_id}:{text}".encode()).hexdigest()
    audio_path = AUDIO_DIR / f"{cache_key}.mp3"

    if not audio_path.exists():
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}",
                headers={
                    "xi-api-key": ELEVENLABS_API_KEY,
                    "Content-Type": "application/json",
                },
                json={
                    "text": text,
                    "model_id": "eleven_turbo_v2",
                    "voice_settings": {
                        "stability": 0.5,
                        "similarity_boost": 0.75,
                        "style": 0.0,
                        "use_speaker_boost": True,
                    },
                },
            )
        if resp.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail=f"ElevenLabs error {resp.status_code}: {resp.text[:200]}"
            )
        audio_path.write_bytes(resp.content)

    public_url = f"{BOOKING_API_PUBLIC_URL}/tts/audio/{cache_key}.mp3"
    return {"audio_url": public_url, "cached": audio_path.exists()}


@app.get("/tts/audio/{filename}", tags=["TTS"], include_in_schema=False)
@app.head("/tts/audio/{filename}", include_in_schema=False)
async def serve_audio(filename: str):
    """Serve cached audio file — called by Twilio <Play>. HEAD supported for Twilio URL validation."""
    audio_path = AUDIO_DIR / filename
    if not audio_path.exists():
        raise HTTPException(status_code=404, detail="Audio file not found")
    return FileResponse(
        path=str(audio_path),
        media_type="audio/mpeg",
        headers={"Cache-Control": "public, max-age=86400"},
    )


# -------------------------------------------------------
# WEBSITE PAGES (HTML)
# -------------------------------------------------------

@app.get("/", include_in_schema=False)
async def homepage(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/rooms", include_in_schema=False)
async def rooms_page(request: Request):
    return templates.TemplateResponse("rooms.html", {"request": request})


@app.get("/book", include_in_schema=False)
async def book_page(request: Request):
    return templates.TemplateResponse("book.html", {"request": request})


@app.get("/my-reservation", include_in_schema=False)
async def my_reservation_page(request: Request):
    return templates.TemplateResponse("my_reservation.html", {"request": request})


# -------------------------------------------------------
# PUBLIC WEB API (no API key — for the hotel website frontend)
# -------------------------------------------------------

@app.get("/web/availability", tags=["Web"], include_in_schema=False)
def web_check_availability(
    check_in: str = Query(...),
    check_out: str = Query(...),
    guests: int = Query(default=1, ge=1, le=8),
    db: Session = Depends(get_db),
):
    """Availability endpoint for the hotel website (no API key required)."""
    try:
        ci = datetime.strptime(check_in, "%Y-%m-%d").date()
        co = datetime.strptime(check_out, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Dates must be YYYY-MM-DD format")

    if ci >= co:
        raise HTTPException(status_code=400, detail="Check-out must be after check-in")
    if ci < date.today():
        raise HTTPException(status_code=400, detail="Check-in cannot be in the past")

    sql = text("""
        SELECT type_code, room_name, bed_type, max_occupancy,
               price_weekday, price_weekend, available_count, estimated_total
        FROM check_room_availability(CAST(:ci AS date), CAST(:co AS date), NULL)
        WHERE max_occupancy >= :guests
    """)
    rows = db.execute(sql, {"ci": check_in, "co": check_out, "guests": guests}).fetchall()
    num_nights = (co - ci).days

    return [
        {
            "type_code": row.type_code,
            "room_name": row.room_name,
            "bed_type": row.bed_type,
            "max_occupancy": row.max_occupancy,
            "price_per_night_weekday": float(row.price_weekday),
            "price_per_night_weekend": float(row.price_weekend),
            "available_rooms": int(row.available_count),
            "estimated_total": float(row.estimated_total),
            "num_nights": num_nights,
        }
        for row in rows
    ]


@app.post("/web/reservations", tags=["Web"], include_in_schema=False)
def web_create_reservation(payload: ReservationCreate, db: Session = Depends(get_db)):
    """Create reservation from hotel website (no API key required)."""
    ci = datetime.strptime(payload.check_in_date, "%Y-%m-%d").date()
    co = datetime.strptime(payload.check_out_date, "%Y-%m-%d").date()

    if ci >= co:
        raise HTTPException(status_code=400, detail="Check-out must be after check-in")
    if ci < date.today():
        raise HTTPException(status_code=400, detail="Check-in cannot be in the past")

    rt = db.query(RoomType).filter(
        RoomType.type_code == payload.room_type_code,
        RoomType.is_active == True
    ).first()
    if not rt:
        raise HTTPException(status_code=404, detail=f"Room type '{payload.room_type_code}' not found")

    if payload.num_guests > rt.max_occupancy:
        raise HTTPException(status_code=400,
            detail=f"{rt.name} accommodates max {rt.max_occupancy} guests.")

    avail = db.execute(
        text("""SELECT available_count, estimated_total
                FROM check_room_availability(CAST(:ci AS date), CAST(:co AS date), CAST(:tc AS varchar))"""),
        {"ci": payload.check_in_date, "co": payload.check_out_date, "tc": payload.room_type_code}
    ).fetchone()

    if not avail or avail.available_count == 0:
        raise HTTPException(status_code=409,
            detail=f"No {rt.name} rooms available for those dates.")

    customer = db.query(Customer).filter(Customer.phone == payload.phone).first()
    if customer:
        customer.first_name = payload.first_name
        customer.last_name = payload.last_name
        if payload.email:
            customer.email = payload.email
    else:
        customer = Customer(phone=payload.phone, first_name=payload.first_name,
                            last_name=payload.last_name, email=payload.email)
        db.add(customer)
        db.flush()

    conf_code = generate_confirmation_code()
    while db.query(Reservation).filter(Reservation.confirmation_code == conf_code).first():
        conf_code = generate_confirmation_code()

    reservation = Reservation(
        confirmation_code=conf_code,
        customer_id=customer.id,
        room_type_id=rt.id,
        check_in_date=ci,
        check_out_date=co,
        num_guests=payload.num_guests,
        total_price=Decimal(str(float(avail.estimated_total))),
        status="confirmed",
        special_requests=payload.special_requests,
    )
    db.add(reservation)
    db.commit()
    db.refresh(reservation)

    return ReservationResponse(
        confirmation_code=reservation.confirmation_code,
        customer_name=f"{customer.first_name} {customer.last_name}",
        room_type=rt.name,
        check_in_date=str(reservation.check_in_date),
        check_out_date=str(reservation.check_out_date),
        num_nights=(co - ci).days,
        num_guests=reservation.num_guests,
        total_price=float(reservation.total_price),
        status=reservation.status,
        special_requests=reservation.special_requests,
        created_at=str(reservation.created_at),
    )


@app.get("/web/reservations/{confirmation_code}", tags=["Web"], include_in_schema=False)
def web_get_reservation(confirmation_code: str, db: Session = Depends(get_db)):
    """Look up a reservation from the hotel website (no API key required)."""
    res = db.query(Reservation).filter(
        Reservation.confirmation_code == confirmation_code.upper()
    ).first()
    if not res:
        raise HTTPException(status_code=404, detail=f"Reservation '{confirmation_code}' not found")

    customer = db.query(Customer).filter(Customer.id == res.customer_id).first()
    rt = db.query(RoomType).filter(RoomType.id == res.room_type_id).first()

    return ReservationResponse(
        confirmation_code=res.confirmation_code,
        customer_name=f"{customer.first_name} {customer.last_name}" if customer else "Unknown",
        room_type=rt.name if rt else "Unknown",
        check_in_date=str(res.check_in_date),
        check_out_date=str(res.check_out_date),
        num_nights=(res.check_out_date - res.check_in_date).days,
        num_guests=res.num_guests,
        total_price=float(res.total_price) if res.total_price else 0.0,
        status=res.status,
        special_requests=res.special_requests,
        created_at=str(res.created_at),
    )


@app.delete("/web/reservations/{confirmation_code}", tags=["Web"], include_in_schema=False)
def web_cancel_reservation(confirmation_code: str, db: Session = Depends(get_db)):
    """Cancel a reservation from the hotel website (no API key required)."""
    res = db.query(Reservation).filter(
        Reservation.confirmation_code == confirmation_code.upper()
    ).first()
    if not res:
        raise HTTPException(status_code=404, detail=f"Reservation '{confirmation_code}' not found")

    if res.status in ("checked_in", "checked_out"):
        raise HTTPException(status_code=400, detail="Cannot cancel a checked-in or checked-out reservation")

    if res.status == "cancelled":
        return {"message": "Already cancelled", "confirmation_code": confirmation_code.upper()}

    res.status = "cancelled"
    res.updated_at = datetime.now()
    db.commit()

    return {"message": "Reservation successfully cancelled", "confirmation_code": confirmation_code.upper()}
