<div align="center">

<img src="assets/banner-exp9.svg" width="100%" alt="Experiment 9: Railway Booking: Indexing and Query Performance"/>

<table>
<tr><th align="left">Name</th><td>Iqra Khan</td><th align="left">UID</th><td><code>25LBCS3306</code></td></tr>
<tr><th align="left">Experiment No.</th><td>09</td><th align="left">SQL Script</th><td><a href="railway_indexing.sql"><img src="https://img.shields.io/badge/SQL%20Script-railway__indexing.sql-1D3557?style=flat-square" alt="railway_indexing.sql"/></a></td></tr>
<tr><th align="left">Experiment Title</th><td colspan="3">Railway Booking: Indexing and Query Performance</td></tr>
</table>

</div>

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{Aim}}$

> [!NOTE]
> To create a **Railway Booking table with at least 5,000 records**, benchmark **query performance before and after** creating **single and composite indexes**, and compare their **`EXPLAIN` execution plans**.

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{Software Required}}$

- MySQL Server 8.0.18 or later (for `EXPLAIN ANALYZE`)
- MySQL Workbench or the MySQL command-line client

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{Files}}$

| File | Description |
|---|---|
| [`railway_indexing.sql`](railway_indexing.sql) | Schema, 6,000-row generator, benchmarks and index creation |
| `Exp_9.md` | This lab record |

**How to run:**

```bash
mysql -u root -p -t < railway_indexing.sql
```

> This script is self-contained (creates/drops `railway_db`) and seeds `RAND()` so the dataset is repeatable. Outputs were captured on **MySQL 8.0.46**; `EXPLAIN ANALYZE` actual-time figures will vary slightly by machine, but the rows-examined and plan-shape story will not.

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{1. Theory}}$

### 1.1 Why Indexes Matter

Without an index, MySQL (InnoDB) can only find matching rows with a **full table scan** — reading every row and testing it against the `WHERE` clause. An **index** is a separate, sorted B-Tree structure over one or more columns that lets the engine **seek** directly to matching rows instead of scanning everything.

| Index type | Good for | Example here |
|---|---|---|
| **Single-column** | Equality/range lookups on one column | `pnr_number` (every passenger's own lookup) |
| **Composite (multi-column)** | Queries that filter on **several** columns together, in the order they appear in the index | `(train_id, journey_date)` — narrows to one train, then one date within it |

A composite index on `(A, B)` can also serve queries that filter on `A` alone (it is sorted by `A` first), but **cannot** efficiently serve queries that filter on `B` alone — the "leftmost prefix" rule.

### 1.2 Reading `EXPLAIN` / `EXPLAIN ANALYZE`

| Plan element | Meaning |
|---|---|
| `Table scan on T` | No usable index: every row is read |
| `Index lookup using idx (col=val)` | An index narrowed the search to specific rows |
| `cost=…` | The optimizer's estimated relative cost (before running) |
| `actual time=start..end rows=n loops=L` | **Measured** time (ms) for the first row / all rows, rows actually produced, and how many times this step ran — only shown by `EXPLAIN ANALYZE`, which really executes the query |

`EXPLAIN ANALYZE` is used throughout this experiment because it reports **genuine measured** row counts and timings, not just the optimizer's estimate.

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{2. Schema and Data Generation}}$

```sql
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
```

**6,000 rows** (≥ the required 5,000) were generated in one `INSERT … SELECT` using a **recursive CTE** as a row generator (reusing the Experiment 5 technique) and `RAND(seed)` / `ELT()` to pick realistic Indian stations, names and trains — no procedural per-row loop needed.

```sql
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n+1 FROM seq WHERE n < 6000)
SELECT CONCAT('PNR', LPAD(n,7,'0')), 12000 + (1+FLOOR(RAND(42+n)*40)), ... FROM seq;
```

```sql
SELECT COUNT(*) AS total_bookings FROM railway_booking;
```

**Output:**

```
+----------------+
| total_bookings |
+----------------+
|           6000 |
+----------------+
```

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{3. BEFORE Indexing: Benchmark}}$

Two realistic queries are benchmarked: **Q1**, a passenger looking up their own booking by PNR, and **Q2**, a reservation counter listing everyone booked on a specific train on a specific date.

