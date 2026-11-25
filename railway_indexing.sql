-- ============================================================================
-- Experiment 9: Railway Booking table with >= 5,000 records. Benchmark query
--               performance before and after single and composite indexes,
--               and compare EXPLAIN / EXPLAIN ANALYZE execution plans.
-- Database   : railway_db
-- Note       : Row counts/content are seeded with RAND(42) for repeatability;
--              actual timings will vary slightly machine to machine, but the
--              rows-examined and index-usage story is what matters here.
-- ============================================================================

DROP DATABASE IF EXISTS railway_db;
CREATE DATABASE railway_db;
USE railway_db;

SET @@cte_max_recursion_depth = 10000;

-- Reference list of trains, so a (train_id, journey_date) query is realistic.
CREATE TABLE train (
    train_id   INT PRIMARY KEY,
    train_name VARCHAR(60) NOT NULL
);
INSERT INTO train
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 40
)
SELECT 12000 + n,
       ELT(1 + ((n - 1) MOD 10),
           'Rajdhani Express','Shatabdi Express','Duronto Express','Garib Rath Express',
           'Jan Shatabdi Express','Humsafar Express','Tejas Express','Vande Bharat Express',
           'Sampark Kranti Express','Intercity Express')
FROM seq;

-- ----------------------------------------------------------------------------
-- 1. railway_booking: no secondary indexes yet (only the PRIMARY KEY).
-- ----------------------------------------------------------------------------
CREATE TABLE railway_booking (
    booking_id       INT AUTO_INCREMENT PRIMARY KEY,
    pnr_number       CHAR(10)     NOT NULL,
    train_id         INT          NOT NULL,
    source_station   VARCHAR(40)  NOT NULL,
    dest_station     VARCHAR(40)  NOT NULL,
    journey_date     DATE         NOT NULL,
    passenger_name   VARCHAR(60)  NOT NULL,
    passenger_age    TINYINT      NOT NULL,
    passenger_gender ENUM('M','F') NOT NULL,
    class            ENUM('SL','3A','2A','1A','CC') NOT NULL,
    quota            ENUM('GENERAL','TATKAL','LADIES','SENIOR') NOT NULL,
    coach            VARCHAR(6)   NOT NULL,
    seat_number      TINYINT      NOT NULL,
    fare             DECIMAL(8,2) NOT NULL,
    booking_status   ENUM('CONFIRMED','RAC','WAITLIST','CANCELLED') NOT NULL,
    booking_date     DATE         NOT NULL
);

-- 6,000 rows generated from a recursive sequence; stations/names chosen with ELT().
INSERT INTO railway_booking
    (pnr_number, train_id, source_station, dest_station, journey_date, passenger_name,
     passenger_age, passenger_gender, class, quota, coach, seat_number, fare, booking_status, booking_date)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 6000
)
SELECT
    CONCAT('PNR', LPAD(n, 7, '0')),
    12000 + (1 + FLOOR(RAND(42 + n) * 40)),
    ELT(1 + FLOOR(RAND(100 + n) * 15),
        'New Delhi','Mumbai Central','Chennai Central','Howrah Jn','Bengaluru City',
        'Pune Jn','Ahmedabad Jn','Jaipur Jn','Lucknow NR','Patna Jn',
        'Bhopal Jn','Nagpur Jn','Kochi Jn','Guwahati','Chandigarh'),
    ELT(1 + FLOOR(RAND(200 + n) * 15),
        'New Delhi','Mumbai Central','Chennai Central','Howrah Jn','Bengaluru City',
        'Pune Jn','Ahmedabad Jn','Jaipur Jn','Lucknow NR','Patna Jn',
        'Bhopal Jn','Nagpur Jn','Kochi Jn','Guwahati','Chandigarh'),
    DATE_ADD('2026-11-01', INTERVAL FLOOR(RAND(300 + n) * 180) DAY),
    CONCAT(
        ELT(1 + FLOOR(RAND(400 + n) * 12),
            'Aarav','Vivaan','Aditya','Ishaan','Rohan','Kabir','Ananya','Diya','Isha','Meera','Saanvi','Kiara'),
        ' ',
        ELT(1 + FLOOR(RAND(500 + n) * 10),
            'Sharma','Verma','Gupta','Iyer','Reddy','Nair','Singh','Patel','Rao','Mehta')
    ),
    18 + FLOOR(RAND(600 + n) * 55),
    ELT(1 + FLOOR(RAND(700 + n) * 2), 'M','F'),
    ELT(1 + FLOOR(RAND(800 + n) * 5), 'SL','3A','2A','1A','CC'),
    ELT(1 + FLOOR(RAND(900 + n) * 4), 'GENERAL','TATKAL','LADIES','SENIOR'),
    CONCAT(ELT(1 + FLOOR(RAND(1000 + n) * 5), 'S','A','B','H','C'), 1 + FLOOR(RAND(1100 + n) * 12)),
    1 + FLOOR(RAND(1200 + n) * 72),
    300 + FLOOR(RAND(1300 + n) * 2500),
    ELT(1 + FLOOR(RAND(1400 + n) * 4), 'CONFIRMED','RAC','WAITLIST','CANCELLED'),
    DATE_SUB(DATE_ADD('2026-11-01', INTERVAL FLOOR(RAND(300 + n) * 180) DAY), INTERVAL (1 + FLOOR(RAND(1500 + n) * 30)) DAY)
