-- ============================================================================
-- Experiment 10: A >= 10,000-row dataset, five slow queries, EXPLAIN analysis,
--                optimization by indexing and query rewriting, and before/after
--                execution-time comparison.
-- Database   : retail_orders_db
-- ============================================================================

DROP DATABASE IF EXISTS retail_orders_db;
CREATE DATABASE retail_orders_db;
USE retail_orders_db;

SET @@cte_max_recursion_depth = 15000;

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

-- 12,000 rows, RAND() seeded for repeatability.
INSERT INTO orders
    (customer_id, customer_name, category, city, order_date, quantity, unit_price, total_amount, payment_mode, order_status)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 12000
)
SELECT
    1000 + FLOOR(RAND(42 + n) * 3000),
    CONCAT(
        ELT(1 + FLOOR(RAND(100 + n) * 12),
            'Aarav','Vivaan','Aditya','Ishaan','Rohan','Kabir','Ananya','Diya','Isha','Meera','Saanvi','Kiara'),
        ' ',
        ELT(1 + FLOOR(RAND(200 + n) * 10),
            'Sharma','Verma','Gupta','Iyer','Reddy','Nair','Singh','Patel','Rao','Mehta')
    ),
    ELT(1 + FLOOR(RAND(300 + n) * 6),
        'Electronics','Clothing','Grocery','Furniture','Books','Sports'),
    ELT(1 + FLOOR(RAND(400 + n) * 10),
        'Mumbai','Delhi','Bengaluru','Chennai','Kolkata','Hyderabad','Pune','Ahmedabad','Jaipur','Lucknow'),
    DATE_ADD('2024-01-01', INTERVAL FLOOR(RAND(500 + n) * 730) DAY),
    1 + FLOOR(RAND(600 + n) * 5),
    100 + FLOOR(RAND(700 + n) * 9900),
    0,  -- filled in below
    ELT(1 + FLOOR(RAND(800 + n) * 4), 'UPI','CARD','NETBANKING','COD'),
    ELT(1 + FLOOR(RAND(900 + n) * 4), 'DELIVERED','SHIPPED','CANCELLED','RETURNED')
FROM seq;

UPDATE orders SET total_amount = quantity * unit_price;

SELECT COUNT(*) AS total_orders FROM orders;

-- ============================================================================
-- SLOW QUERY 1: a function wrapped around an indexed/indexable column makes
-- it non-sargable, so MySQL cannot seek -- it must evaluate YEAR() per row.
-- ============================================================================
-- BEFORE: no index on order_date, and YEAR() disables any index anyway.
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders WHERE YEAR(order_date) = 2025;

CREATE INDEX idx_order_date ON orders (order_date);

-- Rewrite: a sargable range predicate lets the optimizer seek the index.
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders WHERE order_date >= '2025-01-01' AND order_date < '2026-01-01';

-- ============================================================================
-- SLOW QUERY 2: a LEADING wildcard LIKE cannot use a normal B-Tree index.
-- ============================================================================
-- BEFORE: full scan, every row's customer_name is pattern-matched.
EXPLAIN ANALYZE
SELECT order_id, customer_name FROM orders WHERE customer_name LIKE '%Sharma%';

CREATE FULLTEXT INDEX idx_customer_name_ft ON orders (customer_name);

-- Rewrite: a FULLTEXT index + MATCH ... AGAINST turns this into an index search.
EXPLAIN ANALYZE
SELECT order_id, customer_name FROM orders WHERE MATCH(customer_name) AGAINST ('Sharma' IN NATURAL LANGUAGE MODE);

-- ============================================================================
-- SLOW QUERY 3: OR across two different unindexed columns forces a full scan.
-- ============================================================================
-- BEFORE
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders WHERE city = 'Mumbai' OR payment_mode = 'COD';

CREATE INDEX idx_city ON orders (city);
CREATE INDEX idx_payment_mode ON orders (payment_mode);

-- AFTER (same query): the optimizer can now use index merge / union on the two indexes.
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders WHERE city = 'Mumbai' OR payment_mode = 'COD';

-- Rewrite as an explicit UNION of two indexed lookups (de-duplicates automatically).
EXPLAIN ANALYZE
SELECT order_id FROM orders WHERE city = 'Mumbai'
UNION
SELECT order_id FROM orders WHERE payment_mode = 'COD';

-- ============================================================================
-- SLOW QUERY 4: a correlated subquery recomputes AVG(total_amount) once PER ROW.
-- ============================================================================
-- BEFORE
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders o
WHERE o.total_amount > (SELECT AVG(total_amount) FROM orders o2 WHERE o2.category = o.category);

CREATE INDEX idx_category ON orders (category);

-- Rewrite: compute each category's average ONCE in a derived table, then JOIN.
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM orders o
JOIN (SELECT category, AVG(total_amount) AS avg_amount FROM orders GROUP BY category) ca
  ON ca.category = o.category
WHERE o.total_amount > ca.avg_amount;

-- ============================================================================
-- SLOW QUERY 5: ORDER BY ... LIMIT on an unindexed column forces a filesort
-- over the WHOLE result before the top 20 can be returned.
-- ============================================================================
-- BEFORE
EXPLAIN ANALYZE
SELECT order_id, customer_name, total_amount FROM orders ORDER BY total_amount DESC LIMIT 20;

CREATE INDEX idx_total_amount ON orders (total_amount);

-- AFTER: the index is already in total_amount order, so MySQL can walk it
-- backwards and stop at the 20th row -- no filesort needed.
EXPLAIN ANALYZE
SELECT order_id, customer_name, total_amount FROM orders ORDER BY total_amount DESC LIMIT 20;

-- ----------------------------------------------------------------------------
-- Final index list on `orders`.
-- ----------------------------------------------------------------------------
SHOW INDEX FROM orders;