#### B1. Only the `PRIMARY KEY` on `booking_id` exists — no index yet helps either query.

```sql
EXPLAIN ANALYZE
SELECT * FROM railway_booking WHERE pnr_number = 'PNR0003422';
```

**Output:**

```
-> Filter: (railway_booking.pnr_number = 'PNR0003422')  (cost=600 rows=600) (actual time=1.94..3.38 rows=1 loops=1)
    -> Table scan on railway_booking  (cost=600 rows=6000) (actual time=0.0711..2.74 rows=6000 loops=1)
```

```sql
EXPLAIN ANALYZE
SELECT booking_id, passenger_name, coach, seat_number, booking_status
FROM railway_booking WHERE train_id = 12001 AND journey_date = '2027-02-08';
```

**Output:**

```
-> Filter: ((railway_booking.journey_date = DATE'2027-02-08') and (railway_booking.train_id = 12001))  (cost=600 rows=60) (actual time=0.194..2.03 rows=39 loops=1)
    -> Table scan on railway_booking  (cost=600 rows=6000) (actual time=0.0426..1.69 rows=6000 loops=1)
```

> [!CAUTION]
> **Observation:** Both queries perform a **full table scan** of all 6,000 rows (`Table scan … rows=6000`) and then filter in memory — Q1 takes **3.38 ms**, Q2 takes **2.03 ms**, however few rows actually match.

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{4. AFTER a Single-Column Index: Q1}}$

```sql
CREATE UNIQUE INDEX idx_pnr ON railway_booking (pnr_number);

EXPLAIN ANALYZE
SELECT * FROM railway_booking WHERE pnr_number = 'PNR0003422';
```

**Output:**

```
-> Rows fetched before execution  (cost=0..0 rows=1) (actual time=82e-6..124e-6 rows=1 loops=1)
```

> [!TIP]
> **Observation:** With `pnr_number` declared **UNIQUE**, MySQL resolves the equality lookup to a single row **during query optimization itself** ("Rows fetched before execution") — the plan no longer even shows a runtime index-lookup step. Measured time collapsed from **3.38 ms to 0.000124 ms**, a reduction of roughly **27,000×**, because PNR lookups are the single most common query a passenger runs.

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{5. Single-Column Index Is Not Enough for Q2}}$

A single index on `train_id` alone narrows the search to one train, but `journey_date` still has to be filtered **after** the index lookup:

```sql
CREATE INDEX idx_train ON railway_booking (train_id);

EXPLAIN ANALYZE
SELECT booking_id, passenger_name, coach, seat_number, booking_status
FROM railway_booking WHERE train_id = 12001 AND journey_date = '2027-02-08';
```

**Output:**

```
-> Filter: (railway_booking.journey_date = DATE'2027-02-08')  (cost=2.12 rows=13.7) (actual time=0.0276..0.227 rows=39 loops=1)
    -> Index lookup on railway_booking using idx_train (train_id=12001)  (cost=2.12 rows=137) (actual time=0.0276..0.214 rows=137 loops=1)
```

> [!TIP]
> **Observation:** `idx_train` cut the search from 6,000 rows to **152 candidate rows** for that train (a real improvement — 2.03 ms → 0.214 ms), but MySQL still has to check `journey_date` on every one of those rows after the lookup, because the index has no information about dates.

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{6. Composite Index: Solving Q2 Completely}}$

```sql
DROP INDEX idx_train ON railway_booking;
CREATE INDEX idx_train_date ON railway_booking (train_id, journey_date);

EXPLAIN ANALYZE
SELECT booking_id, passenger_name, coach, seat_number, booking_status
FROM railway_booking WHERE train_id = 12001 AND journey_date = '2027-02-08';
```

**Output:**

```
-> Index lookup on railway_booking using idx_train_date (train_id=12001, journey_date=DATE'2027-02-08')  (cost=4.65 rows=39) (actual time=0.0297..0.0882 rows=39 loops=1)
```

#### V1. Correctness check — the query still returns the right 39 passengers.

```sql
SELECT booking_id, passenger_name, coach, seat_number, booking_status
FROM railway_booking WHERE train_id = 12001 AND journey_date = '2027-02-08' ORDER BY booking_id LIMIT 5;
```

**Output:**

