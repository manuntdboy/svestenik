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
select t.ok(t.rows(format($$insert into events(church_id,kind,starts_at,duration_minutes,for_whom) values (%L,'arhiereyska',now() + interval '3 day',360,'Арх')$$, :'cid')) = 1,
            'Архиерейска Литургия се записва (6 часа)');
select t.ok((select visibility from events where for_whom = 'Арх') = 'church', 'Архиерейската Литургия е винаги споделена');
select id as arh from events where for_whom = 'Арх' \gset
select t.as_user(:'B');
select t.ok(public.confirm_event(:'arh') is not null, 'свещеник от храма потвърждава участие');
select t.ok(public.confirm_event(:'arh') is not null, 'повторното потвърждение не пречи');
select t.fails(format($$insert into event_confirmations(event_id) values (%L)$$, :'arh'), 'потвърждение не се пише директно', 'row-level security');
select t.fails(format($$select public.confirm_event(%L)$$, (select id from events where for_whom = 'А споделено')),
               'обикновено събитие не се потвърждава така', 'not_church_event');
select t.as_user(:'A');
select t.ok((select count(*) from event_confirmations where event_id = :'arh') = 1, 'председателят вижда кой е потвърдил');
select t.as_user(:'A');
delete from events where for_whom = 'Арх';
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
select t.fails(format($$select public.set_member_permission(%L,%L,'cash',true)$$, :'cid', :'C'),
               'втори касиер в храма се отказва', 'one_cashier');
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
select t.ok((select count(*) from profile_details where user_id = :'A') = 1
            and (select count(*) from storage.objects where name = :'A' || '/avatar.jpg') = 1,
            'колегата от храма вижда личния профил и снимката');
select t.as_user(:'C');
select t.ok((select count(*) from profile_details) = 0 and (select count(*) from storage.objects) = 0,
            'извън храма не се виждат нито профилът, нито снимката');
select t.as_user(:'B');
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
select t.as_user(:'B');
insert into leave_requests (church_id, start_date, end_date, note) values
  (:'cid', current_date + 40, current_date + 41, 'за отказ'),
  (:'cid', current_date + 50, current_date + 52, 'бъдеща'),
  (:'cid', current_date - 3, current_date + 3, 'тече');
select t.as_user(:'A');
select t.ok((select decision_note from public.decide_leave((select id from leave_requests where note = 'за отказ'), false, '  Има кръщене тогава  '))
            = 'Има кръщене тогава', 'при отказ се пази коментар на председателя');
select t.fails(format('select public.decide_leave(%L, true)', (select id from leave_requests where note = 'за отказ')),
               'решена заявка не се решава втори път', 'not_pending');
select public.decide_leave(id, true) from leave_requests where note in ('бъдеща', 'тече') \g /dev/null
select t.as_user(:'B');
select t.fails(format('select public.end_leave(%L, null)', (select id from leave_requests where note = 'тече')),
               'свещеник не прекратява почивка', 'not_manager');
select t.as_user(:'A');
select t.ok((select status from public.end_leave((select id from leave_requests where note = 'бъдеща'), 'нужен сте'))
            = 'ended', 'непочнала почивка се отменя цялата');
select (public.end_leave((select id from leave_requests where note = 'тече'), null)).end_date as le \gset
select t.ok(:'le'::date = (now() at time zone 'Europe/Sofia')::date - 1
            and (select planned_end from leave_requests where note = 'тече') = current_date + 3
            and not public.is_on_leave(:'cid', :'B', (now() at time zone 'Europe/Sofia')::date),
            'течаща почивка приключва вчера, първоначалният край се пази');
select t.fails(format('select public.end_leave(%L, null)', (select id from leave_requests where note = 'тече')),
               'вече прекратена почивка не се прекратява пак', 'leave_over');
select t.as_user(:'B');
select t.ok((select decision_seen_at from leave_requests where note = 'за отказ') is null, 'отказът чака „ОК“ от свещеника');
select public.leave_ack(id) from leave_requests where note = 'за отказ' \g /dev/null
select t.ok((select decision_seen_at from leave_requests where note = 'за отказ') is not null, 'след „ОК“ картата изчезва');
select t.as_user(:'A');
delete from leave_requests where note in ('за отказ', 'бъдеща', 'тече');

\echo '== Дежурства'
select t.as_user(:'B');
select t.fails(format('select public.duty_add(%L, %L, current_date, current_date + 6)', :'cid', :'B'),
               'свещеник не задава дежурства', 'not_manager');
select t.as_user(:'A');
select public.duty_series(:'cid', current_date + 100, 7, array[:'B', :'C']::uuid[], 4) as ser \gset
select t.ok(jsonb_array_length(:'ser'::jsonb) = 4
            and (select count(*) from duties where church_id = :'cid' and start_date >= current_date + 100) = 4
            and (select user_id from duties where church_id = :'cid' and start_date = current_date + 107) = :'C',
            'серия дежурства по ред');
select t.fails(format('select public.duty_add(%L, %L, current_date + 103, current_date + 104)', :'cid', :'A'),
               'дежурствата не се застъпват', 'duty_overlap');
select t.ok(jsonb_array_length(public.duty_add(:'cid', :'A', current_date + 200, current_date + 203, 'празници')) = 1,
            'дежурство с ръчно избрани дни');
select id as d1 from duties where church_id = :'cid' and start_date = current_date + 100 \gset
select id as d2 from duties where church_id = :'cid' and start_date = current_date + 107 \gset
select t.ok(jsonb_array_length(public.duty_update(:'d1', :'C', current_date + 100, current_date + 106)) = 2,
            'смяна на дежурния – известие и за двамата');
select public.duty_update(:'d1', :'B', current_date + 100, current_date + 106) \g /dev/null
select t.as_user(:'C');
select t.ok((select count(*) from duties where church_id = :'cid') >= 5, 'целият храм вижда графика');
select t.fails($$insert into duties(church_id,user_id,start_date,end_date) values ((select id from churches limit 1), auth.uid(), current_date, current_date)$$,
               'дежурства не се пишат директно', 'row-level security');
select t.fails(format('select public.duty_swap_request(%L, %L)', :'d1', :'d2'), 'не се разменя чуждо дежурство', 'not_yours');
select t.as_user(:'B');
select id as sw from public.duty_swap_request(:'d1', :'d2', 'имам сватба') \gset
select t.fails(format('select public.duty_swap_request(%L, %L)', :'d1', :'d2'), 'една отворена размяна на дежурство', 'swap_exists');
select t.fails(format('select public.duty_swap_peer(%L, true)', :'sw'), 'предложилият не приема сам', 'not_yours');
select t.as_user(:'C');
select t.ok((public.duty_swap_peer(:'sw', true)).status = 'chair', 'колегата приема – чака председателя');
select t.ok((select user_id from duties where id = :'d1') = :'B', 'преди одобрение нищо не се сменя');
select t.fails(format('select public.duty_swap_decide(%L, true)', :'sw'), 'свещеник не одобрява размяна', 'not_manager');
select t.as_user(:'A');
select (public.duty_swap_decide(:'sw', true)).status as sws \gset
select t.ok(:'sws' = 'approved'
            and (select user_id from duties where id = :'d1') = :'C'
            and (select user_id from duties where id = :'d2') = :'B', 'председателят одобрява – дежурствата се разменят');
select t.ok(jsonb_array_length(public.duty_delete(:'d1')) = 1, 'председателят трие дежурство');
delete from duties where church_id = :'cid';

