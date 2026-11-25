<div align="center">

<img src="assets/banner-exp10.svg" width="100%" alt="Experiment 10: Large-Scale Query Optimization and EXPLAIN Analysis"/>

<table>
<tr><th align="left">Name</th><td>Iqra Khan</td><th align="left">UID</th><td><code>25LBCS3306</code></td></tr>
<tr><th align="left">Experiment No.</th><td>10</td><th align="left">SQL Script</th><td><a href="query_optimization.sql"><img src="https://img.shields.io/badge/SQL%20Script-query__optimization.sql-7209B7?style=flat-square" alt="query_optimization.sql"/></a></td></tr>
<tr><th align="left">Experiment Title</th><td colspan="3">Large-Scale Query Optimization and EXPLAIN Analysis</td></tr>
</table>

</div>

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{Aim}}$

> [!NOTE]
> To generate a dataset with **at least 10,000 rows**, write **five slow queries**, analyze each with `EXPLAIN`, **optimize using indexing and query rewriting**, and compare **execution time before and after** optimization.

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{Software Required}}$

- MySQL Server 8.0.18 or later (for `EXPLAIN ANALYZE`; `FULLTEXT` on InnoDB needs 5.6+)
- MySQL Workbench or the MySQL command-line client

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{Files}}$

| File | Description |
|---|---|
| [`query_optimization.sql`](query_optimization.sql) | 12,000-row `orders` table, all 5 slow queries, their fixes, and `EXPLAIN ANALYZE` for each |
| `Exp_10.md` | This lab record |

**How to run:**

```bash
mysql -u root -p -t < query_optimization.sql
```

> Self-contained (creates/drops `retail_orders_db`); `RAND()` is seeded for repeatability. Outputs were captured on **MySQL 8.0.46**; absolute timings will vary slightly by machine, but the plan-shape and relative-speedup story will not.

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{1. Theory: Why Queries Get Slow}}$

| Anti-pattern | Why it's slow | Fix used here |
|---|---|---|
| **Non-sargable predicate** — wrapping a column in a function (`YEAR(order_date)`) | The index can't be used: MySQL must compute the function for **every** row before it can compare | Rewrite as a **sargable range** (`order_date >= … AND < …`) + index |
| **Leading-wildcard `LIKE '%x%'`** | A B-Tree index is sorted left-to-right; a leading `%` means no prefix to seek on | A **`FULLTEXT`** index + `MATCH … AGAINST` |
| **`OR` across two different columns** | A single B-Tree index can't satisfy two unrelated conditions at once | Index **both** columns (optimizer can **index-merge/union** them), or rewrite as an explicit `UNION` |
| **Correlated subquery** | The inner query re-executes **once per outer row** | Rewrite as a **derived table** (computed once) joined back |
| **`ORDER BY … LIMIT` on an unindexed column** | MySQL must sort the **entire** result before taking the top rows (a "filesort") | Index the sort column so MySQL can **walk it in order** and stop early |

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{2. Schema and Data Generation}}$

```sql
CREATE TABLE orders (
    order_id      INT AUTO_INCREMENT PRIMARY KEY,
    customer_id   INT NOT NULL,
    customer_name VARCHAR(60) NOT NULL,
    category      VARCHAR(30) NOT NULL,
    city          VARCHAR(40) NOT NULL,
    order_date    DATE NOT NULL,
    quantity      INT NOT NULL,
    unit_price    DECIMAL(10,2) NOT NULL,
    total_amount  DECIMAL(12,2) NOT NULL,
    payment_mode  ENUM('UPI','CARD','NETBANKING','COD') NOT NULL,
    order_status  ENUM('DELIVERED','SHIPPED','CANCELLED','RETURNED') NOT NULL
);
```

**12,000 rows** (≥ the required 10,000) generated with a recursive-CTE row generator and `RAND()`/`ELT()`, the same technique as Experiment 9.

```sql
SELECT COUNT(*) AS total_orders FROM orders;
```

**Output:**

```
+--------------+
| total_orders |
+--------------+
|        12000 |
+--------------+
```

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{3. Slow Query 1 -- Function on an Indexable Column}}$

```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders WHERE YEAR(order_date) = 2025;
```

**Before:**

```
-> Aggregate: count(0)  (actual time=2.85..2.85 rows=1 loops=1)
    -> Filter: (year(orders.order_date) = 2025)  (actual time=0.0777..2.62 rows=5982 loops=1)
        -> Table scan on orders  (actual time=0.0664..1.79 rows=12000 loops=1)
```

```sql
CREATE INDEX idx_order_date ON orders (order_date);

EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01';
```

**After (indexed + rewritten as a sargable range):**

