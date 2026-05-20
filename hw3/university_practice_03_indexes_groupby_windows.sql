-- Тема практики: Индексы + Группировки + Оконные функции

------------------------------------------------------------
-- 0) Подготовка
------------------------------------------------------------

SET search_path TO university, public;

-- Быстрая проверка, что данные есть
SELECT 'departments' AS t, COUNT(*) FROM departments UNION ALL
SELECT 'instructors', COUNT(*) FROM instructors UNION ALL
SELECT 'students',    COUNT(*) FROM students UNION ALL
SELECT 'courses',     COUNT(*) FROM courses UNION ALL
SELECT 'enrollments', COUNT(*) FROM enrollments;

------------------------------------------------------------
-- 1) Группировка
------------------------------------------------------------

-- 1.1. Количество студентов по кафедрам
SELECT
    d.name AS department_name,
    COUNT(*) AS students_count,
    ROUND(AVG(s.gpa), 2) AS avg_gpa
FROM students s
JOIN departments d ON d.department_id = s.major_department_id
GROUP BY d.name
ORDER BY students_count DESC, department_name;

-- 1.2. Количество курсов и суммарные кредиты по кафедрам
SELECT
    d.name AS department_name,
    COUNT(c.course_id) AS courses_count,
    SUM(c.credits) AS total_credits,
    ROUND(AVG(c.credits), 2) AS avg_credits
FROM departments d
LEFT JOIN courses c ON c.department_id = d.department_id
GROUP BY d.name
ORDER BY courses_count DESC, department_name;

-- 1.3. HAVING: показываем только кафедры, где >= 10 студентов
SELECT
    d.name AS department_name,
    COUNT(*) AS students_count,
    ROUND(AVG(s.gpa), 2) AS avg_gpa
FROM students s
JOIN departments d ON d.department_id = s.major_department_id
GROUP BY d.name
HAVING COUNT(*) >= 10
ORDER BY avg_gpa DESC;

-- 1.4. Агрегаты с FILTER: несколько счётчиков в одном GROUP BY
-- Сколько записей на курс и сколько успешных/неуспешных
SELECT
    c.code,
    c.title,
    COUNT(*) AS total_enrollments,
    COUNT(*) FILTER (WHERE e.is_passed) AS passed_count,
    COUNT(*) FILTER (WHERE NOT e.is_passed) AS failed_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE e.is_passed) / NULLIF(COUNT(*), 0), 2) AS passed_percent
FROM enrollments e
JOIN courses c ON c.course_id = e.course_id
GROUP BY c.code, c.title
ORDER BY passed_percent DESC, total_enrollments DESC;

-- 1.5. По семестрам: сколько зачислений, средняя посещаемость
SELECT
    semester,
    COUNT(*) AS enrollments_count,
    ROUND(AVG(attendance_percent), 2) AS avg_attendance
FROM enrollments
GROUP BY semester
ORDER BY semester;

-- 1.6. GROUPING SETS: статистика по семестрам, по курсам, и общий итог
SELECT
    semester,
    course_id,
    COUNT(*) AS enrollments_count,
    ROUND(AVG(attendance_percent), 2) AS avg_attendance
FROM enrollments
GROUP BY GROUPING SETS (
    (semester),
    (course_id),
    ()
)
ORDER BY semester NULLS LAST, course_id NULLS LAST;

-- 1.7. Сколько оценок не выставлено (grade IS NULL) по семестрам
SELECT
    semester,
    COUNT(*) AS total,
    COUNT(grade) AS with_grade,                   -- считает только НЕ NULL
    COUNT(*) - COUNT(grade) AS without_grade      -- сколько grade = NULL
FROM enrollments
GROUP BY semester
ORDER BY semester;

------------------------------------------------------------
-- 2) Оконные функции
------------------------------------------------------------

-- 2.1. Рейтинг студентов по GPA внутри своей кафедры
SELECT
    d.name AS department_name,
    s.student_id,
    s.first_name,
    s.last_name,
    s.gpa,
    RANK()       OVER (PARTITION BY s.major_department_id ORDER BY s.gpa DESC) AS rnk,
    DENSE_RANK() OVER (PARTITION BY s.major_department_id ORDER BY s.gpa DESC) AS dense_rnk,
    ROW_NUMBER() OVER (PARTITION BY s.major_department_id ORDER BY s.gpa DESC) AS row_num
FROM students s
JOIN departments d ON d.department_id = s.major_department_id
ORDER BY department_name, rnk, s.last_name;

-- 2.2. Top-5 студентов по GPA в каждой кафедре
WITH ranked AS (
    SELECT
        s.*,
        ROW_NUMBER() OVER (PARTITION BY s.major_department_id ORDER BY s.gpa DESC) AS rn
    FROM students s
)
SELECT
    d.name AS department_name,
    r.student_id,
    r.first_name,
    r.last_name,
    r.gpa,
    r.rn
