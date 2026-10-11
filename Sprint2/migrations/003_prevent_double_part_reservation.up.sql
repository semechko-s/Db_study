BEGIN;
-- Блокировка одной строки part сериализует резервирование
-- одной и той же запчасти в параллельных транзакциях.
CREATE OR REPLACE FUNCTION check_part_reservation_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
v_stock INTEGER;
v_reserved INTEGER;
BEGIN
-- Блокируем запчасть до проверки доступного остатка.
SELECT stock_quantity
INTO v_stock
FROM part
WHERE id = NEW.part_id
FOR UPDATE;
IF NOT FOUND THEN
    RAISE EXCEPTION 'Запчасть с id=% не найдена', NEW.part_id;
END IF;

-- Проверяем только активные резервы этой запчасти.
-- При UPDATE не учитываем старую версию текущего резерва.
SELECT COALESCE(SUM(quantity), 0)::INTEGER
INTO v_reserved
FROM part_reservation
WHERE part_id = NEW.part_id
  AND status = 'Активен'
  AND id IS DISTINCT FROM NEW.id;

IF NEW.status = 'Активен'
   AND v_reserved + NEW.quantity > v_stock THEN
    RAISE EXCEPTION
        'Недостаточно запчастей: доступно %, запрошено %',
        GREATEST(v_stock - v_reserved, 0),
        NEW.quantity
        USING ERRCODE = '23514';
END IF;

RETURN NEW;
END;
$$;
CREATE TRIGGER trg_check_part_reservation_stock
BEFORE INSERT OR UPDATE OF part_id, quantity, status
ON part_reservation
FOR EACH ROW
EXECUTE FUNCTION check_part_reservation_stock();
-- Индекс ускоряет подсчёт активных резервов запчасти.
CREATE INDEX idx_part_reservation_active_part
ON part_reservation(part_id)
WHERE status = 'Активен';
COMMIT;