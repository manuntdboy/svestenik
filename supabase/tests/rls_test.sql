-- =====================================================================
-- Пълен тест на базата на Кайрос: таблици, функции и правила за достъп.
-- Пуска се след stub.sql и всички миграции (ci/run_db_tests.sh).
-- Всеки ред „OK …“ е минала проверка; първата грешка спира теста.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

-- ---------------------------------------------------------------- помощни
create schema t;
grant usage on schema t to authenticated, anon;

create function t.ok(cond boolean, name text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', name; end if;
  raise notice 'OK  %', name;
end $$;

-- Очаква грешка; [expect] (по желание) трябва да се съдържа в съобщението.
create function t.fails(stmt text, name text, expect text default null) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if expect is not null and position(expect in sqlerrm) = 0 then
      raise exception 'FAIL: % (друга грешка: %)', name, sqlerrm;
    end if;
    raise notice 'OK  % (отказано: %)', name, left(sqlerrm, 60);
    return;
  end;
  raise exception 'FAIL: % (трябваше да бъде отказано)', name;
end $$;

-- Изпълнява заявка и връща колко реда е засегнала.
create function t.rows(stmt text) returns int language plpgsql as $$
declare n int;
begin
  execute stmt;
  get diagnostics n = row_count;
  return n;
end $$;

create function t.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false);
$$;

grant execute on all functions in schema t to authenticated, anon;

-- ---------------------------------------------------------------- хора
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a', 'a@x.bg', '{"username":"Georgi","full_name":"Отец Георги"}'),
 ('00000000-0000-0000-0000-00000000000b', 'b@x.bg', '{"username":"ivan","full_name":"Отец Иван"}'),
 ('00000000-0000-0000-0000-00000000000c', 'c@x.bg', '{"username":"petar","full_name":"Отец Петър"}'),
 ('00000000-0000-0000-0000-00000000000d', 'd@x.bg', '{"username":"stefan","full_name":"Отец Стефан"}');
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set C '00000000-0000-0000-0000-00000000000c'
\set D '00000000-0000-0000-0000-00000000000d'

\echo '== Регистрация и профили'
select t.ok((select count(*) from profiles) = 4, 'профилът се създава при регистрация');
select t.ok((select username from profiles where id = :'A') = 'georgi', 'потребителското име е с малки букви');
select t.fails($$insert into auth.users(email,raw_user_meta_data) values ('x@x.bg','{"username":"GEORGI","full_name":"Отец Х"}')$$,
               'дублирано потребителско име се отказва', 'duplicate');
select t.fails($$insert into auth.users(email,raw_user_meta_data) values ('y@x.bg','{"username":"аз","full_name":"Отец Х"}')$$,
               'потребителско име на кирилица се отказва', 'check');

set role anon;
select t.ok(public.username_available('novo') and not public.username_available('IVAN'),
            'anon: проверка за свободно име');
select t.fails($$select public.create_church('X','Y','Z')$$, 'anon не създава храм', 'permission');
select t.ok((select count(*) from profiles) = 0, 'anon не вижда профили');
select t.ok((select count(*) from events) = 0, 'anon не вижда събития');
reset role;

\echo '== Храм и код'
set role authenticated;
select t.as_user(:'A');
select id as cid, join_code as code from public.create_church('Св. Николай', 'Стара Загора', 'Стара Загора') \gset
select t.ok(length(:'code') = 6 and :'code' ~ '^[A-HJKMNP-Z2-9]{6}$', 'кодът е 6 знака без 0/O/1/I/L');
select t.ok(public.is_manager(:'cid'), 'създателят е председател');
select t.ok((select count(*) from churches) = 1, 'председателят вижда храма');

select t.as_user(:'B');
select t.fails(format('select public.join_church(%L)', 'ZZZZZZ'), 'грешен код се отказва', 'invalid_code');
select t.ok((select name from public.join_church(lower(substr(:'code',1,3) || '-' || substr(:'code',4)))) = 'Св. Николай',
            'присъединяване с малки букви и тире');
