-- ============================================================
-- Hotel Demo Database Schema + Seed Data
-- Choice Hotels Style Demo (Grand Choice Inn & Suites)
-- ============================================================

\c hotel_db;

-- -------------------------------------------------------
-- EXTENSIONS
-- -------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -------------------------------------------------------
-- HOTEL INFO TABLE
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS hotel_info (
    key         VARCHAR(100) PRIMARY KEY,
    value       TEXT NOT NULL,
    updated_at  TIMESTAMP DEFAULT NOW()
);

-- -------------------------------------------------------
-- ROOM TYPES TABLE
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS room_types (
    id              SERIAL PRIMARY KEY,
    type_code       VARCHAR(50) UNIQUE NOT NULL,   -- e.g. 'KING', 'QUEEN_DOUBLE'
    name            VARCHAR(100) NOT NULL,
    description     TEXT,
    max_occupancy   INT NOT NULL DEFAULT 2,
    bed_type        VARCHAR(50),
    price_weekday   NUMERIC(10,2) NOT NULL,
    price_weekend   NUMERIC(10,2) NOT NULL,
    total_rooms     INT NOT NULL DEFAULT 10,
    amenities       TEXT[],                         -- array of amenity strings
    is_active       BOOLEAN DEFAULT TRUE
);

-- -------------------------------------------------------
-- ROOMS TABLE (individual room instances)
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS rooms (
    id              SERIAL PRIMARY KEY,
    room_number     VARCHAR(10) UNIQUE NOT NULL,
    floor           INT NOT NULL,
    room_type_id    INT REFERENCES room_types(id),
    status          VARCHAR(20) DEFAULT 'available', -- available | occupied | maintenance
    notes           TEXT
);

-- -------------------------------------------------------
-- CUSTOMERS TABLE
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
    id              SERIAL PRIMARY KEY,
    phone           VARCHAR(20) UNIQUE,
    first_name      VARCHAR(100),
    last_name       VARCHAR(100),
    email           VARCHAR(200),
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP DEFAULT NOW()
);

-- -------------------------------------------------------
-- RESERVATIONS TABLE
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS reservations (
    id                  SERIAL PRIMARY KEY,
    confirmation_code   VARCHAR(20) UNIQUE NOT NULL,
    customer_id         INT REFERENCES customers(id),
    room_type_id        INT REFERENCES room_types(id),
    room_id             INT REFERENCES rooms(id),   -- assigned at check-in
    check_in_date       DATE NOT NULL,
    check_out_date      DATE NOT NULL,
    num_guests          INT NOT NULL DEFAULT 1,
    num_nights          INT GENERATED ALWAYS AS (check_out_date - check_in_date) STORED,
    total_price         NUMERIC(10,2),
    status              VARCHAR(20) DEFAULT 'confirmed', -- confirmed | checked_in | checked_out | cancelled
    special_requests    TEXT,
    created_at          TIMESTAMP DEFAULT NOW(),
    updated_at          TIMESTAMP DEFAULT NOW()
);

-- -------------------------------------------------------
-- CALL SESSIONS TABLE (for n8n voice agent memory)
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS call_sessions (
    call_sid            VARCHAR(100) PRIMARY KEY,
    caller_phone        VARCHAR(64),
    customer_id         INT REFERENCES customers(id),
    conversation_history JSONB DEFAULT '[]'::jsonb,
    call_status         VARCHAR(20) DEFAULT 'active', -- active | ended
    started_at          TIMESTAMP DEFAULT NOW(),
    ended_at            TIMESTAMP,
    intent              VARCHAR(50)  -- detected intent: reservation | confirmation | availability | info
);

-- -------------------------------------------------------
-- INDEXES
-- -------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_reservations_confirmation ON reservations(confirmation_code);
CREATE INDEX IF NOT EXISTS idx_reservations_customer ON reservations(customer_id);
CREATE INDEX IF NOT EXISTS idx_reservations_dates ON reservations(check_in_date, check_out_date);
CREATE INDEX IF NOT EXISTS idx_reservations_status ON reservations(status);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_call_sessions_phone ON call_sessions(caller_phone);

