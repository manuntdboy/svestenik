-- Още санове: йеродякон, архидякон, йеромонах, архимандрит, епископ.
alter table public.profiles drop constraint if exists profiles_rank_check;
alter table public.profiles add constraint profiles_rank_check check (rank in (
  'deacon', 'hierodeacon', 'protodeacon', 'archdeacon',
  'priest', 'hieromonk', 'archpriest', 'stavrophor', 'archimandrite', 'bishop'));
