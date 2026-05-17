from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from sqlalchemy import Column, Integer, String, Numeric, Boolean, Date, DateTime, Text, ARRAY, ForeignKey, func
from sqlalchemy.dialects.postgresql import JSONB
import os

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://hotel_user:hotel_pass@localhost:5432/hotel_db")

engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_size=10, max_overflow=20)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


class HotelInfo(Base):
    __tablename__ = "hotel_info"
    key = Column(String(100), primary_key=True)
    value = Column(Text, nullable=False)
    updated_at = Column(DateTime, server_default=func.now())


class RoomType(Base):
    __tablename__ = "room_types"
    id = Column(Integer, primary_key=True, autoincrement=True)
    type_code = Column(String(50), unique=True, nullable=False)
    name = Column(String(100), nullable=False)
    description = Column(Text)
    max_occupancy = Column(Integer, nullable=False, default=2)
    bed_type = Column(String(50))
    price_weekday = Column(Numeric(10, 2), nullable=False)
    price_weekend = Column(Numeric(10, 2), nullable=False)
    total_rooms = Column(Integer, nullable=False, default=10)
    amenities = Column(ARRAY(Text))
    is_active = Column(Boolean, default=True)


class Room(Base):
    __tablename__ = "rooms"
    id = Column(Integer, primary_key=True, autoincrement=True)
    room_number = Column(String(10), unique=True, nullable=False)
    floor = Column(Integer, nullable=False)
    room_type_id = Column(Integer, ForeignKey("room_types.id"))
    status = Column(String(20), default="available")
    notes = Column(Text)


class Customer(Base):
    __tablename__ = "customers"
    id = Column(Integer, primary_key=True, autoincrement=True)
    phone = Column(String(20), unique=True)
    first_name = Column(String(100))
    last_name = Column(String(100))
    email = Column(String(200))
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class Reservation(Base):
    __tablename__ = "reservations"
    id = Column(Integer, primary_key=True, autoincrement=True)
    confirmation_code = Column(String(20), unique=True, nullable=False)
    customer_id = Column(Integer, ForeignKey("customers.id"))
    room_type_id = Column(Integer, ForeignKey("room_types.id"))
    room_id = Column(Integer, ForeignKey("rooms.id"), nullable=True)
    check_in_date = Column(Date, nullable=False)
    check_out_date = Column(Date, nullable=False)
    num_guests = Column(Integer, nullable=False, default=1)
    total_price = Column(Numeric(10, 2))
    status = Column(String(20), default="confirmed")
    special_requests = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class CallSession(Base):
    __tablename__ = "call_sessions"
    call_sid = Column(String(100), primary_key=True)
    caller_phone = Column(String(64))
    customer_id = Column(Integer, ForeignKey("customers.id"), nullable=True)
    conversation_history = Column(JSONB, default=list)
    call_status = Column(String(20), default="active")
    started_at = Column(DateTime, server_default=func.now())
    ended_at = Column(DateTime, nullable=True)
    intent = Column(String(50), nullable=True)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
