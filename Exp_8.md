<div align="center">

<img src="assets/banner-exp8.svg" width="100%" alt="Experiment 8: Banking Transactions, Savepoints and Isolation Levels"/>

<table>
<tr><th align="left">Name</th><td>Iqra Khan</td><th align="left">UID</th><td><code>25LBCS3306</code></td></tr>
<tr><th align="left">Experiment No.</th><td>08</td><th align="left">SQL Script</th><td><a href="banking_transactions.sql"><img src="https://img.shields.io/badge/SQL%20Script-banking__transactions.sql-E63946?style=flat-square" alt="banking_transactions.sql"/></a></td></tr>
<tr><th align="left">Experiment Title</th><td colspan="3">Banking Transactions, Savepoints and Isolation Levels</td></tr>
</table>

</div>

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{Aim}}$

> [!NOTE]
> To implement **banking-style transactions** using `BEGIN`, `COMMIT`, `ROLLBACK` and `SAVEPOINT`, to **simulate partial failures**, and to **demonstrate isolation levels and concurrency anomalies** using two sessions.

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{Software Required}}$

- MySQL Server 8.0 or later, **InnoDB** storage engine (transactional, row-level locking)
- Two concurrent MySQL command-line clients (two terminals), both connected to `bank_db`

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{Files}}$

| File | Description |
|---|---|
| [`banking_transactions.sql`](banking_transactions.sql) | Schema, single-session transactions/savepoints, and the two-session scripts (as comments, labelled `[A]`/`[B]`) |
| `Exp_8.md` | This lab record |

**How to run:**

```bash
mysql -u root -p -t --force < banking_transactions.sql   # Sections 1-4 (single session)
```

> Section 5 (concurrency anomalies) needs **two terminals**; its commands are given as `[A]`/`[B]`-labelled comments in the script and run interactively, interleaved in the order shown. `--force` keeps the script running after the **intentional** constraint violation in Section 3. Outputs were captured on **MySQL 8.0.46**.

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{1. Theory}}$

### 1.1 The ACID Transaction Model

| Statement | Effect |
|---|---|
| `START TRANSACTION` / `BEGIN` | Opens a transaction; subsequent statements are not permanent until `COMMIT` |
| `COMMIT` | Makes every change in the transaction permanent and visible to others |
| `ROLLBACK` | Undoes every change made since the transaction started |
| `SAVEPOINT name` | Marks a point inside the transaction to which it can later be partially undone |
| `ROLLBACK TO SAVEPOINT name` | Undoes only the changes made **after** that savepoint; the transaction stays open |
| `RELEASE SAVEPOINT name` | Forgets the savepoint (its changes are kept); does not end the transaction |

**Atomicity** means a transaction's statements succeed or fail **as a unit**. MySQL does **not** automatically roll back a whole transaction just because one statement inside it errors (unless the storage engine itself deadlocks or the server forces it) — it is the **application's** job to catch the error and issue `ROLLBACK`. This is exactly what Section 3 below demonstrates.

### 1.2 Isolation Levels and the Anomalies They Allow

InnoDB supports four SQL-standard isolation levels, set with `SET SESSION TRANSACTION ISOLATION LEVEL …`:

| Level | Dirty Read | Non-repeatable Read | Phantom Read |
|---|:---:|:---:|:---:|
| `READ UNCOMMITTED` | Possible | Possible | Possible |
| `READ COMMITTED` | Prevented | Possible | Possible |
| `REPEATABLE READ` *(InnoDB default)* | Prevented | Prevented | **Prevented by MVCC**\* |
| `SERIALIZABLE` | Prevented | Prevented | Prevented |

\* InnoDB's `REPEATABLE READ` prevents phantoms for plain (consistent, snapshot) reads via **MVCC**, which is stricter than the SQL standard requires at this level. (Locking reads such as `SELECT … FOR UPDATE` use gap locks instead, which is a different mechanism not used in this experiment.)