\echo '== Чат'
select t.as_user(:'B');
select (public.chat_send(:'cid', null, 'Утре закъснявам')).id as m1 \gset
select (public.chat_send(:'cid', :'C', 'Лично за теб')).id as m2 \gset
select t.as_user(:'C');
select t.ok((select count(*) from chat_messages where id in (:'m1', :'m2')) = 2, 'колегата вижда общия чат и личното си съобщение');
select public.chat_mute(:'cid', 'c', true) \g /dev/null
select t.fails(format('select public.chat_delete(%L)', :'m1'), 'свещеник не трие чуждо съобщение', 'not_allowed');
select t.as_user(:'A');
select t.ok((select count(*) from chat_messages where id = :'m2') = 0, 'чуждите лични съобщения не се виждат');
select t.ok((select count(*) from chat_mutes where church_id = :'cid' and user_id = :'C') = 1, 'председателят вижда кой е заглушил');
select t.ok((select count(*) from chat_reads where church_id = :'cid' and user_id = :'B' and thread = 'c') = 1,
            'вижда се докъде са прочели колегите (видяно от)');
select t.ok((select count(*) from chat_reads where user_id = :'B' and thread = :'C') = 0, 'чуждите лични прочитания не се виждат');
select public.chat_delete(:'m1') \g /dev/null
select t.ok((select count(*) from chat_messages where id = :'m1') = 0, 'председателят трие съобщение в общия чат');
select t.fails($$select public.chat_send(gen_random_uuid(), null, 'x')$$, 'не се пише в чужд храм', 'not_member');
reset role;
insert into chat_messages (church_id, sender_id, body, created_at) values (:'cid', :'A', 'старо', now() - interval '7 months');
set role authenticated;
select t.as_user(:'A');
select public.chat_send(:'cid', null, 'ново') \g /dev/null
select t.ok((select count(*) from chat_messages where body = 'старо') = 0, 'съобщенията над 6 месеца се трият');
reset role;
insert into app_creators (user_id) values (:'A') on conflict do nothing;
set role authenticated;
select t.as_user(:'A');
select (public.creator_chat_stats()) as chs \gset
select t.ok((:'chs'::jsonb->>'sent_all')::int >= 2 and (:'chs'::jsonb->>'deleted_all')::int = 1
            and (:'chs'::jsonb->>'expired_all')::int = 1, 'статистика на чата: изпратени, изтрити, изтекли');
reset role;
delete from app_creators where user_id = :'A';
set role authenticated;
select t.as_user(:'A');

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

\echo '== Каса'
select t.as_user(:'D');
select id as cid2, join_code as code2 from public.create_church('Св. Георги', 'Казанлък', 'Казанлък') \gset
select t.as_user(:'C');
select public.join_church(:'code2') \g /dev/null
select t.as_user(:'B');
select public.join_church(:'code2') \g /dev/null
select t.as_user(:'D');
select public.approve_member(:'cid2', :'C') \g /dev/null
select public.approve_member(:'cid2', :'B') \g /dev/null
-- Само председател (няма касиер): разходът влиза веднага.
select id as x1 from public.cash_add(:'cid2','expense',500,'Ремонти',null,'покрив','cash',null,null,null) \gset
select t.ok((select status = 'approved' and auto_reason = 'single' and number = 1 from cash_entries where id = :'x1'),
            'без касиер: разходът на председателя влиза веднага (Р-1)');
select t.as_user(:'C');
select id as i1 from public.cash_add(:'cid2','income',50,'Треби',null,'кръщене','cash',null,null,null) \gset
select t.ok((select status from cash_entries where id = :'i1') = 'pending', 'приход от свещеник чака приемане');
select t.ok((select count(*) from cash_entries where church_id = :'cid2') = 1, 'свещеникът вижда само своите записи');
select t.fails(format($$select public.cash_add(%L,'expense',10,'Друго',null,null,'cash',null,null,null)$$, :'cid2'),
               'свещеник не въвежда разход', 'not_cash_holder');
select t.fails(format($$select public.cash_decide(%L, true, null)$$, :'i1'), 'свещеник не приема приходи', 'not_cash_holder');
select t.fails(format($$insert into cash_entries(church_id,book,amount,category) values (%L,'income',1,'x')$$, :'cid2'),
               'записи не се пишат директно', 'row-level security');
select t.ok(t.rows(format($$update cash_entries set amount = 1 where id = %L$$, :'i1')) = 0, 'записи не се променят директно');
select t.as_user(:'D');
select t.ok((select number from public.cash_decide(:'i1', true, null)) = 1, 'председателят (без касиер) приема прихода – П-1');
-- Назначаваме касиер: вече са нужни двама.
select public.set_member_permission(:'cid2', :'B', 'cash', true) \g /dev/null
select id as x2 from public.cash_add(:'cid2','expense',80,'Свещи',null,null,'cash',null,null,null) \gset
select id as x3 from public.cash_add(:'cid2','expense',30,'Свещи',null,null,'cash',null,null,null) \gset
select id as x4 from public.cash_add(:'cid2','expense',200,'Заплати',null,null,'cash',null,null,null) \gset
select t.ok((select status = 'approved' and auto_reason = 'under_limit' from cash_entries where id = :'x2'),
            'разход до 100 € влиза веднага');
select t.ok((select status from cash_entries where id = :'x3') = 'pending', 'над дневния лимит (80 + 30) чака одобрение');
select t.ok((select status from cash_entries where id = :'x4') = 'pending', 'разход над 100 € чака одобрение');
select t.fails(format($$select public.cash_decide(%L, true, null)$$, :'x4'), 'никой не одобрява своя разход', 'own_entry');
select t.as_user(:'C');
select id as i2 from public.cash_add(:'cid2','income',20,'Свещи',null,null,'cash',null,null,null) \gset
select t.as_user(:'D');
select t.fails(format($$select public.cash_decide(%L, true, null)$$, :'i2'), 'при касиер приходите ги приема касиерът', 'not_cashier');
select t.as_user(:'B');
select t.ok(public.cash_holder(:'cid2'), 'касиерът има достъп до касата');
select t.ok((select number from public.cash_decide(:'i2', true, null)) = 2, 'касиерът приема прихода – П-2');
select t.ok((select number from public.cash_decide(:'x4', true, null)) = 3, 'касиерът одобрява разхода на председателя – Р-3');
select t.ok((select status from public.cash_decide(:'x3', false, 'двойно')) = 'returned', 'касиерът връща разход с причина');
select t.fails(format($$select public.cash_add(%L,'transfer',300,'Банка',null,null,'cash','to_bank',null,null)$$, :'cid2'),
               'без включена банка няма банкови движения', 'no_bank');
select t.as_user(:'D');
select public.cash_save_settings(:'cid2', 100, true) \g /dev/null
select id as t1 from public.cash_add(:'cid2','transfer',300,'Внасяне',null,null,'cash','to_bank',null,null) \gset
select t.ok((select status from cash_entries where id = :'t1') = 'pending', 'внасяне в банката чака другия');
select id as r1 from public.cash_reverse(:'i1', 'грешна сума') \gset
select t.ok((select amount = -50 and status = 'pending' from cash_entries where id = :'r1'), 'сторното е обратен запис и чака одобрение');
select t.fails(format($$select public.cash_reverse(%L, 'пак')$$, :'i1'), 'не се сторнира два пъти', 'already_reversed');
select t.as_user(:'B');
select t.fails(format('select public.cash_save_settings(%L, 1000, true)', :'cid2'), 'касиерът не пипа настройките на касата', 'not_manager');
select t.as_user(:'D');
select public.cash_save_settings(:'cid2', 5000, true) \g /dev/null
select t.ok((select limit_eur from cash_settings where church_id = :'cid2') = 100, 'лимитът остава 100 €, каквото и да се прати');
select t.as_user(:'B');
select public.cash_decide(:'t1', true, null) \g /dev/null
select public.cash_decide(:'r1', true, null) \g /dev/null
select t.ok((select reversed_by is not null from cash_entries where id = :'i1'), 'сторнираният запис е отбелязан');
select t.ok((select sum(amount) from cash_entries where church_id = :'cid2' and book = 'income' and status = 'approved') = 20
            and (select sum(amount) from cash_entries where church_id = :'cid2' and book = 'expense' and status = 'approved') = 780,
            'книгите се сумират вярно (приходи 20, разходи 780)');
