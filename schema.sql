-- database/schema.sql — модели физикии notary_queue
-- Лоиҳа: веб-иловаи навбати электронӣ барои идораи нотариалӣ
-- СИПД: MariaDB 10.11 / MySQL 8 (InnoDB, utf8mb4)
-- Скрипт такроран иҷрошаванда аст (DROP DATABASE IF EXISTS).

DROP DATABASE IF EXISTS notary_queue;
CREATE DATABASE notary_queue
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE notary_queue;
SET NAMES utf8mb4;

-- ---------------------------------------------------------------
-- 1. Ҷадвалҳои маълумотномавӣ
-- ---------------------------------------------------------------

-- Идораҳои нотариалӣ (шӯъбаҳо). head_employee_id баъд бо ALTER TABLE илова мешавад
CREATE TABLE notary_offices (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name             VARCHAR(150) NOT NULL,
    address          VARCHAR(255) NOT NULL,
    phone            VARCHAR(20)  NULL,
    head_employee_id INT UNSIGNED NULL,
    is_active        TINYINT(1)   NOT NULL DEFAULT 1,
    CONSTRAINT uq_offices_name UNIQUE (name)
) ENGINE=InnoDB;

-- Хидматҳои нотариалӣ (намуди амал)
CREATE TABLE services (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code             VARCHAR(20)   NOT NULL,
    name             VARCHAR(200)  NOT NULL,
    category         ENUM('certification','contracts','inheritance','representation','other') NOT NULL,
    description      VARCHAR(500)  NULL,
    duration_minutes SMALLINT UNSIGNED NOT NULL DEFAULT 15,
    state_fee        DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    ticket_prefix    VARCHAR(3)    NOT NULL,
    is_active        TINYINT(1)    NOT NULL DEFAULT 1,
    CONSTRAINT uq_services_code UNIQUE (code),
    CONSTRAINT uq_services_name UNIQUE (name),
    CONSTRAINT chk_services_duration CHECK (duration_minutes > 0),
    CONSTRAINT chk_services_fee CHECK (state_fee >= 0)
) ENGINE=InnoDB;