FROM ranked r
JOIN departments d ON d.department_id = r.major_department_id
WHERE r.rn <= 5
ORDER BY department_name, r.rn;

-- 2.3. Средний GPA по кафедре рядом с GPA студента
SELECT
    d.name AS department_name,
    s.student_id,
    s.first_name,
    s.last_name,
    s.gpa,
    ROUND(AVG(s.gpa) OVER (PARTITION BY s.major_department_id), 2) AS dept_avg_gpa,
    ROUND(s.gpa - AVG(s.gpa) OVER (PARTITION BY s.major_department_id), 2) AS delta_from_dept_avg
FROM students s
JOIN departments d ON d.department_id = s.major_department_id
ORDER BY department_name, s.gpa DESC;

-- 2.4. LAG на агрегированных данных: сравниваем среднюю посещаемость по семестрам
WITH sem_att AS (
    SELECT
        semester,
        ROUND(AVG(attendance_percent), 2) AS avg_attendance
    FROM enrollments
    GROUP BY semester
)
SELECT
    semester,
    avg_attendance,
    LAG(avg_attendance)  OVER (ORDER BY semester) AS prev_sem_avg,
    ROUND(avg_attendance - LAG(avg_attendance) OVER (ORDER BY semester), 2) AS diff_from_prev
FROM sem_att
ORDER BY semester;

-- 2.5. Скользящее среднее по семестрам (окно из 3 значений)
WITH sem_att AS (
    SELECT
        semester,
        ROUND(AVG(attendance_percent), 2) AS avg_attendance
    FROM enrollments
    GROUP BY semester
)
SELECT
    semester,
    avg_attendance,
    ROUND(AVG(avg_attendance) OVER (
        ORDER BY semester
        ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
    ), 2) AS moving_avg_3
FROM sem_att
ORDER BY semester;

-- 2.6. Накопительный итог зачислений по семестрам
WITH sem_cnt AS (
    SELECT semester, COUNT(*) AS enrollments_count
    FROM enrollments
    GROUP BY semester
)
SELECT
    semester,
    enrollments_count,
    SUM(enrollments_count) OVER (ORDER BY semester) AS cumulative_enrollments
FROM sem_cnt
ORDER BY semester;

------------------------------------------------------------
-- 3) Индексы + EXPLAIN
------------------------------------------------------------

-- 3.0. Посмотреть индексы в схеме university
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'university'
ORDER BY tablename, indexname;

-- 3.1. План запроса ДО индекса: зачисления конкретного студента
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM enrollments
WHERE student_id = 1;

-- 3.2. Индекс на enrollments(student_id)
CREATE INDEX IF NOT EXISTS enrollments_student_id_idx
ON enrollments (student_id);

-- План ПОСЛЕ индекса
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM enrollments
WHERE student_id = 1;

-- 3.3. Индекс на enrollments(course_id)
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM enrollments
WHERE course_id = 1;

CREATE INDEX IF NOT EXISTS enrollments_course_id_idx
ON enrollments (course_id);

EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM enrollments
WHERE course_id = 1;

-- 3.4. Составной индекс под фильтр "semester + course_id"
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    semester, course_id, COUNT(*) AS cnt
FROM enrollments
WHERE semester = 'Fall 2023'
  AND course_id = 1
GROUP BY semester, course_id;

CREATE INDEX IF NOT EXISTS enrollments_sem_course_idx
ON enrollments (semester, course_id);

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    semester, course_id, COUNT(*) AS cnt
FROM enrollments
WHERE semester = 'Fall 2023'
  AND course_id = 1
GROUP BY semester, course_id;

-- 3.5. Индексы на внешние ключи (на практике полезно в OLTP-системах)
CREATE INDEX IF NOT EXISTS students_major_department_idx
ON students (major_department_id);

CREATE INDEX IF NOT EXISTS instructors_department_idx
ON instructors (department_id);

CREATE INDEX IF NOT EXISTS courses_department_idx
ON courses (department_id);

-- Проверочный JOIN + агрегирование
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    d.name,
    COUNT(*) AS students_count
FROM students s
JOIN departments d ON d.department_id = s.major_department_id
GROUP BY d.name
ORDER BY students_count DESC;

-- 3.6. Частичный индекс (partial): ускоряем поиск только для "провалов"
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM enrollments
WHERE is_passed = FALSE;

CREATE INDEX IF NOT EXISTS enrollments_failed_partial_idx
ON enrollments (course_id, semester)
WHERE is_passed = FALSE;

EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM enrollments
WHERE is_passed = FALSE;

-- 3.7. Индекс по выражению (expression): поиск email без учёта регистра
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM students
WHERE lower(email) = lower('alex.ivanov1@student.university.example');

CREATE INDEX IF NOT EXISTS students_lower_email_idx
ON students (lower(email));

EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM students
WHERE lower(email) = lower('alex.ivanov1@student.university.example');