select t.as_user(:'D');
select id as o1 from public.cash_add(:'cid2','opening',1000,'Начално салдо',null,null,'cash',null,null,null) \gset
select t.ok((select status from cash_entries where id = :'o1') = 'pending', 'началното салдо чака касиера');
select t.fails(format($$select public.cash_add(%L,'opening',5,'Начално салдо',null,null,'cash',null,null,null)$$, :'cid2'),
               'само едно начално салдо за брой', 'opening_exists');
select t.as_user(:'C');
select t.fails(format($$select public.cash_add(%L,'opening',5,'Начално салдо',null,null,'cash',null,null,null)$$, :'cid2'),
               'свещеник не въвежда начално салдо', 'not_cash_holder');
select t.as_user(:'B');
select t.ok((select number from public.cash_decide(:'o1', true, null)) = 1, 'касиерът потвърждава началното салдо – Н-1');
select t.as_user(:'D');
select t.fails(format($$select public.cash_reverse(%L, 'смяна')$$, :'o1'), 'началното салдо не се сторнира', 'not_reversible');
select t.fails(format($$select public.cash_add(%L,'opening',5,'Начално салдо',null,null,'cash',null,null,null)$$, :'cid2'),
               'началното салдо е еднократно', 'opening_exists');
-- Приключване на месец и задна дата
select (date_trunc('month', current_date) - interval '1 month')::date as prev \gset
select t.as_user(:'D');
select t.fails(format('select public.cash_close_request(%L, %L)', :'cid2', :'prev'), 'при касиер месеца го приключва касиерът', 'not_cashier');
select t.as_user(:'B');
select t.fails(format('select public.cash_close_request(%L, current_date)', :'cid2'), 'текущ месец не се приключва', 'month_not_over');
select t.ok((select status from public.cash_close_request(:'cid2', :'prev')) = 'pending', 'касиерът иска приключване');
select t.fails(format('select public.cash_close_decide(%L, %L, true)', :'cid2', :'prev'), 'касиерът не одобрява сам', 'not_manager');
select t.as_user(:'C');
select t.fails(format('select public.cash_close_request(%L, %L)', :'cid2', :'prev'), 'свещеник не приключва', 'not_cash_holder');
select t.as_user(:'D');
select t.ok(public.cash_close_decide(:'cid2', :'prev', true) = 'closed', 'председателят одобрява – месецът е приключен');
select id as bd from public.cash_add(:'cid2','expense',10,'Свещи',null,'забравена бележка','cash',null,null,:'prev') \gset
select t.ok((select status = 'pending' and backdated from cash_entries where id = :'bd'),
            'разход със задна дата в приключен месец чака одобрение дори под лимита');
select t.as_user(:'B');
select t.ok((select status from public.cash_decide(:'bd', true, null)) = 'approved', 'касиерът одобрява записа със задна дата');
select t.fails(format('select public.cash_close_request(%L, %L)', :'cid2', :'prev'), 'месецът не се приключва два пъти', 'already_closed');
-- Изключено второ одобрение (тестов режим)
select t.as_user(:'B');
select t.fails(format('select public.cash_save_settings(%L, 100, true, true)', :'cid2'), 'само председателят изключва одобрението', 'not_manager');
select t.as_user(:'D');
select t.fails(format('select public.cash_save_settings(%L, 100, true, true)', :'cid2'),
               'без разрешение от създателя председателят не изключва одобрението', 'approvals_locked');
reset role;
update churches set approvals_toggle_allowed = true where id = :'cid2';
set role authenticated;
select t.as_user(:'D');
select public.cash_save_settings(:'cid2', 100, true, true) \g /dev/null
select id as off1 from public.cash_add(:'cid2','expense',900,'Ремонти',null,null,'cash',null,null,null) \gset
select t.ok((select status = 'approved' and auto_reason = 'off' from cash_entries where id = :'off1'),
            'при изключено одобрение и голям разход влиза веднага');
select t.as_user(:'C');
select id as off2 from public.cash_add(:'cid2','income',15,'Свещи',null,null,'cash',null,null,null) \gset
select t.ok((select status from cash_entries where id = :'off2') = 'approved', 'и приходът от свещеник влиза веднага');
select t.as_user(:'D');
select public.cash_save_settings(:'cid2', 100, true, false) \g /dev/null
select id as off3 from public.cash_add(:'cid2','expense',900,'Ремонти',null,null,'cash',null,null,null) \gset
select t.ok((select status from cash_entries where id = :'off3') = 'pending', 'след включване одобрението пак се иска');
-- Проведено събитие с приход не се връща като предстоящо
select t.as_user(:'D');
insert into events (church_id, kind, starts_at, visibility, for_whom, status) values (:'cid2', 'vodosvet', now(), 'church', 'Прих-ев', 'done');
select id as pev from events where for_whom = 'Прих-ев' \gset
select public.cash_add(:'cid2','income',40,'Треби',null,null,'cash',null,:'pev',null) \g /dev/null
select t.fails(format($$update events set status = 'planned' where id = %L$$, :'pev'), 'събитие с приход не се връща като предстоящо', 'event_has_income');
select t.fails(format($$delete from events where id = %L$$, :'pev'), 'събитие с приход не се изтрива', 'event_has_income');
\echo '== Склад'
select t.as_user(:'B');
select public.stock_load(:'cid2', 'cert_baptism', 3, 'доставка') \g /dev/null
select public.stock_load(:'cid2', 'cert_wedding', 4, null) \g /dev/null
select public.stock_load(:'cid2', 'diploma', 2, null) \g /dev/null
select t.ok((select sum(qty) from stock_moves where church_id = :'cid2' and item = 'cert_baptism' and status = 'approved') = 3,
            'зареждането влиза веднага');
select t.as_user(:'C');
select t.fails(format($$select public.stock_load(%L, 'candle_1', 5, null)$$, :'cid2'), 'свещеник не зарежда склада', 'not_cash_holder');
select t.ok((select count(*) from stock_moves) = 0, 'свещеникът не вижда склада');
-- кръщене: проведено → −1, върнато → +1
insert into events (church_id, kind, starts_at, visibility, for_whom) values (:'cid2', 'krashtene', now(), 'church', 'Скл-кр');
update events set status = 'done' where for_whom = 'Скл-кр';
select t.as_user(:'B');
select t.ok((select sum(qty) from stock_moves where church_id = :'cid2' and item = 'cert_baptism' and status = 'approved') = 2,
            'проведено кръщене изписва 1 кръщелно (и когато го отбележи свещеник)');
select t.as_user(:'C');
update events set status = 'planned' where for_whom = 'Скл-кр';
select t.as_user(:'B');
select t.ok((select sum(qty) from stock_moves where church_id = :'cid2' and item = 'cert_baptism' and status = 'approved') = 3,
            'върнато като предстоящо – кръщелното се връща');
select t.as_user(:'D');
insert into events (church_id, kind, starts_at, visibility, for_whom, status) values (:'cid2', 'venchavka', now(), 'church', 'Скл-вен', 'done');
select t.ok((select sum(qty) from stock_moves where church_id = :'cid2' and item = 'cert_wedding') = 2
            and (select sum(qty) from stock_moves where church_id = :'cid2' and item = 'diploma') = 1,
            'проведена венчавка изписва 2 венчални и 1 грамота');