-- Рӯзҳои истироҳат ва ид (ҳамаи идораҳо)
CREATE TABLE holidays (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    holiday_date DATE         NOT NULL,
    name         VARCHAR(100) NOT NULL,
    CONSTRAINT uq_holidays_date UNIQUE (holiday_date)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------
-- 2. Идора: ҷадвали корӣ ва равзанаҳо (мизҳои қабул)
-- ---------------------------------------------------------------

-- Ҷадвали корӣ: як сатр барои ҳар рӯзи ҳафта (1 = душанбе ... 7 = якшанбе)
CREATE TABLE work_schedules (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    office_id   INT UNSIGNED NOT NULL,
    weekday     TINYINT UNSIGNED NOT NULL,
    is_day_off  TINYINT(1) NOT NULL DEFAULT 0,
    open_time   TIME NULL,
    close_time  TIME NULL,
    break_start TIME NULL,
    break_end   TIME NULL,
    CONSTRAINT uq_schedule_office_weekday UNIQUE (office_id, weekday),
    CONSTRAINT chk_schedule_weekday CHECK (weekday BETWEEN 1 AND 7),
    CONSTRAINT chk_schedule_times CHECK (
        is_day_off = 1
        OR (open_time IS NOT NULL AND close_time IS NOT NULL AND close_time > open_time)
    ),
    CONSTRAINT fk_schedule_office FOREIGN KEY (office_id)
        REFERENCES notary_offices(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Равзана (мизи қабул) дар идора
CREATE TABLE service_windows (
    id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    office_id INT UNSIGNED NOT NULL,
    number    TINYINT UNSIGNED NOT NULL,
    title     VARCHAR(100) NOT NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    CONSTRAINT uq_windows_office_number UNIQUE (office_id, number),
    CONSTRAINT fk_windows_office FOREIGN KEY (office_id)
        REFERENCES notary_offices(id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Алоқаи M:N — кадом равзана кадом хидматҳоро иҷро мекунад
CREATE TABLE window_services (
    window_id  INT UNSIGNED NOT NULL,
    service_id INT UNSIGNED NOT NULL,
    PRIMARY KEY (window_id, service_id),
    CONSTRAINT fk_ws_window FOREIGN KEY (window_id)
        REFERENCES service_windows(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ws_service FOREIGN KEY (service_id)
        REFERENCES services(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------
-- 3. Кормандон ва корбарони низом
-- ---------------------------------------------------------------

CREATE TABLE employees (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    office_id   INT UNSIGNED NOT NULL,
    last_name   VARCHAR(60)  NOT NULL,
    first_name  VARCHAR(60)  NOT NULL,
    middle_name VARCHAR(60)  NULL,
    position    ENUM('notary','assistant','operator','manager') NOT NULL,
    phone       VARCHAR(20)  NULL,
    email       VARCHAR(120) NULL,
    hire_date   DATE         NOT NULL,
    is_active   TINYINT(1)   NOT NULL DEFAULT 1,
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_employees_email UNIQUE (email),
    CONSTRAINT fk_employees_office FOREIGN KEY (office_id)
        REFERENCES notary_offices(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_employees_last_name (last_name)
) ENGINE=InnoDB;

-- Алоқаи даврӣ: роҳбари идора — корманд.
-- employees пас аз notary_offices сохта мешавад, бинобар ин FK-ро ҷудо илова мекунем.
ALTER TABLE notary_offices
    ADD CONSTRAINT fk_offices_head FOREIGN KEY (head_employee_id)
        REFERENCES employees(id) ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE users (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    employee_id   INT UNSIGNED NULL,
    username      VARCHAR(50)  NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          ENUM('admin','manager','notary','operator') NOT NULL,
    is_active     TINYINT(1)   NOT NULL DEFAULT 1,
    last_login_at DATETIME     NULL,
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_employee UNIQUE (employee_id),
    CONSTRAINT fk_users_employee FOREIGN KEY (employee_id)
        REFERENCES employees(id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------
-- 4. Муроҷиатқунандагон ва навбат
-- ---------------------------------------------------------------

CREATE TABLE clients (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    last_name   VARCHAR(60)  NOT NULL,
    first_name  VARCHAR(60)  NOT NULL,
    middle_name VARCHAR(60)  NULL,
    phone       VARCHAR(20)  NOT NULL,   -- VARCHAR: нишони «+» ва сифрҳо гум намешаванд
    email       VARCHAR(120) NULL,
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_clients_phone UNIQUE (phone),
    INDEX idx_clients_last_name (last_name)
) ENGINE=InnoDB;

-- Қайд дар навбат: ҳам сабти пешакӣ (онлайн), ҳам навбати зинда (киоск/қабулгоҳ)
-- Ҳолатҳо: booked → waiting → called → in_service → completed;
--          cancelled (бекор кардан), no_show (наомадан)
CREATE TABLE appointments (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ticket_number    VARCHAR(10)  NOT NULL,
    public_code      CHAR(10)     NOT NULL,   -- рамзи тасодуфӣ барои пайгирӣ/бекор кардан бо истинод
    office_id        INT UNSIGNED NOT NULL,
    service_id       INT UNSIGNED NOT NULL,
    client_id        INT UNSIGNED NOT NULL,
    window_id        INT UNSIGNED NULL,       -- пас аз даъват муайян мешавад
    employee_id      INT UNSIGNED NULL,       -- корманди хизматрасон
    appointment_date DATE         NOT NULL,
    appointment_time TIME         NULL,       -- NULL барои навбати зинда
    source           ENUM('online','kiosk','reception') NOT NULL DEFAULT 'online',
    status           ENUM('booked','waiting','called','in_service','completed','no_show','cancelled')
                     NOT NULL DEFAULT 'booked',
    comment          VARCHAR(255) NULL,
    cancel_reason    VARCHAR(255) NULL,
    created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    called_at        DATETIME     NULL,
    started_at       DATETIME     NULL,
    finished_at      DATETIME     NULL,
    CONSTRAINT uq_appointments_ticket UNIQUE (office_id, appointment_date, ticket_number),
    CONSTRAINT uq_appointments_public_code UNIQUE (public_code),
    CONSTRAINT chk_appt_started CHECK (started_at IS NULL OR called_at IS NULL OR started_at >= called_at),
    CONSTRAINT chk_appt_finished CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at),
    CONSTRAINT fk_appt_office FOREIGN KEY (office_id)
        REFERENCES notary_offices(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_appt_service FOREIGN KEY (service_id)
        REFERENCES services(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_appt_client FOREIGN KEY (client_id)
        REFERENCES clients(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_appt_window FOREIGN KEY (window_id)
        REFERENCES service_windows(id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_appt_employee FOREIGN KEY (employee_id)
        REFERENCES employees(id) ON DELETE SET NULL ON UPDATE CASCADE,
    -- барои тахтаи навбат ва ҳисоботи рӯзона
    INDEX idx_appt_office_date_status (office_id, appointment_date, status),
    -- барои санҷиши вақтҳои банд ҳангоми сабти онлайн
    INDEX idx_appt_service_slot (service_id, appointment_date, appointment_time),
    INDEX idx_appt_client (client_id)
) ENGINE=InnoDB;

-- Огоҳиномаҳо (SMS / email)
CREATE TABLE notifications (
    id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    appointment_id INT UNSIGNED NOT NULL,
    channel        ENUM('sms','email') NOT NULL,
    type           ENUM('confirmation','reminder','call','cancellation') NOT NULL,
    message        VARCHAR(500) NOT NULL,
    status         ENUM('pending','sent','failed') NOT NULL DEFAULT 'pending',
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sent_at        DATETIME NULL,
    CONSTRAINT fk_notifications_appt FOREIGN KEY (appointment_id)
        REFERENCES appointments(id) ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_notifications_status (status)
) ENGINE=InnoDB;

-- Журнали амалҳои корбарон
CREATE TABLE audit_log (
    id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id    INT UNSIGNED NULL,
    action     VARCHAR(50)  NOT NULL,
    entity     VARCHAR(50)  NOT NULL,
    entity_id  INT UNSIGNED NULL,
    details    VARCHAR(500) NULL,
    ip_address VARCHAR(45)  NULL,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audit_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE,
    INDEX idx_audit_created (created_at)
) ENGINE=InnoDB;
