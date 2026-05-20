# Инструкция по импорту университетских датасетов в PostgreSQL

В этом наборе вы получили 5 связанных таблиц в формате CSV:

1. `university_departments.csv` — кафедры/факультеты
2. `university_instructors.csv` — преподаватели
3. `university_students.csv` — студенты
4. `university_courses.csv` — курсы
5. `university_enrollments.csv` — записи о зачислении студентов на курсы

## 1. Создание схемы БД

Подключитесь к PostgreSQL (например, через `psql`) и по желанию создайте отдельную схему:

```sql
CREATE SCHEMA IF NOT EXISTS university;
SET search_path TO university;
```

## 2. Создание таблиц

Создайте таблицы с подходящими типами данных и связями.

```sql
-- 1) Кафедры / факультеты
CREATE TABLE university.departments (
    department_id     INTEGER PRIMARY KEY,
    name              TEXT NOT NULL,
    building          TEXT NOT NULL,
    budget            NUMERIC(12,2) NOT NULL,
    created_at        DATE NOT NULL,
    is_active         BOOLEAN NOT NULL
);

-- 2) Преподаватели
CREATE TABLE university.instructors (
    instructor_id     INTEGER PRIMARY KEY,
    department_id     INTEGER NOT NULL REFERENCES university.departments(department_id),
    first_name        TEXT NOT NULL,
    last_name         TEXT NOT NULL,
    email             TEXT NOT NULL UNIQUE,
    hire_date         DATE NOT NULL,
    position          TEXT NOT NULL,
    salary            NUMERIC(10,2) NOT NULL,
    is_tenured        BOOLEAN NOT NULL
);

-- 3) Студенты
CREATE TABLE university.students (
    student_id        INTEGER PRIMARY KEY,
    first_name        TEXT NOT NULL,
    last_name         TEXT NOT NULL,
    email             TEXT NOT NULL UNIQUE,
    enrollment_year   INTEGER NOT NULL,
    date_of_birth     DATE NOT NULL,
    major_department_id INTEGER NOT NULL REFERENCES university.departments(department_id),
    gpa               NUMERIC(3,2) NOT NULL,
    is_full_time      BOOLEAN NOT NULL,
    created_at        TIMESTAMP NOT NULL
);

-- 4) Курсы
CREATE TABLE university.courses (
    course_id         INTEGER PRIMARY KEY,
    department_id     INTEGER NOT NULL REFERENCES university.departments(department_id),
    code              TEXT NOT NULL,
    title             TEXT NOT NULL,
    credits           INTEGER NOT NULL,
    level             TEXT NOT NULL,
    is_active         BOOLEAN NOT NULL
);

-- 5) Зачисления
CREATE TABLE university.enrollments (
    enrollment_id     INTEGER PRIMARY KEY,
    student_id        INTEGER NOT NULL REFERENCES university.students(student_id),
    course_id         INTEGER NOT NULL REFERENCES university.courses(course_id),
    semester          TEXT NOT NULL,
    grade             TEXT,
    attendance_percent NUMERIC(5,2) NOT NULL,
    is_passed         BOOLEAN NOT NULL
);
```

## 3. Импорт CSV-файлов

Предположим, что вы скачали все файлы в каталог, например:

- Linux/macOS: `/home/username/data/university/`
- Windows: `C:\Users\username\data\university\`

**Важно:** PostgreSQL-сервер должен иметь доступ к этим файлам.  
Поменяйте путь в командах ниже на свой.

```sql
-- 1) Импорт кафедр
COPY university.departments
FROM '/path/to/university_departments.csv'
DELIMITER ',' CSV HEADER ENCODING 'UTF8';

-- 2) Импорт преподавателей
COPY university.instructors
FROM '/path/to/university_instructors.csv'
DELIMITER ',' CSV HEADER ENCODING 'UTF8';

-- 3) Импорт студентов
COPY university.students
FROM '/path/to/university_students.csv'
DELIMITER ',' CSV HEADER ENCODING 'UTF8';

-- 4) Импорт курсов
COPY university.courses
FROM '/path/to/university_courses.csv'
DELIMITER ',' CSV HEADER ENCODING 'UTF8';

-- 5) Импорт зачислений
COPY university.enrollments
FROM '/path/to/university_enrollments.csv'
DELIMITER ',' CSV HEADER ENCODING 'UTF8';
```

Другой вариант, если Вы используете `psql` можно пользоваться клиентской командой `\copy` :

```sql
psql -h localhost -U postgres -d university

\copy university.departments FROM '/path/to/university_departments.csv' DELIMITER ',' CSV HEADER ENCODING 'UTF8';
\copy university.instructors FROM '/path/to/university_instructors.csv' DELIMITER ',' CSV HEADER ENCODING 'UTF8';
\copy university.students FROM '/path/to/university_students.csv' DELIMITER ',' CSV HEADER ENCODING 'UTF8';
\copy university.courses FROM '/path/to/university_courses.csv' DELIMITER ',' CSV HEADER ENCODING 'UTF8';
\copy university.enrollments FROM '/path/to/university_enrollments.csv' DELIMITER ',' CSV HEADER ENCODING 'UTF8';
```

Третий вариант, импорт через эксплорер:

1. Правый клик по таблице → Import Data / Импорт данных.

2. Выбрать CSV-файл (university_courses.csv и т.д.).

3. Указать разделитель `,`, включённый заголовок (HEADER).

4. Сопоставить колонки CSV с колонками таблицы.

6. Запустить импорт.

## 4. Проверка данных

Примеры простых запросов для проверки:

```sql
SELECT * FROM university.departments LIMIT 10;

SELECT d.name AS department, COUNT(*) AS num_instructors
FROM university.departments d
JOIN university.instructors i ON i.department_id = d.department_id
GROUP BY d.name
ORDER BY num_instructors DESC;

SELECT s.first_name, s.last_name, c.code, c.title, e.semester, e.grade
FROM university.enrollments e
JOIN university.students s ON s.student_id = e.student_id
JOIN university.courses c ON c.course_id = e.course_id
LIMIT 20;
```