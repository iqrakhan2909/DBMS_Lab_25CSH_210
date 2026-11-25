-- ============================================================================
-- Experiment 7: Functional Dependencies and Normalization (UNF -> 1NF -> 2NF ->
--               3NF -> BCNF) of a denormalized Sales table, with SQL-based
--               verification of lossless join and dependency preservation.
-- Database   : sales_normalization_db
-- ============================================================================

DROP DATABASE IF EXISTS sales_normalization_db;
CREATE DATABASE sales_normalization_db;
USE sales_normalization_db;

-- ----------------------------------------------------------------------------
-- 0. UNF: the sales register as it would be kept on paper / in a spreadsheet.
--    One row per sale, products sold in that sale kept as a repeating group
--    (not atomic -> violates 1NF).
-- ----------------------------------------------------------------------------
CREATE TABLE sales_unf (
    sale_id         INT PRIMARY KEY,
    sale_date       DATE NOT NULL,
    customer_id     INT NOT NULL,
    customer_name   VARCHAR(60) NOT NULL,
    customer_phone  VARCHAR(15) NOT NULL,
    customer_city   VARCHAR(40) NOT NULL,
    salesperson_id  INT NOT NULL,
    salesperson_name VARCHAR(60) NOT NULL,
    store_id        INT NOT NULL,
    store_name      VARCHAR(60) NOT NULL,
    store_city      VARCHAR(40) NOT NULL,
    -- repeating group: every product sold in this sale, as a JSON array (not atomic -> 1NF violation)
    products_ordered JSON NOT NULL
);

INSERT INTO sales_unf VALUES
(1,'2026-10-01',201,'Rohit Sharma','9810012345','Delhi',301,'Ananya Iyer',1,'Prime Retail - CP','Delhi',
 '[{"product_id":"P01","product_name":"Wireless Mouse","product_category":"Electronics","unit_price":650.00,"quantity":2},
   {"product_id":"P03","product_name":"Notebook Set","product_category":"Stationery","unit_price":120.00,"quantity":5}]'),
(2,'2026-10-01',202,'Kavita Reddy','9845011111','Hyderabad',302,'Farhan Sheikh',2,'Prime Retail - Banjara Hills','Hyderabad',
 '[{"product_id":"P02","product_name":"Bluetooth Speaker","product_category":"Electronics","unit_price":1800.00,"quantity":1}]'),
(3,'2026-10-02',201,'Rohit Sharma','9810012345','Delhi',301,'Ananya Iyer',1,'Prime Retail - CP','Delhi',
 '[{"product_id":"P04","product_name":"Office Chair","product_category":"Furniture","unit_price":4200.00,"quantity":1},
   {"product_id":"P01","product_name":"Wireless Mouse","product_category":"Electronics","unit_price":650.00,"quantity":1}]'),
(4,'2026-10-02',203,'Meera Pillai','9995522222','Kochi',303,'Deepak Nair',3,'Prime Retail - MG Road','Kochi',
 '[{"product_id":"P05","product_name":"LED Desk Lamp","product_category":"Furniture","unit_price":950.00,"quantity":2},
   {"product_id":"P02","product_name":"Bluetooth Speaker","product_category":"Electronics","unit_price":1800.00,"quantity":1},
   {"product_id":"P03","product_name":"Notebook Set","product_category":"Stationery","unit_price":120.00,"quantity":10}]'),
(5,'2026-10-03',204,'Arjun Malhotra','9876543210','Chandigarh',301,'Ananya Iyer',1,'Prime Retail - CP','Delhi',
 '[{"product_id":"P06","product_name":"Mechanical Keyboard","product_category":"Electronics","unit_price":3200.00,"quantity":1}]'),
(6,'2026-10-03',202,'Kavita Reddy','9845011111','Hyderabad',304,'Sunil Verma',2,'Prime Retail - Banjara Hills','Hyderabad',
 '[{"product_id":"P04","product_name":"Office Chair","product_category":"Furniture","unit_price":4200.00,"quantity":2},
   {"product_id":"P05","product_name":"LED Desk Lamp","product_category":"Furniture","unit_price":950.00,"quantity":2}]'),
(7,'2026-10-04',205,'Priya Nambiar','9911223344','Bengaluru',305,'Kiran Rao',4,'Prime Retail - Indiranagar','Bengaluru',
 '[{"product_id":"P01","product_name":"Wireless Mouse","product_category":"Electronics","unit_price":650.00,"quantity":3},
   {"product_id":"P06","product_name":"Mechanical Keyboard","product_category":"Electronics","unit_price":3200.00,"quantity":1},
   {"product_id":"P03","product_name":"Notebook Set","product_category":"Stationery","unit_price":120.00,"quantity":4}]'),
