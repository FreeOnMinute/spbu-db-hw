-- Тема практики: Транзакции

------------------------------------------------------------
-- 0) Подготовка
------------------------------------------------------------

SET search_path TO university, public;

-- Проверка данных
SELECT 'students' AS t, COUNT(*) FROM students UNION ALL
SELECT 'courses', COUNT(*) FROM courses UNION ALL
SELECT 'enrollments', COUNT(*) FROM enrollments;

------------------------------------------------------------
-- 1) ТРАНЗАКЦИИ: базовые операции (BEGIN/COMMIT/ROLLBACK)
------------------------------------------------------------

-- Чтобы не портить учебные таблицы, создадим отдельную мини-таблицу "счета"
-- в схеме university. Она нужна только для демонстрации транзакций.
DROP TABLE IF EXISTS tx_accounts;
CREATE TABLE tx_accounts (
    account_id   INT PRIMARY KEY,
    owner_name   TEXT NOT NULL,
    balance      NUMERIC(12,2) NOT NULL CHECK (balance >= 0),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Заполним начальными данными
INSERT INTO tx_accounts (account_id, owner_name, balance) VALUES
(1, 'Alice', 1000.00),
(2, 'Bob',    250.00),
(3, 'Carol',  500.00);

SELECT * FROM tx_accounts ORDER BY account_id;

-- 1.1. Пример ROLLBACK: изменения откатываются целиком
BEGIN;
    UPDATE tx_accounts SET balance = balance + 100 WHERE account_id = 1;
    UPDATE tx_accounts SET balance = balance - 100 WHERE account_id = 2;
    SELECT * FROM tx_accounts ORDER BY account_id;  -- внутри транзакции вы увидите изменения
ROLLBACK;

-- Проверка: ничего не изменилось
SELECT * FROM tx_accounts ORDER BY account_id;

-- 1.2. Пример COMMIT: изменения фиксируются
BEGIN;
    UPDATE tx_accounts SET balance = balance + 50 WHERE account_id = 1;
    UPDATE tx_accounts SET balance = balance - 50 WHERE account_id = 3;
COMMIT;

SELECT * FROM tx_accounts ORDER BY account_id;
------------------------------------------------------------
-- 2) АТОМАРНОСТЬ и ОГРАНИЧЕНИЯ: "или всё, или ничего"
------------------------------------------------------------

-- 2.1. Попытка сделать перевод, который приведёт к отрицательному балансу.
-- Из-за CHECK(balance >= 0) транзакция должна завершиться ошибкой.
BEGIN;
    -- Снимем слишком много со счета Bob (account_id=2)
    UPDATE tx_accounts SET balance = balance - 100000 WHERE account_id = 2;
    -- Даже если следующая команда "успешная", из-за ошибки будет откат
    UPDATE tx_accounts SET balance = balance + 100000 WHERE account_id = 1;
COMMIT; -- эта строка обычно не выполнится из-за ошибки (или транзакция станет "aborted")

-- После ошибки: транзакция "сломана" до ROLLBACK
ROLLBACK;

-- Проверка: балансы остались прежними
SELECT * FROM tx_accounts ORDER BY account_id;

------------------------------------------------------------
-- 3) SAVEPOINT: частичный откат внутри транзакции
------------------------------------------------------------

BEGIN;
    UPDATE tx_accounts SET balance = balance + 10 WHERE account_id = 1;

    SAVEPOINT sp1;  -- точка сохранения

    UPDATE tx_accounts SET balance = balance + 9999 WHERE account_id = 2;
    SELECT * FROM tx_accounts ORDER BY account_id;

    -- Откатываем только часть (до savepoint), а не всю транзакцию:
    ROLLBACK TO SAVEPOINT sp1;

    -- После отката к sp1 изменения со счетом 2 должны исчезнуть,
    -- а изменения до SAVEPOINT (по account_id=1) остаться.
    SELECT * FROM tx_accounts ORDER BY account_id;

COMMIT;

SELECT * FROM tx_accounts ORDER BY account_id;

------------------------------------------------------------
-- 4) ИЗОЛЯЦИЯ ТРАНЗАКЦИЙ и MVCC: READ COMMITTED vs REPEATABLE READ
-- Для этого блока откройте ДВА окна:
--   Console A и Console B
------------------------------------------------------------

-- Подготовим таблицу для демонстрации
DROP TABLE IF EXISTS tx_demo;
CREATE TABLE tx_demo (
    id   SERIAL PRIMARY KEY,
    note TEXT NOT NULL
);

TRUNCATE tx_demo;
INSERT INTO tx_demo(note) VALUES ('row1'), ('row2'), ('row3');

SELECT * FROM tx_demo ORDER BY id;

-- 4.1. READ COMMITTED (по умолчанию): каждый SELECT видит "самую свежую" фиксированную версию
-- ===== Console A =====
-- BEGIN;
-- SHOW transaction_isolation;  -- должно быть read committed (если не меняли)
-- SELECT COUNT(*) FROM tx_demo; -- запомните число (например 3)
--
-- ===== Console B =====
-- BEGIN;
-- INSERT INTO tx_demo(note) VALUES ('row_from_B');
-- COMMIT;
--
-- ===== Console A =====
-- SELECT COUNT(*) FROM tx_demo; -- число может стать 4 (фантом в рамках транзакции)
-- COMMIT;

