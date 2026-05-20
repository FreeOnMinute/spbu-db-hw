-- Тема практики: Виртуализация в PostgreSQL (CTE, VIEW, TEMP + сравнение VIEW vs MATERIALIZED VIEW)

----------------------------------------------------------------------
-- 0) Подготовка: выбор схемы
----------------------------------------------------------------------

-- Ставим схему по умолчанию (если ваши таблицы в схеме university)
SET search_path TO university, public;

-- Быстрая проверка, что таблицы есть и данные загружены
SELECT 'departments'  AS t, COUNT(*) AS cnt FROM departments  UNION ALL
SELECT 'instructors'  AS t, COUNT(*) AS cnt FROM instructors  UNION ALL
SELECT 'students'     AS t, COUNT(*) AS cnt FROM students     UNION ALL
SELECT 'courses'      AS t, COUNT(*) AS cnt FROM courses      UNION ALL
SELECT 'enrollments'  AS t, COUNT(*) AS cnt FROM enrollments;

-- Посмотреть структуру (в DataGrip можно открыть DDL), но через SQL тоже можно:
-- Колонки students
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='university' AND table_name='students'
ORDER BY ordinal_position
LIMIT 100;

----------------------------------------------------------------------
-- 1) CTE (WITH): виртуальная таблица внутри ОДНОГО запроса
--    CTE помогает:
--    - сделать сложный запрос читабельным
--    - убрать повторение одной и той же агрегации
--    - подготовить "ступени" вычислений
----------------------------------------------------------------------

-- 1.1. Базовый CTE:
-- Сильные студенты + статистика по их кафедрам
WITH strong_students AS (
    SELECT student_id, major_department_id, gpa
    FROM students
    WHERE gpa >= 3.5
)
SELECT
    d.name AS department_name,
    COUNT(*) AS strong_count,
    ROUND(AVG(ss.gpa), 2) AS avg_gpa_strong
FROM strong_students ss
JOIN departments d ON d.department_id = ss.major_department_id
GROUP BY d.name
ORDER BY strong_count DESC, department_name
LIMIT 100;

-- 1.2. Последовательныe CTE:
-- Cчитаем популярность курсов, затем берём TOP-10
WITH course_counts AS (
    SELECT course_id, COUNT(*) AS enrollments_count
    FROM enrollments
    GROUP BY course_id
),
top_courses AS (
    SELECT *
    FROM course_counts
    ORDER BY enrollments_count DESC
    LIMIT 10
)
SELECT
    c.code,
    c.title,
    d.name AS department_name,
    t.enrollments_count
FROM top_courses t
JOIN courses c ON c.course_id = t.course_id
JOIN departments d ON d.department_id = c.department_id
ORDER BY t.enrollments_count DESC, c.code
LIMIT 100;

-- 1.3. CTE как "слой подготовки": статистика по студентам, потом JOIN справочников
WITH student_stats AS (
    SELECT
        e.student_id,
        COUNT(*) AS courses_taken,
        ROUND(AVG(e.attendance_percent), 2) AS avg_attendance,
        SUM(CASE WHEN e.is_passed THEN 1 ELSE 0 END) AS passed_count
    FROM enrollments e
    GROUP BY e.student_id
)
SELECT
    s.student_id,
    s.first_name,
    s.last_name,
    d.name AS major_department,
    ss.courses_taken,
    ss.passed_count,
    ss.avg_attendance
FROM student_stats ss
JOIN students s ON s.student_id = ss.student_id
JOIN departments d ON d.department_id = s.major_department_id
WHERE ss.courses_taken >= 5
ORDER BY ss.courses_taken DESC, ss.passed_count DESC, ss.avg_attendance DESC
LIMIT 100;

-- 1.4. CTE + CASE: уровень успеха курса по доле сдавших
WITH course_pass AS (
    SELECT
        course_id,
        COUNT(*) AS total,
        SUM(CASE WHEN is_passed THEN 1 ELSE 0 END) AS passed
    FROM enrollments
    GROUP BY course_id
)
SELECT
    c.code,
    c.title,
    cp.total,
    cp.passed,
    ROUND(100.0 * cp.passed / NULLIF(cp.total,0), 2) AS pass_percent,
    CASE
        WHEN (100.0 * cp.passed / NULLIF(cp.total,0)) >= 80 THEN 'High'
        WHEN (100.0 * cp.passed / NULLIF(cp.total,0)) >= 60 THEN 'Medium'
        ELSE 'Low'
    END AS pass_level