-- -------------------------------------------------------
-- SEED: HOTEL INFO
-- -------------------------------------------------------
INSERT INTO hotel_info (key, value) VALUES
  ('hotel_name',        'Grand Choice Inn & Suites'),
  ('hotel_address',     '1500 Commerce Blvd, Atlanta, GA 30328'),
  ('hotel_phone',       '+1-404-555-0190'),
  ('hotel_email',       'reservations@grandchoiceinn.com'),
  ('checkin_time',      '3:00 PM'),
  ('checkout_time',     '11:00 AM'),
  ('total_floors',      '3'),
  ('total_rooms',       '42'),
  ('star_rating',       '3'),
  ('parking',           'Free self-parking and covered parking available'),
  ('wifi',              'Complimentary high-speed WiFi throughout the property'),
  ('pool',              'Heated indoor pool open 6 AM - 10 PM'),
  ('fitness_center',    'Fitness center open 24 hours'),
  ('restaurant',        'The Harvest Grille - open daily 6 AM to 10 PM, serving breakfast, lunch, and dinner'),
  ('bar',               'The Lobby Bar open 4 PM to midnight'),
  ('pet_policy',        'Pet-friendly rooms available. $25 per night pet fee. Max 2 pets, 50 lbs each.'),
  ('cancellation',      'Free cancellation up to 24 hours before check-in. Late cancellations charged one night stay.'),
  ('shuttle',           'Complimentary airport shuttle runs every 30 minutes, 5 AM to 11 PM'),
  ('breakfast',         'Complimentary hot breakfast buffet included for Choice Privileges members. Available 6 AM - 10 AM.'),
  ('loyalty_program',   'Choice Privileges - earn points on every stay, redeem for free nights and rewards'),
  ('accessibility',     'ADA-accessible rooms available on request. Roll-in showers and grab bars upon request.'),
  ('smoking_policy',    'This is a 100% smoke-free property. Designated outdoor smoking area near main entrance.'),
  ('early_checkin',     'Early check-in available from 1 PM based on availability, $25 fee'),
  ('late_checkout',     'Late checkout until 1 PM available on request, subject to availability')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- -------------------------------------------------------