-- 4.2. REPEATABLE READ: транзакция видит "снимок" на момент начала
-- ===== Console A =====
-- BEGIN ISOLATION LEVEL REPEATABLE READ;
-- SELECT COUNT(*) FROM tx_demo; -- например 4
--
-- ===== Console B =====
-- INSERT INTO tx_demo(note) VALUES ('another_row_from_B');
-- COMMIT;
--
-- ===== Console A =====
-- SELECT COUNT(*) FROM tx_demo; -- останется 4 (снимок), хотя в БД уже 5
-- COMMIT;

------------------------------------------------------------
-- 5) БЛОКИРОВКИ: SELECT ... FOR UPDATE и наблюдение за блокировками
-- Для этого блока снова откройте ДВА окна: Console A и Console B
------------------------------------------------------------

-- 5.1. В Console A заблокируем строку и "подержим" её, чтобы увидеть блокировку
-- ===== Console A =====
-- BEGIN;
-- SELECT * FROM tx_accounts WHERE account_id = 1 FOR UPDATE;
-- -- не коммитьте сразу, оставьте транзакцию открытой
--
-- ===== Console B =====
-- -- Эта команда будет ждать освобождения блокировки (пока A не COMMIT/ROLLBACK):
-- UPDATE tx_accounts SET balance = balance + 1 WHERE account_id = 1;
--
-- ===== Console A =====
-- -- В этот момент посмотрите, кто кого блокирует:
-- SELECT
--   a.pid,
--   a.state,
--   a.wait_event_type,
--   a.wait_event,
--   a.query
-- FROM pg_stat_activity a
-- WHERE a.datname = current_database()
-- ORDER BY a.pid;
--
-- -- Посмотреть locks (кто держит, кто ждёт):
-- SELECT
--   l.pid,
--   l.locktype,
--   l.mode,
--   l.granted,
--   a.query
-- FROM pg_locks l
-- JOIN pg_stat_activity a ON a.pid = l.pid
-- WHERE a.datname = current_database()
-- ORDER BY l.granted DESC, l.pid;
--
-- ===== Console A =====
-- COMMIT;  -- после коммита UPDATE в B продолжится

------------------------------------------------------------
-- 6) SERIALIZABLE и ошибки сериализации
-- Идея: две транзакции принимают решения на основе прочитанного состояния.
-- В SERIALIZABLE одна из них может упасть с ошибкой "could not serialize access..."
------------------------------------------------------------

DROP TABLE IF EXISTS tx_budget;
CREATE TABLE tx_budget (
    id INT PRIMARY KEY,
    limit_total NUMERIC(12,2) NOT NULL
);

INSERT INTO tx_budget (id, limit_total) VALUES (1, 100.00)
ON CONFLICT (id) DO UPDATE SET limit_total = EXCLUDED.limit_total;

-- ===== Console A =====
-- BEGIN ISOLATION LEVEL SERIALIZABLE;
-- SELECT limit_total FROM tx_budget WHERE id=1;  -- прочитали 100
--
-- ===== Console B =====
-- BEGIN ISOLATION LEVEL SERIALIZABLE;
-- SELECT limit_total FROM tx_budget WHERE id=1;  -- тоже прочитали 100
--
-- ===== Console A =====
-- UPDATE tx_budget SET limit_total = limit_total - 60 WHERE id=1;
-- COMMIT;
--
-- ===== Console B =====
-- UPDATE tx_budget SET limit_total = limit_total - 60 WHERE id=1;
-- COMMIT;  -- может упасть с ошибкой сериализации
--
-- Если упало: сделайте ROLLBACK в Console B и повторите транзакцию заново.

------------------------------------------------------------
-- Домашнее задание
------------------------------------------------------------

-- ЗАДАНИЕ 1 (транзакции):
-- Реализуйте "перевод денег" между счетами tx_accounts:
--   - списать со счета 1 сумму 200
--   - зачислить на счет 2 сумму 200
--   - если на счете 1 недостаточно средств — откатить
-- Подсказка: SELECT ... FOR UPDATE + проверка + UPDATE + COMMIT/ROLLBACK.
BEGIN;

SELECT balance FROM tx_accounts WHERE account_id = 1 FOR UPDATE;

UPDATE tx_accounts
SET balance = balance - 200, updated_at = now()
WHERE account_id = 1 AND balance >= 200;

UPDATE tx_accounts
SET balance = balance + 200, updated_at = now()
WHERE account_id = 2;

COMMIT;

SELECT * FROM tx_accounts ORDER BY account_id;
-- ЗАДАНИЕ 2 (savepoint):
-- В одной транзакции:
--   - обновить Alice (+10)
--   - SAVEPOINT
--   - сделать действие, которое нарушит CHECK
--   - откатиться к SAVEPOINT и завершить COMMIT.
BEGIN;

UPDATE tx_accounts SET balance = balance + 10, updated_at = now() WHERE account_id = 1;
SAVEPOINT sp1;

UPDATE tx_accounts
SET balance = balance - 9999, updated_at = now()
WHERE account_id = 2 AND balance >= 9999;
ROLLBACK TO SAVEPOINT sp1;

COMMIT;

SELECT * FROM tx_accounts ORDER BY account_id;
-- ЗАДАНИЕ 3 (изоляция):
-- В 2 консолях сравните READ COMMITTED и REPEATABLE READ на tx_demo и сформулируйте вывод.

-- READ COMMITTED:
-- Видит зафиксированные изменения других транзакций
-- SELECT COUNT(*) дал разный результат (3 → 4) — фантомное чтение

-- REPEATABLE READ:
-- Работает со снимком на момент начала транзакции
-- SELECT COUNT(*) дал одинаковый результат (4 → 4) — фантомов нет