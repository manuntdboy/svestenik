-- Пробата на митрополитския изглед приключи: създателят вече не е митрополит
-- (по негово искане, 18.11.2026). Санът му се връща, както при освобождаване.
update profiles p set rank = p.rank_before_metro, rank_before_metro = null
 where p.id in (select user_id from app_creators) and p.rank = 'metropolitan';
delete from diocese_staff where role = 'metropolitan' and user_id in (select user_id from app_creators);