-- SEED: ROOM TYPES
-- -------------------------------------------------------
INSERT INTO room_types (type_code, name, description, max_occupancy, bed_type, price_weekday, price_weekend, total_rooms, amenities) VALUES
  ('ECONOMY',
   'Economy Room',
   'Comfortable economy room with all the essentials for a restful stay. Perfect for the budget-conscious traveler.',
   2, 'Queen', 79.00, 89.00, 6,
   ARRAY['Free WiFi', 'Flat-screen TV', 'Coffee maker', 'Mini-fridge', 'Air conditioning', 'Hair dryer']),

  ('STD_QUEEN',
   'Standard Queen',
   'Spacious standard room featuring a plush queen bed, work desk, and modern amenities. Great for couples and solo travelers.',
   2, 'Queen', 99.00, 119.00, 5,
   ARRAY['Free WiFi', '55" Smart TV', 'Coffee maker', 'Mini-fridge', 'Microwave', 'Work desk', 'Air conditioning', 'Hair dryer', 'Iron & ironing board']),

  ('STD_KING',
   'Standard King',
   'Our classic king room with a premium king bed, ideal for business or leisure travelers seeking extra comfort.',
   2, 'King', 109.00, 129.00, 7,
   ARRAY['Free WiFi', '55" Smart TV', 'Coffee maker', 'Mini-fridge', 'Microwave', 'Work desk', 'Air conditioning', 'Hair dryer', 'Iron & ironing board', 'Blackout curtains']),

  ('DBL_QUEEN',
   'Double Queen Room',
   'Ideal for families or groups — two queen beds with ample space and all standard amenities for everyone.',
   4, 'Two Queens', 119.00, 139.00, 7,
   ARRAY['Free WiFi', '55" Smart TV', 'Coffee maker', 'Mini-fridge', 'Microwave', 'Air conditioning', 'Hair dryer', 'Iron & ironing board', 'Sofa seating area']),

  ('DELUXE_KING',
   'Deluxe King Room',
   'Elevated king room with premium furnishings, city view, and deluxe bath amenities. Our most popular choice.',
   2, 'King', 149.00, 179.00, 10,
   ARRAY['Free WiFi', '65" Smart TV', 'Keurig coffee maker', 'Mini-fridge', 'Microwave', 'Work desk', 'Premium bath amenities', 'Bathrobe & slippers', 'Air conditioning', 'Hair dryer', 'City view']),

  ('SUITE_KING',
   'King Suite',
   'Spacious suite with a separate living area, king bed, pull-out sofa, wet bar, and premium amenities throughout.',
   4, 'King + Sofa Bed', 199.00, 239.00, 4,
   ARRAY['Free WiFi', '65" Smart TV + 32" bedroom TV', 'Full kitchen with microwave', 'Wet bar', 'Mini-fridge', 'Separate living area', 'Pull-out sofa', 'Premium bath amenities', 'Bathrobe & slippers', 'City/pool view', 'Complimentary bottled water']),

  ('ACCESSIBLE',
   'Accessible Queen Room',
   'ADA-compliant room with roll-in shower, grab bars, and lowered fixtures designed for full accessibility.',
   2, 'Queen', 99.00, 119.00, 3,
   ARRAY['Free WiFi', '55" Smart TV', 'Coffee maker', 'Mini-fridge', 'Roll-in shower', 'Grab bars', 'Lowered fixtures', 'Visual alarms', 'Air conditioning', 'Hair dryer'])
ON CONFLICT (type_code) DO UPDATE SET
  total_rooms = EXCLUDED.total_rooms,
  description = EXCLUDED.description,
  price_weekday = EXCLUDED.price_weekday,
  price_weekend = EXCLUDED.price_weekend;