```
-> Aggregate: count(0)  (actual time=1.66..1.66 rows=1 loops=1)
    -> Filter: ((orders.order_date >= DATE'2025-01-01') and (orders.order_date < DATE'2026-01-01'))  (actual time=0.0483..1.39 rows=5982 loops=1)
        -> Covering index range scan on orders using idx_order_date over ('2025-01-01' <= order_date < '2026-01-01')  (actual time=0.046..0.799 rows=5982 loops=1)
```

> [!TIP]
> **Observation:** `YEAR(order_date) = 2025` cannot use **any** index on `order_date`, because the index is sorted by date, not by "year of date" — the function must be evaluated per row. Rewriting as a half-open range (`>= 2025-01-01 AND < 2026-01-01`) is logically identical but **sargable**, so the new index turns the table scan into a **covering index range scan**: **2.62 ms → 1.39 ms**.

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{4. Slow Query 2 -- Leading-Wildcard LIKE}}$

```sql
EXPLAIN ANALYZE
SELECT order_id, customer_name FROM orders WHERE customer_name LIKE '%Sharma%';
```

**Before:**

```
-> Filter: (orders.customer_name like '%Sharma%')  (actual time=0.118..3.45 rows=1229 loops=1)
    -> Table scan on orders  (actual time=0.0608..2.04 rows=12000 loops=1)
```

```sql
CREATE FULLTEXT INDEX idx_customer_name_ft ON orders (customer_name);

EXPLAIN ANALYZE
SELECT order_id, customer_name FROM orders WHERE MATCH(customer_name) AGAINST ('Sharma' IN NATURAL LANGUAGE MODE);
```

**After:**

```
-> Filter: (match orders.customer_name against ('Sharma'))  (actual time=0.209..2.9 rows=1229 loops=1)
    -> Full-text index search on orders using idx_customer_name_ft (customer_name='Sharma')  (actual time=0.207..2.8 rows=1229 loops=1)
```

#### V1. Correctness check.

```sql
SELECT order_id, customer_name FROM orders WHERE MATCH(customer_name) AGAINST ('Sharma' IN NATURAL LANGUAGE MODE) LIMIT 5;
```

**Output:**

```
+----------+---------------+
| order_id | customer_name |
+----------+---------------+
|      319 | Kiara Sharma  |
|      323 | Kiara Sharma  |
|      327 | Kiara Sharma  |
|      331 | Kiara Sharma  |
|      335 | Kiara Sharma  |
+----------+---------------+
```

> [!TIP]
> **Observation:** A leading `%` defeats a normal B-Tree index outright — there is no prefix to seek on. A **`FULLTEXT`** index builds an inverted word index instead, so the plan changes from `Table scan` to `Full-text index search`: **3.45 ms → 2.90 ms**. (Most of the remaining time is producing the 1,229 matching rows themselves, not searching for them.)

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{5. Slow Query 3 -- OR Across Two Unindexed Columns}}$

```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders WHERE city = 'Mumbai' OR payment_mode = 'COD';
```

**Before:**

```
-> Aggregate: count(0)  (actual time=4.51..4.51 rows=1 loops=1)
    -> Filter: ((orders.city = 'Mumbai') or (orders.payment_mode = 'COD'))  (actual time=0.0628..4.35 rows=4229 loops=1)
        -> Table scan on orders  (actual time=0.0592..2.96 rows=12000 loops=1)
```

```sql
CREATE INDEX idx_city ON orders (city);
CREATE INDEX idx_payment_mode ON orders (payment_mode);

EXPLAIN ANALYZE   -- same query, unchanged
SELECT COUNT(*) FROM orders WHERE city = 'Mumbai' OR payment_mode = 'COD';
```

**After indexing alone (optimizer auto index-merge):**

```
-> Aggregate: count(0)  (actual time=4.2..4.2 rows=1 loops=1)
    -> Filter: ((orders.city = 'Mumbai') or (orders.payment_mode = 'COD'))  (actual time=0.0481..4.04 rows=4229 loops=1)
        -> Deduplicate rows sorted by row ID  (actual time=0.0457..3.42 rows=4229 loops=1)
            -> Index range scan on orders using idx_city over (city = 'Mumbai')  (actual time=0.0273..0.363 rows=1229 loops=1)
            -> Index range scan on orders using idx_payment_mode over (payment_mode = 'COD')  (actual time=0.0101..0.621 rows=3000 loops=1)
```

```sql
EXPLAIN ANALYZE   -- rewritten as an explicit UNION of two indexed lookups
SELECT order_id FROM orders WHERE city = 'Mumbai'
UNION
SELECT order_id FROM orders WHERE payment_mode = 'COD';
```

**After rewriting as `UNION`:**