(8,'2026-10-04',203,'Meera Pillai','9995522222','Kochi',303,'Deepak Nair',3,'Prime Retail - MG Road','Kochi',
 '[{"product_id":"P02","product_name":"Bluetooth Speaker","product_category":"Electronics","unit_price":1800.00,"quantity":2}]'),
(9,'2026-10-05',206,'Suresh Pawar','9822334455','Pune',302,'Farhan Sheikh',2,'Prime Retail - Banjara Hills','Hyderabad',
 '[{"product_id":"P05","product_name":"LED Desk Lamp","product_category":"Furniture","unit_price":950.00,"quantity":1},
   {"product_id":"P04","product_name":"Office Chair","product_category":"Furniture","unit_price":4200.00,"quantity":1}]'),
(10,'2026-10-05',204,'Arjun Malhotra','9876543210','Chandigarh',305,'Kiran Rao',4,'Prime Retail - Indiranagar','Bengaluru',
 '[{"product_id":"P06","product_name":"Mechanical Keyboard","product_category":"Electronics","unit_price":3200.00,"quantity":2},
   {"product_id":"P01","product_name":"Wireless Mouse","product_category":"Electronics","unit_price":650.00,"quantity":1}]');

-- ----------------------------------------------------------------------------
-- 1.1  First Normal Form (1NF): eliminate the repeating group.
--      One row per (sale_id, product_id) line item. All attributes atomic.
--      JSON_TABLE splits the comma-separated repeating group into rows.
-- ----------------------------------------------------------------------------
CREATE TABLE sales_1nf (
    sale_id          INT NOT NULL,
    sale_date        DATE NOT NULL,
    customer_id      INT NOT NULL,
    customer_name    VARCHAR(60) NOT NULL,
    customer_phone   VARCHAR(15) NOT NULL,
    customer_city    VARCHAR(40) NOT NULL,
    salesperson_id   INT NOT NULL,
    salesperson_name VARCHAR(60) NOT NULL,
    store_id         INT NOT NULL,
    store_name       VARCHAR(60) NOT NULL,
    store_city       VARCHAR(40) NOT NULL,
    product_id       VARCHAR(10) NOT NULL,
    product_name     VARCHAR(60) NOT NULL,
    product_category VARCHAR(30) NOT NULL,
    unit_price       DECIMAL(10,2) NOT NULL,
    quantity         INT NOT NULL,
    PRIMARY KEY (sale_id, product_id)
);

INSERT INTO sales_1nf
SELECT u.sale_id, u.sale_date, u.customer_id, u.customer_name, u.customer_phone, u.customer_city,
       u.salesperson_id, u.salesperson_name, u.store_id, u.store_name, u.store_city,
       jt.product_id, jt.product_name, jt.product_category, jt.unit_price, jt.quantity
FROM sales_unf u,
     JSON_TABLE(
        u.products_ordered,
        '$[*]' COLUMNS (
            product_id       VARCHAR(10)  PATH '$.product_id',
            product_name     VARCHAR(60)  PATH '$.product_name',
            product_category VARCHAR(30)  PATH '$.product_category',
            unit_price       DECIMAL(10,2) PATH '$.unit_price',
            quantity         INT          PATH '$.quantity'
        )
     ) AS jt;

-- ----------------------------------------------------------------------------
-- 1.2 Functional dependencies identified on sales_1nf
--     (candidate key: {sale_id, product_id})
--
--   FD1  sale_id -> sale_date, customer_id, salesperson_id
--   FD2  customer_id -> customer_name, customer_phone, customer_city
--   FD3  salesperson_id -> salesperson_name, store_id
--   FD4  store_id -> store_name, store_city
--   FD5  product_id -> product_name, product_category, unit_price
--   FD6  {sale_id, product_id} -> quantity
--
--   FD2..FD5 are PARTIAL dependencies on the composite key (2NF violation).
--   customer_id -> ... and salesperson_id -> store_id -> ... are TRANSITIVE
--   dependencies once sale_id's dependents are grouped together (3NF violation).
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- 2. Second Normal Form (2NF): remove partial dependencies on the composite key.
--    Split into: sales_header (depends only on sale_id), product (depends
--    only on product_id) and sale_item (the genuine fact of the composite key).
-- ----------------------------------------------------------------------------
CREATE TABLE sales_header_2nf (
    sale_id          INT PRIMARY KEY,
    sale_date        DATE NOT NULL,
    customer_id      INT NOT NULL,
    customer_name    VARCHAR(60) NOT NULL,
    customer_phone   VARCHAR(15) NOT NULL,
    customer_city    VARCHAR(40) NOT NULL,
    salesperson_id   INT NOT NULL,
    salesperson_name VARCHAR(60) NOT NULL,
    store_id         INT NOT NULL,
    store_name       VARCHAR(60) NOT NULL,
    store_city       VARCHAR(40) NOT NULL
);
INSERT INTO sales_header_2nf
SELECT DISTINCT sale_id, sale_date, customer_id, customer_name, customer_phone, customer_city,
                salesperson_id, salesperson_name, store_id, store_name, store_city
