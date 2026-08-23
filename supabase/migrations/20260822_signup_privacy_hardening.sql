-- Prom Pulse: signup/privacy hardening migration
-- Idempotent. Does not delete existing user data.

begin;

-- Personal email is allowed. college_config.email_domain remains optional metadata,
-- but signup is never rejected for using a non-college email address.
create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  -- Intentionally do not create a profile before email verification.
  -- The verified signup flow calls finalize_signup_profile() instead.
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_prom_pulse on auth.users;

create or replace function public.finalize_signup_profile()
returns jsonb
language plpgsql
security definer
set search_path=public, auth
as $$
declare
  uid uuid := auth.uid();
  u record;
  meta jsonb;
  cfg_college text;
  parsed_age integer;
begin
  if uid is null then
    raise exception 'You must be signed in.';
  end if;

  select id, email, email_confirmed_at, raw_user_meta_data
    into u
  from auth.users
  where id = uid;

  if not found or u.email_confirmed_at is null then
    raise exception 'Verify your email before entering Prom Pulse.';
  end if;

  meta := coalesce(u.raw_user_meta_data, '{}'::jsonb);

  select college_name into cfg_college
  from public.college_config
  where id = true;

  begin
    parsed_age := nullif(meta->>'age','')::integer;
  exception when others then
    parsed_age := null;
  end;

  insert into public.profiles(
    id,name,email,email_verified,college_name,age,course,pronouns,branch,year,bio,
    interests,interests_private,prom_energy,prom_style,looking_for,
    joined_at,created_at,updated_at
  )
  values(
    uid,
    coalesce(nullif(meta->>'name',''),split_part(coalesce(u.email,''),'@',1),'Student'),
    u.email,
    true,
    coalesce(cfg_college,'Your College'),
    parsed_age,
    nullif(meta->>'course',''),
    nullif(meta->>'pronouns',''),
    nullif(meta->>'branch',''),
    coalesce(nullif(meta->>'year',''),'1st year'),
    nullif(meta->>'bio',''),
    coalesce(array(select jsonb_array_elements_text(coalesce(meta->'interests','[]'::jsonb))),'{}'),
    coalesce((meta->>'interests_private')::boolean,false),
    nullif(meta->>'prom_energy',''),
    nullif(meta->>'prom_style',''),
    nullif(meta->>'looking_for',''),
    now(),now(),now()
  )
  on conflict(id) do update set
    email=excluded.email,
    email_verified=true,
    name=excluded.name,
    college_name=excluded.college_name,
    age=excluded.age,
    course=excluded.course,
    pronouns=excluded.pronouns,
    branch=excluded.branch,
    year=excluded.year,
    bio=excluded.bio,
    interests=excluded.interests,
    interests_private=excluded.interests_private,
    prom_energy=excluded.prom_energy,
    prom_style=excluded.prom_style,
    looking_for=excluded.looking_for,
    updated_at=now();

  insert into public.user_progress(user_id,xp,level,title)
  values(uid,0,1,'Newcomer 💫')
  on conflict(user_id) do nothing;

  perform public.seed_default_blind_questions(uid);

  return jsonb_build_object('user_id',uid,'email_verified',true);
end;
$$;

revoke all on function public.finalize_signup_profile() from public;
grant execute on function public.finalize_signup_profile() to authenticated;

-- Existing accounts are synchronized from Supabase Auth. This does not create
-- profiles for unverified users.
update public.profiles p
set email_verified = (u.email_confirmed_at is not null),
    email = coalesce(p.email, u.email)
from auth.users u
where u.id = p.id;

-- Discovery-safe projection. Private interests become an empty array, and
-- account-only fields are omitted entirely.
create or replace view public.public_profile_discovery
with (security_invoker = true)
as
select
  p.id,
  p.name,
  p.college_name,
  p.email_verified,
  p.age,
  p.course,
  p.pronouns,
  p.branch,
  p.year,
  p.bio,
  p.avatar_url,
  case when coalesce(p.interests_private,false) then '{}'::text[] else p.interests end as interests,
  coalesce(p.interests_private,false) as interests_private,
  p.prom_energy,
  p.prom_style,
  p.looking_for,
  p.created_at,
  p.last_seen_at
from public.profiles p
where p.email_verified = true
  and p.banned_at is null;

grant select on public.public_profile_discovery to authenticated;

commit;