| Anomaly | Definition |
|---|---|
| **Dirty read** | Reading another transaction's **uncommitted** change |
| **Non-repeatable read** | Re-reading the same row twice in one transaction and getting **different** values, because another transaction committed a change in between |
| **Phantom read** | Re-running the same range query twice in one transaction and getting a **different set of rows**, because another transaction committed an insert/delete in between |

```mermaid
sequenceDiagram
    participant A as Session A
    participant B as Session B
    Note over A,B: Dirty Read (READ UNCOMMITTED)
    B->>B: START TRANSACTION; UPDATE balance -15000
    A->>A: SELECT balance  --> sees -15000 (dirty!)
    B->>B: ROLLBACK
    A->>A: SELECT balance  --> back to original
```

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{2. Schema}}$

```sql
CREATE TABLE account (
    account_id   INT PRIMARY KEY,
    owner_name   VARCHAR(60) NOT NULL,
    account_type ENUM('SAVINGS','CURRENT') NOT NULL,
    balance      DECIMAL(12,2) NOT NULL CHECK (balance >= 0)
) ENGINE = InnoDB;

CREATE TABLE transaction_log (
    txn_id      INT AUTO_INCREMENT PRIMARY KEY,
    from_acct   INT, to_acct INT, amount DECIMAL(12,2) NOT NULL,
    status      ENUM('SUCCESS','FAILED') NOT NULL,
    logged_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;
```

| account_id | owner_name | account_type | balance (opening) |
|---|---|---|---:|
| 1001 | Ravi Kumar | SAVINGS | 50,000.00 |
| 1002 | Sunita Agarwal | SAVINGS | 30,000.00 |
| 1003 | Imran Qureshi | CURRENT | 120,000.00 |
| 1004 | Lakshmi Narayanan | SAVINGS | 8,000.00 |
| 1005 | Harpreet Singh | CURRENT | 25,000.00 |

The `CHECK (balance >= 0)` constraint is the safety net used in Section 3 to simulate a failure.

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{3. A Successful Transfer: BEGIN ... COMMIT}}$

```sql
START TRANSACTION;
UPDATE account SET balance = balance - 10000 WHERE account_id = 1001;
UPDATE account SET balance = balance + 10000 WHERE account_id = 1002;
INSERT INTO transaction_log (from_acct, to_acct, amount, status) VALUES (1001, 1002, 10000, 'SUCCESS');
COMMIT;

SELECT account_id, owner_name, balance FROM account WHERE account_id IN (1001,1002);
```

**Output:**

```
+------------+----------------+----------+
| account_id | owner_name     | balance  |
+------------+----------------+----------+
|       1001 | Ravi Kumar     | 40000.00 |
|       1002 | Sunita Agarwal | 40000.00 |
+------------+----------------+----------+
```

> [!TIP]
> **Observation:** Both updates and the log entry became permanent together, exactly once, with `COMMIT`.

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{4. SAVEPOINT: Undoing Only One Leg of a Multi-Leg Transfer}}$

Harpreet (1005) makes two payments in **one transaction**: 5,000 to Lakshmi (fine), then an attempted 20,000 to account `9999`, which does not exist. Rather than aborting the whole transaction, only the second leg is rolled back to its savepoint:

```sql
START TRANSACTION;

SAVEPOINT before_leg1;
UPDATE account SET balance = balance - 5000 WHERE account_id = 1005;
UPDATE account SET balance = balance + 5000 WHERE account_id = 1004;
INSERT INTO transaction_log (from_acct, to_acct, amount, status) VALUES (1005, 1004, 5000, 'SUCCESS');
RELEASE SAVEPOINT before_leg1;                      -- leg 1 is fine, keep it

SAVEPOINT before_leg2;
UPDATE account SET balance = balance - 20000 WHERE account_id = 1005;
INSERT INTO transaction_log (from_acct, to_acct, amount, status)
SELECT 1005, 9999, 20000, 'FAILED' WHERE NOT EXISTS (SELECT 1 FROM account WHERE account_id = 9999);
ROLLBACK TO SAVEPOINT before_leg2;                  -- leg 2's debit AND its log row are undone

COMMIT;

SELECT account_id, owner_name, balance FROM account WHERE account_id IN (1004,1005);
SELECT txn_id, from_acct, to_acct, amount, status FROM transaction_log ORDER BY txn_id;
```

