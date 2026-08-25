-- Prom Pulse feature update: request cancellation/re-request, Secret Crush toggle,
-- two-gender discovery, visible matched profiles, persistent locked chats,
-- and one-attempt-per-person Blind Match.

-- -----------------------------------------------------------------------------
-- 1. Two genders only. Existing accounts that used the removed value must choose
-- again instead of being silently reassigned.
-- -----------------------------------------------------------------------------
update public.profiles set gender = null where lower(coalesce(gender,'')) = 'gay';

create or replace function public.discovery_gender_allowed(viewer_gender text, target_gender text)
returns boolean
language sql immutable
as $$
  select case
    when viewer_gender = 'boy' then target_gender = 'girl'
    when viewer_gender = 'girl' then target_gender = 'boy'
    else false
  end
$$;

grant execute on function public.discovery_gender_allowed(text,text) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Discovery: matched people remain visible, but the UI marks them as matched.
-- The current user's own match still cannot be used to create another request.
-- -----------------------------------------------------------------------------
create or replace function public.discovery_target_visible(target_id uuid, viewer_id uuid)
returns boolean
language plpgsql stable security definer set search_path=public
as $$
declare
  viewer_gender text;
  viewer_college text;
  target_gender text;
begin
  if viewer_id is null or target_id is null or viewer_id = target_id then return false; end if;
  select gender, college_name into viewer_gender, viewer_college from public.profiles where id=viewer_id;
  select gender into target_gender from public.profiles where id=target_id;
  if viewer_gender is null or target_gender is null then return false; end if;
  if not public.discovery_gender_allowed(viewer_gender,target_gender) then return false; end if;
  if not exists(select 1 from public.profiles p where p.id=target_id and p.college_name=viewer_college and p.banned_at is null and public.auth_user_email_verified(p.id)) then return false; end if;
  if exists(select 1 from public.user_blocks b where (b.blocker_id=target_id and b.blocked_id=viewer_id) or (b.blocker_id=viewer_id and b.blocked_id=target_id)) then return false; end if;
  return true;
end;
$$;

grant execute on function public.discovery_target_visible(uuid,uuid) to authenticated;

drop view if exists public.public_profile_discovery;
create view public.public_profile_discovery
with (security_invoker = true)
as
select
  p.id,p.name,p.college_name,p.email_verified,p.age,p.course,p.pronouns,p.branch,p.year,
  p.bio,p.avatar_url,
  case when coalesce(p.interests_private,false) then '{}'::text[] else p.interests end as interests,
  coalesce(p.interests_private,false) as interests_private,
  p.prom_energy,p.prom_style,p.looking_for,p.created_at,p.last_seen_at,
  exists(select 1 from public.match_requests r where r.status='accepted' and (r.requester_id=p.id or r.receiver_id=p.id)) as is_matched
from public.profiles p
where public.discovery_target_visible(p.id,auth.uid());

grant select on public.public_profile_discovery to authenticated;

drop policy if exists "profiles_select_same_college" on public.profiles;
create policy "profiles_select_same_college" on public.profiles
for select to authenticated
using(
  public.is_admin(auth.uid())
  or id=auth.uid()
  or (
    college_name=public.my_college()
    and banned_at is null
    and public.auth_user_email_verified(id)
    and not public.viewer_is_blocked_by(id,auth.uid())
    and public.discovery_gender_allowed(public.current_viewer_gender(), gender)
  )
);

