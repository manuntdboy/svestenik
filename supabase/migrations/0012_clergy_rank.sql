-- Сан на свещенослужителя. Вижда се от колегите и стои пред името:
-- „Протойерей Тодор Чобанов“. Не е задължителен.
alter table public.profiles
  add column rank text check (rank in ('deacon', 'protodeacon', 'priest', 'archpriest', 'stavrophor'));