select t.ok((select status from church_members where user_id = :'B') = 'pending', 'новият свещеник чака одобрение');
select t.ok((select count(*) from events) = 0 and not public.is_member(:'cid'), 'чакащият не е член');
select t.fails(format($$insert into events(church_id,kind,starts_at) values (%L,'drugo',now())$$, :'cid'),
               'чакащият не записва събития', 'row-level security');
select t.fails(format('select public.approve_member(%L,%L)', :'cid', :'B'), 'чакащият не се одобрява сам', 'not_manager');

select t.as_user(:'C');
select 1 from public.join_church(:'code') \g /dev/null

select t.as_user(:'A');
select t.ok((select count(*) from church_members where status = 'pending') = 2, 'председателят вижда чакащите');
select t.ok((select count(*) from profiles where username in ('ivan','petar')) = 2, 'председателят вижда имената на чакащите');
select public.approve_member(:'cid', :'B') \g /dev/null
select public.approve_member(:'cid', :'C') \g /dev/null
select t.ok((select count(*) from church_members where status = 'active') = 3, 'председателят одобрява');

select t.as_user(:'D');
select t.ok((select count(*) from churches) = 0 and (select count(*) from profiles) = 1,
            'външен свещеник не вижда храма и чужди профили');

\echo '== Събития: лични, споделени, за колега'
select t.as_user(:'A');
insert into events (church_id, kind, starts_at, for_whom) values (:'cid', 'sluzhba', now() + interval '1 day', 'А лично');
insert into events (church_id, kind, starts_at, visibility, for_whom) values (:'cid', 'vodosvet', now() + interval '2 day', 'church', 'А споделено');
insert into events (church_id, kind, starts_at, visibility, assignee_id, for_whom, duration_minutes)
  values (:'cid', 'krashtene', now() + interval '3 day', 'church', :'B', 'за Б', 60);
select t.ok((select assignee_id = owner_id from events where for_whom = 'А лично'), 'свещеникът по подразбиране е записалият');
select t.ok((select status from events where for_whom = 'А лично') = 'planned', 'състоянието по подразбиране е „предстои“');
select t.fails(format($$insert into events(church_id,kind,starts_at,visibility,assignee_id) values (%L,'drugo',now(),'private',%L)$$, :'cid', :'B'),
               'събитие за колега не може да е лично', 'events_assigned_is_shared');
select t.fails(format($$insert into events(church_id,kind,starts_at,visibility,assignee_id) values (%L,'drugo',now(),'church',%L)$$, :'cid', :'D'),
               'не може да се запише за свещеник извън храма', 'row-level security');
select t.fails(format($$insert into events(church_id,kind,starts_at,duration_minutes) values (%L,'drugo',now(),5)$$, :'cid'),
               'продължителност под 15 мин се отказва', 'check');
select t.fails(format($$insert into events(church_id,kind,starts_at,status) values (%L,'drugo',now(),'lost')$$, :'cid'),
               'непознато състояние се отказва', 'check');
select t.fails(format($$insert into events(owner_id,church_id,kind,starts_at) values (%L,%L,'drugo',now())$$, :'B', :'cid'),
               'не може да се записва от чуждо име', 'row-level security');

select t.as_user(:'B');
select t.ok((select string_agg(for_whom, ',' order by for_whom) from events) = 'А споделено,за Б',
            'Иван вижда споделеното и своето, не личното на Георги');
select t.ok(t.rows($$update events set note = 'ще закъснея' where for_whom = 'за Б'$$) = 1, 'свещеникът редактира събитие за него');
select t.rows(format($$update events set owner_id = %L where for_whom = 'за Б'$$, :'B')) \g /dev/null
select t.ok((select owner_id from events where for_whom = 'за Б') = :'A', 'записалият не може да бъде сменен');
select t.fails(format($$update events set assignee_id = %L where for_whom = 'за Б'$$, :'C'),
               'свещеникът не прехвърля събитието на трети', 'row-level security');