delete from events where for_whom = 'Скл-вен';
select t.ok((select sum(qty) from stock_moves where church_id = :'cid2' and item = 'cert_wedding') = 4,
            'изтрито проведено събитие връща бланките');
select public.stock_load(:'cid2', 'candle_1', 5, null) \g /dev/null
select id as sw from public.stock_writeoff(:'cid2', 'candle_1', 1, 'повредени') \gset
select t.ok((select status from stock_moves where id = :'sw') = 'pending', 'ръчното изписване чака другия');
select t.fails(format($$select public.stock_decide(%L, true, null)$$, :'sw'), 'никой не одобрява своето изписване', 'own_entry');
select t.fails(format($$select public.stock_writeoff(%L, 'candle_1', 1, '')$$, :'cid2'), 'изписване без причина се отказва', 'reason_required');
select t.as_user(:'B');
select t.ok((select status from public.stock_decide(:'sw', true, null)) = 'approved', 'касиерът одобрява изписването');
select t.fails(format($$select public.stock_writeoff(%L, 'candle_4', 1, 'За храма')$$, :'cid2'),
               'не се изписва повече от наличното', 'not_enough_stock');
select t.as_user(:'D');
insert into events (church_id, kind, starts_at, visibility, for_whom) values (:'cid2', 'krashtene', now(), 'church', 'Скл-0');
select public.stock_writeoff(:'cid2', 'cert_baptism', 3, 'повредени') \g /dev/null
select t.fails($$update events set status = 'done' where for_whom = 'Скл-0'$$,
               'без кръщелни в склада кръщенето не се отбелязва проведено', 'not_enough_stock');
select t.as_user(:'B');
select t.ok((select book_qty from public.stock_audit(:'cid2', gen_random_uuid(), 'candle_1', 1, 'преброено')) = 4
            and (select coalesce(sum(qty),0) from stock_moves where church_id = :'cid2' and item = 'candle_1' and status = 'approved') = 4,
            'ревизията записва преброеното, без да мени наличността');
select batch as ab from stock_audits where church_id = :'cid2' limit 1 \gset
select t.fails(format('select public.stock_audit_delete(%L, %L)', :'cid2', :'ab'), 'касиерът не трие ревизии', 'not_manager');
select t.as_user(:'D');
select public.stock_audit_delete(:'cid2', :'ab') as dn \gset
select t.ok(:dn = 1
            and (select count(*) from stock_audits where batch = :'ab') = 0
            and (select coalesce(sum(qty),0) from stock_moves where church_id = :'cid2' and item = 'candle_1' and status = 'approved') = 4,
            'председателят трие ревизия, складът не се променя');
select t.as_user(:'B');
select t.as_user(:'C');
select t.fails(format($$select public.stock_audit(%L, gen_random_uuid(), 'candle_1', 1, null)$$, :'cid2'), 'свещеник не прави ревизия', 'not_cash_holder');
select t.ok((select amount from public.cash_add(:'cid2','income',999999999999.99,'Дарение',null,null,'cash',null,null,null)) = 999999999999.99,
            'касата приема 12-цифрени суми');
select t.fails(format($$select public.cash_add(%L,'income',1000000000000,'Дарение',null,null,'cash',null,null,null)$$, :'cid2'),
               'над 12 цифри се отказва', 'amount_check');
select id as don from public.cash_add(:'cid2','income',25,'Дарение',null,null,'cash',null,null,null) \gset
select public.cash_set_donor(:'don', 'Иван Петров') \g /dev/null
select t.as_user(:'B');
select t.ok((select donor from cash_entries where id = :'don') = 'Иван Петров', 'дарителят се записва към дарението');
select (public.stock_load(:'cid2', 'candle_2', 3, 'доставка', 18.5)).unit_price as up \gset
select t.ok(:up = 18.50
            and (select price from stock_prices where church_id = :'cid2' and item = 'candle_2') = 18.50,
            'зареждане с покупна цена – пази се в движението и става текуща');
select public.stock_set_price(:'cid2', 'diploma', 0.8) \g /dev/null
select t.ok((select price from stock_prices where church_id = :'cid2' and item = 'diploma') = 0.80, 'цената се настройва');
select public.stock_set_threshold(:'cid2', 'candle_020', 8);
select t.ok((select min_qty from stock_thresholds where church_id = :'cid2' and item = 'candle_020') = 8, 'границата за предупреждение се настройва');
select public.stock_set_hidden(:'cid2', 'diploma', true) \g /dev/null
select t.ok((select hidden from stock_thresholds where church_id = :'cid2' and item = 'diploma'), 'артикулът се изключва от склада');
select public.stock_set_hidden(:'cid2', 'candle_020', true) \g /dev/null
select t.ok((select min_qty from stock_thresholds where church_id = :'cid2' and item = 'candle_020') = 8, 'изключването пази границата');
select public.stock_set_hidden(:'cid2', 'candle_020', false) \g /dev/null
select t.ok(not (select hidden from stock_thresholds where church_id = :'cid2' and item = 'candle_020'), 'и се включва пак');
select t.fails($$insert into stock_moves(church_id, item, qty, kind) values (gen_random_uuid(), 'diploma', 1, 'load')$$,
               'складът не се пише директно', 'row-level security');
select t.as_user(:'A');
select t.ok((select count(*) from cash_entries where church_id = :'cid2') = 0, 'друг храм не вижда касата');

-- ---------------------------------------------------------------- създател
select t.as_user(:'C');
select t.fails($$select public.creator_stats()$$, 'обикновен потребител не вижда общия преглед', 'forbidden');
select t.fails($$select * from app_creators$$, 'списъкът на създателите е затворен', 'permission denied');
reset role;
insert into app_creators (user_id) values (:'A');
update auth.users set last_sign_in_at = now() where id = :'A';
set role authenticated;
select t.as_user(:'A');
select t.ok(public.is_creator(), 'създателят е разпознат');
select public.report_version(85) \g /dev/null
select public.report_version(86) \g /dev/null
select (public.creator_stats()) as cs \gset
select t.ok((:'cs'::jsonb->'totals'->>'users')::int >= 4
            and jsonb_array_length(:'cs'::jsonb->'users') = (:'cs'::jsonb->'totals'->>'users')::int
            and (:'cs'::jsonb->'totals'->>'churches')::int >= 2
            and jsonb_array_length(:'cs'::jsonb->'churches') = (:'cs'::jsonb->'totals'->>'churches')::int
            and (:'cs'::jsonb->'totals'->>'active_1')::int >= 1,
            'създателят вижда всички регистрирани, храмове и активни');
select t.ok((:'cs'::jsonb->'versions'->>'86')::int = 1 and (:'cs'::jsonb->'versions'->'85') is null,
            'версията на всеки се пази една – последната');
reset role;
delete from notify_log;
insert into notify_log (type, status, info) values
  ('cash_pending', 200, '{"sent": 2, "devices": 2, "fcm_errors": []}'),
  ('event', 200, '{"sent": 0, "reason": "no_devices"}'),
  ('smoke', 401, '{"error": "not_authenticated"}'),
  ('event', 401, '{"error": "not_authenticated"}'),
  ('leave_request', 500, '{"error": "fcm_not_configured"}'),
  ('event', 200, '{"sent": 0, "fcm_errors": [403]}'),
  ('member_approved', 200, '{"sent": 0, "fcm_errors": [404, 404]}'),
  ('event', 200, '{"sent": 1, "stale": 1, "fcm_errors": []}');