-- -------------------------------------------------------
-- SEED: ROOMS — 3 floors, 14 rooms per floor (42 total)
-- Floor 1 (101-114): Accessible + Economy + Standard Queen
-- Floor 2 (201-214): Standard King + Double Queen
-- Floor 3 (301-314): Deluxe King + King Suite
-- -------------------------------------------------------
DO $$
DECLARE rt_id INT;
BEGIN
  -- ---- FLOOR 1 (101-114) ----
  -- 101-103: Accessible Queen (3 rooms)
  SELECT id INTO rt_id FROM room_types WHERE type_code = 'ACCESSIBLE';
  INSERT INTO rooms (room_number, floor, room_type_id, status) VALUES
    ('101', 1, rt_id, 'available'), ('102', 1, rt_id, 'available'), ('103', 1, rt_id, 'available')
  ON CONFLICT (room_number) DO UPDATE SET room_type_id = EXCLUDED.room_type_id;

  -- 104-109: Economy (6 rooms)
  SELECT id INTO rt_id FROM room_types WHERE type_code = 'ECONOMY';
  INSERT INTO rooms (room_number, floor, room_type_id, status) VALUES
    ('104', 1, rt_id, 'available'), ('105', 1, rt_id, 'available'), ('106', 1, rt_id, 'available'),
    ('107', 1, rt_id, 'available'), ('108', 1, rt_id, 'available'), ('109', 1, rt_id, 'available')
  ON CONFLICT (room_number) DO UPDATE SET room_type_id = EXCLUDED.room_type_id;

  -- 110-114: Standard Queen (5 rooms)
  SELECT id INTO rt_id FROM room_types WHERE type_code = 'STD_QUEEN';
  INSERT INTO rooms (room_number, floor, room_type_id, status) VALUES
    ('110', 1, rt_id, 'available'), ('111', 1, rt_id, 'available'), ('112', 1, rt_id, 'available'),
    ('113', 1, rt_id, 'available'), ('114', 1, rt_id, 'available')
  ON CONFLICT (room_number) DO UPDATE SET room_type_id = EXCLUDED.room_type_id;

  -- ---- FLOOR 2 (201-214) ----
  -- 201-207: Standard King (7 rooms)
  SELECT id INTO rt_id FROM room_types WHERE type_code = 'STD_KING';
  INSERT INTO rooms (room_number, floor, room_type_id, status) VALUES
    ('201', 2, rt_id, 'available'), ('202', 2, rt_id, 'available'), ('203', 2, rt_id, 'available'),
    ('204', 2, rt_id, 'available'), ('205', 2, rt_id, 'available'), ('206', 2, rt_id, 'available'),
    ('207', 2, rt_id, 'available')
  ON CONFLICT (room_number) DO UPDATE SET room_type_id = EXCLUDED.room_type_id;

  -- 208-214: Double Queen (7 rooms)
  SELECT id INTO rt_id FROM room_types WHERE type_code = 'DBL_QUEEN';
  INSERT INTO rooms (room_number, floor, room_type_id, status) VALUES
    ('208', 2, rt_id, 'available'), ('209', 2, rt_id, 'available'), ('210', 2, rt_id, 'available'),
    ('211', 2, rt_id, 'available'), ('212', 2, rt_id, 'available'), ('213', 2, rt_id, 'available'),
    ('214', 2, rt_id, 'available')
  ON CONFLICT (room_number) DO UPDATE SET room_type_id = EXCLUDED.room_type_id;

  -- ---- FLOOR 3 (301-314) ----
  -- 301-310: Deluxe King (10 rooms)
  SELECT id INTO rt_id FROM room_types WHERE type_code = 'DELUXE_KING';
  INSERT INTO rooms (room_number, floor, room_type_id, status) VALUES
    ('301', 3, rt_id, 'available'), ('302', 3, rt_id, 'available'), ('303', 3, rt_id, 'available'),
    ('304', 3, rt_id, 'available'), ('305', 3, rt_id, 'available'), ('306', 3, rt_id, 'available'),
    ('307', 3, rt_id, 'available'), ('308', 3, rt_id, 'available'), ('309', 3, rt_id, 'available'),
    ('310', 3, rt_id, 'available')
  ON CONFLICT (room_number) DO UPDATE SET room_type_id = EXCLUDED.room_type_id;

  -- 311-314: King Suite (4 rooms)
  SELECT id INTO rt_id FROM room_types WHERE type_code = 'SUITE_KING';
  INSERT INTO rooms (room_number, floor, room_type_id, status) VALUES
    ('311', 3, rt_id, 'available'), ('312', 3, rt_id, 'available'),
    ('313', 3, rt_id, 'available'), ('314', 3, rt_id, 'available')
  ON CONFLICT (room_number) DO UPDATE SET room_type_id = EXCLUDED.room_type_id;
END $$;

-- -------------------------------------------------------
-- SEED: SAMPLE EXISTING RESERVATIONS (for demo)
-- -------------------------------------------------------
INSERT INTO customers (phone, first_name, last_name, email) VALUES
  ('+14045550001', 'Sarah', 'Johnson', 'sarah.j@email.com'),
  ('+14045550002', 'Michael', 'Chen', 'mchen@email.com'),
  ('+14045550003', 'Emily', 'Rodriguez', 'erodriguez@email.com')
ON CONFLICT (phone) DO NOTHING;

INSERT INTO reservations (confirmation_code, customer_id, room_type_id, check_in_date, check_out_date, num_guests, total_price, status, special_requests)
SELECT
  'GCI-2024-001',
  c.id,
  rt.id,
  CURRENT_DATE + 5,
  CURRENT_DATE + 8,
  2,
  447.00,
  'confirmed',
  'High floor preferred'