**Output:**

```
+------------+-------------------+----------+
| account_id | owner_name        | balance  |
+------------+-------------------+----------+
|       1004 | Lakshmi Narayanan |  13000.00 |
|       1005 | Harpreet Singh    |  20000.00 |
+------------+-------------------+----------+

+--------+-----------+---------+----------+---------+
| txn_id | from_acct | to_acct | amount   | status  |
+--------+-----------+---------+----------+---------+
|      1 |      1001 |    1002 | 10000.00 | SUCCESS |
|      2 |      1005 |    1004 |  5000.00 | SUCCESS |
+--------+-----------+---------+----------+---------+
```

> [!TIP]
> **Observation:** Harpreet's balance is 20,000 (25,000 − 5,000; the 20,000 debit for leg 2 was undone). Lakshmi's successful 5,000 credit is kept. The log has only **2** rows — `ROLLBACK TO SAVEPOINT` undid leg 2's debit **and** its own `FAILED` log insert, because that insert happened after `before_leg2`. A savepoint rolls back everything after it, including writes to other tables.

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{5. Partial Failure Without a Savepoint: the Whole Transaction Rolls Back}}$

Lakshmi now has 13,000. Attempt to credit Imran by 2,000 **and** overdraw Lakshmi by 50,000 in the same transaction — the second statement violates `CHECK (balance >= 0)`:

```sql
START TRANSACTION;
UPDATE account SET balance = balance + 2000 WHERE account_id = 1003;    -- would succeed in isolation
UPDATE account SET balance = balance - 50000 WHERE account_id = 1004;   -- violates balance >= 0
ROLLBACK;   -- the application catches the error and issues this explicitly

SELECT account_id, owner_name, balance FROM account WHERE account_id IN (1003,1004);
```

**Output:**

```
mysql> UPDATE account SET balance = balance - 50000 WHERE account_id = 1004;
ERROR 3819 (HY000): Check constraint 'account_chk_1' is violated.

+------------+-------------------+-----------+
| account_id | owner_name        | balance   |
+------------+-------------------+-----------+
|       1003 | Imran Qureshi     | 120000.00 |
|       1004 | Lakshmi Narayanan |  13000.00 |
+------------+-------------------+-----------+
```

> [!CAUTION]
> **Observation:** MySQL did **not** auto-rollback the transaction after the `CHECK` violation — the first `UPDATE` (Imran +2,000) stayed **pending** inside the open transaction until the explicit `ROLLBACK` undid it too. Both balances ended up unchanged, proving atomicity — but only because the application correctly reacted to the error with `ROLLBACK`. A client that ignored the error and called `COMMIT` instead would have committed Imran's half of a broken transfer.

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{6. Isolation Levels and Concurrency Anomalies (Two Sessions)}}$

Each demo opens **Session A** and **Session B** as two separate `mysql bank_db` clients and interleaves their statements in the numbered order.

### 6.1 Dirty Read (`READ UNCOMMITTED`)

| Step | Session | Statement | Result |
|:---:|:---:|---|---|
| 1 | A, B | `SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;` | |
| 2 | B | `START TRANSACTION;` | |
| 3 | B | `UPDATE account SET balance = balance - 15000 WHERE account_id = 1001;` | (uncommitted) |
| 4 | A | `START TRANSACTION;` | |
| 5 | A | `SELECT account_id, balance FROM account WHERE account_id = 1001;` | **`25000.00`** |
| 6 | B | `ROLLBACK;` | |
| 7 | A | `SELECT account_id, balance FROM account WHERE account_id = 1001;` | `40000.00` |
| 8 | A | `COMMIT;` | |

**Captured output (steps 5 and 7):**