FROM sales_1nf;

CREATE TABLE product_2nf (
    product_id       VARCHAR(10) PRIMARY KEY,
    product_name     VARCHAR(60) NOT NULL,
    product_category VARCHAR(30) NOT NULL,
    unit_price       DECIMAL(10,2) NOT NULL
);
INSERT INTO product_2nf
SELECT DISTINCT product_id, product_name, product_category, unit_price FROM sales_1nf;

CREATE TABLE sale_item (
    sale_id    INT NOT NULL,
    product_id VARCHAR(10) NOT NULL,
    quantity   INT NOT NULL,
    PRIMARY KEY (sale_id, product_id),
    FOREIGN KEY (sale_id) REFERENCES sales_header_2nf(sale_id),
    FOREIGN KEY (product_id) REFERENCES product_2nf(product_id)
);
INSERT INTO sale_item SELECT sale_id, product_id, quantity FROM sales_1nf;

-- ----------------------------------------------------------------------------
-- 3. Third Normal Form (3NF): remove transitive dependencies from sales_header_2nf.
--    customer_id -> customer_name/phone/city        (transitive via customer_id)
--    salesperson_id -> salesperson_name, store_id    (transitive via salesperson_id)
--    store_id -> store_name, store_city              (transitive via store_id)
-- ----------------------------------------------------------------------------
CREATE TABLE customer (
    customer_id    INT PRIMARY KEY,
    customer_name  VARCHAR(60) NOT NULL,
    customer_phone VARCHAR(15) NOT NULL,
    customer_city  VARCHAR(40) NOT NULL
);
INSERT INTO customer SELECT DISTINCT customer_id, customer_name, customer_phone, customer_city FROM sales_header_2nf;

CREATE TABLE store (
    store_id   INT PRIMARY KEY,
    store_name VARCHAR(60) NOT NULL,
    store_city VARCHAR(40) NOT NULL
);
INSERT INTO store SELECT DISTINCT store_id, store_name, store_city FROM sales_header_2nf;

CREATE TABLE salesperson (
    salesperson_id   INT PRIMARY KEY,
    salesperson_name VARCHAR(60) NOT NULL,
    store_id         INT NOT NULL,
    FOREIGN KEY (store_id) REFERENCES store(store_id)
);
INSERT INTO salesperson SELECT DISTINCT salesperson_id, salesperson_name, store_id FROM sales_header_2nf;

CREATE TABLE sales_header_3nf (
    sale_id        INT PRIMARY KEY,
    sale_date      DATE NOT NULL,
    customer_id    INT NOT NULL,
    salesperson_id INT NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    FOREIGN KEY (salesperson_id) REFERENCES salesperson(salesperson_id)
);
INSERT INTO sales_header_3nf SELECT sale_id, sale_date, customer_id, salesperson_id FROM sales_header_2nf;

-- sale_item and product_2nf (renamed product) carry over unchanged into 3NF/BCNF.
RENAME TABLE product_2nf TO product;

-- ----------------------------------------------------------------------------
-- 4. BCNF check: for every relation, is every determinant a candidate key?
--    customer(customer_id -> ...)            : customer_id is the PK           -> BCNF
--    store(store_id -> ...)                  : store_id is the PK              -> BCNF
--    salesperson(salesperson_id -> ...)      : salesperson_id is the PK        -> BCNF
--    product(product_id -> ...)              : product_id is the PK           -> BCNF
--    sales_header_3nf(sale_id -> ...)         : sale_id is the PK              -> BCNF
--    sale_item({sale_id,product_id} -> qty)  : the composite PK is the only
--                                              determinant                     -> BCNF
--    No further decomposition is required: the 3NF schema above is already BCNF.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- 5. Final normalized (BCNF) schema, reproduced from scratch for clarity.
-- ----------------------------------------------------------------------------
-- customer, store, salesperson, product, sales_header_3nf, sale_item (created above)

