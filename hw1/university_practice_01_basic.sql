-- Тема практики: ER-диаграммы и базовые запросы.

-- Почему Postgres?
-- Что можно хранить?
-- Как хранится?
-- ER-Диаграммы

------------------------------------------------------------
-- 0. Подготовка: выбор схемы
------------------------------------------------------------

-- Если вы создавали схему `university`, установите её в search_path,
-- чтобы можно было писать имена таблиц без префикса university.
SET search_path TO university, public;

-- 0.1. Вывод схем.
SELECT
    table_name,
    table_type
FROM information_schema.tables
WHERE table_schema = 'university'
ORDER BY table_name;


-- 0.2. Вывод таблиц.
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'university'
  AND table_name   = 'students'
ORDER BY ordinal_position;

-- 0.3. Трассировка EXPLAIN / EXPLAIN ANALYSE.
EXPLAIN SELECT * FROM students;

EXPLAIN ANALYSE SELECT * FROM students;

------------------------------------------------------------
-- 1. Разведка данных
------------------------------------------------------------

-- 1.1. Посмотреть первые строки каждой таблицы.
SELECT * FROM departments   LIMIT 5;
SELECT * FROM instructors   LIMIT 5;
SELECT * FROM students      LIMIT 5;
SELECT * FROM courses       LIMIT 5;
SELECT * FROM enrollments   LIMIT 5;

-- 1.2. Подсчитать количество записей в каждой таблице (без GROUP BY).
SELECT COUNT(*) AS department_count FROM departments;
SELECT COUNT(*) AS instructor_count FROM instructors;
SELECT COUNT(*) AS student_count    FROM students;
SELECT COUNT(*) AS course_count     FROM courses;
SELECT COUNT(*) AS enrollment_count FROM enrollments;

-- COUNT(*) — считает все строки.
-- COUNT(столбец) — считает только строки, где этот столбец НЕ NULL.

------------------------------------------------------------
-- 2. Простые SELECT и выбор нужных столбцов
------------------------------------------------------------

-- 2.1. Вывести только имена и здания кафедр.
SELECT
    name,
    building
FROM departments LIMIT 100;

-- 2.2. Вывести имя, фамилию и зарплату преподавателей.
SELECT
    first_name,
    last_name,
    salary
FROM instructors LIMIT 100;

-- 2.3. Вывести только имя, фамилию и год поступления студентов.
SELECT
    first_name,
    last_name,
    enrollment_year
FROM students LIMIT 100;

------------------------------------------------------------
-- 3. Фильтрация данных (WHERE)
------------------------------------------------------------

-- 3.1. Студенты, которые зачислены после 2020 года.
SELECT
    student_id,
    first_name,
    last_name,
    enrollment_year
FROM students
WHERE enrollment_year > 2020 LIMIT 100;

-- 3.2. Преподаватели с зарплатой больше 80 000.
SELECT
    instructor_id,
    first_name,
    last_name,
    salary
FROM instructors
WHERE salary > 80000 LIMIT 100;

-- 3.3. Курсы уровня 'Master'.
SELECT
    course_id,
    code,
    title,
    level
FROM courses
WHERE level = 'Master' LIMIT 100;

-- 3.4. Студенты с GPA не ниже 3.5.
SELECT
    student_id,
    first_name,
    last_name,
    gpa
FROM students
WHERE gpa >= 3.5 LIMIT 100;

-- 3.5. Примеры с BETWEEN и IN:
-- Студенты с годом поступления с 2019 по 2021 включительно.
SELECT
    student_id,
    first_name,
    last_name,
    enrollment_year
FROM students
WHERE enrollment_year BETWEEN 2019 AND 2021 LIMIT 100;

-- Курсы с количеством кредитов 3 или 4.
SELECT
    course_id,
    code,
    title,
    credits
FROM courses
WHERE credits IN (3, 4) LIMIT 100;

------------------------------------------------------------
-- 4. Сортировка результатов (ORDER BY)
------------------------------------------------------------

-- 4.1. Студенты, отсортированные по году поступления, затем по фамилии.
SELECT
    student_id,
    first_name,
    last_name,
    enrollment_year
FROM students
ORDER BY enrollment_year DESC
LIMIT 100;

-- 4.2. Преподаватели, отсортированные по зарплате по убыванию.
SELECT
    instructor_id,
    first_name,
    last_name,
    salary
FROM instructors
ORDER BY salary DESC
LIMIT 100;

-- 4.3. Курсы, отсортированные сначала по уровню, затем по коду курса.
SELECT
    course_id,
    code,
    title,
    level
FROM courses
ORDER BY level, code
LIMIT 100;

------------------------------------------------------------
-- 5. Миграции / Инструменты
------------------------------------------------------------

-- 5.1. Alembic (revision / upgrade / downgrade)
-- 5.2. Django migrations (makemigrations / migrate)

------------------------------------------------------------
-- 6. Домашнее задание
------------------------------------------------------------

-- ЗАДАНИЕ 1.
-- Найти всех студентов, которые учатся на кафедре 'Computer Science'.
-- Подсказка: нужна связка students + departments.
SELECT
    students.student_id,
    students.first_name,
    students.last_name,
    students.major_department_id
FROM students
WHERE major_department_id = 1;
-- через JOIN
SELECT
    s.student_id,
    s.first_name,
    s.last_name,
    d.name
FROM students s
JOIN departments d ON s.major_department_id = d.department_id
WHERE s.major_department_id = 1;


-- ЗАДАНИЕ 2.
-- Вывести список курсов, которые принадлежат кафедре 'Mathematics',
-- только поле code и title, отсортировать по code.
SELECT
    c.course_id,
    c.code,
    c.title
FROM courses c
WHERE c.department_id = 2
ORDER BY c.code;

-- ЗАДАНИЕ 3.
-- Вывести студентов, у которых GPA < 2.5, отсортировать по GPA по возрастанию.
SELECT
    s.first_name,
    s.last_name,
    s.gpa
FROM students s
WHERE s.gpa < 2.5
ORDER BY s.gpa;

-- ЗАДАНИЕ 4.
-- Сделать запрос, который покажет:
--   имя студента, фамилию, семестр и код курса,
--   только для зачислений, где есть оценка (grade не пустой).
SELECT
    s.first_name,
    s.last_name,
    e.semester,
    c.code,
    e.grade
FROM students s
JOIN enrollments e ON s.student_id = e.student_id
JOIN courses c ON e.course_id = c.course_id
WHERE e.grade IS NOT NULL;
-- ЗАДАНИЕ 5.
-- Вывести 10 студентов с самым высоким GPA (TOP-10).
SELECT
    s.first_name,
    s.last_name,
    s.gpa
FROM students s
ORDER BY s.gpa DESC LIMIT 10;