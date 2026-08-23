-- Prom Pulse launch-critical gender discovery + unmatch migration.
-- Idempotent and non-destructive. Existing users must choose a gender in Profile
-- before they reappear in gender-filtered discovery.

alter table public.profiles
  add column if not exists gender text;

-- Keep the existing match_status enum. `cancelled` is already part of the enum
-- and represents an unmatch without deleting the conversation record.

drop function if exists public.unmatch_prom(uuid);
create or replace function public.unmatch_prom(request_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  row_match record;
begin
  if uid is null then
    raise exception 'You must be signed in.';
  end if;

  select * into row_match
  from public.match_requests r
  where r.id = request_uuid
    and (r.requester_id = uid or r.receiver_id = uid)
  for update;

  if not found then
    raise exception 'Prom match not found.';
  end if;

  if row_match.status <> 'accepted' then
    raise exception 'Only an accepted Prom match can be unmatched.';
  end if;

  update public.match_requests r
  set status = 'cancelled', updated_at = now()
  where r.id = request_uuid;
end;
$$;

revoke all on function public.unmatch_prom(uuid) from public;
grant execute on function public.unmatch_prom(uuid) to authenticated;

create or replace function public.discovery_gender_allowed(viewer_gender text, target_gender text)
returns boolean
language sql
immutable
as $$
  select case
    when viewer_gender = 'boy' then target_gender = 'girl'
    when viewer_gender = 'girl' then target_gender = 'boy'
    when viewer_gender = 'gay' then target_gender = 'boy'
    else false
  end
$$;

revoke all on function public.discovery_gender_allowed(text,text) from public;
grant execute on function public.discovery_gender_allowed(text,text) to authenticated;

create or replace function public.discovery_target_visible(target_id uuid, viewer_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer_gender text;
  viewer_college text;
  target_gender text;
begin
  if viewer_id is null or target_id is null or viewer_id = target_id then
    return false;
  end if;

  select p.gender, p.college_name
    into viewer_gender, viewer_college
  from public.profiles p
  where p.id = viewer_id;

  select p.gender into target_gender
  from public.profiles p
  where p.id = target_id;

  if viewer_gender is null or target_gender is null then
    return false;
  end if;

  if not public.discovery_gender_allowed(viewer_gender, target_gender) then
    return false;
  end if;

  if exists (
    select 1 from public.match_requests r
    where r.status = 'accepted'
      and (r.requester_id = target_id or r.receiver_id = target_id)
  ) then
    return false;
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = target_id
      and p.college_name = viewer_college
      and p.banned_at is null
      and public.auth_user_email_verified(p.id)
  ) then
    return false;
  end if;

  if exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = target_id and b.blocked_id = viewer_id)
       or (b.blocker_id = viewer_id and b.blocked_id = target_id)
  ) then
    return false;
  end if;

  return true;
end;
$$;

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
where public.discovery_target_visible(p.id, auth.uid());

grant select on public.public_profile_discovery to authenticated;

-- Keep the consolidated schema in sync for future environments.

create or replace function public.current_viewer_gender()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select gender from public.profiles where id = auth.uid()
$$;

revoke all on function public.current_viewer_gender() from public;
grant execute on function public.current_viewer_gender() to authenticated;

-- Enforce the same visibility rules at the table level so the UI cannot be
-- bypassed by directly querying public.profiles.
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
    and (
      not exists(select 1 from public.match_requests r where r.status='accepted' and (r.requester_id=id or r.receiver_id=id))
      or exists(select 1 from public.match_requests r where r.status='accepted' and ((r.requester_id=auth.uid() and r.receiver_id=id) or (r.requester_id=id and r.receiver_id=auth.uid())))
    )
  )
);