-- ----------------------------------------------------------------------------
-- 6. Lossless-join verification: rebuild the original flat relation from the
--    BCNF tables and compare it, row for row, with sales_1nf.
-- ----------------------------------------------------------------------------
CREATE VIEW sales_reconstructed AS
SELECT h.sale_id, h.sale_date, h.customer_id, c.customer_name, c.customer_phone, c.customer_city,
       h.salesperson_id, sp.salesperson_name, sp.store_id, st.store_name, st.store_city,
       si.product_id, p.product_name, p.product_category, p.unit_price, si.quantity
FROM sales_header_3nf h
JOIN customer    c  ON c.customer_id   = h.customer_id
JOIN salesperson sp ON sp.salesperson_id = h.salesperson_id
JOIN store       st ON st.store_id     = sp.store_id
JOIN sale_item   si ON si.sale_id      = h.sale_id
JOIN product     p  ON p.product_id    = si.product_id;

-- D1. Row counts must match.
SELECT (SELECT COUNT(*) FROM sales_1nf) AS original_rows,
       (SELECT COUNT(*) FROM sales_reconstructed) AS rejoined_rows;

-- D2. Nothing in the original is missing from the rejoin, and nothing extra appears.
SELECT * FROM sales_1nf EXCEPT SELECT * FROM sales_reconstructed;
SELECT * FROM sales_reconstructed EXCEPT SELECT * FROM sales_1nf;

-- ----------------------------------------------------------------------------
-- 7. Dependency-preservation verification: every original FD must be checkable
--    (and enforceable) from the decomposed tables alone, without rejoining.
-- ----------------------------------------------------------------------------
-- D3. FD2 (customer_id -> name/phone/city) holds in `customer`.
SELECT customer_id, COUNT(DISTINCT customer_name) AS distinct_names,
       COUNT(DISTINCT customer_phone) AS distinct_phones, COUNT(DISTINCT customer_city) AS distinct_cities
FROM customer GROUP BY customer_id HAVING distinct_names > 1 OR distinct_phones > 1 OR distinct_cities > 1;

-- D4. FD3 (salesperson_id -> name, store_id) holds in `salesperson`.
SELECT salesperson_id, COUNT(DISTINCT salesperson_name) AS distinct_names, COUNT(DISTINCT store_id) AS distinct_stores
FROM salesperson GROUP BY salesperson_id HAVING distinct_names > 1 OR distinct_stores > 1;

-- D5. FD4 (store_id -> name, city) holds in `store`; FD5 (product_id -> ...) holds in `product`.
SELECT store_id, COUNT(DISTINCT store_name) AS distinct_names, COUNT(DISTINCT store_city) AS distinct_cities
FROM store GROUP BY store_id HAVING distinct_names > 1 OR distinct_cities > 1;

SELECT product_id, COUNT(DISTINCT product_name) AS distinct_names, COUNT(DISTINCT unit_price) AS distinct_prices
FROM product GROUP BY product_id HAVING distinct_names > 1 OR distinct_prices > 1;

-- D6. All 6 original FDs are each testable on exactly one decomposed table -> dependency preserved.
--     (No FD needs sales_reconstructed / a join to be checked.)

-- ----------------------------------------------------------------------------
-- 8. Why normalization matters: update anomaly in the UNF/1NF design.
-- ----------------------------------------------------------------------------
-- E1. In the flat design, Rohit Sharma's city is repeated on every line of every sale.
SELECT sale_id, product_id, customer_id, customer_city FROM sales_1nf WHERE customer_id = 201;

-- E2. A careless UPDATE that only patches one line item creates an inconsistency
--     the flat table cannot prevent (the same customer now has two cities on record).
UPDATE sales_1nf SET customer_city = 'Gurugram' WHERE sale_id = 1 AND product_id = 'P01';
SELECT sale_id, product_id, customer_id, customer_city FROM sales_1nf WHERE customer_id = 201;

-- E3. The same update on the normalized schema touches ONE row in `customer` and is
--     instantly consistent everywhere it is used (no duplicate to go stale).
UPDATE customer SET customer_city = 'Gurugram' WHERE customer_id = 201;
SELECT * FROM customer WHERE customer_id = 201;
SELECT sale_id, customer_id FROM sales_header_3nf WHERE customer_id = 201;