FROM customers c, room_types rt
WHERE c.phone = '+14045550001' AND rt.type_code = 'STD_KING'
ON CONFLICT (confirmation_code) DO NOTHING;

INSERT INTO reservations (confirmation_code, customer_id, room_type_id, check_in_date, check_out_date, num_guests, total_price, status)
SELECT
  'GCI-2024-002',
  c.id,
  rt.id,
  CURRENT_DATE + 2,
  CURRENT_DATE + 4,
  1,
  218.00,
  'confirmed'
FROM customers c, room_types rt
WHERE c.phone = '+14045550002' AND rt.type_code = 'DELUXE_KING'
ON CONFLICT (confirmation_code) DO NOTHING;

-- -------------------------------------------------------
-- VIEWS
-- -------------------------------------------------------
CREATE OR REPLACE VIEW available_rooms_summary AS
SELECT
  rt.type_code,
  rt.name,
  rt.max_occupancy,
  rt.bed_type,
  rt.price_weekday,
  rt.price_weekend,
  COUNT(r.id) AS total_rooms,
  SUM(CASE WHEN r.status = 'available' THEN 1 ELSE 0 END) AS available_rooms
FROM room_types rt
LEFT JOIN rooms r ON r.room_type_id = rt.id
WHERE rt.is_active = TRUE
GROUP BY rt.id, rt.type_code, rt.name, rt.max_occupancy, rt.bed_type, rt.price_weekday, rt.price_weekend;

-- -------------------------------------------------------
-- FUNCTION: Check availability for date range
-- -------------------------------------------------------
CREATE OR REPLACE FUNCTION check_room_availability(
  p_check_in   DATE,
  p_check_out  DATE,
  p_type_code  VARCHAR DEFAULT NULL
)
RETURNS TABLE (
  type_code       VARCHAR,
  room_name       VARCHAR,
  bed_type        VARCHAR,
  max_occupancy   INT,
  price_weekday   NUMERIC,
  price_weekend   NUMERIC,
  available_count BIGINT,
  estimated_total NUMERIC
) AS $$
DECLARE
  num_weekdays    INT;
  num_weekends    INT;
BEGIN
  SELECT
    COUNT(*) FILTER (WHERE EXTRACT(DOW FROM dd) NOT IN (0,6)),
    COUNT(*) FILTER (WHERE EXTRACT(DOW FROM dd) IN (0,6))
  INTO num_weekdays, num_weekends
  FROM generate_series(p_check_in, p_check_out - 1, '1 day'::interval) dd;

  RETURN QUERY
  SELECT
    rt.type_code,
    rt.name::VARCHAR,
    rt.bed_type,
    rt.max_occupancy,
    rt.price_weekday,
    rt.price_weekend,
    -- Total rooms of this type minus confirmed/checked-in reservations overlapping the date range
    (
      SELECT COUNT(*) FROM rooms r WHERE r.room_type_id = rt.id
    ) - (
      SELECT COUNT(*) FROM reservations res
      WHERE res.room_type_id = rt.id
        AND res.status IN ('confirmed', 'checked_in')
        AND res.check_in_date < p_check_out
        AND res.check_out_date > p_check_in
    ) AS available_count,
    ROUND(
      (rt.price_weekday * num_weekdays + rt.price_weekend * num_weekends)::NUMERIC, 2
    ) AS estimated_total
  FROM room_types rt
  WHERE rt.is_active = TRUE
    AND (p_type_code IS NULL OR rt.type_code = p_type_code)
    AND (
      SELECT COUNT(*) FROM rooms r WHERE r.room_type_id = rt.id
    ) - (
      SELECT COUNT(*) FROM reservations res
      WHERE res.room_type_id = rt.id
        AND res.status IN ('confirmed', 'checked_in')
        AND res.check_in_date < p_check_out
        AND res.check_out_date > p_check_in
    ) > 0
  ORDER BY rt.price_weekday;
END;
$$ LANGUAGE plpgsql;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO hotel_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO hotel_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO hotel_user;