set role authenticated;
select t.as_user(:'A');
select (public.creator_stats()->'notify'->'d1') as nd \gset
select t.ok((:'nd'::jsonb->>'delivered')::int = 3 and (:'nd'::jsonb->>'no_recipient')::int = 1
            and (:'nd'::jsonb->>'stale')::int = 3
            and (:'nd'::jsonb->>'refused')::int = 2 and (:'nd'::jsonb->>'errors')::int = 2,
            'известията се делят на доставени, без получател, стари телефони, отказани и грешки');
select t.ok(jsonb_array_length(public.creator_stats()->'notify_failed') = 2,
            'в „неуспешни“ са само истинските грешки, не проверките');
select t.as_user(:'B');
select t.ok(not public.is_creator(), 'другите не са създатели');
select t.fails($$select * from app_versions$$, 'версиите не се четат директно', 'permission denied');
reset role;
insert into password_resets (user_id, by_user) values (:'C', :'A');
set role authenticated;
select t.as_user(:'C');
select t.ok(public.password_must_change(), 'след временна парола свещеникът трябва да я смени');
select public.password_changed() \g /dev/null
select t.ok(not public.password_must_change(), 'след смяната повече не се иска');
select t.fails($$select * from password_resets$$, 'дневникът на паролите е затворен', 'permission denied');
select t.as_user(:'C');
select public.privacy_accept(1) \g /dev/null
select t.ok((select privacy_version from profiles where id = :'C') = 1
            and (select privacy_accepted_at from profiles where id = :'C') is not null, 'съгласието за личните данни се записва');
\echo '== Инструменти на създателя'
select t.as_user(:'B');
select t.fails($$select public.creator_announce('x', null, null)$$, 'само създателят праща съобщения', 'forbidden');
select t.fails($$select public.creator_set_min_build(5)$$, 'само създателят задава версия', 'forbidden');
select t.ok(public.report_error(90, 'Каса', 'Null check operator', 'stack') is not null, 'грешката от телефона се записва');
select t.fails($$select * from app_errors$$, 'дневникът на грешките е затворен', 'permission denied');
insert into feedback (body, build) values ('Бутонът се реже', 104);
select t.ok((select count(*) from feedback) = 1, 'свещеникът вижда своята обратна връзка');
select t.as_user(:'C');
select t.ok((select count(*) from feedback) = 0, 'чуждата обратна връзка не се вижда');
select t.as_user(:'A');
select (public.creator_announce('Нова версия', 'Обновете', null)).id as ann \gset
select public.creator_set_min_build(105) \g /dev/null
select t.ok((select min_build from app_config) = 105, 'минималната версия се задава');
select (public.creator_extra()) as cx \gset
select t.ok(jsonb_array_length(:'cx'::jsonb->'feedback') = 1 and (:'cx'::jsonb->>'errors_24')::int >= 1,
            'създателят вижда обратната връзка и грешките');
select public.creator_feedback_delete(array(select id from feedback)) as fdel \gset
select t.ok(:fdel = 1 and (public.creator_extra()->'feedback') = '[]'::jsonb, 'създателят изтрива отзиви');
select public.creator_church_settings(:'cid2', true, false, null) \g /dev/null
select t.ok((public.creator_extra()->'church_settings'->:'cid2'->>'stock')::boolean = false, 'складът се изключва за храм');
select public.creator_church_settings(:'cid2', true, true, null) \g /dev/null
select t.as_user(:'C');
select t.ok((select count(*) from announcements where id = :'ann') = 1, 'съобщението до всички се вижда');
select public.announcement_ack(:'ann') \g /dev/null
select t.ok((select count(*) from announcement_seen where announcement_id = :'ann' and user_id = :'C') = 1, '„ОК“ на съобщението се пази');
\echo '== Създателят сменя роли и изважда от храм'
select t.as_user(:'B');
select id as rcid, join_code as rcode from public.create_church('Роли', 'Казанлък', 'Казанлък') \gset
select t.as_user(:'C');
select 1 from public.join_church(:'rcode') \g /dev/null
select t.as_user(:'D');
select 1 from public.join_church(:'rcode') \g /dev/null
select t.as_user(:'B');
select public.approve_member(:'rcid', :'C') \g /dev/null
select public.approve_member(:'rcid', :'D') \g /dev/null
select t.fails(format('select public.creator_set_role(%L,%L,false,true)', :'rcid', :'C'), 'само създателят сменя роли', 'forbidden');
select t.fails(format('select public.creator_remove_member(%L,%L)', :'rcid', :'C'), 'само създателят изважда', 'forbidden');
select t.as_user(:'A');
select t.ok(jsonb_array_length(public.creator_user_churches(:'C')) >= 1, 'създателят вижда храмовете на човека');
select cardinality(public.creator_set_role(:'rcid', :'C', false, true)) as n1 \gset
select t.ok(:n1 = 2 and (select (x->>'cashier')::boolean from jsonb_array_elements(public.creator_user_churches(:'C')) x where x->>'church_id' = :'rcid'),
            'касиер + известие до него и до председателя');
select cardinality(public.creator_set_role(:'rcid', :'D', false, true)) as n2 \gset
select t.ok(:n2 = 3 and not ((select (x->>'cashier')::boolean from jsonb_array_elements(public.creator_user_churches(:'C')) x where x->>'church_id' = :'rcid')),
            'нов касиер – старият губи правото и също разбира');
select cardinality(public.creator_set_role(:'rcid', :'D', true, false)) as n3 \gset
select t.ok(:n3 = 2 and (select (x->>'chair')::boolean from jsonb_array_elements(public.creator_user_churches(:'D')) x where x->>'church_id' = :'rcid')
            and not (select (x->>'chair')::boolean from jsonb_array_elements(public.creator_user_churches(:'B')) x where x->>'church_id' = :'rcid')
            and not ((select (x->>'cashier')::boolean from jsonb_array_elements(public.creator_user_churches(:'D')) x where x->>'church_id' = :'rcid')),
            'нов председател – старият става свещеник, председателят не е касиер');
select t.fails(format('select public.creator_set_role(%L,%L,false,false)', :'rcid', :'D'), 'председателят не се сваля без заместник', 'need_chair');
select t.fails(format('select public.creator_remove_member(%L,%L)', :'rcid', :'D'), 'председателят не се изважда, докато има други', 'need_chair');
select cardinality(public.creator_remove_member(:'rcid', :'B')) as n4 \gset
select t.ok(:n4 = 2 and not exists (select 1 from jsonb_array_elements(public.creator_user_churches(:'B')) x where x->>'church_id' = :'rcid'), 'изваждане от храма');
select t.as_user(:'B');
select t.ok((select count(*) from announcements where recipient_id = :'B' and title like 'Извадени%') = 1,
            'изваденият вижда съобщението, макар да не е в храма');
select t.as_user(:'C');
select t.ok((select count(*) from announcements where recipient_id is not null and recipient_id <> :'C') = 0,
            'чуждите лични съобщения не се виждат');
select t.ok((select count(*) from announcements where recipient_id = :'C') = 2, 'своите лични съобщения се виждат');
\echo '== Контрол на създателя: дневник, „какво вижда“, каса'
select t.as_user(:'C');
select t.fails(format('select public.creator_activity(%L, null, 10)', :'B'), 'дневникът е само за създателя', 'forbidden');
select t.fails(format('select public.creator_view_as(%L)', :'B'), '„какво вижда“ е само за създателя', 'forbidden');
select t.fails(format('select public.creator_cash_overview(%L)', :'cid'), 'касата на създателя е само за него', 'forbidden');
select t.fails($$select * from activity_log$$, 'дневникът не се чете директно', 'permission denied');
select t.as_user(:'A');
select t.ok(jsonb_array_length(public.creator_activity(null, :'cid', 500)) > 5, 'действията в храма се записват в дневника');
select t.ok(jsonb_array_length(public.creator_activity(:'B', null, 50)) > 0, 'дневник по човек');
select t.ok(exists (select 1 from jsonb_array_elements(public.creator_activity(null, :'rcid', 50)) x
                     where x->>'action' = 'Извади от храма'), 'изваждането от създателя е в дневника');
