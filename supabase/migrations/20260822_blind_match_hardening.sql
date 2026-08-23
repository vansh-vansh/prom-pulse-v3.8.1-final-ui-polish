-- Prom Pulse: Blind Match hardening + question-bank reliability.
-- Idempotent and safe for existing users. Does not delete custom questions.

-- Keep the original full branch catalog used by the existing app. The branch
-- selector is a product catalog, not a list inferred from current profiles.
-- No database constraint is changed here because existing profile data must survive.

-- Ensure every existing account has at least three active questions. Custom
-- questions are preserved; the helper only tops up missing active questions.
do $$
declare r record;
begin
  for r in select id from public.profiles loop
    perform public.seed_default_blind_questions(r.id);
  end loop;
end $$;

-- Server-side round creation. The browser receives prompts/options only.
-- Correct-answer metadata remains inside question_snapshot on the server.
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
  if target_user_id is null or target_user_id = uid then raise exception 'Invalid Blind Match target.'; end if;
  if exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = target_user_id and b.blocked_id = uid)
       or (b.blocker_id = uid and b.blocked_id = target_user_id)
  ) then raise exception 'This person is unavailable.'; end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = target_user_id
      and p.banned_at is null
      and p.college_name = public.my_college()
      and p.email_verified = true
  ) then raise exception 'That person is unavailable.'; end if;

  perform public.seed_default_blind_questions(target_user_id);

  select array_agg(x.id order by x.random_key),
         jsonb_agg(
           jsonb_build_object(
             'id', x.id,
             'prompt', x.prompt,
             'options', (
               select jsonb_agg(value->>'label' order by ord)
               from jsonb_array_elements(x.options) with ordinality as e(value, ord)
             )
           ) order by x.random_key
         ),
         jsonb_agg(
           jsonb_build_object('id', x.id, 'prompt', x.prompt, 'options', x.options)
           order by x.random_key
         )
    into qids, qjson, qfull
  from (
    select id, prompt, options, random() as random_key
    from public.blind_questions
    where user_id = target_user_id and active = true
    order by random()
    limit 3
  ) x;

  if coalesce(array_length(qids, 1), 0) <> 3 then
    raise exception 'This person needs at least three active Blind Match questions.';
  end if;

  expires := now() + interval '60 seconds';
  insert into public.blind_rounds(challenger_id, target_id, question_ids, question_snapshot, expires_at)
  values(uid, target_user_id, qids, qfull, expires)
  returning id into rid;

  return jsonb_build_object(
    'round_id', rid,
    'target_id', target_user_id,
    'expires_at', expires,
    'questions', qjson
  );
end;
$$;
revoke all on function public.start_blind_round(uuid) from public;
grant execute on function public.start_blind_round(uuid) to authenticated;

-- Strict server-side scoring. Each of the three distinct round questions must
-- be answered exactly once. The client never receives the correct flags.
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
  seen_ids uuid[] := '{}';
  expected_ids uuid[];
  award jsonb;
begin
  if uid is null then raise exception 'You must be signed in.'; end if;
  select * into r from public.blind_rounds where id = round_uuid and challenger_id = uid for update;
  if not found then raise exception 'Blind Match round not found.'; end if;
  if r.status <> 'active' then
    return jsonb_build_object('success', r.status = 'success', 'score', coalesce(r.score, 0), 'expired', r.status = 'expired');
  end if;
  if now() > r.expires_at then
    update public.blind_rounds set status='expired', answered_at=now() where id=round_uuid;
    return jsonb_build_object('success', false, 'expired', true, 'score', 0);
  end if;
  if jsonb_typeof(answers) <> 'array' or jsonb_array_length(answers) <> 3 then
    raise exception 'Exactly three answers are required.';
  end if;

  expected_ids := r.question_ids;
  for item in select * from jsonb_array_elements(answers) loop
    qid := (item->>'question_id')::uuid;
    idx := (item->>'option_index')::integer;
    if qid = any(seen_ids) then raise exception 'A Blind Match question can only be answered once.'; end if;
    if not qid = any(expected_ids) then raise exception 'Invalid question in this round.'; end if;
    seen_ids := array_append(seen_ids, qid);

    select value into q
    from jsonb_array_elements(r.question_snapshot)
    where (value->>'id')::uuid = qid;
    if q is null then raise exception 'Invalid question in this round.'; end if;
    if idx < 0 or idx >= jsonb_array_length(q->'options') then raise exception 'Invalid answer.'; end if;
    correct := coalesce(((q->'options'->idx->>'correct')::boolean), false);
    if correct then score := score + 1; end if;
  end loop;

  if cardinality(seen_ids) <> 3 then raise exception 'Exactly three distinct answers are required.'; end if;
  if not (expected_ids <@ seen_ids and seen_ids <@ expected_ids) then raise exception 'All round questions must be answered.'; end if;

  if score = 3 then
    update public.blind_rounds set status='success', score=3, answered_at=now() where id=round_uuid;
    begin
      award := public.award_blind_match_xp(r.target_id);
    exception when others then
      award := jsonb_build_object();
    end;
    insert into public.notifications(user_id,type,title,body,related_id)
    values(r.target_id,'blind_success','Someone cracked your Blind Match 🎯','Someone answered all three of your questions before the clock ran out.',round_uuid);
    return jsonb_build_object('success',true,'score',3,'progress',award->'progress','xp_transaction',award->'xp_transaction','badges',award->'badges');
  end if;

  update public.blind_rounds set status='failed', score=score, answered_at=now() where id=round_uuid;
  return jsonb_build_object('success',false,'score',score);
end;
$$;
revoke all on function public.submit_blind_round(uuid,jsonb) from public;
grant execute on function public.submit_blind_round(uuid,jsonb) to authenticated;
