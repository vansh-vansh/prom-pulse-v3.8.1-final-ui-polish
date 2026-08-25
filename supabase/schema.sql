-- PROM PULSE v3.6.3
-- Consolidated, rerunnable Supabase schema for the existing Prom Pulse project.
-- This file intentionally replaces the older layered migration history.
-- Safe to run on the existing project. It does NOT drop user data.

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- ENUMS
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_type
    where typname = 'match_status'
      and typnamespace = 'public'::regnamespace
  ) then
    create type public.match_status as enum ('pending','accepted','declined','cancelled');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- CORE TABLES
-- -----------------------------------------------------------------------------
create table if not exists public.college_config (
  id boolean primary key default true,
  college_name text not null default 'Your College',
  email_domain text default null,
  prom_date timestamptz not null default '2026-09-05T19:00:00+05:30',
  prom_title text not null default 'PROM ''26',
  allow_join boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint college_config_singleton check (id = true)
);

insert into public.college_config(id, college_name, email_domain, prom_date, prom_title)
values (true, 'Your College', null, '2026-09-05T19:00:00+05:30', 'PROM ''26')
on conflict (id) do nothing;

-- Personal emails are intentionally allowed. Email OTP is the only signup/login gate.
update public.college_config set email_domain = null where id = true;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default 'Student',
  email text,
  email_verified boolean not null default false,
  college_name text not null default 'Your College',
  age integer check (age between 16 and 100),
  course text,
  pronouns text,
  branch text,
  year text,
  bio text,
  avatar_url text,
  interests text[] not null default '{}',
  prom_energy text,
  prom_style text,
  looking_for text,
  gender text,
  banned_at timestamptz,
  joined_at timestamptz default now(),
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists email_verified boolean not null default false;
update public.profiles p
set email_verified = (u.email_confirmed_at is not null)
from auth.users u
where u.id = p.id;
alter table public.profiles add column if not exists college_name text;
alter table public.profiles add column if not exists age integer;
alter table public.profiles add column if not exists course text;
alter table public.profiles add column if not exists pronouns text;
alter table public.profiles add column if not exists branch text;
alter table public.profiles add column if not exists year text;
alter table public.profiles add column if not exists bio text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists interests text[] not null default '{}';
alter table public.profiles add column if not exists interests_private boolean not null default false;
alter table public.profiles add column if not exists prom_energy text;
alter table public.profiles add column if not exists prom_style text;
alter table public.profiles add column if not exists looking_for text;
alter table public.profiles add column if not exists gender text;
alter table public.profiles add column if not exists banned_at timestamptz;
alter table public.profiles add column if not exists joined_at timestamptz default now();
alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

update public.profiles p
set college_name = coalesce(nullif(p.college_name,''), (select c.college_name from public.college_config c where c.id=true), 'Your College')
where p.college_name is null or trim(p.college_name) = '';