select t.ok(t.rows($$delete from events where for_whom = 'за Б'$$) = 0, 'свещеникът не трие чуждо събитие');
select t.ok(t.rows($$update events set note = 'x' where for_whom = 'А споделено'$$) = 0, 'колега не редактира споделено чуждо');
select t.ok(t.rows($$update events set status = 'done' where for_whom = 'за Б'$$) = 1, 'свещеникът отбелязва „проведено“');

select t.as_user(:'C');
select t.ok((select count(*) from events) = 2, 'Петър вижда двете споделени');
insert into events (church_id, kind, starts_at, visibility, for_whom) values (:'cid', 'panihida', now() + interval '4 day', 'church', 'В споделено');

select t.as_user(:'A');
select t.ok(t.rows($$delete from events where for_whom = 'В споделено'$$) = 1, 'председателят трие споделено събитие на колега');
select t.ok(t.rows(format($$update events set assignee_id = %L where for_whom = 'за Б'$$, :'C')) = 1, 'записалият прехвърля на друг');

\echo '== Права: касиер'
select t.ok(public.has_permission(:'cid', 'cash'), 'председателят има касата');
select t.as_user(:'B');
select t.ok(not public.has_permission(:'cid', 'cash'), 'редовият свещеник няма касата');
select t.fails(format($$select public.set_member_permission(%L,%L,'cash',true)$$, :'cid', :'B'), 'свещеник не си дава права', 'not_manager');
select t.ok(t.rows($$update church_members set permissions = '{cash}' where user_id = auth.uid()$$) = 0, 'членството не се променя директно');
select t.as_user(:'A');
select public.set_member_permission(:'cid', :'B', 'cash', true) \g /dev/null
select public.set_member_permission(:'cid', :'B', 'cash', true) \g /dev/null
select t.fails(format($$select public.set_member_permission(%L,%L,'admin',true)$$, :'cid', :'B'), 'непознато право се отказва', 'unknown_permission');
select t.as_user(:'B');
select t.ok(public.has_permission(:'cid', 'cash'), 'касиерът има касата');
select t.ok((select permissions from church_members where user_id = :'B') = '{cash}', 'правото е записано веднъж');
select t.as_user(:'C');
select t.ok(not public.has_permission(:'cid', 'cash'), 'останалите нямат касата');
select t.as_user(:'A');
select public.set_member_permission(:'cid', :'B', 'cash', false) \g /dev/null
select t.as_user(:'B');
select t.ok(not public.has_permission(:'cid', 'cash'), 'правото се отнема');

\echo '== Код и членове'
select t.fails(format('select public.regenerate_join_code(%L)', :'cid'), 'свещеник не сменя кода', 'not_manager');
select t.fails(format('select public.remove_member(%L,%L)', :'cid', :'C'), 'свещеник не премахва колеги', 'not_manager');
select t.as_user(:'A');
select t.ok(public.regenerate_join_code(:'cid') <> :'code', 'председателят сменя кода');
select t.fails(format('select public.join_church(%L)', :'code'), 'старият код спира да работи', 'invalid_code');
select t.fails(format('select public.remove_member(%L,%L)', :'cid', :'A'), 'председателят не премахва себе си', 'cannot_remove_self');
select public.remove_member(:'cid', :'C') \g /dev/null
select t.as_user(:'C');
select t.ok((select count(*) from events where visibility = 'church') = 0 or
            (select count(*) from events where assignee_id = auth.uid()) = (select count(*) from events),
            'премахнатият вижда само своите събития');

\echo '== Устройства за push'
select t.as_user(:'B');
select public.register_device('tok-1') \g /dev/null
select t.as_user(:'D');
select t.ok((select count(*) from device_tokens) = 0, 'чужди устройства не се виждат');
select public.register_device('tok-1') \g /dev/null
select t.ok((select count(*) from device_tokens) = 1, 'телефонът минава към новия профил');
select t.as_user(:'B');
select t.ok((select count(*) from device_tokens) = 0, 'старият профил губи устройството');
select t.fails($$insert into device_tokens(token,user_id) values ('x', auth.uid())$$, 'устройство не се записва директно', 'row-level security');

\echo '== Личен профил и снимки'
select t.as_user(:'A');
insert into profile_details (three_names, birth_date, ordination_date, name_day_month, name_day_day, photo_path)
  values ('Георги Иванов Петров', '1975-04-23', '2001-05-06', 5, 6, :'A' || '/avatar.jpg');