select public.creator_view_as(:'C') as va \gset
select t.ok(jsonb_array_length(:'va'::jsonb->'churches') >= 1 and (:'va'::jsonb ? 'cards'), '„какво вижда“ връща храмове и карти');
select t.ok(public.creator_cash_overview(:'cid') ? 'pending', 'създателят вижда чакащите в касата');
select t.fails(format('select public.creator_cash_reopen(%L, %L)', :'cid', '1990-01-01'), 'неприключен месец не се отключва', 'not_found');
\echo '== Епархии и околии'
select t.ok((select count(*) from dioceses where not hidden) = 15, '15 епархии в менюто, „Тест“ е скрита');
select t.ok((select count(*) from vicariates v join dioceses d on d.id = v.diocese_id
              where d.name = 'Старозагорска епархия') = 6, 'Старозагорска: център + 5 околии');
select t.ok((select d.name from churches c join dioceses d on d.id = c.diocese_id where c.id = :'cid') = 'Тест'
            and (select vicariate_id is not null from churches where id = :'cid'), 'новият храм е в епархията на създателя, в центъра');
select id as szd from dioceses where name = 'Старозагорска епархия' \gset
select id as kzl from vicariates where name = 'Казанлъшка духовна околия' \gset
select id as tst from dioceses where name = 'Тест' \gset
reset role;
select join_code as jc from churches where id = :'cid' \gset
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-0000000000e1', 'e1@x.bg', json_build_object('username','eparh1','full_name','Отец Е','diocese_id',:'szd')::jsonb),
 ('00000000-0000-0000-0000-0000000000e2', 'e2@x.bg', json_build_object('username','eparh2','full_name','Отец Ж','diocese_id',:'tst')::jsonb);
\set E1 '00000000-0000-0000-0000-0000000000e1'
\set E2 '00000000-0000-0000-0000-0000000000e2'
select t.ok((select diocese_id from profiles where id = :'E1') = :'szd', 'епархията идва от регистрацията');
select t.ok((select diocese_id is null from profiles where id = :'E2'), 'скритата „Тест“ не се приема при регистрация');
set role authenticated;
select t.as_user(:'E1');
select t.fails(format('select public.join_church(%L)', :'jc'),
               'не се влиза в храм от чужда епархия', 'other_diocese');
select t.as_user(:'E2');
select public.join_church(:'jc') \g /dev/null
reset role;
select t.ok((select diocese_id from profiles where id = :'E2') = :'tst', 'без епархия – поема епархията на храма');
set role authenticated;
select t.as_user(:'B');
select t.fails(format('select public.church_set_vicariate(%L, %L)', :'cid', :'kzl'), 'околията не я сменя никой освен създателя', 'forbidden');
select t.fails(format('select public.create_church_in(%L, %L, %L, %L)', 'Х', 'У', 'З', :'kzl'),
               'нов храм само в своята епархия', 'other_diocese');
select t.fails(format('select public.creator_set_user_diocese(%L, %L)', :'E1', :'tst'), 'само създателят сменя епархия', 'forbidden');
select t.as_user(:'A');
select t.ok(public.creator_set_user_diocese(:'E1', :'tst') = 0, 'създателят сменя епархията');
select t.as_user(:'E1');
select public.join_church(:'jc') \g /dev/null
select t.ok(exists (select 1 from church_members where church_id = :'cid' and user_id = :'E1'), 'след смяната влиза в храма');
select t.as_user(:'A');
select t.ok(public.creator_set_user_diocese(:'E1', :'szd') = 1, 'смяна на епархия – напуска храмовете от старата');
select t.as_user(:'E1');
select id as szc from public.create_church_in('Св. Тест', 'Казанлък', 'Казанлък', :'kzl') \gset
select t.ok((select vicariate_id from churches where id = :'szc') = :'kzl', 'нов храм – в избраната околия');
select t.fails(format('select public.church_set_vicariate(%L, %L)', :'szc', :'kzl'), 'председателят не сменя околията', 'forbidden');
select t.as_user(:'A');
select public.creator_vicariate_save(:'szd', null, 'Тестова околия') as nv \gset
select t.ok((select diocese_id from vicariates where id = :'nv') = :'szd', 'създателят добавя околия');
select t.fails(format('select public.creator_vicariate_save(%L, null, %L)', :'szd', 'Тестова околия'), 'околиите не се повтарят', 'name_taken');
select t.fails(format('select public.church_set_vicariate(%L, %L)', :'cid', :'kzl'),
               'храм с членове от друга епархия не се мести', 'members_other_diocese');
\echo '== Митрополия: длъжности и изглед „Епархия“'
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-0000000000e3', 'e3@x.bg', json_build_object('username','mitro','full_name','Киприан','diocese_id',:'szd')::jsonb);
set role authenticated;
\set E3 '00000000-0000-0000-0000-0000000000e3'
select t.as_user(:'E1');
select t.fails(format('select public.staff_set(%L, %L)', :'E1', 'metropolitan'), 'никой не става сам митрополит', 'forbidden');
select t.fails($$select public.diocese_overview()$$, 'без длъжност – няма изглед „Епархия“', 'forbidden');
select t.as_user(:'A');
select public.staff_set(:'E3', 'metropolitan') \g /dev/null
reset role;
select t.ok((select rank from profiles where id = :'E3') = 'metropolitan', 'създателят оторизира митрополита');
set role authenticated;
select t.as_user(:'E3');
select public.diocese_overview() as ov \gset
select t.ok((:'ov'::jsonb->'diocese'->>'id') = :'szd', 'митрополитът вижда своята епархия');
select t.ok(jsonb_array_length(:'ov'::jsonb->'sections') = 7, 'всички раздели (център + 5 околии + новата)');
select t.ok(exists (select 1 from jsonb_array_elements(:'ov'::jsonb->'sections') s,
                     jsonb_array_elements(s->'churches') c, jsonb_array_elements(c->'priests') p
                     where c->>'name' = 'Св. Тест' and (p->>'chair')::boolean), 'храмовете и председателят са в изгледа');
select t.ok(:'ov'::text not like '%amount%' and :'ov'::text not like '%starts_at%', 'без каса и без служби');
select public.staff_set(:'E1', 'secretary') \g /dev/null
select public.staff_set(:'E1', 'vicar', :'kzl') \g /dev/null
select t.ok((select count(*) from diocese_staff where diocese_id = :'szd') = 3, 'митрополитът назначава секретар и наместник');
select t.fails(format('select public.staff_set(%L, %L, %L)', :'E1', 'vicar',
                      (select id from vicariates where name = 'Тестова духовна околия')),
               'наместник само в своята епархия', 'other_diocese');