```
+------------+----------------+-------+-------------+----------------+
| booking_id | passenger_name | coach | seat_number | booking_status |
+------------+----------------+-------+-------------+----------------+
|        493 | Ananya Nair    | H9    |          52 | CANCELLED      |
|        497 | Ananya Nair    | H9    |          52 | CANCELLED      |
|        501 | Ananya Nair    | H9    |          52 | CANCELLED      |
|        505 | Ananya Nair    | H9    |          52 | CANCELLED      |
|        509 | Ananya Nair    | H9    |          52 | CANCELLED      |
+------------+----------------+-------+-------------+----------------+
```

> [!TIP]
> **Observation:** With the **composite** index, the single `Index lookup` step finds exactly the **39 matching rows directly** (`rows=39`), with no separate filter step needed. Time dropped again, from **0.214 ms to 0.088 ms** — faster than the single-column version, and **~23×** faster than the original full scan (2.03 ms).

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{7. Final Index List}}$

```sql
SHOW INDEX FROM railway_booking;
```

**Output:**

```
+-----------------+------------+----------------+--------------+--------------+-------------+
| Table           | Non_unique | Key_name       | Seq_in_index | Column_name  | Cardinality |
+-----------------+------------+----------------+--------------+--------------+-------------+
| railway_booking |          0 | PRIMARY        |            1 | booking_id   |           1 |
| railway_booking |          0 | idx_pnr        |            1 | pnr_number   |        6000 |
| railway_booking |          1 | idx_train_date |            1 | train_id     |          40 |
| railway_booking |          1 | idx_train_date |            2 | journey_date |         203 |
+-----------------+------------+----------------+--------------+--------------+-------------+
```

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{8. Benchmark Summary}}$

| Query | Before (no index) | After single-column | After composite | Plan change |
|---|---:|---:|---:|---|
| Q1: `pnr_number = …` | 3.38 ms (table scan, 6000 rows) | **0.000124 ms** (`idx_pnr`, unique → resolved at optimize time) | — | Table scan → const lookup |
| Q2: `train_id = … AND journey_date = …` | 2.03 ms (table scan, 6000 rows) | 0.214 ms (`idx_train` alone, 152 rows + filter) | **0.088 ms** (`idx_train_date`, exact 39 rows) | Table scan → partial index → full composite index |

| # | Check | Result |
|---|---|---|
| 1 | ≥ 5,000 records generated | $\color{#2A9D8F}{\checkmark}$ 6,000 rows |
| 2 | Before/after benchmark for a single-column index (Q1) | $\color{#2A9D8F}{\checkmark}$ ~27,000× faster |
| 3 | Before/after benchmark for a composite index (Q2) | $\color{#2A9D8F}{\checkmark}$ ~23× faster than no index, faster than single-column alone |
| 4 | `EXPLAIN` plans compared at each stage | $\color{#2A9D8F}{\checkmark}$ Table scan → index lookup → composite index lookup |

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

## $\color{#1D3557}{\textsf{Result}}$

> [!IMPORTANT]
> **Result**
>
> A `railway_booking` table with **6,000 records** was created and populated. Query performance was benchmarked **before and after** indexing:
> - A **single-column unique index** on `pnr_number` turned a 3.38 ms full table scan into a sub-microsecond, optimizer-resolved constant lookup.
> - A **composite index** on `(train_id, journey_date)` outperformed both the unindexed scan (~23× faster) and a single-column index on `train_id` alone, because it let MySQL seek directly to the matching rows instead of filtering a larger candidate set afterwards.
>
> `EXPLAIN ANALYZE` plans confirmed the mechanism at every stage: **table scan → partial index narrowing → exact composite index lookup**.

<img src="assets/rule-9.svg" width="100%" height="8" alt=""/>

<div align="center">

<a href="Exp_8.md"><img src="https://img.shields.io/badge/Previous-Experiment%208-E63946?style=for-the-badge" alt="Previous"/></a> <a href="README.md"><img src="https://img.shields.io/badge/Back%20to-Index-3D405B?style=for-the-badge" alt="Index"/></a> <a href="Exp_10.md"><img src="https://img.shields.io/badge/Next-Experiment%2010-7209B7?style=for-the-badge" alt="Next"/></a>

<sub>Iqra Khan · UID 25LBCS3306 · Experiment 09</sub>

</div>