insert into storage.objects (bucket_id, name) values ('avatars', :'A' || '/avatar.jpg');
select t.fails(format($$insert into storage.objects(bucket_id,name) values ('avatars', %L)$$, :'B' || '/avatar.jpg'),
               'снимка не се качва в чужда папка', 'row-level security');
select t.fails($$update profile_details set name_day_day = null$$, 'имен ден без ден се отказва', 'check');
select t.fails($$update profile_details set birth_date = '1800-01-01'$$, 'невъзможна дата се отказва', 'check');
select t.as_user(:'B');
select t.ok((select count(*) from profile_details) = 0 and (select count(*) from storage.objects) = 0,
            'личният профил и снимката не се виждат от колеги');
select t.ok(t.rows($$update profile_details set three_names = 'x'$$) = 0, 'колега не променя чужд профил');
select t.fails(format($$insert into profile_details(user_id,three_names) values (%L,'x')$$, :'A'),
               'не се записва профил от чуждо име', 'row-level security');
select t.ok((select full_name from profiles where id = :'A') = 'Отец Георги', 'името за календара остава видимо за колегите');
select t.ok(t.rows($$update profiles set full_name = 'Нов' where id = '00000000-0000-0000-0000-00000000000a'$$) = 0,
            'колега не сменя чуждо име');
select t.ok(t.rows($$update profiles set full_name = 'Отец Иван Петров' where id = auth.uid()$$) = 1, 'свещеникът сменя своето име');

\echo '== Потвърждение, отказ и заместник'
-- Иван е одобрен член; Петър беше премахнат – връщаме го и одобряваме пак.
select t.as_user(:'A');
select public.regenerate_join_code(:'cid') as code2 \gset
select t.as_user(:'C');
select 1 from public.join_church(:'code2') \g /dev/null
select t.as_user(:'A');
select public.approve_member(:'cid', :'C') \g /dev/null
-- за себе си → прието; за колега → чака
insert into events (church_id, kind, starts_at, for_whom) values (:'cid', 'drugo', now() + interval '5 day', 'аз за мен');
select t.ok((select assignment_status from events where for_whom = 'аз за мен') = 'accepted', 'за себе си: прието веднага');
insert into events (church_id, kind, starts_at, visibility, assignee_id, for_whom)
  values (:'cid', 'venchavka', now() + interval '6 day', 'church', :'B', 'молба 1') ;
select id as ev1 from events where for_whom = 'молба 1' \gset
select t.ok((select assignment_status from events where id = :'ev1') = 'pending', 'за колега: чака потвърждение');
select t.rows(format($$update events set assignment_status = 'accepted' where id = %L$$, :'ev1')) \g /dev/null
select t.ok((select assignment_status from events where id = :'ev1') = 'pending', 'записалият не може да приеме вместо колегата');
select t.fails(format('select public.respond_assignment(%L, true)', :'ev1'), 'само свещеникът отговаря', 'not_assignee');

select t.as_user(:'B');
select t.fails(format('select public.resolve_decline(%L, %L)', :'ev1', :'C'), 'свещеник не решава откази', 'not_manager');
select t.fails(format('select public.respond_assignment(%L, false, %L, %L)', :'ev1', 'x', :'B'), 'не може да предложи себе си', 'bad_substitute');
select t.fails(format('select public.respond_assignment(%L, false, %L, %L)', :'ev1', 'x', :'D'), 'заместникът трябва да е от храма', 'bad_substitute');
select (public.respond_assignment(:'ev1', false, '  Служба в друг храм  ', :'C')).assignment_status as st \gset
select t.ok(:'st' = 'declined', 'отказ с причина и заместник');
select t.ok((select decline_reason from events where id = :'ev1') = 'Служба в друг храм'
            and (select proposed_substitute from events where id = :'ev1') = :'C'
            and (select declined_by from events where id = :'ev1') = :'B', 'причината и заместникът са записани');