```
mysql[A]> SELECT account_id, balance FROM account WHERE account_id = 1001;
+------------+----------+
| account_id | balance  |
+------------+----------+
|       1001 | 25000.00 |
+------------+----------+

-- (Session B then ROLLBACK;)

mysql[A]> SELECT account_id, balance FROM account WHERE account_id = 1001;
+------------+----------+
| account_id | balance  |
+------------+----------+
|       1001 | 40000.00 |
+------------+----------+
```

> [!CAUTION]
> **Observation:** A read B's **uncommitted** 15,000 debit (25,000.00) at step 5. When B rolled back at step 6, that debit never happened — A had read a value that **never existed permanently**. This is a classic **dirty read**, possible only under `READ UNCOMMITTED`.

### 6.2 Non-repeatable Read (`READ COMMITTED`, then prevented by `REPEATABLE READ`)

```
mysql[A]> SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
mysql[A]> START TRANSACTION;
mysql[A]> SELECT account_id, balance FROM account WHERE account_id = 1002;
+------------+----------+
| account_id | balance  |
+------------+----------+
|       1002 | 40000.00 |
+------------+----------+

mysql[B]> START TRANSACTION;
mysql[B]> UPDATE account SET balance = balance + 5000 WHERE account_id = 1002;
mysql[B]> COMMIT;

mysql[A]> SELECT account_id, balance FROM account WHERE account_id = 1002;
+------------+----------+
| account_id | balance  |
+------------+----------+
|       1002 | 45000.00 |
+------------+----------+
mysql[A]> COMMIT;
```

> [!CAUTION]
> **Observation:** The **same** query, re-run inside the same still-open transaction A, returned **two different values** (40000 → 45000) because B committed in between. This is a **non-repeatable read**.

Repeating the scenario under `REPEATABLE READ` (account 1003) shows the anomaly **prevented**:

```
mysql[A]> SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
mysql[A]> START TRANSACTION;
mysql[A]> SELECT account_id, balance FROM account WHERE account_id = 1003;
+------------+-----------+
| account_id | balance   |
+------------+-----------+
|       1003 | 120000.00 |
+------------+-----------+

mysql[B]> START TRANSACTION;
mysql[B]> UPDATE account SET balance = balance + 2000 WHERE account_id = 1003;
mysql[B]> COMMIT;

mysql[A]> SELECT account_id, balance FROM account WHERE account_id = 1003;   -- same transaction, re-read
+------------+-----------+
| account_id | balance   |
+------------+-----------+
|       1003 | 120000.00 |
+------------+-----------+
mysql[A]> COMMIT;
mysql[A]> SELECT account_id, balance FROM account WHERE account_id = 1003;   -- new transaction
+------------+-----------+
| account_id | balance   |
+------------+-----------+
|       1003 | 122000.00 |
+------------+-----------+
```

> [!TIP]
> **Observation:** Under `REPEATABLE READ`, A's **consistent snapshot** (taken at its first read) kept returning `120000.00` even after B committed +2,000 — the non-repeatable read is **prevented**. Only after A's own `COMMIT` (ending its snapshot) does a fresh query see `122000.00`.

### 6.3 Phantom Read (`READ COMMITTED` vs `REPEATABLE READ`)

```
mysql[A]> SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
mysql[A]> START TRANSACTION;
mysql[A]> SELECT COUNT(*) AS savings_accounts FROM account WHERE account_type = 'SAVINGS';
+------------------+
| savings_accounts |
+------------------+
|                3 |
+------------------+

mysql[B]> START TRANSACTION;
mysql[B]> INSERT INTO account VALUES (1006, 'Test Phantom RC', 'SAVINGS', 10000.00);
mysql[B]> COMMIT;

mysql[A]> SELECT COUNT(*) AS savings_accounts FROM account WHERE account_type = 'SAVINGS';
+------------------+
| savings_accounts |
+------------------+
|                4 |
+------------------+
mysql[A]> COMMIT;
```

> [!CAUTION]
> **Observation:** The same range query returned **3, then 4** inside the same transaction — B's committed `INSERT` appeared mid-transaction. This is a **phantom read**, possible under `READ COMMITTED`.

Repeated under `REPEATABLE READ`:

```
mysql[A]> SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
mysql[A]> START TRANSACTION;
mysql[A]> SELECT COUNT(*) AS savings_accounts FROM account WHERE account_type = 'SAVINGS';
+------------------+
| savings_accounts |
+------------------+
|                4 |
+------------------+

mysql[B]> START TRANSACTION;
mysql[B]> INSERT INTO account VALUES (1007, 'Test Phantom RR', 'SAVINGS', 5000.00);
mysql[B]> COMMIT;

mysql[A]> SELECT COUNT(*) AS savings_accounts FROM account WHERE account_type = 'SAVINGS';   -- same transaction
+------------------+
| savings_accounts |
+------------------+
|                4 |
+------------------+
mysql[A]> COMMIT;
mysql[A]> SELECT COUNT(*) AS savings_accounts FROM account WHERE account_type = 'SAVINGS';   -- new transaction
+------------------+
| savings_accounts |
+------------------+
|                5 |
+------------------+
```

> [!TIP]
> **Observation:** Under `REPEATABLE READ`, the count stayed at **4** throughout A's transaction despite B's committed insert — InnoDB's MVCC snapshot prevents the phantom for this plain (non-locking) read. The 5th row becomes visible only in a **new** transaction, after A commits.

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{7. Summary}}$

| # | Demonstration | Mechanism | Result |
|---|---|---|---|
| 1 | Plain transfer | `BEGIN … COMMIT` | $\color{#2A9D8F}{\checkmark}$ Atomic, permanent |
| 2 | Multi-leg transfer, one leg invalid | `SAVEPOINT` / `ROLLBACK TO SAVEPOINT` | $\color{#2A9D8F}{\checkmark}$ Only the bad leg undone |
| 3 | `CHECK` violation mid-transaction | Explicit `ROLLBACK` after the error | $\color{#2A9D8F}{\checkmark}$ Whole transaction undone |
| 4 | Dirty read | `READ UNCOMMITTED` | $\color{#2A9D8F}{\checkmark}$ Reproduced, then gone after B's rollback |
| 5 | Non-repeatable read | `READ COMMITTED` vs `REPEATABLE READ` | $\color{#2A9D8F}{\checkmark}$ Reproduced, then prevented |
| 6 | Phantom read | `READ COMMITTED` vs `REPEATABLE READ` | $\color{#2A9D8F}{\checkmark}$ Reproduced, then prevented |

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

## $\color{#E63946}{\textsf{Result}}$

> [!IMPORTANT]
> **Result**
>
> Banking-style transactions were implemented with `BEGIN`/`START TRANSACTION`, `COMMIT`, `ROLLBACK` and `SAVEPOINT` on an InnoDB `account` table. A **partial failure** was simulated two ways: a `SAVEPOINT`-scoped rollback that undid only a failed leg of a multi-part transfer, and a `CHECK`-constraint violation that required an **explicit** `ROLLBACK` to undo the whole transaction, since MySQL does not do this automatically.
>
> Using **two sessions**, all three classic concurrency anomalies were reproduced and then prevented by raising the isolation level: **dirty reads** (`READ UNCOMMITTED` → prevented from `READ COMMITTED` up), **non-repeatable reads** (`READ COMMITTED` → prevented by `REPEATABLE READ`), and **phantom reads** (`READ COMMITTED` → prevented by `REPEATABLE READ`'s MVCC snapshot).

<img src="assets/rule-8.svg" width="100%" height="8" alt=""/>

<div align="center">

<a href="Exp_7.md"><img src="https://img.shields.io/badge/Previous-Experiment%207-3D405B?style=for-the-badge" alt="Previous"/></a> <a href="README.md"><img src="https://img.shields.io/badge/Back%20to-Index-3D405B?style=for-the-badge" alt="Index"/></a> <a href="Exp_9.md"><img src="https://img.shields.io/badge/Next-Experiment%209-1D3557?style=for-the-badge" alt="Next"/></a>

<sub>Iqra Khan · UID 25LBCS3306 · Experiment 08</sub>

</div>
