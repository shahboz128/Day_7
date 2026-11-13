-- database/queries.sql — дархостҳои назоратӣ барои notary_queue
-- Иҷро: mysql -u root --default-character-set=utf8mb4 --table < database/queries.sql
-- Рақамҳои ТФ-xx — талабот аз Шартҳои Техникӣ; дар ҳимоя бо СТ-и худ мутобиқ кунед.
USE notary_queue;
SET NAMES utf8mb4;

-- 1. JOIN-и чор ҷадвал: рӯйхати сабтҳо барои идораи №1 дар санаи 2026-11-13,
--    бо хидмат, муроҷиатқунанда ва ҳолат. (ТФ-03: тахтаи навбат ва рӯйхати сабтҳо)
SELECT a.id, a.ticket_number, a.appointment_time,
       CONCAT(c.last_name, ' ', c.first_name) AS client,
       s.name AS service, o.name AS office, a.status
FROM appointments a
JOIN clients c        ON c.id = a.client_id
JOIN services s       ON s.id = a.service_id
JOIN notary_offices o ON o.id = a.office_id
WHERE a.office_id = 1 AND a.appointment_date = '2026-11-13'
ORDER BY a.appointment_time IS NULL, a.appointment_time, a.ticket_number;

-- 2. LIKE: ҷустуҷӯи муроҷиатқунанда аз рӯи ибтидои насаб (ҳарфҳои кириллӣ).
--    (ТФ-05: ҷустуҷӯи муроҷиатқунанда). Интизор: Ғаффоров
SELECT id, last_name, first_name, phone
FROM clients
WHERE last_name LIKE 'Ғ%';

-- 3. GROUP BY + COUNT: шумораи сабтҳои анҷомёфта аз рӯи хидмат ва идора.
--    (ТФ-09: ҳисобот оид ба хидматҳо)
SELECT o.name AS office, s.name AS service,
       COUNT(*) AS completed_count,
       SUM(s.state_fee) AS fee_total
FROM appointments a
JOIN services s       ON s.id = a.service_id
JOIN notary_offices o ON o.id = a.office_id
WHERE a.status = 'completed'
GROUP BY o.name, s.name
ORDER BY o.name, completed_count DESC, s.name;

-- 4. LEFT JOIN: сарбории равзанаҳо — шумораи сабтҳои анҷомёфта барои ҳар равзана;
--    равзанаҳои бе сабт низ намоёнанд (0). (ТФ-10: ҳисобот оид ба сарбории равзанаҳо)
SELECT o.name AS office, w.number AS window_no, w.title,
       COUNT(a.id) AS completed_count
FROM service_windows w
JOIN notary_offices o ON o.id = w.office_id
LEFT JOIN appointments a ON a.window_id = w.id AND a.status = 'completed'
GROUP BY w.id, o.name, w.number, w.title
ORDER BY o.name, w.number;

-- 5. Филтр аз рӯи ҳолат ва категория: сабтҳои фаъол (booked/waiting) барои хидматҳои
--    категорияи «шартномаҳо» ва «мерос», аз санаи имрӯз. (ТФ-04: филтри сабтҳо)
SELECT a.id, a.appointment_date, a.appointment_time, a.ticket_number,
       s.category, s.name AS service, a.status,
       CONCAT(c.last_name, ' ', c.first_name) AS client
FROM appointments a
JOIN services s ON s.id = a.service_id
JOIN clients c  ON c.id = a.client_id
WHERE a.status IN ('booked','waiting')
  AND s.category IN ('contracts','inheritance')
  AND a.appointment_date >= '2026-11-13'
ORDER BY a.appointment_date, a.appointment_time;

-- 6. LIMIT/OFFSET: саҳифабандӣ — саҳифаи дуюм, 5 сабт дар як саҳифа
--    (ТФ-06: саҳифабандии рӯйхатҳо)
SELECT a.id, a.appointment_date, a.ticket_number, a.status
FROM appointments a
ORDER BY a.appointment_date DESC, a.id DESC
LIMIT 5 OFFSET 5;

-- ---------------------------------------------------------------
-- Иловагӣ: санҷиши индекс (дар сутуни key бояд idx_clients_last_name бошад)
-- EXPLAIN SELECT * FROM clients WHERE last_name LIKE 'Ра%';
--
-- Санҷиши маҳдудиятҳо (ҳар дуи онҳо бояд бо хато анҷом ёбанд):
-- -- CHECK: вақти анҷом аз вақти оғоз пештар аст → ERROR 4025
-- UPDATE appointments SET started_at = '2026-11-13 10:10', finished_at = '2026-11-13 10:00' WHERE id = 7;
-- -- RESTRICT: хидматро, ки сабт дорад, нест кардан мумкин нест → ERROR 1451
-- DELETE FROM services WHERE id = 1;
-- ---------------------------------------------------------------