-- -----------------------------------------------------------------------------
-- 3. Secret Crush becomes a true toggle. Removing a crush does not undo an
-- already-created mutual Prom match.
-- -----------------------------------------------------------------------------
create or replace function public.save_secret_crush(target_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public
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
  if target_user_id is null or target_user_id=uid then raise exception 'Invalid Secret Crush target.'; end if;
  if exists(select 1 from public.user_blocks b where (b.blocker_id=target_user_id and b.blocked_id=uid) or (b.blocker_id=uid and b.blocked_id=target_user_id)) then raise exception 'This person is unavailable.'; end if;
  if not exists(select 1 from public.profiles where id=target_user_id and banned_at is null and college_name=public.my_college()) then raise exception 'That student is unavailable.'; end if;

  select id into existing_id from public.secret_crushes where from_user_id=uid and to_user_id=target_user_id;
  if existing_id is not null then
    delete from public.secret_crushes where id=existing_id;
    return jsonb_build_object('status','removed','crush_id',existing_id);
  end if;

  select exists(select 1 from public.secret_crushes where from_user_id=target_user_id and to_user_id=uid) into mutual;
  select name into target_name from public.profiles where id=target_user_id;
  insert into public.secret_crushes(from_user_id,to_user_id) values(uid,target_user_id) returning id into crush_id;

  if mutual then
    select id into match_id from public.match_requests
    where (requester_id=uid and receiver_id=target_user_id) or (requester_id=target_user_id and receiver_id=uid)
    order by created_at desc limit 1;
    if match_id is not null then
      update public.match_requests set status='accepted', updated_at=now() where id=match_id;
    else
      insert into public.match_requests(requester_id,receiver_id,status) values(uid,target_user_id,'accepted') returning id into match_id;
    end if;
    insert into public.notifications(user_id,type,title,body,related_id) values
      (uid,'secret_match','It’s a Secret Crush Match 💘',coalesce(target_name,'Someone')||' secretly chose you too.',crush_id),
      (target_user_id,'secret_match','It’s a Secret Crush Match 💘',(select name from public.profiles where id=uid)||' secretly chose you too.',crush_id);
    return jsonb_build_object('status','mutual','crush_id',crush_id,'match_id',match_id);
  end if;

  insert into public.notifications(user_id,type,title,body,related_id)
  values(uid,'secret_crush','Secret crush saved 💗','They will never know unless they choose you too.',crush_id);
  return jsonb_build_object('status','saved','crush_id',crush_id);
end;
$$;
revoke all on function public.save_secret_crush(uuid) from public;
grant execute on function public.save_secret_crush(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Prom requests: one active match at a time, cancel pending requests, and
-- allow the person who declined a request to send a fresh request later.
-- -----------------------------------------------------------------------------
create or replace function public.send_prom_request(target_user_id uuid)
returns uuid language plpgsql security definer set search_path=public
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
  if exists(select 1 from public.match_requests where status='accepted' and (requester_id=auth.uid() or receiver_id=auth.uid())) then
    raise exception 'You are already matched. Unmatch first to ask someone else.';
  end if;

  select college_name into my_college_name from public.college_config where id=true;
  select banned_at,college_name into target_banned,target_college from public.profiles where id=target_user_id;
  if target_college is null then raise exception 'That student profile does not exist.'; end if;
  if target_banned is not null then raise exception 'That account is unavailable.'; end if;
  if target_college <> my_college_name then raise exception 'You can only send requests within your college.'; end if;
  if exists(select 1 from public.user_blocks b where b.blocker_id=target_user_id and b.blocked_id=auth.uid()) then raise exception 'This person is unavailable to you.'; end if;
  if exists(select 1 from public.match_requests where status='accepted' and (requester_id=target_user_id or receiver_id=target_user_id)) then
    raise exception 'That person is already matched.';
  end if;

  select id,status,requester_id,receiver_id into existing_id,existing_status,existing_requester,existing_receiver
  from public.match_requests
  where ((requester_id=auth.uid() and receiver_id=target_user_id) or (requester_id=target_user_id and receiver_id=auth.uid()))
    and status in ('pending','accepted','declined')
  order by created_at desc limit 1;

  if existing_id is not null then
    if existing_status='accepted' then raise exception 'You already matched with this person.'; end if;
    if existing_status='pending' then raise exception 'A prom request is already pending.'; end if;
    if existing_status='declined' and existing_receiver <> auth.uid() then raise exception 'This request was declined. The person who declined it can send a new request.'; end if;
  end if;

  insert into public.match_requests(requester_id,receiver_id,status) values(auth.uid(),target_user_id,'pending') returning id into new_id;
  return new_id;
end;
$$;
revoke all on function public.send_prom_request(uuid) from public;
grant execute on function public.send_prom_request(uuid) to authenticated;

create or replace function public.cancel_prom_request(request_uuid uuid)
returns void language plpgsql security definer set search_path=public
as $$
declare uid uuid := auth.uid(); current_status text; requester uuid;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;
  select status::text, requester_id into current_status, requester
  from public.match_requests where id=request_uuid for update;
  if not found then raise exception 'Prom request not found.'; end if;
  if requester <> uid then raise exception 'Only the person who sent the request can cancel it.'; end if;
  if current_status <> 'pending' then raise exception 'Only a pending request can be cancelled.'; end if;
  update public.match_requests set status='cancelled', updated_at=now() where id=request_uuid;
end;
$$;
revoke all on function public.cancel_prom_request(uuid) from public;
grant execute on function public.cancel_prom_request(uuid) to authenticated;

create or replace function public.respond_prom_request(request_uuid uuid, new_status text)
returns void language plpgsql security definer set search_path=public
as $$
declare current_status text; requester uuid; receiver uuid;
begin
  if auth.uid() is null then raise exception 'You must be signed in.'; end if;
  if new_status not in ('accepted','declined') then raise exception 'Invalid response.'; end if;
  select status::text, requester_id, receiver_id into current_status, requester, receiver
  from public.match_requests where id=request_uuid and receiver_id=auth.uid();
  if not found then raise exception 'Request not found or you are not the receiver.'; end if;
  if current_status <> 'pending' then raise exception 'This request has already been answered.'; end if;
  if exists(select 1 from public.user_blocks b where (b.blocker_id=auth.uid() and b.blocked_id=requester) or (b.blocker_id=requester and b.blocked_id=auth.uid())) then raise exception 'This request is unavailable.'; end if;
  if new_status='accepted' and (exists(select 1 from public.match_requests r where r.status='accepted' and (r.requester_id=auth.uid() or r.receiver_id=auth.uid())) or exists(select 1 from public.match_requests r where r.status='accepted' and (r.requester_id=requester or r.receiver_id=requester))) then
    raise exception 'One of you is already matched.';
  end if;
  update public.match_requests set status=new_status::public.match_status, updated_at=now() where id=request_uuid;
end;
$$;
revoke all on function public.respond_prom_request(uuid,text) from public;
grant execute on function public.respond_prom_request(uuid,text) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Persistent chat history after unmatch. Reading remains allowed for a
-- cancelled relationship; inserts remain restricted to accepted matches.
-- -----------------------------------------------------------------------------
drop policy if exists "messages_select_match" on public.messages;
create policy "messages_select_match" on public.messages
for select to authenticated
using(public.is_admin(auth.uid()) or exists(
  select 1 from public.match_requests r
  where r.id=conversation_id and r.status in ('accepted','cancelled') and (r.requester_id=auth.uid() or r.receiver_id=auth.uid())
));

drop policy if exists "messages_insert_match" on public.messages;
create policy "messages_insert_match" on public.messages
for insert to authenticated
with check(sender_id=auth.uid() and exists(
  select 1 from public.match_requests r
  where r.id=conversation_id and r.status='accepted' and (r.requester_id=auth.uid() or r.receiver_id=auth.uid())
));

-- -----------------------------------------------------------------------------
-- 6. Blind Match: one attempt per person, enforced server-side.
-- -----------------------------------------------------------------------------
drop policy if exists "blind_rounds_select_own" on public.blind_rounds;
create policy "blind_rounds_select_own" on public.blind_rounds
for select to authenticated using(challenger_id=auth.uid());

create or replace function public.start_blind_round(target_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  uid uuid := auth.uid(); rid uuid; expires timestamptz; qids uuid[]; qjson jsonb; qfull jsonb;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;
  if target_user_id is null or target_user_id=uid then raise exception 'Invalid Blind Match target.'; end if;
  if exists(select 1 from public.blind_rounds where challenger_id=uid and target_id=target_user_id) then raise exception 'Already attempted this person.'; end if;
  if exists(select 1 from public.user_blocks b where (b.blocker_id=target_user_id and b.blocked_id=uid) or (b.blocker_id=uid and b.blocked_id=target_user_id)) then raise exception 'This person is unavailable.'; end if;
  if not exists(select 1 from public.profiles p where p.id=target_user_id and p.banned_at is null and p.college_name=public.my_college() and p.email_verified=true) then raise exception 'That person is unavailable.'; end if;
  perform public.seed_default_blind_questions(target_user_id);
  select array_agg(x.id order by x.random_key),
         jsonb_agg(jsonb_build_object('id',x.id,'prompt',x.prompt,'options',(select jsonb_agg(value->>'label' order by ord) from jsonb_array_elements(x.options) with ordinality as e(value,ord))) order by x.random_key),
         jsonb_agg(jsonb_build_object('id',x.id,'prompt',x.prompt,'options',x.options) order by x.random_key)
  into qids,qjson,qfull
  from (select id,prompt,options,random() as random_key from public.blind_questions where user_id=target_user_id and active=true order by random() limit 3) x;
  if coalesce(array_length(qids,1),0) <> 3 then raise exception 'This person needs at least three active Blind Match questions.'; end if;
  expires := now()+interval '60 seconds';
  insert into public.blind_rounds(challenger_id,target_id,question_ids,question_snapshot,expires_at) values(uid,target_user_id,qids,qfull,expires) returning id into rid;
  return jsonb_build_object('round_id',rid,'target_id',target_user_id,'expires_at',expires,'questions',qjson);
end;
$$;
revoke all on function public.start_blind_round(uuid) from public;
grant execute on function public.start_blind_round(uuid) to authenticated;


-- Remove the old Chemistry-branded mission/badge wording while keeping earned
-- records intact. Existing users keep their earned badge history.
update public.prom_missions
set title='Blind Match Challenge'
where title='Chemistry Challenge';

update public.badges
set name='Connection Hunter'
where slug='chemistry_hunter';