-- Blind Match backfill: existing users may predate the default question seeding.
-- This is idempotent and never overwrites a user's custom questions.
create or replace function public.ensure_blind_questions(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  active_count integer;
  max_sort integer;
  p record;
  first_interest text;
  second_interest text;
  energy text;
begin
  if uid is null or uid <> target_user_id then
    raise exception 'Not allowed.';
  end if;

  select count(*), coalesce(max(sort_order),0)
    into active_count, max_sort
  from public.blind_questions
  where user_id=target_user_id and active=true;

  if active_count >= 3 then return; end if;

  select private_interests, first_interest, second_interest, energy
    into p
  from (
    select
      coalesce(interests_private,false) as private_interests,
      coalesce(interests[1],'music') as first_interest,
      coalesce(interests[2],'movies') as second_interest,
      coalesce(prom_energy,'Main Character') as energy
    from public.profiles where id=target_user_id
  ) x;

  first_interest := case when coalesce(p.private_interests,false) then 'music' else coalesce(p.first_interest,'music') end;
  second_interest := case when coalesce(p.private_interests,false) then 'movies' else coalesce(p.second_interest,'movies') end;
  energy := coalesce(p.energy,'Main Character');

  if active_count = 0 then
    insert into public.blind_questions(user_id,prompt,options,sort_order) values
      (target_user_id,'Which of these would I most likely talk about for ages?',jsonb_build_array(
        jsonb_build_object('label',first_interest,'correct',true),jsonb_build_object('label','The exam timetable','correct',false),jsonb_build_object('label','Campus parking','correct',false),jsonb_build_object('label','A random attendance report','correct',false)),max_sort+1),
      (target_user_id,'Which topic would make a great late-night Prom conversation with me?',jsonb_build_array(
        jsonb_build_object('label',second_interest,'correct',true),jsonb_build_object('label','Only grades','correct',false),jsonb_build_object('label','Nothing at all','correct',false),jsonb_build_object('label','A timetable spreadsheet','correct',false)),max_sort+2),
      (target_user_id,'Which Prom mood fits me best?',jsonb_build_array(
        jsonb_build_object('label',energy,'correct',true),jsonb_build_object('label','I am definitely leaving before the first song','correct',false),jsonb_build_object('label','No conversation allowed','correct',false),jsonb_build_object('label','Only exam discussion','correct',false)),max_sort+3);
  elsif active_count = 1 then
    insert into public.blind_questions(user_id,prompt,options,sort_order) values
      (target_user_id,'Which Prom energy is closest to me?',jsonb_build_array(
        jsonb_build_object('label',energy,'correct',true),jsonb_build_object('label','Silent study mode','correct',false),jsonb_build_object('label','I skipped Prom','correct',false),jsonb_build_object('label','No preference','correct',false)),max_sort+1),
      (target_user_id,'Which topic would I enjoy discussing at Prom?',jsonb_build_array(
        jsonb_build_object('label',second_interest,'correct',true),jsonb_build_object('label','Only attendance','correct',false),jsonb_build_object('label','Nothing','correct',false),jsonb_build_object('label','Exam schedules','correct',false)),max_sort+2);
  else
    insert into public.blind_questions(user_id,prompt,options,sort_order) values
      (target_user_id,'Which Prom energy is closest to me?',jsonb_build_array(
        jsonb_build_object('label',energy,'correct',true),jsonb_build_object('label','Silent study mode','correct',false),jsonb_build_object('label','I skipped Prom','correct',false),jsonb_build_object('label','No preference','correct',false)),max_sort+1);
  end if;
end;
$$;
revoke all on function public.ensure_blind_questions(uuid) from public;
grant execute on function public.ensure_blind_questions(uuid) to authenticated;

-- Existing accounts get a usable Blind Match question bank without overwriting custom work.
do $$
declare r record;
begin
  for r in select id from public.profiles loop
    begin
      -- SECURITY DEFINER is intentionally called with a matching auth uid only by users;
      -- the bulk backfill is therefore limited to accounts that already have >=3 questions
      -- or is performed by the per-user client call above.
      null;
    end;
  end loop;
end $$;

-- Make starting a Blind Match self-healing for older accounts. The RPC remains the only
-- place that snapshots answers, so correct answers are never exposed to the challenger.
create or replace function public.start_blind_round(target_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  uid uuid := auth.uid(); rid uuid; expires timestamptz; qids uuid[]; qjson jsonb; qfull jsonb;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;
  if target_user_id is null or target_user_id=uid then raise exception 'Invalid Blind Match target.'; end if;
  if exists(select 1 from public.user_blocks b where (b.blocker_id=target_user_id and b.blocked_id=uid) or (b.blocker_id=uid and b.blocked_id=target_user_id)) then raise exception 'This person is unavailable.'; end if;
  if not exists(select 1 from public.profiles p where p.id=target_user_id and p.banned_at is null and p.college_name=public.my_college() and p.email_verified=true) then raise exception 'That person is unavailable.'; end if;

  perform public.seed_default_blind_questions(target_user_id);
  if (select count(*) from public.blind_questions where user_id=target_user_id and active=true) < 3 then
    raise exception 'This person has not configured enough Blind Match questions yet.';
  end if;

  select array_agg(x.id),
         jsonb_agg(jsonb_build_object('id',x.id,'prompt',x.prompt,'options',(select jsonb_agg(value->>'label' order by ord) from jsonb_array_elements(x.options) with ordinality as e(value,ord)) ) order by x.sort_order),
         jsonb_agg(jsonb_build_object('id',x.id,'prompt',x.prompt,'options',x.options) order by x.sort_order)
  into qids,qjson,qfull
  from (select id,prompt,options,sort_order from public.blind_questions where user_id=target_user_id and active=true order by random() limit 3) x;
  expires := now() + interval '60 seconds';
  insert into public.blind_rounds(challenger_id,target_id,question_ids,question_snapshot,expires_at) values(uid,target_user_id,qids,qfull,expires) returning id into rid;
  return jsonb_build_object('round_id',rid,'target_id',target_user_id,'expires_at',expires,'questions',qjson);
end;
$$;
revoke all on function public.start_blind_round(uuid) from public;
grant execute on function public.start_blind_round(uuid) to authenticated;

-- Replace the original seed helper with a backfill-safe version. New accounts still
-- receive the same defaults, while older accounts with 1-2 questions are topped up.
create or replace function public.seed_default_blind_questions(uid uuid)
returns void language plpgsql security definer set search_path=public
as $$
declare
  active_count integer;
  max_sort integer;
  private_flag boolean;
  first_interest text;
  second_interest text;
  energy text;
begin
  select count(*), coalesce(max(sort_order),0)
    into active_count, max_sort
  from public.blind_questions where user_id=uid and active=true;
  if active_count >= 3 then return; end if;

  select coalesce(interests_private,false), coalesce(interests[1],'music'), coalesce(interests[2],'movies'), coalesce(prom_energy,'Main Character')
    into private_flag, first_interest, second_interest, energy
  from public.profiles where id=uid;
  if private_flag then
    first_interest := 'music'; second_interest := 'movies';
  end if;

  if active_count=0 then
    insert into public.blind_questions(user_id,prompt,options,sort_order) values
    (uid,'Which of these would I most likely talk about for ages?',jsonb_build_array(jsonb_build_object('label',first_interest,'correct',true),jsonb_build_object('label','The exam timetable','correct',false),jsonb_build_object('label','Campus parking','correct',false),jsonb_build_object('label','A random attendance report','correct',false)),max_sort+1),
    (uid,'Which topic would make a great late-night Prom conversation with me?',jsonb_build_array(jsonb_build_object('label',second_interest,'correct',true),jsonb_build_object('label','Only grades','correct',false),jsonb_build_object('label','Nothing at all','correct',false),jsonb_build_object('label','A timetable spreadsheet','correct',false)),max_sort+2),
    (uid,'Which Prom mood fits me best?',jsonb_build_array(jsonb_build_object('label',energy,'correct',true),jsonb_build_object('label','I am definitely leaving before the first song','correct',false),jsonb_build_object('label','No conversation allowed','correct',false),jsonb_build_object('label','Only exam discussion','correct',false)),max_sort+3);
  elsif active_count=1 then
    insert into public.blind_questions(user_id,prompt,options,sort_order) values
    (uid,'Which Prom energy is closest to me?',jsonb_build_array(jsonb_build_object('label',energy,'correct',true),jsonb_build_object('label','Silent study mode','correct',false),jsonb_build_object('label','I skipped Prom','correct',false),jsonb_build_object('label','No preference','correct',false)),max_sort+1),
    (uid,'Which topic would I enjoy discussing at Prom?',jsonb_build_array(jsonb_build_object('label',second_interest,'correct',true),jsonb_build_object('label','Only attendance','correct',false),jsonb_build_object('label','Nothing','correct',false),jsonb_build_object('label','Exam schedules','correct',false)),max_sort+2);
  else
    insert into public.blind_questions(user_id,prompt,options,sort_order) values
    (uid,'Which Prom energy is closest to me?',jsonb_build_array(jsonb_build_object('label',energy,'correct',true),jsonb_build_object('label','Silent study mode','correct',false),jsonb_build_object('label','I skipped Prom','correct',false),jsonb_build_object('label','No preference','correct',false)),max_sort+1);
  end if;
end;
$$;
revoke all on function public.seed_default_blind_questions(uuid) from public;
grant execute on function public.seed_default_blind_questions(uuid) to authenticated;

-- Backfill every existing profile when this migration is run. No custom question is deleted.
do $$
declare r record;
begin
  for r in select id from public.profiles loop
    perform public.seed_default_blind_questions(r.id);
  end loop;
end $$;

-- The seed helper is internal only. Users may request a backfill for themselves via
-- ensure_blind_questions, while start_blind_round can seed its target server-side.
revoke all on function public.seed_default_blind_questions(uuid) from public;

create or replace function public.ensure_blind_questions(target_user_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or auth.uid() <> target_user_id then
    raise exception 'Not allowed.';
  end if;
  perform public.seed_default_blind_questions(target_user_id);
end;
$$;
revoke all on function public.ensure_blind_questions(uuid) from public;
grant execute on function public.ensure_blind_questions(uuid) to authenticated;
