-- Диагностика на известията. Без имена и имейли (логовете в GitHub са публични):
-- хората са означени с букви, храмовете с номера.
with u as (
  select id, chr(64 + row_number() over (order by created_at)::int) as who from profiles
), c as (
  select id, row_number() over (order by created_at) as n from churches
)
select 'член' as what, 'храм ' || c.n as church, u.who, m.role, m.status,
       (select count(*) from device_tokens t where t.user_id = m.user_id) as phones,
       (select to_char(max(t.updated_at) at time zone 'Europe/Sofia', 'DD.MM HH24:MI') from device_tokens t where t.user_id = m.user_id) as phone_seen
  from church_members m join u on u.id = m.user_id join c on c.id = m.church_id
 order by church, who;

with u as (
  select id, chr(64 + row_number() over (order by created_at)::int) as who from profiles
), c as (
  select id, row_number() over (order by created_at) as n from churches
)
select 'почивка' as what, 'храм ' || c.n as church, u.who as requested_by, l.status,
       (select ud.who from u ud where ud.id = l.decided_by) as decided_by,
       exists (select 1 from church_members m where m.church_id = l.church_id and m.user_id = l.user_id and m.role = 'manager') as requester_is_chair,
       to_char(l.created_at at time zone 'Europe/Sofia', 'DD.MM HH24:MI') as created,
       to_char(l.decided_at at time zone 'Europe/Sofia', 'DD.MM HH24:MI') as decided
  from leave_requests l join u on u.id = l.user_id join c on c.id = l.church_id
 where l.created_at > now() - interval '14 days'
 order by l.created_at;