select t.fails(format('select public.respond_assignment(%L, true)', :'ev1'), 'отказаното не се приема повторно', 'not_pending');
select t.rows(format($$update events set assignment_status = 'accepted', decline_reason = null where id = %L$$, :'ev1')) \g /dev/null
select t.ok((select assignment_status from events where id = :'ev1') = 'declined', 'отказът не се отменя на ръка');

select t.as_user(:'A');
select t.fails(format('select public.resolve_decline(%L, %L)', :'ev1', :'D'), 'председателят не дава на човек извън храма', 'bad_substitute');
select (public.resolve_decline(:'ev1', :'C')).assignment_status as st \gset
select t.ok(:'st' = 'pending' and (select assignee_id from events where id = :'ev1') = :'C', 'председателят прехвърля на заместника – чака него');
select t.fails(format('select public.resolve_decline(%L, %L)', :'ev1', :'B'), 'решава се само отказано', 'not_declined');

select t.as_user(:'C');
select t.ok((select count(*) from events where id = :'ev1') = 1, 'заместникът вижда събитието');
select (public.respond_assignment(:'ev1', true)).assignment_status as st \gset
select t.ok(:'st' = 'accepted', 'заместникът приема');

-- председателят оставя на същия свещеник
select t.as_user(:'A');
insert into events (church_id, kind, starts_at, visibility, assignee_id, for_whom)
  values (:'cid', 'panihida', now() + interval '7 day', 'church', :'B', 'молба 2');
select id as ev2 from events where for_whom = 'молба 2' \gset
select t.as_user(:'B');
select public.respond_assignment(:'ev2', false) \g /dev/null
select t.as_user(:'A');
select (public.resolve_decline(:'ev2', :'B')).assignment_status as st \gset
select t.ok(:'st' = 'accepted' and (select assignee_id from events where id = :'ev2') = :'B', 'председателят оставя на същия – прието');

-- записалият сменя свещеника при редакция → новият потвърждава
select t.ok(t.rows(format($$update events set assignee_id = %L where id = %L$$, :'C', :'ev2')) = 1, 'записалият сменя свещеника');
select t.ok((select assignment_status from events where id = :'ev2') = 'pending', 'смяна на свещеника иска ново потвърждение');
select t.ok(t.rows(format($$update events set assignee_id = %L, visibility = 'church' where id = %L$$, :'A', :'ev2')) = 1, 'записалият поема сам');
select t.ok((select assignment_status from events where id = :'ev2') = 'accepted', 'поето от записалия – прието');

\echo '== Почивки'
select t.as_user(:'B');
insert into leave_requests (church_id, start_date, end_date, note)
  values (:'cid', current_date + 10, current_date + 12, 'отпуск');
select id as lv1 from leave_requests where note = 'отпуск' \gset
select t.ok((select status from leave_requests where id = :'lv1') = 'pending', 'заявката чака одобрение');
select t.fails(format($$insert into leave_requests(church_id,start_date,end_date,status) values (%L,current_date,current_date,'approved')$$, :'cid')
               || '; select 1/(select count(*)-count(*) from leave_requests where status=''approved'' and user_id=auth.uid())',
               'не може да се заяви одобрена почивка', 'division');
select t.fails(format($$insert into leave_requests(church_id,user_id,start_date,end_date) values (%L,%L,current_date,current_date)$$, :'cid', :'C'),
               'не се заявява почивка за друг', 'row-level security');
select t.fails(format($$insert into leave_requests(church_id,start_date,end_date) values (%L,current_date+5,current_date+1)$$, :'cid'),
               'краят не може да е преди началото', 'check');
select t.fails(format('select public.decide_leave(%L, true)', :'lv1'), 'свещеник не одобрява почивки', 'not_manager');
select t.as_user(:'C');
select t.ok((select count(*) from leave_requests where id = :'lv1') = 0, 'колегите не виждат чакащата заявка');
select t.as_user(:'A');
select t.ok((select count(*) from leave_requests where id = :'lv1') = 1, 'председателят вижда заявката');
select (public.decide_leave(:'lv1', true)).status as st \gset
select t.ok(:'st' = 'approved', 'председателят одобрява');
select t.as_user(:'C');
select t.ok((select count(*) from leave_requests where id = :'lv1') = 1, 'колегите виждат одобрената почивка');
select t.ok(public.is_on_leave(:'cid', :'B', current_date + 11) and not public.is_on_leave(:'cid', :'B', current_date + 13),
            'почивката важи само в дните си');