select t.fails(format('select public.staff_set(%L, %L)', :'B', 'secretary'), 'не назначава хора от друга епархия', 'forbidden');
select t.as_user(:'E1');
select t.ok(jsonb_array_length(public.diocese_overview()->'sections') = 7, 'секретарят вижда цялата епархия');
select t.as_user(:'E3');
select public.staff_remove(:'E1', 'secretary') \g /dev/null
select t.as_user(:'E1');
select t.fails(format('select public.staff_remove(%L, %L, %L)', :'E1', 'vicar', :'kzl'), 'само митрополитът освобождава', 'forbidden');
select t.ok(jsonb_array_length(public.diocese_overview()->'sections') = 1, 'наместникът вижда само своята околия');
select t.as_user(:'B');
select t.fails($$select public.diocese_overview()$$, 'свещеник без длъжност не вижда епархията', 'forbidden');
select t.as_user(:'A');
\echo '== Администрация на митрополията и чат „Митрополия“'
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-0000000000e4', 'e4@x.bg', json_build_object('username','schet','full_name','Мария Счетоводна','diocese_id',:'szd')::jsonb);
set role authenticated;
\set E4 '00000000-0000-0000-0000-0000000000e4'
select t.as_user(:'E3');
select t.fails(format('select public.staff_set(%L, %L)', :'E4', 'employee'), 'служител – само с титла', 'bad_name');
select t.fails(format('select public.staff_add_employee(%L, %L, %L)', :'szd', 'nyama', 'Х'), 'служител – по съществуващо име', 'user_not_found');
select public.staff_add_employee(:'szd', 'schet', 'Счетоводител') \g /dev/null
select public.staff_set(:'E1', 'protosyngel') \g /dev/null
select t.ok((select title from diocese_staff where user_id = :'E4') = 'Счетоводител', 'митрополитът назначава служител с титла');
select public.metro_chat_send(:'szd', null, 'Добро утро на всички') \g /dev/null
select public.metro_chat_send(:'szd', :'E4', 'Мария, моля сметките') \g /dev/null
select t.as_user(:'E4');
select t.ok((select count(*) from metro_messages) = 2, 'служителят вижда общия чат и личното до него');
select t.fails($$select public.diocese_overview()$$, 'служителят няма изглед „Епархия“', 'forbidden');
select t.as_user(:'E1');
select t.ok((select count(*) from metro_messages) = 1, 'протосингелът вижда общия, но не чуждото лично');
select t.as_user(:'E2');
select t.fails(format('select public.metro_chat_send(%L, null, %L)', :'szd', 'здравейте'), 'извън администрацията не пише', 'not_member');
select t.ok((select count(*) from metro_messages) = 0, 'извън администрацията не чете');
select t.as_user(:'E3');
select public.staff_set(:'E1', 'vicar', :'kzl') \g /dev/null
select public.staff_remove(:'E1', 'protosyngel') \g /dev/null
select t.as_user(:'E1');
select t.ok((select count(*) from metro_messages) = 0, 'наместникът не е в чата на администрацията');
select t.as_user(:'A');
\echo '== Кабинетът на владиката: повикване, календар, храм от епархията'
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-0000000000e5', 'e5@x.bg', json_build_object('username','sekr','full_name','Иван Секретаров','diocese_id',:'szd')::jsonb);
set role authenticated;
\set E5 '00000000-0000-0000-0000-0000000000e5'
select t.as_user(:'E3');
select public.staff_add(:'szd', 'sekr', 'secretary') \g /dev/null
select t.ok(cardinality(public.metro_call(array[:'E4', :'E5']::uuid[], 'С папката за Шипка')) = 2, 'владиката вика двама');
select t.fails(format('select public.metro_call(array[%L]::uuid[])', :'E1'), 'наместникът не се вика в кабинета', 'not_member');
select t.fails($$select public.metro_call('{}'::uuid[])$$, 'без избран човек – няма повикване', 'no_people');
select t.as_user(:'E5');
select t.fails(format('select public.metro_call(array[%L]::uuid[])', :'E4'), 'само митрополитът вика', 'forbidden');
select t.ok((select count(*) from metro_calls) = 1, 'повиканият вижда само своето повикване');
select id as call5 from metro_calls \gset
select public.metro_call_answer(:'call5', 'coming') \g /dev/null
select t.as_user(:'E4');
select t.fails(format('select public.metro_call_answer(%L, %L)', :'call5', 'cannot'), 'чуждо повикване не се отговаря', 'not_found');
select t.as_user(:'E3');
select t.ok((select answer from metro_calls where callee_id = :'E5') = 'coming', 'владиката вижда „Идвам“');
select public.metro_event_save(null, :'szd', now() + interval '1 day', null, false, 'Среща с кмета', 'Кабинетът', null, false) as ev1 \gset
select public.metro_event_save(null, :'szd', now() + interval '2 day', null, true, 'Лично', null, null, true) as ev2 \gset
select t.as_user(:'E5');
select t.ok((select count(*) from metro_events) = 1, 'секретарят не вижда записите „само за мен“');
select public.metro_event_save(null, :'szd', now() + interval '3 day', null, false, 'Посещение в Шипка', 'Шипка', null, false) \g /dev/null
select t.fails(format('select public.metro_event_save(null, %L, now(), null, false, %L, null, null, true)', :'szd', 'Х'),
               'секретарят не пише „само за мен“', 'forbidden');
select t.fails(format('select public.metro_event_delete(%L)', :'ev2'), 'секретарят не трие личните записи', 'not_found');
select public.metro_event_save(:'ev1', :'szd', now() + interval '1 day', null, false, 'Среща с кмета на града', 'Кабинетът', null, false) \g /dev/null
select t.as_user(:'E3');
select t.ok((select count(*) from metro_events) = 3 and exists (select 1 from metro_events where title = 'Среща с кмета на града'),
            'владиката вижда всичко, вкл. промяната на секретаря');
select t.as_user(:'E4');
select t.ok((select count(*) from metro_events) = 0, 'служителят не вижда календара на владиката');
select t.fails(format('select public.metro_event_save(null, %L, now(), null, false, %L, null, null, false)', :'szd', 'Х'),
               'служителят не пише в календара на владиката', 'forbidden');
reset role;
insert into duties (church_id, user_id, start_date, end_date) values (:'szc', :'E1', current_date, current_date + 6);
set role authenticated;
select t.as_user(:'E5');
select public.diocese_church(:'szc') as dc \gset
select t.ok(:'dc'::jsonb ? 'address' and not (:'dc'::jsonb ? 'duties') and :'dc'::text not like '%amount%',
            'секретарят вижда адреса на храма, но не и дежурствата и касата');
select t.as_user(:'E4');
select t.fails(format('select public.diocese_church(%L)', :'szc'), 'служителят не вижда храмовете', 'forbidden');
select t.as_user(:'E1');
select t.ok(public.diocese_church(:'szc')->>'name' = 'Св. Тест', 'наместникът вижда храм от своята околия');
select t.as_user(:'B');
select t.fails(format('select public.diocese_church(%L)', :'szc'), 'свещеник от друг храм не вижда', 'forbidden');
select t.as_user(:'E3');
select t.ok(jsonb_array_length(public.staff_candidates(:'szd', 'Секретар')) = 1, 'владиката намира човек по име');
select t.ok(public.staff_candidates(:'szd', 'Секретар')->0->>'staff' = 'secretary', 'вижда, че вече е секретар');
select t.ok(jsonb_array_length(public.staff_candidates(:'szd', 'x')) = 0, 'под 2 букви – нищо');
select t.as_user(:'E5');
select t.fails(format('select public.staff_candidates(%L, %L)', :'szd', 'Иван'), 'секретарят не търси хора за администрацията', 'forbidden');
select t.as_user(:'A');
\echo '== Митрополит за проба: предишният сан се връща'
reset role;
update profiles set rank = 'priest' where id = :'E5';
set role authenticated;
select t.as_user(:'A');
select public.staff_set(:'E5', 'metropolitan') \g /dev/null
reset role;
select t.ok((select rank from profiles where id = :'E5') = 'metropolitan' and (select rank from profiles where id = :'E3') is null,
            'новият става митрополит, досегашният си връща сана');