FROM course_pass cp
JOIN courses c ON c.course_id = cp.course_id
ORDER BY pass_percent DESC, cp.total DESC
LIMIT 100;

----------------------------------------------------------------------
-- 3) VIEW: обычное представление (виртуальная таблица, хранит SQL)
-- VIEW:
--   - НЕ хранит данные (в обычном смысле)
--   - при SELECT выполняет запрос заново (использует актуальные данные таблиц)
--   - удобно прятать JOIN'ы и стандартизировать отчёты
----------------------------------------------------------------------

-- 3.1. VIEW: "плоская" витрина зачислений (удобно для выборок)
CREATE OR REPLACE VIEW v_student_course_enrollments AS
SELECT
    e.enrollment_id,
    e.semester,
    e.grade,
    e.attendance_percent,
    e.is_passed,

    s.student_id,
    s.first_name AS student_first_name,
    s.last_name  AS student_last_name,
    s.enrollment_year,
    s.gpa,
    s.is_full_time,

    c.course_id,
    c.code AS course_code,
    c.title AS course_title,
    c.credits,
    c.level AS course_level,

    d.department_id AS course_department_id,
    d.name AS course_department_name
FROM enrollments e
JOIN students s  ON s.student_id = e.student_id
JOIN courses  c  ON c.course_id  = e.course_id
JOIN departments d ON d.department_id = c.department_id
LIMIT 100;

-- Используем VIEW как таблицу
SELECT
    student_id,
    student_first_name,
    student_last_name,
    course_code,
    semester,
    grade,
    attendance_percent
FROM v_student_course_enrollments
WHERE semester = 'Fall 2023'
ORDER BY attendance_percent DESC
LIMIT 20;

-- 3.2. VIEW как "слой отчёта": GPA по major кафедрам
CREATE OR REPLACE VIEW v_major_department_gpa AS
SELECT
    d.department_id,
    d.name AS department_name,
    COUNT(s.student_id) AS students_count,
    ROUND(AVG(s.gpa), 2) AS avg_gpa
FROM departments d
JOIN students s ON s.major_department_id = d.department_id
GROUP BY d.department_id, d.name
LIMIT 100;

SELECT * FROM v_major_department_gpa ORDER BY avg_gpa DESC
LIMIT 100;

-- 3.3. Как посмотреть определение VIEW (для контроля)
SELECT pg_get_viewdef('v_student_course_enrollments'::regclass, true);

----------------------------------------------------------------------
-- 4) TEMP таблицы: временные таблицы (живут в рамках соединения/сессии)
-- TEMP:
--   - удобно "материализовать" промежуточный результат на время работы
--   - можно индексировать
--   - исчезают при переподключении (или ON COMMIT DROP/DELETE ROWS)
----------------------------------------------------------------------

-- 4.1. TEMP таблица топ-студентов (CTAS)
DROP TABLE IF EXISTS tmp_top_students;
CREATE TEMP TABLE tmp_top_students AS
SELECT
    student_id,
    first_name,
    last_name,
    gpa,
    major_department_id
FROM students
WHERE is_full_time = TRUE
ORDER BY gpa DESC
LIMIT 20;

SELECT * FROM tmp_top_students ORDER BY gpa DESC
LIMIT 100;

-- 4.2. Индекс на TEMP
CREATE INDEX tmp_top_students_major_idx ON tmp_top_students (major_department_id);

-- 4.3. Используем TEMP данными в JOIN
SELECT
    t.student_id,
    t.first_name,
    t.last_name,
    t.gpa,
    d.name AS major_department
FROM tmp_top_students t
JOIN departments d ON d.department_id = t.major_department_id
ORDER BY t.gpa DESC
LIMIT 100;

-- 4.4. TEMP таблица как "снимок" популярности курсов по семестрам
DROP TABLE IF EXISTS tmp_course_popularity;
CREATE TEMP TABLE tmp_course_popularity AS
SELECT
    semester,
    course_id,
    COUNT(*) AS enrollments_count