select t.fails(format($$insert into events(church_id,kind,starts_at,visibility,assignee_id) values (%L,'drugo',(current_date+11)::timestamp + time '12:00','church',%L)$$, :'cid', :'B'),
               'не се записва събитие за свещеник в почивка', 'assignee_on_leave');
insert into events (church_id, kind, starts_at, visibility, assignee_id, for_whom)
  values (:'cid', 'drugo', (current_date + 14)::timestamp + time '12:00', 'church', :'B', 'след почивката');
select t.ok((select count(*) from events where for_whom = 'след почивката') = 1, 'след почивката може');
select t.fails(format($$update events set starts_at = (current_date+11)::timestamp + time '12:00' where for_whom = 'след почивката'$$),
               'не се мести събитие на колега в дните на почивката му', 'assignee_on_leave');
select t.as_user(:'B');
select t.ok(t.rows(format($$delete from leave_requests where id = %L$$, :'lv1')) = 0, 'одобрена почивка не се трие от свещеника');
insert into leave_requests (church_id, start_date, end_date, note) values (:'cid', current_date + 30, current_date + 30, 'чакаща');
select t.ok(t.rows($$delete from leave_requests where note = 'чакаща'$$) = 1, 'свещеникът оттегля чакаща заявка');
select t.as_user(:'A');
select public.cancel_leave(:'lv1') \g /dev/null
select t.ok((select count(*) from leave_requests where id = :'lv1') = 0, 'председателят отменя одобрена почивка');

\echo '== Смяна на председателя'
select t.as_user(:'B');
select t.fails(format('select public.propose_chair(%L,%L)', :'cid', :'B'), 'свещеник не предлага председател', 'not_manager');
select t.fails(format('select public.respond_chair(%L,true)', :'cid'), 'без предложение не може да се приеме', 'no_offer');
select t.as_user(:'A');
select t.fails(format('select public.propose_chair(%L,%L)', :'cid', :'D'), 'не се предлага човек извън храма', 'bad_substitute');
select t.fails(format('select public.propose_chair(%L,%L)', :'cid', :'A'), 'председателят не предлага себе си', 'already_chair');
select public.propose_chair(:'cid', :'B') \g /dev/null
select t.ok((select pending_chair from churches where id = :'cid') = :'B', 'предложението е записано');
select t.as_user(:'C');
select t.fails(format('select public.respond_chair(%L,true)', :'cid'), 'трети не може да приеме вместо предложения', 'no_offer');
select t.as_user(:'B');
select public.respond_chair(:'cid', false) \g /dev/null
select t.ok((select pending_chair from churches where id = :'cid') is null and public.is_manager(:'cid') = false,
            'отказ: нищо не се сменя');
select t.as_user(:'A');
select t.ok(public.is_manager(:'cid'), 'председателят остава след отказа');
select public.propose_chair(:'cid', :'B') \g /dev/null
select public.cancel_chair_transfer(:'cid') \g /dev/null
select t.as_user(:'B');
select t.fails(format('select public.respond_chair(%L,true)', :'cid'), 'оттеглено предложение не може да се приеме', 'no_offer');
select t.as_user(:'A');
select public.propose_chair(:'cid', :'B') \g /dev/null
select t.as_user(:'B');
select public.respond_chair(:'cid', true) \g /dev/null
select t.ok(public.is_manager(:'cid'), 'новият председател има председателски права');
select t.ok(public.has_permission(:'cid', 'cash'), 'новият председател вижда касата');
select t.as_user(:'A');
select t.ok(not public.is_manager(:'cid') and public.is_member(:'cid'), 'досегашният председател е редови свещеник');
select t.fails(format('select public.regenerate_join_code(%L)', :'cid'), 'досегашният вече не сменя кода', 'not_manager');
select t.ok((select count(*) from church_members where church_id = :'cid' and role = 'manager') = 1, 'председателят е само един');
-- връщаме Георги за председател, за да остане тестът ясен
select t.as_user(:'B');
select public.propose_chair(:'cid', :'A') \g /dev/null
select t.as_user(:'A');
select public.respond_chair(:'cid', true) \g /dev/null
select t.ok(public.is_manager(:'cid'), 'председателството се връща по същия начин');