set role authenticated;
select t.as_user(:'A');
select public.staff_remove(:'E5', 'metropolitan') \g /dev/null
select public.staff_set(:'E3', 'metropolitan') \g /dev/null
reset role;
select t.ok((select rank from profiles where id = :'E5') = 'priest', 'при освобождаване санът „иерей“ се връща');
set role authenticated;
select t.as_user(:'A');
\echo '== Адрес и Булстат на храма'
select t.as_user(:'B');
select t.fails(format('select public.church_set_info(%L, %L, %L)', :'cid', 'ул. Х 1', '123456789'), 'свещеникът не сменя адреса', 'not_manager');
select t.as_user(:'A');
select t.fails(format('select public.church_set_info(%L, %L, %L)', :'cid', 'ул. Х 1', '12345'), 'Булстатът е 9 или 13 цифри', 'bad_bulstat');
select public.church_set_info(:'cid', '  ул. „Цар Симеон Велики“   112 ', '176 543 210') \g /dev/null
select t.as_user(:'B');
select t.ok((select address = 'ул. „Цар Симеон Велики“ 112' and bulstat = '176543210' from churches where id = :'cid'),
            'председателят записва, членът вижда адреса и Булстата');
select t.as_user(:'A');
select public.church_set_info(:'cid', '', null) \g /dev/null
select t.ok((select address is null and bulstat is null from churches where id = :'cid'), 'полетата се изчистват');
select t.ok(exists (select 1 from jsonb_array_elements(public.creator_activity(null, :'cid', 50)) x
                     where x->>'action' = 'Адрес и Булстат на храма'), 'промяната е в дневника');
\echo '== Основен храм'
select t.as_user(:'B');
select public.set_primary_church(:'cid') \g /dev/null
select t.ok((select primary_church = :'cid' from profiles where id = :'B'), 'свещеникът си отбелязва основен храм');
select t.fails(format('select public.set_primary_church(%L)', gen_random_uuid()), 'чужд храм не може да е основен', 'not_member');
select public.set_primary_church(null) \g /dev/null
select t.ok((select primary_church is null from profiles where id = :'B'), 'основният храм се маха');
select public.set_primary_church(:'cid') \g /dev/null
select t.as_user(:'A');
select t.ok((select primary_church = :'cid' from profiles where id = :'B'), 'колегата вижда профила (полето не е тайна)');
\echo '== Създателят изтрива храм'
select t.as_user(:'C');
select t.fails(format('select public.creator_delete_church(%L, %L)', :'rcid', 'Роли'), 'само създателят трие храмове', 'forbidden');
select t.as_user(:'A');
select t.fails(format('select public.creator_delete_church(%L, %L)', :'rcid', 'Друго'), 'грешно име – храмът не се трие', 'name_mismatch');
select t.ok((public.creator_church_summary(:'rcid')->>'members')::int >= 1, 'създателят вижда какво ще се изтрие');
select cardinality(public.creator_delete_church(:'rcid', ' роли ')) as dn \gset
select t.ok(:dn >= 1 and public.creator_church_summary(:'rcid')->>'name' is null, 'храмът е изтрит, членовете получават съобщение');
select t.as_user(:'C');
select t.ok((select count(*) from announcements where recipient_id = :'C' and title like 'Храмът%изтрит') = 1, 'бившият член вижда съобщението');
select t.as_user(:'A');
reset role;
select t.ok((select public from storage.buckets where id = 'avatars') = false, 'хранилището за снимки е частно');
\echo '== Създателят не вижда суми'
set role authenticated;
select t.as_user(:'A');
select t.ok(public.creator_activity()::text !~ '€', 'дневникът на създателя е без суми');
select t.ok(exists (select 1 from jsonb_array_elements(public.creator_activity()) x where x->>'details' in ('приход','разход','движение')),
            'вижда само вида на записа в касата');
reset role;
\echo '== Календар в Google (iCal връзка)'
set role authenticated;
select t.as_user(:'A');
select public.calendar_feed_get()->>'token' as toka \gset
select t.ok(char_length(:'toka') = 48, 'всеки получава лична тайна връзка');
select t.ok(public.calendar_feed_get()->>'token' = :'toka', 'връзката е една и съща, докато не се смени');
select public.calendar_feed_set('church', true) \g /dev/null
select t.ok((select scope from calendar_feeds) = 'church', 'настройката се пази');
select t.ok(public.calendar_feed_reset()->>'token' <> :'toka', '„Нова връзка“ сменя адреса');
select t.fails(format('select public.calendar_feed_data(%L)', :'toka'), 'данните не се четат от приложението', 'permission denied');
select t.as_user(:'B');
select t.ok((select count(*) from calendar_feeds) = 0, 'чуждите връзки не се виждат');
reset role;
select t.ok(public.calendar_feed_data(:'toka') is null, 'старата връзка вече не дава нищо');
select t.ok(jsonb_typeof(public.calendar_feed_data((select token from calendar_feeds where user_id = :'A'))->'events') = 'array',
            'новата връзка дава събитията');
\echo '== Оперативка на митрополита'
set role authenticated;
select t.as_user(:'E3');
select public.metro_note_save(null, current_date, 'Да се обадя на кмета', null, false, null) as n1 \gset
select public.metro_note_save(null, current_date, 'Писмо до общината', now() + interval '2 day', false, array[:'E4', :'E5']::uuid[]) as n2 \gset
select t.ok((select count(*) from metro_notes) = 2 and (select count(*) from metro_note_assignees) = 2,
            'митрополитът записва бележки и възлага на двама');
select t.fails(format('select public.metro_note_save(null, current_date, %L, null, false, array[%L]::uuid[])', 'Х', :'E1'),
               'не се възлага на човек извън администрацията', 'not_member');
select t.as_user(:'E5');
select t.ok((select count(*) from metro_notes) = 1 and (select count(*) from metro_note_assignees) = 1,
            'секретарят вижда само възложеното на него, не и бележките и другия изпълнител');
select t.fails(format('select public.metro_note_save(null, current_date, %L, null, false, null)', 'Х'),
               'секретарят не пише в оперативката', 'forbidden');
select t.fails(format('select public.metro_note_done(%L, true)', :'n2'), 'секретарят не отмята бележката', 'not_found');
select public.metro_task_done(:'n2', true, 'Пуснато по пощата') \g /dev/null
select t.as_user(:'E2');
select t.ok((select count(*) from metro_notes) = 0, 'извън администрацията не вижда нищо');
select t.fails(format('select public.metro_task_done(%L, true)', :'n2'), 'чужда задача не се отмята', 'not_found');
select t.as_user(:'E3');
select t.ok((select count(*) from metro_note_assignees where note_id = :'n2' and done_at is not null) = 1
            and (select done_note from metro_note_assignees where user_id = :'E5') = 'Пуснато по пощата',
            'митрополитът вижда ✓ и бележката на изпълнителя');
select public.metro_task_return(:'n2', :'E5', 'Липсва подписът') \g /dev/null
select t.as_user(:'E5');
select t.ok((select done_at is null and return_note = 'Липсва подписът' from metro_note_assignees), '„Върни“ отваря задачата наново');
select t.as_user(:'E3');
select public.metro_note_save(:'n2', current_date, 'Писмо до общината', null, false, array[:'E5']::uuid[]) \g /dev/null
select t.ok((select count(*) from metro_note_assignees where note_id = :'n2') = 1, 'изпълнителят се маха при промяна');
select public.metro_note_done(:'n1', true) \g /dev/null
select public.metro_note_delete(:'n2') \g /dev/null
select t.ok((select count(*) from metro_notes where done_at is not null) = 1 and (select count(*) from metro_notes) = 1,
            'отмятане и изтриване');
reset role;
\echo '== ВСИЧКИ ПРОВЕРКИ МИНАХА'