FROM enrollments
GROUP BY semester, course_id
LIMIT 100;

SELECT *
FROM tmp_course_popularity
ORDER BY semester, enrollments_count DESC
LIMIT 20;

----------------------------------------------------------------------
-- 5) MATERIALIZED VIEW: материализованное представление
-- Главное отличие от VIEW:
--
-- VIEW:
--   - хранит только запрос
--   - всегда показывает актуальные данные
--   - каждое обращение к VIEW выполняет запрос (логически)
--
-- MATERIALIZED VIEW:
--   - хранит РЕЗУЛЬТАТ (данные) как таблицу
--   - данные НЕ обновляются автоматически
--   - чтобы обновить: REFRESH MATERIALIZED VIEW
--   - можно создавать индексы на материализованном представлении (важно!)

-- 5.1. Создадим VIEW и MATERIALIZED VIEW для одного и того же отчёта:
-- "популярность курсов" (кол-во зачислений на курс)
CREATE OR REPLACE VIEW v_course_popularity AS
SELECT
    c.course_id,
    c.code,
    c.title,
    COUNT(e.enrollment_id) AS enrollments_count
FROM courses c
JOIN enrollments e ON e.course_id = c.course_id
GROUP BY c.course_id, c.code, c.title;

DROP MATERIALIZED VIEW IF EXISTS mv_course_popularity;
CREATE MATERIALIZED VIEW mv_course_popularity AS
SELECT
    c.course_id,
    c.code,
    c.title,
    COUNT(e.enrollment_id) AS enrollments_count
FROM courses c
JOIN enrollments e ON e.course_id = c.course_id
GROUP BY c.course_id, c.code, c.title;

-- 5.2. Сравним оба объекта (одинаковый результат)
SELECT * FROM v_course_popularity ORDER BY enrollments_count DESC, code LIMIT 10;
SELECT * FROM mv_course_popularity ORDER BY enrollments_count DESC, code LIMIT 10;

-- 5.3. Покажем ключевое отличие: VIEW = "всегда актуально", MV = "заморожено до REFRESH"
-- Сделаем учебную транзакцию: добавим "фиктивное" зачисление (enrollments)
-- ВНИМАНИЕ!!!!: мы сделаем ROLLBACK в конце, чтобы не портить базу.
BEGIN;

-- Выберем существующего студента и курс (просто любые)
-- Здесь мы делаем insert через SELECT, чтобы не гадать id.
INSERT INTO enrollments (enrollment_id, student_id, course_id, semester, grade, attendance_percent, is_passed)
SELECT
    (SELECT COALESCE(MAX(enrollment_id), 0) + 1 FROM enrollments) AS new_enrollment_id,
    (SELECT student_id FROM students ORDER BY student_id LIMIT 1)  AS any_student_id,
    1 AS any_course_id,
    'Fall 2023' AS semester,
    'A' AS grade,
    100.00 AS attendance_percent,
    TRUE AS is_passed;

-- Теперь проверим:
-- VIEW видит изменения сразу (потому что считает по текущим таблицам)
SELECT * FROM v_course_popularity ORDER BY enrollments_count DESC, code LIMIT 10;

-- MATERIALIZED VIEW НЕ изменился (результат материализован ранее)
SELECT * FROM mv_course_popularity ORDER BY enrollments_count DESC, code LIMIT 10;

-- Чтобы MV увидел изменения — его нужно обновить:
REFRESH MATERIALIZED VIEW mv_course_popularity;

-- Теперь MV тоже "подтянул" данные.
SELECT * FROM mv_course_popularity ORDER BY enrollments_count DESC, code LIMIT 10;

-- Откатываем учебную вставку, чтобы вернуть базу как была
ROLLBACK;

-- Важный вывод: после ROLLBACK таблицы вернулись, но MV мы обновляли внутри транзакции.
-- После ROLLBACK и VIEW, и MV снова показывают оригинальные значения.
-- Проверим:
SELECT * FROM v_course_popularity ORDER BY enrollments_count DESC, code LIMIT 5;
SELECT * FROM mv_course_popularity ORDER BY enrollments_count DESC, code LIMIT 5;