-- 3.8. Индекс под сортировку (не всегда помогает на маленьких данных, но концепция важна):
EXPLAIN (ANALYZE, BUFFERS)
SELECT student_id, first_name, last_name, gpa
FROM students
ORDER BY gpa DESC
LIMIT 10;

CREATE INDEX IF NOT EXISTS students_gpa_desc_idx
ON students (gpa DESC);

EXPLAIN (ANALYZE, BUFFERS)
SELECT student_id, first_name, last_name, gpa
FROM students
ORDER BY gpa DESC
LIMIT 10;

-- 3.9. Попробовать трюк: отключить Seq Scan, чтобы увидеть, что индекс "может" быть выбран.
-- В реальной жизни так не делают — это только демонстрация.
-- SET enable_seqscan = off;
-- EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM enrollments WHERE student_id = 1;
-- SET enable_seqscan = on;

DROP INDEX IF EXISTS enrollments_student_id_idx;
DROP INDEX IF EXISTS enrollments_course_id_idx;
DROP INDEX IF EXISTS enrollments_sem_course_idx;
DROP INDEX IF EXISTS students_major_department_idx;
DROP INDEX IF EXISTS instructors_department_idx;
DROP INDEX IF EXISTS courses_department_idx;
DROP INDEX IF EXISTS enrollments_failed_partial_idx;
DROP INDEX IF EXISTS students_lower_email_idx;
DROP INDEX IF EXISTS students_gpa_desc_idx;

------------------------------------------------------------

-- ЗАДАНИЕ 1 (GROUP BY + HAVING):
-- Найдите курсы, у которых доля сдавших (is_passed=true) < 60%.
-- Выведите: code, title, total, passed, passed_percent.
SELECT
    c.course_id,
    c.code,
    c.title,
    COUNT(*) AS total,
    COUNT(*) FILTER ( WHERE e.is_passed = true ) AS passed,
    100.0 * COUNT(*) FILTER ( WHERE e.is_passed = true) / COUNT(*) passed_percent
FROM courses c
JOIN enrollments e ON c.course_id = e.course_id
GROUP BY c.course_id
HAVING 100.0 * COUNT(*) FILTER ( WHERE e.is_passed = true) / COUNT(*) < 60

-- ЗАДАНИЕ 2 (WINDOW):
-- Для каждого курса выведите:
--   semester, course_code, enrollments_count,
--   и место курса в семестре (RANK) по числу зачислений.
-- Подсказка: сначала GROUP BY semester, course_id, потом оконная.

SELECT
    e.semester,
    c.code,
    COUNT(*) AS total,
    RANK() OVER (PARTITION BY e.semester ORDER BY COUNT(*) DESC ) AS rnk
FROM enrollments e
JOIN courses c ON c.course_id = e.course_id
GROUP BY e.semester, e.course_id, c.code
ORDER BY rnk

-- ЗАДАНИЕ 3 (WINDOW):
-- Выведите студентов, которые входят в TOP-3 по GPA внутри своей кафедры.
WITH ranked AS (
    SELECT
        s.first_name,
        s.last_name,
        s.gpa,
        d.name AS department,
        RANK() OVER (PARTITION BY s.major_department_id ORDER BY s.gpa DESC) AS rnk
    FROM students s
    JOIN departments d ON s.major_department_id = d.department_id
)
SELECT * FROM ranked WHERE rnk <= 3;
--не фильтрует ECONOMICS

-- ЗАДАНИЕ 4 (INDEX DESIGN):
-- Придумайте индексы для запроса:
--   SELECT * FROM enrollments
--   WHERE semester='Fall 2023' AND is_passed=false
--   ORDER BY course_id;
-- Проверьте EXPLAIN (ANALYZE, BUFFERS) до и после.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM enrollments
WHERE semester = 'Fall 2023' AND is_passed = false
ORDER BY course_id;

CREATE INDEX IF NOT EXISTS index_enrollments_semester_passed_course
ON enrollments (semester, is_passed, course_id);

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM enrollments
WHERE semester = 'Fall 2023' AND is_passed = false
ORDER BY course_id;

DROP INDEX IF EXISTS index_enrollments_semester_passed_course

-- ЗАДАНИЕ 5 (EXPLAIN):
-- Возьмите любой ваш запрос с JOIN + GROUP BY и разберите план:
--   scan (Seq/Index/Bitmap), join (Nested/Hash/Merge), где узкое место.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.course_id,
    c.code,
    c.title,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE e.is_passed = true) AS passed,
    100.0 * COUNT(*) FILTER (WHERE e.is_passed = true) / COUNT(*) AS passed_percent
FROM courses c
JOIN enrollments e ON c.course_id = e.course_id
GROUP BY c.course_id
HAVING 100.0 * COUNT(*) FILTER (WHERE e.is_passed = true) / COUNT(*) < 60;

---Узкое место: Seq Scan on enrollments.
---На больших объёмах — узкое место. Рекомендация: индекс на enrollments(course_id)
---для Index Scan вместо Seq Scan при JOIN, если таблица вырастет.