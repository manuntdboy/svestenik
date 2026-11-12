-- Телефон на свещеника. Не е задължителен; въвежда го само самият той.
-- Вижда се само от одобрените колеги в общ храм (правилото profiles_select),
-- за бутоните „Обади се“ и „Viber“ в профила му.
alter table public.profiles
  add column phone text check (phone is null or (length(phone) between 6 and 20 and phone ~ '^[+0-9 ()/-]+$'));
