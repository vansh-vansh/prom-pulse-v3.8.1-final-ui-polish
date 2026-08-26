-- Salsa Night 2026-08-24 remaining feature fixes
-- Run this ONCE in Supabase SQL Editor for the production project.
-- Safe to re-run.

-- 1) Secret Crush: true toggle (click again removes the crush).
create or replace function public.save_secret_crush(target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  uid uuid := auth.uid();
  mutual boolean;
  match_id uuid;
  target_name text;
  crush_id uuid;
  existing_id uuid;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;
  if target_user_id is null or target_user_id = uid then raise exception 'Invalid Secret Crush target.'; end if;

  if exists (
    select 1 from public.user_blocks b
    where (b.blocker_id=target_user_id and b.blocked_id=uid)
       or (b.blocker_id=uid and b.blocked_id=target_user_id)
  ) then
    raise exception 'This person is unavailable.';
  end if;

  if not exists (
    select 1 from public.profiles
    where id=target_user_id and banned_at is null and college_name=public.my_college()
  ) then
    raise exception 'That student is unavailable.';
  end if;

  select id into existing_id
  from public.secret_crushes
  where from_user_id=uid and to_user_id=target_user_id;

  if existing_id is not null then
    delete from public.secret_crushes where id=existing_id;
    return jsonb_build_object('status','removed','crush_id',existing_id);
  end if;

  select exists(
    select 1 from public.secret_crushes
    where from_user_id=target_user_id and to_user_id=uid
  ) into mutual;

  select name into target_name from public.profiles where id=target_user_id;

  insert into public.secret_crushes(from_user_id,to_user_id)
  values(uid,target_user_id)
  returning id into crush_id;

  if mutual then
    select id into match_id
    from public.match_requests
    where (requester_id=uid and receiver_id=target_user_id)
       or (requester_id=target_user_id and receiver_id=uid)
    order by created_at desc
    limit 1;

    if match_id is not null then
      update public.match_requests
      set status='accepted', updated_at=now()
      where id=match_id;
    else
      insert into public.match_requests(requester_id,receiver_id,status)
      values(uid,target_user_id,'accepted')
      returning id into match_id;
    end if;

    insert into public.notifications(user_id,type,title,body,related_id)
    values
      (uid,'secret_match','It’s a Secret Crush Match 💘',
       coalesce(target_name,'Someone')||' secretly chose you too.',crush_id),
      (target_user_id,'secret_match','It’s a Secret Crush Match 💘',
       (select name from public.profiles where id=uid)||' secretly chose you too.',crush_id);

    return jsonb_build_object('status','mutual','crush_id',crush_id,'match_id',match_id);
  end if;

  insert into public.notifications(user_id,type,title,body,related_id)
  values(uid,'secret_crush','Secret crush saved 💗',
         'They will never know unless they choose you too.',crush_id);

  return jsonb_build_object('status','saved','crush_id',crush_id);
end;
$$;

revoke all on function public.save_secret_crush(uuid) from public;
grant execute on function public.save_secret_crush(uuid) to authenticated;


-- 2) Prom request cancellation: the RPC called by the website must exist.
create or replace function public.cancel_prom_request(request_uuid uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  uid uuid := auth.uid();
  current_status public.match_status;
  requester uuid;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;

  select status, requester_id
  into current_status, requester
  from public.match_requests
  where id=request_uuid
  for update;

  if not found then raise exception 'Prom request not found.'; end if;
  if requester <> uid then raise exception 'Only the person who sent the request can cancel it.'; end if;
  if current_status <> 'pending' then raise exception 'Only a pending request can be cancelled.'; end if;

  update public.match_requests
  set status='cancelled', updated_at=now()
  where id=request_uuid;
end;
$$;

revoke all on function public.cancel_prom_request(uuid) from public;
grant execute on function public.cancel_prom_request(uuid) to authenticated;


-- 3) Re-request correctly reuses the existing unique relationship row.
-- This avoids "duplicate key ... match_requests_requester_id_receiver_id_key"
-- after a decline, cancellation, or unmatch.
create or replace function public.send_prom_request(target_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  existing_id uuid;
  new_id uuid;
  target_banned timestamptz;
  target_college text;
  my_college_name text;
  existing_status public.match_status;
  existing_requester uuid;
  existing_receiver uuid;
begin
  if auth.uid() is null then raise exception 'You must be signed in.'; end if;
  if target_user_id = auth.uid() then raise exception 'You cannot send a request to yourself.'; end if;

  if exists(
    select 1 from public.match_requests
    where status='accepted' and (requester_id=auth.uid() or receiver_id=auth.uid())
  ) then
    raise exception 'You are already matched. Unmatch first to ask someone else.';
  end if;

  select college_name into my_college_name
  from public.college_config where id=true;

  select banned_at,college_name into target_banned,target_college
  from public.profiles where id=target_user_id;

  if target_college is null then raise exception 'That student profile does not exist.'; end if;
  if target_banned is not null then raise exception 'That account is unavailable.'; end if;
  if target_college <> my_college_name then raise exception 'You can only send requests within your college.'; end if;

  if exists(
    select 1 from public.user_blocks b
    where b.blocker_id=target_user_id and b.blocked_id=auth.uid()
  ) then
    raise exception 'This person is unavailable to you.';
  end if;

  if exists(
    select 1 from public.match_requests
    where status='accepted' and (requester_id=target_user_id or receiver_id=target_user_id)
  ) then
    raise exception 'That person is already matched.';
  end if;

  select id,status,requester_id,receiver_id
  into existing_id,existing_status,existing_requester,existing_receiver
  from public.match_requests
  where (requester_id=auth.uid() and receiver_id=target_user_id)
     or (requester_id=target_user_id and receiver_id=auth.uid())
  order by created_at desc
  limit 1
  for update;

  if existing_id is not null then
    if existing_status='accepted' then
      raise exception 'You already matched with this person.';
    end if;

    if existing_status='pending' then
      if existing_requester = auth.uid() then
        raise exception 'A prom request is already pending.';
      else
        raise exception 'This person has already sent you a request. Accept it instead.';
      end if;
    end if;

    -- After a decline/cancel/unmatch, reuse the same row and make the
    -- current user the requester. Chat history remains attached to the row.
    if existing_status in ('declined','cancelled') then
      update public.match_requests
      set requester_id=auth.uid(),
          receiver_id=target_user_id,
          status='pending',
          updated_at=now()
      where id=existing_id
      returning id into new_id;

      return new_id;
    end if;
  end if;

  insert into public.match_requests(requester_id,receiver_id,status)
  values(auth.uid(),target_user_id,'pending')
  returning id into new_id;

  return new_id;
end;
$$;

revoke all on function public.send_prom_request(uuid) from public;
grant execute on function public.send_prom_request(uuid) to authenticated;


-- 4) Make sure unmatch remains available and preserves the chat row/history.
create or replace function public.unmatch_prom(request_uuid uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  uid uuid := auth.uid();
  row_match record;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;

  select *
  into row_match
  from public.match_requests r
  where r.id=request_uuid
    and (r.requester_id=uid or r.receiver_id=uid)
  for update;

  if not found then raise exception 'Prom match not found.'; end if;
  if row_match.status <> 'accepted' then
    raise exception 'Only an accepted Prom match can be unmatched.';
  end if;

  update public.match_requests
  set status='cancelled', updated_at=now()
  where id=request_uuid;
end;
$$;

revoke all on function public.unmatch_prom(uuid) from public;
grant execute on function public.unmatch_prom(uuid) to authenticated;