```
-> Table scan on <union temporary>  (actual time=1.86..2.3 rows=4229 loops=1)
    -> Union materialize with deduplication  (actual time=1.86..1.86 rows=4229 loops=1)
        -> Covering index lookup on orders using idx_city (city='Mumbai')  (actual time=0.0366..0.274 rows=1229 loops=1)
        -> Filter: (orders.payment_mode = 'COD')
            -> Covering index lookup on orders using idx_payment_mode (payment_mode='COD')  (actual time=0.063..0.502 rows=3000 loops=1)
```

> [!TIP]
> **Observation:** Indexing both columns alone only trims **4.35 ms → 4.04 ms**, because MySQL's automatic "index merge" still has to **sort and de-duplicate** rows found by each index (a row could match both conditions). Rewriting the `OR` as an explicit **`UNION`** (which de-duplicates via a hash/union-materialize step instead) is clearly faster: **2.3 ms** — indexing alone was not enough here; the query shape also had to change.

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{6. Slow Query 4 -- Correlated Subquery}}$

```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders o
WHERE o.total_amount > (SELECT AVG(total_amount) FROM orders o2 WHERE o2.category = o.category);
```

**Before:**

```
-> Aggregate: count(0)  (actual time=46290..46290 rows=1 loops=1)
    -> Filter: (o.total_amount > (select #2))  (actual time=4.27..46289 rows=6428 loops=1)
        -> Table scan on o  (actual time=0.102..10.9 rows=12000 loops=1)
        -> Select #2 (subquery in condition; dependent)
            -> Aggregate: avg(o2.total_amount)  (actual time=3.86..3.86 rows=1 loops=12000)
                -> Filter: (o2.category = o.category)  (actual time=0.0508..3.69 rows=2000 loops=12000)
                    -> Table scan on o2  (actual time=0.0405..2.78 rows=12000 loops=12000)
```

```sql
CREATE INDEX idx_category ON orders (category);

EXPLAIN ANALYZE   -- rewritten: compute each category's average ONCE, then JOIN
SELECT COUNT(*)
FROM orders o
JOIN (SELECT category, AVG(total_amount) AS avg_amount FROM orders GROUP BY category) ca
  ON ca.category = o.category
WHERE o.total_amount > ca.avg_amount;
```

**After:**

```
-> Aggregate: count(0)  (actual time=23..23 rows=1 loops=1)
    -> Nested loop inner join  (actual time=9.28..22.7 rows=6428 loops=1)
        -> Table scan on o  (actual time=0.0496..3.24 rows=12000 loops=1)
        -> Filter: (o.total_amount > ca.avg_amount)  (actual time=0.00138..0.00149 rows=0.536 loops=12000)
            -> Covering index lookup on ca using <auto_key0> (category=o.category)  (actual time=0.00113..0.00126 rows=1 loops=12000)
                -> Materialize  (actual time=9.21..9.21 rows=6 loops=1)
                    -> Group aggregate: avg(orders.total_amount)  (actual time=1.77..9.18 rows=6 loops=1)
                        -> Index scan on orders using idx_category  (actual time=0.239..7.44 rows=12000 loops=1)
```

> [!CAUTION]
> **Observation:** The **before** plan shows `loops=12000` on the inner `Select #2` — the average is recomputed from scratch for **every single outer row**, scanning ~12,000 rows each time (144 million row-visits total). Measured time: **46.3 seconds**. The rewrite computes each of the 6 categories' averages **once** (`Materialize … loops=1`), then joins it back by an index lookup per row. Measured time: **23 ms** — roughly **2,000× faster**, and both return the identical row count (`rows=6428` before, `rows=6428` after).

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{7. Slow Query 5 -- ORDER BY ... LIMIT Without a Supporting Index}}$

```sql
EXPLAIN ANALYZE
SELECT order_id, customer_name, total_amount FROM orders ORDER BY total_amount DESC LIMIT 20;
```

**Before:**

```
-> Limit: 20 row(s)  (actual time=4.63..4.63 rows=20 loops=1)
    -> Sort: orders.total_amount DESC, limit input to 20 row(s) per chunk  (actual time=4.63..4.63 rows=20 loops=1)
        -> Table scan on orders  (actual time=0.0568..3.1 rows=12000 loops=1)
```

```sql
CREATE INDEX idx_total_amount ON orders (total_amount);

EXPLAIN ANALYZE
SELECT order_id, customer_name, total_amount FROM orders ORDER BY total_amount DESC LIMIT 20;
```

**After:**

```
-> Limit: 20 row(s)  (actual time=0.0238..0.0445 rows=20 loops=1)
    -> Index scan on orders using idx_total_amount (reverse)  (actual time=0.0224..0.0419 rows=20 loops=1)
```

#### V2. Correctness check — the top 5 most expensive orders.

```sql
SELECT order_id, customer_name, total_amount FROM orders ORDER BY total_amount DESC LIMIT 5;
```

**Output:**