\echo '== Видяно'
select t.as_user(:'A');
insert into events (church_id, kind, starts_at, visibility, assignee_id, for_whom)
  values (:'cid', 'vodosvet', now() + interval '8 day', 'church', :'B', 'видяно?');
select id as ev3 from events where for_whom = 'видяно?' \gset
select t.ok((select seen_at from events where id = :'ev3') is null, 'новата молба не е видяна');
select t.rows(format($$update events set seen_at = now() where id = %L$$, :'ev3')) \g /dev/null
select t.ok((select seen_at from events where id = :'ev3') is null, 'записалият не слага „видяно“ вместо свещеника');
select t.ok(public.mark_event_seen(:'ev3') is null, 'само свещеникът слага „видяно“');
select t.as_user(:'B');
select public.mark_event_seen(:'ev3') as seen1 \gset
select t.ok(:'seen1' <> '', 'свещеникът отваря – видяно');
select pg_sleep(0.01) \g /dev/null
select t.ok(public.mark_event_seen(:'ev3')::text = :'seen1', 'видяно се записва само първия път');
select t.as_user(:'A');
select t.ok((select seen_at from events where id = :'ev3') is not null, 'записалият вижда, че е видяно');
select t.rows(format($$update events set assignee_id = %L where id = %L$$, :'C', :'ev3')) \g /dev/null
select t.ok((select seen_at from events where id = :'ev3') is null, 'при прехвърляне „видяно“ се нулира');

-- Сан
select t.as_user(:'B');
select t.rows(format($$update profiles set rank = 'archpriest' where id = %L$$, :'B')) \g /dev/null
select t.ok((select rank from profiles where id = :'B') = 'archpriest', 'свещеникът си избира сан');
select t.rows(format($$update profiles set rank = 'archimandrite' where id = %L$$, :'B')) \g /dev/null
select t.ok((select rank from profiles where id = :'B') = 'archimandrite', 'и монашеските санове се приемат');
select t.rows(format($$update profiles set rank = 'archpriest' where id = %L$$, :'B')) \g /dev/null
select t.fails(format($$update profiles set rank = 'patriarch' where id = %L$$, :'B'), 'непознат сан се отказва');
select t.ok(t.rows(format($$update profiles set rank = 'deacon' where id = %L$$, :'A')) = 0, 'не може да се смени санът на друг');
select t.as_user(:'A');
select t.ok((select rank from profiles where id = :'B') = 'archpriest', 'колегата вижда сана');

-- Телефон на свещеника
select t.as_user(:'B');
select t.rows(format($$update profiles set phone = '0888 123 456' where id = %L$$, :'B')) \g /dev/null
select t.ok((select phone from profiles where id = :'B') = '0888 123 456', 'свещеникът си въвежда телефон');
select t.fails(format($$update profiles set phone = 'обади ми се' where id = %L$$, :'B'), 'невалиден телефон се отказва');
select t.ok(t.rows(format($$update profiles set phone = '0899 000 000' where id = %L$$, :'A')) = 0, 'не може да се смени телефонът на друг');
select t.as_user(:'A');
select t.ok((select phone from profiles where id = :'B') = '0888 123 456', 'колегата вижда телефона');
select t.as_user(:'A');
select t.fails('select * from notify_log', 'дневникът на известията не се чете от потребител');
select t.fails($$insert into notify_log(type, status) values ('x', 200)$$, 'и не се пише от потребител');

reset role;
select t.ok((select public from storage.buckets where id = 'avatars') = false, 'хранилището за снимки е частно');
\echo '== ВСИЧКИ ПРОВЕРКИ МИНАХА'
