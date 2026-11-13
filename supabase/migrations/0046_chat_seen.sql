-- Чат: „Видяно от“ – колегите виждат докъде са прочели другите
-- (общият чат в своя храм; в личен разговор – само другия човек).
drop policy if exists chat_reads_select on public.chat_reads;
create policy chat_reads_select on public.chat_reads for select to authenticated
  using (user_id = auth.uid()
         or (thread = 'c' and public.is_member(church_id))
         or (thread = auth.uid()::text and public.is_member(church_id)));