create table if not exists public.match_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status public.match_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(requester_id, receiver_id),
  check(requester_id <> receiver_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.match_requests(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check(char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  related_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_reads (
  conversation_id uuid not null references public.match_requests(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key(conversation_id, user_id)
);

create table if not exists public.secret_crushes (
  id uuid primary key default gen_random_uuid(),
  from_user_id uuid not null references auth.users(id) on delete cascade,
  to_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(from_user_id, to_user_id),
  check(from_user_id <> to_user_id)
);

create table if not exists public.user_blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(blocker_id, blocked_id),
  check(blocker_id <> blocked_id)
);

create table if not exists public.blind_questions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  prompt text not null check(char_length(prompt) between 5 and 220),
  options jsonb not null default '[]'::jsonb,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.blind_rounds (
  id uuid primary key default gen_random_uuid(),
  challenger_id uuid not null references auth.users(id) on delete cascade,
  target_id uuid not null references auth.users(id) on delete cascade,
  question_ids uuid[] not null,
  question_snapshot jsonb not null default '[]'::jsonb,
  expires_at timestamptz not null,
  status text not null default 'active' check(status in ('active','success','failed','expired')),
  score integer not null default 0,
  started_at timestamptz not null default now(),
  answered_at timestamptz,
  check(challenger_id <> target_id)
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null,
  details text,
  status text not null default 'open' check(status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now()
);

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.prom_missions (
  id uuid primary key default gen_random_uuid(),
  title text not null unique,
  description text not null,
  icon text not null default '✨',
  reward_xp integer not null default 10 check(reward_xp > 0 and reward_xp <= 500),
  active boolean not null default true,
  sort_order integer not null default 0,
  min_level integer not null default 1 check(min_level between 1 and 10),
  is_daily boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.mission_completions (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.prom_missions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  proof text,
  status text not null default 'verified',
  completed_at timestamptz not null default now(),
  completion_date date not null default current_date,
  unique(mission_id, user_id, completion_date)
);

-- Preserve compatibility with older installs that had a fixed mission/user key.
alter table public.mission_completions drop constraint if exists mission_completions_mission_id_user_id_key;

-- Clean up accidental duplicate daily rows before enforcing the daily uniqueness rule.
delete from public.mission_completions a
using public.mission_completions b
where a.id > b.id
  and a.mission_id = b.mission_id
  and a.user_id = b.user_id
  and a.completion_date = b.completion_date;

create unique index if not exists mission_completions_mission_user_day_unique
  on public.mission_completions(mission_id, user_id, completion_date);
update public.mission_completions set status='verified' where status is distinct from 'verified';

create table if not exists public.memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text,
  image_url text,
  event_kind text not null default 'note',
  created_at timestamptz not null default now()
);

create table if not exists public.prom_picks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  picked_user_id uuid not null references auth.users(id) on delete cascade,
  pick_date date not null default current_date,
  score numeric not null default 0,
  unique(user_id, picked_user_id, pick_date),
  check(user_id <> picked_user_id)
);

create table if not exists public.user_progress (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  xp integer not null default 0 check(xp >= 0),
  level integer not null default 1 check(level between 1 and 10),
  title text not null default 'Newcomer 💫',
  updated_at timestamptz not null default now()
);

create table if not exists public.xp_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount integer not null check(amount > 0 and amount <= 500),
  source text not null,
  mission_id uuid references public.prom_missions(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.xp_transactions add column if not exists metadata jsonb not null default '{}'::jsonb;

create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text not null,
  icon text not null
);

create table if not exists public.user_badges (
  user_id uuid not null references public.profiles(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  earned_at timestamptz not null default now(),
  primary key(user_id, badge_id)
);

-- -----------------------------------------------------------------------------
-- HELPERS / PROGRESSION
-- -----------------------------------------------------------------------------
create or replace function public.college_name()
returns text
language sql stable security definer set search_path=public
as $$ select college_name from public.college_config where id=true $$;

create or replace function public.college_domain()
returns text
language sql stable security definer set search_path=public
as $$ select email_domain from public.college_config where id=true $$;

create or replace function public.my_college()
returns text
language sql stable
as $$ select public.college_name() $$;

create or replace function public.is_admin(uid uuid)
returns boolean
language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.admin_users where user_id=uid) $$;

create or replace function public.level_from_xp(total_xp integer)
returns integer language sql immutable
as $$
  select case
    when total_xp >= 2750 then 10
    when total_xp >= 2250 then 9
    when total_xp >= 1800 then 8
    when total_xp >= 1400 then 7
    when total_xp >= 1000 then 6
    when total_xp >= 700 then 5
    when total_xp >= 450 then 4
    when total_xp >= 250 then 3
    when total_xp >= 100 then 2
    else 1
  end
$$;

create or replace function public.level_title(total_xp integer)
returns text language sql immutable
as $$
  select case public.level_from_xp(total_xp)
    when 10 then 'Prom Legend 💎'
    when 9 then 'Main Character 🌟'
    when 8 then 'Prom Icon 👑'
    when 7 then 'Heartbreaker 💘'
    when 6 then 'Connection Hunter 🔥'
    when 5 then 'Prom Explorer 🪩'
    when 4 then 'Connection Maker 💗'
    when 3 then 'Vibe Finder 🎧'
    when 2 then 'Social Spark ✨'
    else 'Newcomer 💫'
  end
$$;

insert into public.badges(slug,name,description,icon) values
('first_connection','First Connection','Made your first Prom connection.','🏅'),
('secret_admirer','Secret Admirer','Got your first mutual Secret Crush.','💗'),
('chemistry_hunter','Connection Hunter','Completed 5 missions.','🎯'),
('speed_heart','Speed Heart','Won a 60-second Blind Match.','⏱️'),
('social_explorer','Social Explorer','Connected across 5 different branches.','🌎'),
('prom_regular','Prom Regular','Completed missions on 7 different days.','🪩'),
('prom_legend','Prom Legend','Reached Level 10.','👑')
on conflict(slug) do update set name=excluded.name, description=excluded.description, icon=excluded.icon;

create or replace function public.grant_badge(uid uuid, badge_slug text)
returns void language plpgsql security definer set search_path=public
as $$
declare bid uuid;
begin
  select id into bid from public.badges where slug=badge_slug;
  if bid is not null then
    insert into public.user_badges(user_id,badge_id) values(uid,bid) on conflict do nothing;
  end if;
end;
$$;

create or replace function public.refresh_badges(uid uuid)
returns void language plpgsql security definer set search_path=public
as $$
declare
  mission_count integer;
  day_count integer;
  branch_count integer;
  has_speed boolean;
  has_mutual boolean;
  level_now integer;
begin
  select count(*) into mission_count from public.mission_completions where user_id=uid and status='verified';
  select count(distinct completion_date) into day_count from public.mission_completions where user_id=uid and status='verified';
  select count(distinct p.branch) into branch_count
  from public.match_requests r
  join public.profiles p on p.id = case when r.requester_id=uid then r.receiver_id else r.requester_id end
  where r.status='accepted' and (r.requester_id=uid or r.receiver_id=uid) and p.branch is not null;
  select exists(select 1 from public.xp_transactions where user_id=uid and source='blind_match') into has_speed;
  select exists(select 1 from public.notifications where user_id=uid and type='secret_match') into has_mutual;
  select level into level_now from public.user_progress where user_id=uid;

  -- True connection badge is tied to a real accepted match.
  if exists(select 1 from public.match_requests where status='accepted' and (requester_id=uid or receiver_id=uid)) then
    perform public.grant_badge(uid,'first_connection');
  end if;
  if has_mutual then perform public.grant_badge(uid,'secret_admirer'); end if;
  if mission_count >= 5 then perform public.grant_badge(uid,'chemistry_hunter'); end if;
  if has_speed then perform public.grant_badge(uid,'speed_heart'); end if;
  if branch_count >= 5 then perform public.grant_badge(uid,'social_explorer'); end if;
  if day_count >= 7 then perform public.grant_badge(uid,'prom_regular'); end if;
  if coalesce(level_now,1) >= 10 then perform public.grant_badge(uid,'prom_legend'); end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- MISSION CATALOG
-- -----------------------------------------------------------------------------
create or replace function public.ensure_prom_mission_catalog()
returns void language plpgsql security definer set search_path=public
as $$
begin
  update public.prom_missions set description='Find someone from your college with the same Prom Energy as you.', icon='🪞', reward_xp=20, sort_order=1, min_level=1, is_daily=false, active=true where title='Meet your Prom Twin';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Meet your Prom Twin','Find someone from your college with the same Prom Energy as you.','🪞',20,1,1,false,true);
  end if;
  update public.prom_missions set description='Ask someone what song they would play during the final dance.', icon='🎵', reward_xp=20, sort_order=2, min_level=1, is_daily=false, active=true where title='Song Swap';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Song Swap','Ask someone what song they would play during the final dance.','🎵',20,2,1,false,true);
  end if;
  update public.prom_missions set description='Send a genuine compliment that is not about appearance.', icon='💌', reward_xp=30, sort_order=3, min_level=1, is_daily=true, active=true where title='Good Vibes Only';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Good Vibes Only','Send a genuine compliment that is not about appearance.','💌',30,3,1,true,true);
  end if;
  update public.prom_missions set description='Start a conversation with someone from a different branch.', icon='🌐', reward_xp=25, sort_order=4, min_level=2, is_daily=false, active=true where title='Branch Beyond';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Branch Beyond','Start a conversation with someone from a different branch.','🌐',25,4,2,false,true);
  end if;
  update public.prom_missions set description='Use the Blind Match questions with a new person.', icon='🎯', reward_xp=30, sort_order=5, min_level=2, is_daily=true, active=true where title='Three Questions';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Three Questions','Use the Blind Match questions with a new person.','🎯',30,5,2,true,true);
  end if;
  update public.prom_missions set description='Find two people with the same Prom Energy as you.', icon='🧭', reward_xp=40, sort_order=6, min_level=3, is_daily=false, active=true where title='Prom Twin Hunt';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Prom Twin Hunt','Find two people with the same Prom Energy as you.','🧭',40,6,3,false,true);
  end if;
  update public.prom_missions set description='Make a connection with someone from a different course.', icon='✨', reward_xp=45, sort_order=7, min_level=3, is_daily=false, active=true where title='Cross-Campus Spark';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Cross-Campus Spark','Make a connection with someone from a different course.','✨',45,7,3,false,true);
  end if;
  update public.prom_missions set description='Complete one Blind Match successfully.', icon='🔥', reward_xp=60, sort_order=8, min_level=4, is_daily=false, active=true where title='Blind Match Challenge';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Blind Match Challenge','Complete one Blind Match successfully.','🔥',60,8,4,false,true);
  end if;
  update public.prom_missions set description='Save your first Secret Crush.', icon='💗', reward_xp=50, sort_order=9, min_level=4, is_daily=false, active=true where title='Secret Signal';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Secret Signal','Save your first Secret Crush.','💗',50,9,4,false,true);
  end if;
  update public.prom_missions set description='Have a meaningful conversation for at least 5 messages.', icon='💬', reward_xp=75, sort_order=10, min_level=5, is_daily=false, active=true where title='Connection Maker';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Connection Maker','Have a meaningful conversation for at least 5 messages.','💬',75,10,5,false,true);
  end if;
  update public.prom_missions set description='Connect across three different branches.', icon='🌎', reward_xp=90, sort_order=11, min_level=6, is_daily=false, active=true where title='Social Explorer';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Social Explorer','Connect across three different branches.','🌎',90,11,6,false,true);
  end if;
  update public.prom_missions set description='Complete two successful Blind Matches.', icon='💘', reward_xp=100, sort_order=12, min_level=7, is_daily=false, active=true where title='Heartbreaker Trial';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Heartbreaker Trial','Complete two successful Blind Matches.','💘',100,12,7,false,true);
  end if;
  update public.prom_missions set description='Earn three different badges.', icon='👑', reward_xp=125, sort_order=13, min_level=8, is_daily=false, active=true where title='Prom Icon Quest';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Prom Icon Quest','Earn three different badges.','👑',125,13,8,false,true);
  end if;
  update public.prom_missions set description='Create a private Memory Vault entry about your Prom journey.', icon='🌟', reward_xp=150, sort_order=14, min_level=9, is_daily=false, active=true where title='Main Character Moment';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Main Character Moment','Create a private Memory Vault entry about your Prom journey.','🌟',150,14,9,false,true);
  end if;
  update public.prom_missions set description='Reach Level 10 and complete one final Prom challenge.', icon='💎', reward_xp=250, sort_order=15, min_level=10, is_daily=false, active=true where title='Prom Legend Finale';
  if not found then
    insert into public.prom_missions(title,description,icon,reward_xp,sort_order,min_level,is_daily,active) values ('Prom Legend Finale','Reach Level 10 and complete one final Prom challenge.','💎',250,15,10,false,true);
  end if;
end;
$$;

grant execute on function public.ensure_prom_mission_catalog() to authenticated;

select public.ensure_prom_mission_catalog();

create or replace function public.seed_default_blind_questions(uid uuid)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  active_count integer;
  max_sort integer;
  first_interest text;
  second_interest text;
  private_interests boolean;
  energy text;
begin
  select count(*), coalesce(max(sort_order),0) into active_count,max_sort
  from public.blind_questions where user_id=uid and active=true;
  if active_count >= 3 then return; end if;
  select interests[1], interests[2], interests_private, coalesce(prom_energy,'Lowkey')
    into first_interest,second_interest,private_interests,energy
  from public.profiles where id=uid;
  if private_interests then first_interest := null; second_interest := null; end if;
  first_interest := coalesce(first_interest,'music'); second_interest := coalesce(second_interest,'movies');
  if active_count=0 then
    insert into public.blind_questions(user_id,prompt,options,sort_order) values
      (uid,'Which of these would I most likely talk about for ages?',jsonb_build_array(jsonb_build_object('label',first_interest,'correct',true),jsonb_build_object('label','The exam timetable','correct',false),jsonb_build_object('label','Campus parking','correct',false),jsonb_build_object('label','A random attendance report','correct',false)),max_sort+1),
      (uid,'Which topic would make a great late-night Prom conversation with me?',jsonb_build_array(jsonb_build_object('label',second_interest,'correct',true),jsonb_build_object('label','Only grades','correct',false),jsonb_build_object('label','Nothing at all','correct',false),jsonb_build_object('label','A timetable spreadsheet','correct',false)),max_sort+2),
      (uid,'Which Prom mood fits me best?',jsonb_build_array(jsonb_build_object('label',energy,'correct',true),jsonb_build_object('label','I am definitely leaving before the first song','correct',false),jsonb_build_object('label','No conversation allowed','correct',false),jsonb_build_object('label','Only exam discussion','correct',false)),max_sort+3);
  elsif active_count=1 then
    insert into public.blind_questions(user_id,prompt,options,sort_order) values
      (uid,'Which Prom energy is closest to me?',jsonb_build_array(jsonb_build_object('label',energy,'correct',true),jsonb_build_object('label','Silent study mode','correct',false),jsonb_build_object('label','I skipped Prom','correct',false),jsonb_build_object('label','No preference','correct',false)),max_sort+1),
      (uid,'Which topic would I enjoy discussing at Prom?',jsonb_build_array(jsonb_build_object('label',second_interest,'correct',true),jsonb_build_object('label','Only attendance','correct',false),jsonb_build_object('label','Nothing','correct',false),jsonb_build_object('label','Exam schedules','correct',false)),max_sort+2);
  elsif active_count=2 then
    insert into public.blind_questions(user_id,prompt,options,sort_order) values
      (uid,'Which Prom energy is closest to me?',jsonb_build_array(jsonb_build_object('label',energy,'correct',true),jsonb_build_object('label','Silent study mode','correct',false),jsonb_build_object('label','I skipped Prom','correct',false),jsonb_build_object('label','No preference','correct',false)),max_sort+1);
  end if;
end;
$$;

grant execute on function public.seed_default_blind_questions(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- AUTH PROFILE TRIGGER
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql security definer set search_path=public
as $$
begin
  -- Profiles are finalized only after email OTP verification.
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_prom_pulse on auth.users;

create or replace function public.finalize_signup_profile()
returns jsonb language plpgsql security definer
set search_path=public, auth
as $$
declare
  uid uuid := auth.uid();
  u record;
  meta jsonb;
  cfg_college text;
  parsed_age integer;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;

  select id,email,email_confirmed_at,raw_user_meta_data into u
  from auth.users where id=uid;

  if not found or u.email_confirmed_at is null then
    raise exception 'Verify your email before entering Prom Pulse.';
  end if;

  meta := coalesce(u.raw_user_meta_data,'{}'::jsonb);
  select college_name into cfg_college from public.college_config where id=true;

  begin
    parsed_age := nullif(meta->>'age','')::integer;
  exception when others then
    parsed_age := null;
  end;

  insert into public.profiles(
    id,name,email,email_verified,college_name,age,course,pronouns,branch,year,bio,
    interests,interests_private,prom_energy,prom_style,looking_for,joined_at,created_at,updated_at
  ) values(
    uid,
    coalesce(nullif(meta->>'name',''),split_part(coalesce(u.email,''),'@',1),'Student'),
    u.email,true,coalesce(cfg_college,'Your College'),parsed_age,
    nullif(meta->>'course',''),nullif(meta->>'pronouns',''),nullif(meta->>'branch',''),
    coalesce(nullif(meta->>'year',''),'1st year'),nullif(meta->>'bio',''),
    coalesce(array(select jsonb_array_elements_text(coalesce(meta->'interests','[]'::jsonb))),'{}'),
    coalesce((meta->>'interests_private')::boolean,false),
    nullif(meta->>'prom_energy',''),nullif(meta->>'prom_style',''),nullif(meta->>'looking_for',''),
    now(),now(),now()
  )
  on conflict(id) do update set
    email=excluded.email,email_verified=true,name=excluded.name,
    college_name=excluded.college_name,age=excluded.age,course=excluded.course,
    pronouns=excluded.pronouns,branch=excluded.branch,year=excluded.year,bio=excluded.bio,
    interests=excluded.interests,interests_private=excluded.interests_private,
    prom_energy=excluded.prom_energy,prom_style=excluded.prom_style,
    looking_for=excluded.looking_for,updated_at=now();

  insert into public.user_progress(user_id,xp,level,title)
  values(uid,0,1,'Newcomer 💫')
  on conflict(user_id) do nothing;

  perform public.seed_default_blind_questions(uid);
  return jsonb_build_object('user_id',uid,'email_verified',true);
end;
$$;

revoke all on function public.finalize_signup_profile() from public;
grant execute on function public.finalize_signup_profile() to authenticated;

-- Keep existing rows compatible while ensuring unverified accounts are not discoverable.
update public.profiles p
set email_verified=(u.email_confirmed_at is not null), email=coalesce(p.email,u.email)
from auth.users u where u.id=p.id;

create or replace function public.discovery_gender_allowed(viewer_gender text, target_gender text)
returns boolean language sql immutable
as $$
  select case
    when viewer_gender = 'boy' then target_gender = 'girl'
    when viewer_gender = 'girl' then target_gender = 'boy'
    
    else false
  end
$$;

create or replace function public.discovery_target_visible(target_id uuid, viewer_id uuid)
returns boolean language plpgsql stable security definer set search_path=public
as $$
declare viewer_gender text; viewer_college text; target_gender text;
begin
  if viewer_id is null or target_id is null or viewer_id=target_id then return false; end if;
  select gender,college_name into viewer_gender,viewer_college from public.profiles where id=viewer_id;
  select gender into target_gender from public.profiles where id=target_id;
  if viewer_gender is null or target_gender is null then return false; end if;
  if not public.discovery_gender_allowed(viewer_gender,target_gender) then return false; end if;
  if exists(select 1 from public.match_requests r where r.status='accepted' and (r.requester_id=target_id or r.receiver_id=target_id)) then return false; end if;
  if not exists(select 1 from public.profiles p where p.id=target_id and p.college_name=viewer_college and p.banned_at is null and public.auth_user_email_verified(p.id)) then return false; end if;
  if exists(select 1 from public.user_blocks b where (b.blocker_id=target_id and b.blocked_id=viewer_id) or (b.blocker_id=viewer_id and b.blocked_id=target_id)) then return false; end if;
  return true;
end;
$$;

drop function if exists public.unmatch_prom(uuid);
create or replace function public.unmatch_prom(request_uuid uuid)
returns void language plpgsql security definer set search_path=public
as $$
declare uid uuid:=auth.uid(); row_match record;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;
  select * into row_match from public.match_requests r where r.id=request_uuid and (r.requester_id=uid or r.receiver_id=uid) for update;
  if not found then raise exception 'Prom match not found.'; end if;
  if row_match.status <> 'accepted' then raise exception 'Only an accepted Prom match can be unmatched.'; end if;
  update public.match_requests r set status='cancelled',updated_at=now() where r.id=request_uuid;
end;
$$;

revoke all on function public.unmatch_prom(uuid) from public;
grant execute on function public.unmatch_prom(uuid) to authenticated;
revoke all on function public.discovery_gender_allowed(text,text) from public;
grant execute on function public.discovery_gender_allowed(text,text) to authenticated;
revoke all on function public.discovery_target_visible(uuid,uuid) from public;
grant execute on function public.discovery_target_visible(uuid,uuid) to authenticated;

create or replace view public.public_profile_discovery
with (security_invoker = true)
as
select
  p.id,p.name,p.college_name,p.email_verified,p.age,p.course,p.pronouns,p.branch,p.year,
  p.bio,p.avatar_url,
  case when coalesce(p.interests_private,false) then '{}'::text[] else p.interests end as interests,
  coalesce(p.interests_private,false) as interests_private,
  p.prom_energy,p.prom_style,p.looking_for,p.created_at,p.last_seen_at
from public.profiles p
where public.discovery_target_visible(p.id,auth.uid());

grant select on public.public_profile_discovery to authenticated;

-- -----------------------------------------------------------------------------
-- ACCOUNT DELETION
-- Permanently deletes the signed-in user's auth record. All profile-linked rows
-- use ON DELETE CASCADE, so the user's Prom Pulse data is removed as well.
-- Avatar files are removed by the client through the Storage API before this
-- function is called. Direct writes to storage.objects are intentionally avoided
-- because Supabase requires Storage API operations for object deletion.
-- -----------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  delete from auth.users
  where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- REQUESTS / NOTIFICATIONS / CHAT
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
begin
  if auth.uid() is null then raise exception 'You must be signed in.'; end if;
  if target_user_id = auth.uid() then raise exception 'You cannot send a request to yourself.'; end if;

  select college_name into my_college_name from public.college_config where id=true;
  select banned_at,college_name into target_banned,target_college from public.profiles where id=target_user_id;
  if target_college is null then raise exception 'That student profile does not exist.'; end if;
  if target_banned is not null then raise exception 'That account is unavailable.'; end if;
  if target_college <> my_college_name then raise exception 'You can only send requests within your college.'; end if;
  if exists(select 1 from public.user_blocks b where b.blocker_id=target_user_id and b.blocked_id=auth.uid()) then raise exception 'This person is unavailable to you.'; end if;

  select id,status into existing_id,existing_status
  from public.match_requests
  where ((requester_id=auth.uid() and receiver_id=target_user_id) or (requester_id=target_user_id and receiver_id=auth.uid()))
    and status in ('pending','accepted','declined')
  order by created_at desc
  limit 1;

  if existing_id is not null then
    if existing_status='accepted' then raise exception 'You already matched with this person.'; end if;
    if existing_status='pending' then raise exception 'A prom request is already pending.'; end if;
    if existing_status='declined' then raise exception 'This request was already declined and cannot be sent again.'; end if;
  end if;

  insert into public.match_requests(requester_id,receiver_id,status) values(auth.uid(),target_user_id,'pending') returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.send_prom_request(uuid) from public;
grant execute on function public.send_prom_request(uuid) to authenticated;

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
  update public.match_requests set status=new_status::public.match_status, updated_at=now() where id=request_uuid;
end;
$$;
revoke all on function public.respond_prom_request(uuid,text) from public;
grant execute on function public.respond_prom_request(uuid,text) to authenticated;

create or replace function public.notify_match_request()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if new.status='pending' then
    insert into public.notifications(user_id,type,title,body,related_id)
    values(new.receiver_id,'request','New prom request 💗',(select name from public.profiles where id=new.requester_id)||' wants to go to prom with you.',new.id);
  elsif new.status='accepted' then
    insert into public.notifications(user_id,type,title,body,related_id)
    values(new.requester_id,'match','It’s a match ✨',(select name from public.profiles where id=new.receiver_id)||' accepted your prom request.',new.id);
  elsif new.status='declined' then
    insert into public.notifications(user_id,type,title,body,related_id)
    values(new.requester_id,'request','Prom request update',(select name from public.profiles where id=new.receiver_id)||' declined the request.',new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists match_request_notification on public.match_requests;
create trigger match_request_notification after insert or update of status on public.match_requests
for each row execute function public.notify_match_request();

create or replace function public.notify_message()
returns trigger language plpgsql security definer set search_path=public
as $$
declare other_user uuid; sender_name text;
begin
  select case when requester_id=new.sender_id then receiver_id else requester_id end,
         (select name from public.profiles where id=new.sender_id)
    into other_user,sender_name
  from public.match_requests where id=new.conversation_id;
  if other_user is not null then
    insert into public.notifications(user_id,type,title,body,related_id)
    values(other_user,'message','New message 💬',sender_name||': '||left(new.body,120),new.conversation_id);
  end if;
  return new;
end;
$$;

drop trigger if exists message_notification on public.messages;
create trigger message_notification after insert on public.messages for each row execute function public.notify_message();

create or replace function public.save_secret_crush(target_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  uid uuid := auth.uid();
  mutual boolean;
  match_id uuid;
  target_name text;
  crush_id uuid;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;
  if target_user_id is null or target_user_id=uid then raise exception 'Invalid Secret Crush target.'; end if;
  if exists(select 1 from public.user_blocks b where (b.blocker_id=target_user_id and b.blocked_id=uid) or (b.blocker_id=uid and b.blocked_id=target_user_id)) then raise exception 'This person is unavailable.'; end if;
  if not exists(select 1 from public.profiles where id=target_user_id and banned_at is null and college_name=public.my_college()) then raise exception 'That student is unavailable.'; end if;

  select exists(select 1 from public.secret_crushes where from_user_id=target_user_id and to_user_id=uid) into mutual;
  select name into target_name from public.profiles where id=target_user_id;

  insert into public.secret_crushes(from_user_id,to_user_id) values(uid,target_user_id)
  on conflict(from_user_id,to_user_id) do nothing
  returning id into crush_id;

  if crush_id is null then
    select id into crush_id from public.secret_crushes where from_user_id=uid and to_user_id=target_user_id;
  end if;

  if mutual then
    select id into match_id from public.match_requests where (requester_id=uid and receiver_id=target_user_id) or (requester_id=target_user_id and receiver_id=uid) order by created_at desc limit 1;
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

drop trigger if exists secret_crush_notification on public.secret_crushes;
drop function if exists public.notify_secret_crush();

-- -----------------------------------------------------------------------------
-- XP / MISSION RPCS
-- -----------------------------------------------------------------------------
create or replace function public.complete_prom_mission(mission_uuid uuid, proof_text text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  m record;
  uid uuid := auth.uid();
  current_progress record;
  old_level integer;
  new_progress record;
  completion_row record;
  transaction_row record;
  badge_rows jsonb;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;

  select id,title,reward_xp,is_daily,active,min_level into m
  from public.prom_missions where id=mission_uuid and active=true;
  if not found then raise exception 'Mission is not available.'; end if;

  select * into current_progress from public.user_progress where user_id=uid;
  if not found then
    insert into public.user_progress(user_id,xp,level,title) values(uid,0,1,'Newcomer 💫') returning * into current_progress;
  end if;

  if current_progress.level < m.min_level then
    raise exception 'Reach Level % to unlock this mission.', m.min_level;
  end if;

  if m.is_daily then
    if exists(select 1 from public.mission_completions where mission_id=mission_uuid and user_id=uid and completion_date=current_date) then
      raise exception 'Mission already completed for today.';
    end if;
  else
    if exists(select 1 from public.mission_completions where mission_id=mission_uuid and user_id=uid) then
      raise exception 'Mission already completed.';
    end if;
  end if;

  old_level := current_progress.level;
  insert into public.mission_completions(mission_id,user_id,proof,status,completed_at,completion_date)
  values(mission_uuid,uid,left(trim(coalesce(proof_text,'')),1000),'verified',now(),current_date)
  returning * into completion_row;

  insert into public.user_progress(user_id,xp,level,title)
  values(uid,m.reward_xp,public.level_from_xp(m.reward_xp),public.level_title(m.reward_xp))
  on conflict(user_id) do update set
    xp=public.user_progress.xp + m.reward_xp,
    level=public.level_from_xp(public.user_progress.xp + m.reward_xp),
    title=public.level_title(public.user_progress.xp + m.reward_xp),
    updated_at=now()
  returning * into new_progress;

  insert into public.xp_transactions(user_id,amount,source,mission_id,metadata)
  values(uid,m.reward_xp,'mission',mission_uuid,jsonb_build_object('mission_title',m.title,'level',new_progress.level))
  returning * into transaction_row;

  perform public.refresh_badges(uid);
  select coalesce(jsonb_agg(b order by ub.earned_at desc),'[]'::jsonb) into badge_rows
  from public.user_badges ub join public.badges b on b.id=ub.badge_id where ub.user_id=uid;

  return jsonb_build_object(
    'completion_id',completion_row.id,
    'completion_date',completion_row.completion_date,
    'xp_awarded',m.reward_xp,
    'progress',to_jsonb(new_progress),
    'xp_transaction',to_jsonb(transaction_row),
    'level_up',new_progress.level > old_level,
    'new_level',new_progress.level,
    'badges',badge_rows
  );
end;
$$;

-- Blind Match XP is a fixed-purpose function. Users cannot choose the XP amount.
create or replace function public.award_blind_match_xp(opponent_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  uid uuid := auth.uid();
  prog record;
  tx record;
  badge_rows jsonb;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;
  if opponent_user_id is null or opponent_user_id=uid then raise exception 'Invalid Blind Match opponent.'; end if;

  if exists(
    select 1 from public.xp_transactions
    where user_id=uid and source='blind_match'
      and metadata->>'opponent_id'=opponent_user_id::text
      and created_at >= current_date
      and created_at < current_date + interval '1 day'
  ) then
    select * into prog from public.user_progress where user_id=uid;
    return jsonb_build_object('progress',to_jsonb(prog),'xp_transaction',null,'badges',(select coalesce(jsonb_agg(b order by ub.earned_at desc),'[]'::jsonb) from public.user_badges ub join public.badges b on b.id=ub.badge_id where ub.user_id=uid));
  end if;

  insert into public.user_progress(user_id,xp,level,title)
  values(uid,100,public.level_from_xp(100),public.level_title(100))
  on conflict(user_id) do update set
    xp=public.user_progress.xp+100,
    level=public.level_from_xp(public.user_progress.xp+100),
    title=public.level_title(public.user_progress.xp+100),
    updated_at=now()
  returning * into prog;

  insert into public.xp_transactions(user_id,amount,source,metadata)
  values(uid,100,'blind_match',jsonb_build_object('opponent_id',opponent_user_id::text))
  returning * into tx;

  perform public.refresh_badges(uid);
  select coalesce(jsonb_agg(b order by ub.earned_at desc),'[]'::jsonb) into badge_rows
  from public.user_badges ub join public.badges b on b.id=ub.badge_id where ub.user_id=uid;

  return jsonb_build_object('progress',to_jsonb(prog),'xp_transaction',to_jsonb(tx),'badges',badge_rows);
end;
$$;

revoke all on function public.complete_prom_mission(uuid,text) from public;
grant execute on function public.complete_prom_mission(uuid,text) to authenticated;
revoke all on function public.award_blind_match_xp(uuid) from public;
grant execute on function public.award_blind_match_xp(uuid) to authenticated;

create or replace function public.block_user(target_user_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or target_user_id is null or target_user_id=auth.uid() then raise exception 'Invalid block target.'; end if;
  insert into public.user_blocks(blocker_id,blocked_id) values(auth.uid(),target_user_id) on conflict do nothing;
end;
$$;
revoke all on function public.block_user(uuid) from public;
grant execute on function public.block_user(uuid) to authenticated;

create or replace function public.unblock_user(target_user_id uuid)
returns void language sql security definer set search_path=public
as $$ delete from public.user_blocks where blocker_id=auth.uid() and blocked_id=target_user_id $$;
revoke all on function public.unblock_user(uuid) from public;
grant execute on function public.unblock_user(uuid) to authenticated;

create or replace function public.start_blind_round(target_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  uid uuid := auth.uid();
  rid uuid;
  expires timestamptz;
  qids uuid[];
  qjson jsonb;
  qfull jsonb;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;
  if target_user_id is null or target_user_id=uid then raise exception 'Invalid Blind Match target.'; end if;
  if exists(select 1 from public.user_blocks b where (b.blocker_id=target_user_id and b.blocked_id=uid) or (b.blocker_id=uid and b.blocked_id=target_user_id)) then raise exception 'This person is unavailable.'; end if;
  if not exists(select 1 from public.profiles p where p.id=target_user_id and p.banned_at is null and p.college_name=public.my_college()) then raise exception 'That person is unavailable.'; end if;

  select array_agg(x.id),
         jsonb_agg(jsonb_build_object('id',x.id,'prompt',x.prompt,'options',(select jsonb_agg(value->>'label' order by ord) from jsonb_array_elements(x.options) with ordinality as e(value,ord)) ) order by x.sort_order),
         jsonb_agg(jsonb_build_object('id',x.id,'prompt',x.prompt,'options',x.options) order by x.sort_order)
  into qids,qjson,qfull
  from (select id,prompt,options,sort_order from public.blind_questions where user_id=target_user_id and active=true order by random() limit 3) x;
  if coalesce(array_length(qids,1),0) <> 3 then raise exception 'This person has fewer than three active Blind Match questions.'; end if;

  expires := now() + interval '60 seconds';
  insert into public.blind_rounds(challenger_id,target_id,question_ids,question_snapshot,expires_at) values(uid,target_user_id,qids,qfull,expires) returning id into rid;
  return jsonb_build_object('round_id',rid,'target_id',target_user_id,'expires_at',expires,'questions',qjson);
end;
$$;
revoke all on function public.start_blind_round(uuid) from public;
grant execute on function public.start_blind_round(uuid) to authenticated;

create or replace function public.submit_blind_round(round_uuid uuid, answers jsonb)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  uid uuid := auth.uid();
  r record;
  item jsonb;
  q jsonb;
  qid uuid;
  idx integer;
  correct boolean;
  score integer := 0;
  award jsonb;
  seen integer := 0;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;
  select * into r from public.blind_rounds where id=round_uuid and challenger_id=uid for update;
  if not found then raise exception 'Blind Match round not found.'; end if;
  if r.status <> 'active' then return jsonb_build_object('success',r.status='success','score',r.score); end if;
  if now() > r.expires_at then
    update public.blind_rounds set status='expired',answered_at=now() where id=round_uuid;
    return jsonb_build_object('success',false,'expired',true,'score',0);
  end if;
  if jsonb_typeof(answers) <> 'array' or jsonb_array_length(answers) <> 3 then raise exception 'Exactly three answers are required.'; end if;

  for item in select * from jsonb_array_elements(answers) loop
    qid := (item->>'question_id')::uuid;
    idx := (item->>'option_index')::integer;
    select value into q from jsonb_array_elements(r.question_snapshot) where (value->>'id')::uuid=qid;
    if q is null then raise exception 'Invalid question in this round.'; end if;
    if idx < 0 or idx >= jsonb_array_length(q->'options') then raise exception 'Invalid answer.'; end if;
    correct := coalesce(((q->'options'->idx->>'correct')::boolean),false);
    if correct then score := score + 1; end if;
    seen := seen + 1;
  end loop;

  if seen <> 3 then raise exception 'Exactly three answers are required.'; end if;
  if score = 3 then
    update public.blind_rounds set status='success',score=3,answered_at=now() where id=round_uuid;
    begin award := public.award_blind_match_xp(r.target_id); exception when others then award := jsonb_build_object(); end;
    insert into public.notifications(user_id,type,title,body,related_id) values(r.target_id,'blind_success','Someone cracked your Blind Match 🎯','Someone answered all three of your questions before the clock ran out.',round_uuid);
    return jsonb_build_object('success',true,'score',3,'progress',award->'progress','xp_transaction',award->'xp_transaction','badges',award->'badges');
  end if;
  update public.blind_rounds set status='failed',score=score,answered_at=now() where id=round_uuid;
  return jsonb_build_object('success',false,'score',score);
end;
$$;
revoke all on function public.submit_blind_round(uuid,jsonb) from public;
grant execute on function public.submit_blind_round(uuid,jsonb) to authenticated;

create or replace function public.viewer_is_blocked_by(profile_id uuid, viewer_id uuid)
returns boolean language sql stable security definer set search_path=public
as $$
  select exists(select 1 from public.user_blocks where blocker_id=profile_id and blocked_id=viewer_id)
$$;

-- -----------------------------------------------------------------------------
-- RLS: DROP FIRST, THEN CREATE. This is deliberately idempotent.
-- -----------------------------------------------------------------------------
alter table public.college_config enable row level security;
alter table public.profiles enable row level security;
alter table public.match_requests enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;
alter table public.conversation_reads enable row level security;
alter table public.secret_crushes enable row level security;
alter table public.user_blocks enable row level security;
alter table public.blind_questions enable row level security;
alter table public.blind_rounds enable row level security;
alter table public.reports enable row level security;
alter table public.admin_users enable row level security;
alter table public.prom_missions enable row level security;
alter table public.mission_completions enable row level security;
alter table public.memories enable row level security;
alter table public.prom_picks enable row level security;
alter table public.user_progress enable row level security;
alter table public.xp_transactions enable row level security;
alter table public.badges enable row level security;
alter table public.user_badges enable row level security;

-- Known legacy policy names from prior Prom Pulse versions are removed too.
do $$
declare r record;
begin
  for r in select schemaname, tablename, policyname from pg_policies where schemaname='public' and tablename in (
    'college_config','profiles','match_requests','messages','notifications','conversation_reads',
    'secret_crushes','user_blocks','blind_questions','blind_rounds','reports','admin_users','prom_missions','mission_completions','memories',
    'prom_picks','user_progress','xp_transactions','badges','user_badges'
  ) loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

create policy "college_config_read" on public.college_config
for select to authenticated using(true);

create or replace function public.auth_user_email_verified(target_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from auth.users u
    where u.id = target_user_id
      and u.email_confirmed_at is not null
  );
$$;

grant execute on function public.auth_user_email_verified(uuid) to authenticated;

create or replace function public.current_viewer_gender()
returns text language sql stable security definer set search_path=public
as $$ select gender from public.profiles where id=auth.uid() $$;

grant execute on function public.current_viewer_gender() to authenticated;

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
    and public.discovery_gender_allowed(public.current_viewer_gender(),gender)
    and (
      not exists(select 1 from public.match_requests r where r.status='accepted' and (r.requester_id=id or r.receiver_id=id))
      or exists(select 1 from public.match_requests r where r.status='accepted' and ((r.requester_id=auth.uid() and r.receiver_id=id) or (r.requester_id=id and r.receiver_id=auth.uid())))
    )
  )
);

create policy "profiles_insert_self" on public.profiles
for insert to authenticated with check(id=auth.uid() and college_name=public.my_college());

create policy "profiles_update_self_or_admin" on public.profiles
for update to authenticated
using(id=auth.uid() or public.is_admin(auth.uid()))
with check(id=auth.uid() or public.is_admin(auth.uid()));

create policy "match_requests_select_participants" on public.match_requests
for select to authenticated using(public.is_admin(auth.uid()) or ((requester_id=auth.uid() or receiver_id=auth.uid()) and not public.viewer_is_blocked_by(case when requester_id=auth.uid() then receiver_id else requester_id end,auth.uid())));

-- Normal request creation uses the security-definer RPC, so direct INSERT is not needed.
create policy "match_requests_update_receiver_or_admin" on public.match_requests
for update to authenticated
using((receiver_id=auth.uid() and not public.viewer_is_blocked_by(requester_id,auth.uid())) or public.is_admin(auth.uid()))
with check(receiver_id=auth.uid() or public.is_admin(auth.uid()));

create policy "messages_select_match" on public.messages
for select to authenticated
using(public.is_admin(auth.uid()) or exists(
  select 1 from public.match_requests r
  where r.id=conversation_id and r.status='accepted' and (r.requester_id=auth.uid() or r.receiver_id=auth.uid())
    and not public.viewer_is_blocked_by(case when r.requester_id=auth.uid() then r.receiver_id else r.requester_id end,auth.uid())
));

create policy "messages_insert_match" on public.messages
for insert to authenticated
with check(sender_id=auth.uid() and exists(
  select 1 from public.match_requests r
  where r.id=conversation_id and r.status='accepted' and (r.requester_id=auth.uid() or r.receiver_id=auth.uid())
    and not public.viewer_is_blocked_by(case when r.requester_id=auth.uid() then r.receiver_id else r.requester_id end,auth.uid())
));

create policy "notifications_select_self" on public.notifications
for select to authenticated using(user_id=auth.uid());

create policy "notifications_update_self" on public.notifications
for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create policy "conversation_reads_self" on public.conversation_reads
for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create policy "secret_crush_select_self" on public.secret_crushes
for select to authenticated using(from_user_id=auth.uid());

create policy "user_blocks_select_self" on public.user_blocks
for select to authenticated using(blocker_id=auth.uid());

create policy "user_blocks_insert_self" on public.user_blocks
for insert to authenticated with check(blocker_id=auth.uid() and blocked_id<>auth.uid());

create policy "user_blocks_delete_self" on public.user_blocks
for delete to authenticated using(blocker_id=auth.uid());

create policy "blind_questions_select_owner" on public.blind_questions
for select to authenticated using(user_id=auth.uid());

create policy "blind_questions_insert_owner" on public.blind_questions
for insert to authenticated with check(user_id=auth.uid());

create policy "blind_questions_update_owner" on public.blind_questions
for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create policy "blind_questions_delete_owner" on public.blind_questions
for delete to authenticated using(user_id=auth.uid());

create policy "reports_insert_self" on public.reports
for insert to authenticated with check(reporter_id=auth.uid() and reported_id<>auth.uid());

create policy "reports_select_self_or_admin" on public.reports
for select to authenticated using(reporter_id=auth.uid() or public.is_admin(auth.uid()));

create policy "reports_update_admin" on public.reports
for update to authenticated using(public.is_admin(auth.uid())) with check(public.is_admin(auth.uid()));

create policy "admin_select_self" on public.admin_users
for select to authenticated using(user_id=auth.uid() or public.is_admin(auth.uid()));

create policy "missions_read_authenticated" on public.prom_missions
for select to authenticated using(active=true or public.is_admin(auth.uid()));

create policy "mission_completion_read_self" on public.mission_completions
for select to authenticated using(user_id=auth.uid());

create policy "memories_self" on public.memories
for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create policy "picks_self" on public.prom_picks
for select to authenticated using(user_id=auth.uid());

create policy "picks_insert_self" on public.prom_picks
for insert to authenticated with check(user_id=auth.uid());

create policy "progress_select_self" on public.user_progress
for select to authenticated using(user_id=auth.uid() or public.is_admin(auth.uid()));

create policy "xp_select_self" on public.xp_transactions
for select to authenticated using(user_id=auth.uid() or public.is_admin(auth.uid()));

create policy "badges_read_authenticated" on public.badges
for select to authenticated using(true);

create policy "user_badges_select_self" on public.user_badges
for select to authenticated using(user_id=auth.uid() or public.is_admin(auth.uid()));

-- -----------------------------------------------------------------------------
-- ADMIN MISSION REVIEW IS INTENTIONALLY NOT PRESENT.
-- Mission completions are private and immediately complete for the user.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- BADGE TRIGGER / REALTIME / STORAGE
-- -----------------------------------------------------------------------------
create or replace function public.grant_first_connection_badge()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if new.status='accepted' then
    perform public.grant_badge(new.requester_id,'first_connection');
    perform public.grant_badge(new.receiver_id,'first_connection');
  end if;
  return new;
end;
$$;

drop trigger if exists match_first_connection_badge on public.match_requests;
create trigger match_first_connection_badge after insert or update of status on public.match_requests
for each row execute function public.grant_first_connection_badge();

insert into storage.buckets(id,name,public)
values('avatars','avatars',true)
on conflict(id) do nothing;

do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'avatar_%' loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;

create policy "avatar_public_read" on storage.objects for select using(bucket_id='avatars');
create policy "avatar_auth_insert" on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "avatar_owner_update" on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "avatar_owner_delete" on storage.objects for delete to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

-- Realtime subscriptions used by the app.
do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='match_requests') then
    alter publication supabase_realtime add table public.match_requests;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='notifications') then
    alter publication supabase_realtime add table public.notifications;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='secret_crushes') then
    alter publication supabase_realtime add table public.secret_crushes;
  end if;
end $$;

-- Final safety refresh of the mission catalog after all policies/tables exist.
select public.ensure_prom_mission_catalog();

-- Recommended event configuration:
-- update public.college_config
-- set college_name='YOUR COLLEGE', email_domain=null,
--     prom_date='2026-09-05T19:00:00+05:30', prom_title='PROM ''26'
-- where id=true;
