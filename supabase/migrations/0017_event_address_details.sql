-- По-подробен адрес за събитие извън храма: населено място и
-- блок/вход/етаж/апартамент отделно от улицата – за по-точно търсене в картата.
alter table public.events
  add column address_town  text check (char_length(address_town) <= 100),
  add column address_extra text check (char_length(address_extra) <= 150);