FROM seq;

SELECT COUNT(*) AS total_bookings FROM railway_booking;

-- ----------------------------------------------------------------------------
-- 2. BEFORE indexing: benchmark two realistic lookups.
--    Q1: point lookup by PNR (how a passenger checks their own booking).
--    Q2: trains running on a specific date (how the reservation counter looks
--        up availability for a train on a given day).
-- ----------------------------------------------------------------------------
SELECT pnr_number FROM railway_booking LIMIT 1 OFFSET 3421;   -- pick a real PNR to query
SELECT train_id, journey_date, COUNT(*) FROM railway_booking GROUP BY train_id, journey_date ORDER BY COUNT(*) DESC LIMIT 1;

-- Q1 BEFORE (no index on pnr_number)
EXPLAIN ANALYZE
SELECT * FROM railway_booking WHERE pnr_number = 'PNR0003422';

-- Q2 BEFORE (no index on train_id / journey_date)
EXPLAIN ANALYZE
SELECT booking_id, passenger_name, coach, seat_number, booking_status
FROM railway_booking
WHERE train_id = 12001 AND journey_date = '2027-02-08';

SHOW SESSION STATUS LIKE 'Handler_read%';

-- ----------------------------------------------------------------------------
-- 3. Create a SINGLE-COLUMN index on pnr_number, and re-run Q1.
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX idx_pnr ON railway_booking (pnr_number);

EXPLAIN ANALYZE
SELECT * FROM railway_booking WHERE pnr_number = 'PNR0003422';

-- ----------------------------------------------------------------------------
-- 4. Create a SINGLE-COLUMN index on train_id only, and re-run Q2: the
--    optimizer can narrow down by train_id but must still scan+filter every
--    matching train_id row for the date, which is NOT enough for a date-level
--    lookup used every day at the counter.
-- ----------------------------------------------------------------------------
CREATE INDEX idx_train ON railway_booking (train_id);

EXPLAIN ANALYZE
SELECT booking_id, passenger_name, coach, seat_number, booking_status
FROM railway_booking
WHERE train_id = 12001 AND journey_date = '2027-02-08';

-- ----------------------------------------------------------------------------
-- 5. Replace it with a COMPOSITE index on (train_id, journey_date): the
--    leading column narrows to one train, the second column narrows straight
--    to the date within it.
-- ----------------------------------------------------------------------------
DROP INDEX idx_train ON railway_booking;
CREATE INDEX idx_train_date ON railway_booking (train_id, journey_date);

EXPLAIN ANALYZE
SELECT booking_id, passenger_name, coach, seat_number, booking_status
FROM railway_booking
WHERE train_id = 12001 AND journey_date = '2027-02-08';

SHOW SESSION STATUS LIKE 'Handler_read%';

-- ----------------------------------------------------------------------------
-- 6. Final index list on railway_booking.
-- ----------------------------------------------------------------------------
SHOW INDEX FROM railway_booking;
