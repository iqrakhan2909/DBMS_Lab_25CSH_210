-- ============================================================================
-- Experiment 8: Banking-style transactions (BEGIN, COMMIT, ROLLBACK, SAVEPOINT),
--               partial-failure simulation, and isolation levels / concurrency
--               anomalies demonstrated with two sessions.
-- Database   : bank_db
-- ============================================================================

DROP DATABASE IF EXISTS bank_db;
CREATE DATABASE bank_db;
USE bank_db;

CREATE TABLE account (
    account_id   INT PRIMARY KEY,
    owner_name   VARCHAR(60) NOT NULL,
    account_type ENUM('SAVINGS','CURRENT') NOT NULL,
    balance      DECIMAL(12,2) NOT NULL CHECK (balance >= 0)
) ENGINE = InnoDB;

CREATE TABLE transaction_log (
    txn_id      INT AUTO_INCREMENT PRIMARY KEY,
    from_acct   INT,
    to_acct     INT,
    amount      DECIMAL(12,2) NOT NULL,
    status      ENUM('SUCCESS','FAILED') NOT NULL,
    logged_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

INSERT INTO account VALUES
(1001,'Ravi Kumar','SAVINGS', 50000.00),
(1002,'Sunita Agarwal','SAVINGS', 30000.00),
(1003,'Imran Qureshi','CURRENT', 120000.00),
(1004,'Lakshmi Narayanan','SAVINGS', 8000.00),
(1005,'Harpreet Singh','CURRENT', 25000.00);

-- ----------------------------------------------------------------------------
-- 1. A plain, successful transfer: BEGIN ... COMMIT.
-- ----------------------------------------------------------------------------
START TRANSACTION;
UPDATE account SET balance = balance - 10000 WHERE account_id = 1001;
UPDATE account SET balance = balance + 10000 WHERE account_id = 1002;
INSERT INTO transaction_log (from_acct, to_acct, amount, status) VALUES (1001, 1002, 10000, 'SUCCESS');
COMMIT;

SELECT account_id, owner_name, balance FROM account WHERE account_id IN (1001,1002);

-- ----------------------------------------------------------------------------
-- 2. SAVEPOINT: a multi-leg transfer where one leg fails; roll back only that
--    leg, then continue and commit the rest.
--    Harpreet (1005) pays two people in one transaction: Lakshmi gets 5,000
--    (OK) and an attempted payment of 50,000 to Imran would be fine for the
--    balance but we simulate a business-rule failure (invalid/closed target
--    account 9999) to show partial rollback via SAVEPOINT.
-- ----------------------------------------------------------------------------
START TRANSACTION;

SAVEPOINT before_leg1;
UPDATE account SET balance = balance - 5000 WHERE account_id = 1005;
UPDATE account SET balance = balance + 5000 WHERE account_id = 1004;
INSERT INTO transaction_log (from_acct, to_acct, amount, status) VALUES (1005, 1004, 5000, 'SUCCESS');
-- Leg 1 looks fine; keep it and move the savepoint forward.
RELEASE SAVEPOINT before_leg1;

SAVEPOINT before_leg2;
UPDATE account SET balance = balance - 20000 WHERE account_id = 1005;
-- account 9999 does not exist: this leg must fail and be undone, not the whole transfer.
-- (Checked in application logic / here via NOT EXISTS before crediting.)
INSERT INTO transaction_log (from_acct, to_acct, amount, status)
SELECT 1005, 9999, 20000, 'FAILED' WHERE NOT EXISTS (SELECT 1 FROM account WHERE account_id = 9999);
ROLLBACK TO SAVEPOINT before_leg2;

COMMIT;

SELECT account_id, owner_name, balance FROM account WHERE account_id IN (1004,1005);
SELECT txn_id, from_acct, to_acct, amount, status FROM transaction_log ORDER BY txn_id;

-- ----------------------------------------------------------------------------
-- 3. Partial failure without a savepoint: a CHECK-constraint violation mid-
--    transaction must roll back the ENTIRE transaction (atomicity).
--    Lakshmi (1004) has ~13,000 after step 2; try to overdraw by 50,000.
-- ----------------------------------------------------------------------------
SELECT balance FROM account WHERE account_id = 1004;

START TRANSACTION;
UPDATE account SET balance = balance + 2000 WHERE account_id = 1003;  -- would succeed in isolation
UPDATE account SET balance = balance - 50000 WHERE account_id = 1004; -- violates balance >= 0
-- The statement above raises ERROR 3819 (HY000); the application issues ROLLBACK.
ROLLBACK;

SELECT account_id, owner_name, balance FROM account WHERE account_id IN (1003,1004);

-- ----------------------------------------------------------------------------
-- 4. Isolation levels: current session default and how to change it.
-- ----------------------------------------------------------------------------
SELECT @@global.transaction_isolation AS global_level, @@session.transaction_isolation AS session_level;

-- ============================================================================
-- 5. Concurrency anomalies, demonstrated with TWO SESSIONS.
--    Open two separate `mysql bank_db` clients (Session A and Session B) and
--    run the statements below in the interleaved order shown by the step
--    number, e.g. open two terminals side by side. Each block is labelled
--    [A] or [B] for the session it runs in.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 5.1 Dirty Read (READ UNCOMMITTED): A sees B's uncommitted debit, which then
--     disappears when B rolls back -- A "read" a value that never existed.
-- ----------------------------------------------------------------------------
-- [A] SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
-- [B] SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
-- [B] START TRANSACTION;
-- [B] UPDATE account SET balance = balance - 15000 WHERE account_id = 1001;
-- [A] START TRANSACTION;
-- [A] SELECT account_id, balance FROM account WHERE account_id = 1001;   -- dirty read: 25000.00
-- [B] ROLLBACK;
-- [A] SELECT account_id, balance FROM account WHERE account_id = 1001;   -- back to 40000.00
-- [A] COMMIT;

-- ----------------------------------------------------------------------------
-- 5.2 Non-repeatable Read (READ COMMITTED): the SAME query re-run inside A's
--     transaction returns a DIFFERENT value once B commits a change.
-- ----------------------------------------------------------------------------
-- [A] SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- [A] START TRANSACTION;
-- [A] SELECT account_id, balance FROM account WHERE account_id = 1002;   -- 40000.00
-- [B] START TRANSACTION;
-- [B] UPDATE account SET balance = balance + 5000 WHERE account_id = 1002;
-- [B] COMMIT;
-- [A] SELECT account_id, balance FROM account WHERE account_id = 1002;   -- 45000.00 (changed!)
-- [A] COMMIT;

-- Repeated under REPEATABLE READ (account 1003) to show the anomaly is PREVENTED:
-- [A] SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- [A] START TRANSACTION;
-- [A] SELECT account_id, balance FROM account WHERE account_id = 1003;   -- 120000.00
-- [B] START TRANSACTION;
-- [B] UPDATE account SET balance = balance + 2000 WHERE account_id = 1003;
-- [B] COMMIT;
-- [A] SELECT account_id, balance FROM account WHERE account_id = 1003;   -- still 120000.00
-- [A] COMMIT;
-- [A] SELECT account_id, balance FROM account WHERE account_id = 1003;   -- now 122000.00

-- ----------------------------------------------------------------------------
-- 5.3 Phantom Read: a range query run twice in the same transaction returns a
--     DIFFERENT row count once B commits a new row that matches the predicate.
-- ----------------------------------------------------------------------------
-- [A] SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- [A] START TRANSACTION;
-- [A] SELECT COUNT(*) AS savings_accounts FROM account WHERE account_type = 'SAVINGS';  -- 3
-- [B] START TRANSACTION;
-- [B] INSERT INTO account VALUES (1006, 'Test Phantom RC', 'SAVINGS', 10000.00);
-- [B] COMMIT;
-- [A] SELECT COUNT(*) AS savings_accounts FROM account WHERE account_type = 'SAVINGS';  -- 4 (phantom!)
-- [A] COMMIT;

-- Repeated under REPEATABLE READ to show the phantom is PREVENTED (InnoDB's
-- consistent-read snapshot, taken at the first read in the transaction):
-- [A] SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- [A] START TRANSACTION;
-- [A] SELECT COUNT(*) AS savings_accounts FROM account WHERE account_type = 'SAVINGS';  -- 4
-- [B] START TRANSACTION;
-- [B] INSERT INTO account VALUES (1007, 'Test Phantom RR', 'SAVINGS', 5000.00);
-- [B] COMMIT;
-- [A] SELECT COUNT(*) AS savings_accounts FROM account WHERE account_type = 'SAVINGS';  -- still 4
-- [A] COMMIT;
-- [A] SELECT COUNT(*) AS savings_accounts FROM account WHERE account_type = 'SAVINGS';  -- now 5