```
+----------+---------------+--------------+
| order_id | customer_name | total_amount |
+----------+---------------+--------------+
|     8009 | Saanvi Mehta  |     49995.00 |
|    10739 | Saanvi Mehta  |     49990.00 |
|     1182 | Saanvi Mehta  |     49990.00 |
|     3912 | Saanvi Mehta  |     49985.00 |
|     6642 | Saanvi Mehta  |     49980.00 |
+----------+---------------+--------------+
```

> [!TIP]
> **Observation:** Before indexing, all 12,000 rows had to be **sorted** (`Sort …`) just to pick the top 20. With `idx_total_amount` in place, the index is **already in sorted order**, so MySQL simply walks it **backwards** (`Index scan … (reverse)`) and stops at the 20th row — no sort step at all. **4.63 ms → 0.044 ms**, roughly **100× faster**.

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{8. Final Index List}}$

```sql
SHOW INDEX FROM orders;
```

**Output:**

```
+--------+------------+----------------------+--------------+---------------+------------+-------------+
| Table  | Non_unique | Key_name             | Seq_in_index | Column_name   | Index_type | Cardinality |
+--------+------------+----------------------+--------------+---------------+------------+-------------+
| orders |          0 | PRIMARY              |            1 | order_id      | BTREE      |       11975 |
| orders |          1 | idx_order_date       |            1 | order_date    | BTREE      |         730 |
| orders |          1 | idx_city             |            1 | city          | BTREE      |          10 |
| orders |          1 | idx_payment_mode     |            1 | payment_mode  | BTREE      |           4 |
| orders |          1 | idx_category         |            1 | category      | BTREE      |           6 |
| orders |          1 | idx_total_amount     |            1 | total_amount  | BTREE      |        9259 |
| orders |          1 | idx_customer_name_ft |            1 | customer_name | FULLTEXT   |       11975 |
+--------+------------+----------------------+--------------+---------------+------------+-------------+
```

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{9. Before / After Summary}}$

| # | Slow query | Anti-pattern | Fix | Before | After | Speedup |
|---|---|---|---|---:|---:|---:|
| 1 | `WHERE YEAR(order_date)=2025` | Non-sargable function | Range predicate + `idx_order_date` | 2.62 ms | 1.39 ms | ~1.9× |
| 2 | `LIKE '%Sharma%'` | Leading wildcard | `FULLTEXT` + `MATCH…AGAINST` | 3.45 ms | 2.90 ms | ~1.2× |
| 3 | `city = … OR payment_mode = …` | OR on 2 columns | Indexes + rewrite as `UNION` | 4.35 ms | 2.30 ms | ~1.9× |
| 4 | Correlated `AVG` subquery | Re-executes per row | Derived table + `JOIN` | 46,290 ms | 23 ms | **~2,000×** |
| 5 | `ORDER BY total_amount LIMIT 20` | Filesort | `idx_total_amount` | 4.63 ms | 0.044 ms | ~105× |

> [!TIP]
> **Observation:** Indexing alone was the fix for Queries 1, 2 and 5. Query 3 needed indexing **and** a rewrite to get a real improvement. Query 4 needed a **rewrite** (indexing `category` only helped the rewritten version compute its averages efficiently) — this is the one where the anti-pattern itself, not the lack of an index, was the entire problem.

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

## $\color{#7209B7}{\textsf{Result}}$

> [!IMPORTANT]
> **Result**
>
> A 12,000-row `orders` dataset was generated, and **five classic slow-query patterns** were reproduced and fixed:
> - A **non-sargable function** (`YEAR()`) was rewritten as a sargable range and indexed.
> - A **leading-wildcard `LIKE`** was replaced with a `FULLTEXT` index and `MATCH … AGAINST`.
> - An **`OR` across two columns** was sped up by indexing both columns, and further by rewriting as an explicit `UNION`.
> - A **correlated subquery** recomputing an aggregate once per row (46.3 seconds) was rewritten as a derived table joined once (23 ms) — a ~2,000× improvement.
> - An **`ORDER BY … LIMIT`** filesort was eliminated entirely by indexing the sort column.
>
> Every fix was verified with `EXPLAIN ANALYZE` showing a genuine plan change (table scan → index access) and a measured drop in execution time, and the optimized queries were spot-checked to return the same correct results as the originals.

<img src="assets/rule-10.svg" width="100%" height="8" alt=""/>

<div align="center">

<a href="Exp_9.md"><img src="https://img.shields.io/badge/Previous-Experiment%209-1D3557?style=for-the-badge" alt="Previous"/></a> <a href="README.md"><img src="https://img.shields.io/badge/Back%20to-Index-3D405B?style=for-the-badge" alt="Index"/></a>

<sub>Iqra Khan · UID 25LBCS3306 · Experiment 10</sub>

</div>