-- 5.4. Индексы на MATERIALIZED VIEW (чего нельзя так сделать для обычного view)
CREATE INDEX IF NOT EXISTS mv_course_popularity_cnt_idx ON mv_course_popularity (enrollments_count DESC);

-- 5.5. REFRESH CONCURRENTLY
-- В реальных системах, чтобы не блокировать читателей, используют:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_name;
-- Но для этого нужен уникальный индекс на MV.

----------------------------------------------------------------------
-- 6. Удаление

DROP VIEW IF EXISTS v_student_course_enrollments;
DROP VIEW IF EXISTS v_major_department_gpa;
DROP VIEW IF EXISTS v_course_popularity;
DROP MATERIALIZED VIEW IF EXISTS mv_course_popularity;

----------------------------------------------------------------------

-- ЗАДАНИЕ 1 (CTE):
-- Найдите студентов, у которых средняя посещаемость >= 85 по всем курсам.
-- Выведите: student_id, ФИО, avg_attendance.
WITH avg AS (
    SELECT
        e.student_id,
        AVG(e.attendance_percent) AS avg_attendance
    FROM enrollments e
    GROUP BY e.student_id
)
SELECT
    s.student_id,
    s.first_name,
    s.last_name,
    a.avg_attendance
FROM students s
JOIN avg a ON a.student_id = s.student_id
WHERE a.avg_attendance >= 85;

-- ЗАДАНИЕ 2 (CTE + TOP-N):
-- Выведите TOP-3 кафедры по среднему GPA студентов (major_department),
WITH department_avg_gpa AS (
    SELECT
        s.major_department_id,
        AVG(s.gpa) AS avg_gpa
    FROM students s
    GROUP BY s.major_department_id
)
SELECT
    d.department_id,
    d.name,
    dag.avg_gpa
FROM departments d
JOIN department_avg_gpa dag ON d.department_id = dag.major_department_id
ORDER BY dag.avg_gpa DESC LIMIT 3;

-- ЗАДАНИЕ 3 (VIEW):
-- Создайте VIEW v_instructor_salary_level:
--   salary >= 100000 -> 'high'
--   salary >= 70000  -> 'mid'
--   иначе            -> 'low'
-- Затем посчитайте, сколько преподавателей в каждой категории.

CREATE OR REPLACE VIEW v_instructor_salary_level AS
SELECT
    i.instructor_id,
    CASE
        WHEN i.salary >= 100000 THEN 'high'
        WHEN i.salary >= 70000 THEN 'mid'
        ELSE 'low'
    END AS salary_level
FROM instructors i;

SELECT
    i.instructor_id,
    i.first_name,
    i.last_name,
    visl.salary_level
FROM instructors i
JOIN v_instructor_salary_level visl ON i.instructor_id = visl.instructor_id;

-- ЗАДАНИЕ 4 (TEMP):
-- Создайте TEMP таблицу tmp_failed_enrollments (is_passed = false).
-- Выведите: топ-10 курсов с максимальным числом провалов (id, число провалов).
DROP TABLE IF EXISTS tmp_failed_enrollments;
CREATE TEMP TABLE tmp_failed_enrollments AS
SELECT
    e.course_id,
    COUNT(*) AS failed_enrollments
FROM enrollments e
WHERE is_passed = false
GROUP BY e.course_id;

SELECT
    c.course_id,
    tfe.failed_enrollments
FROM courses c
JOIN tmp_failed_enrollments tfe ON c.course_id = tfe.course_id
ORDER BY tfe.failed_enrollments DESC LIMIT 10;

-- ЗАДАНИЕ 5 (VIEW + CTE):
-- На основе v_student_course_enrollments найдите студентов, у которых >= 2 оценок 'F'.
-- Выведите student_id, ФИО, count_f.

WITH count_F AS (
    SELECT
        s.student_id,
        COUNT(*) AS Fs
    FROM students s
    JOIN v_student_course_enrollments vsce ON vsce.student_id = s.student_id
    WHERE vsce.grade = 'F'
    GROUP BY s.student_id
)
SELECT
    s.student_id,
    s.first_name,
    s.last_name,
    cF.Fs
FROM students s
JOIN count_F cF ON cF.student_id = s.student_id
WHERE cF.Fs >= 2;
