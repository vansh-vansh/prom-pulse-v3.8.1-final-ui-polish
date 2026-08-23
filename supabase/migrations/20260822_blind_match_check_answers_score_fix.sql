-- Prom Pulse: final fix for Blind Match answer submission.
-- Fixes PostgreSQL 42702: column reference "score" is ambiguous.
-- Safe/idempotent: replaces only the submit_blind_round function.

create or replace function public.submit_blind_round(round_uuid uuid, answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r record;
  item jsonb;
  q jsonb;
  qid uuid;
  idx integer;
  correct boolean;
  v_score integer := 0;
  seen_ids uuid[] := '{}';
  expected_ids uuid[];
  award jsonb := '{}'::jsonb;
begin
  if uid is null then
    raise exception 'You must be signed in.';
  end if;

  select *
    into r
  from public.blind_rounds br
  where br.id = round_uuid
    and br.challenger_id = uid
  for update;

  if not found then
    raise exception 'Blind Match round not found.';
  end if;

  if r.status <> 'active' then
    return jsonb_build_object(
      'success', r.status = 'success',
      'score', coalesce(r.score, 0),
      'expired', r.status = 'expired'
    );
  end if;

  if now() >= r.expires_at then
    update public.blind_rounds br
    set status = 'expired',
        answered_at = now()
    where br.id = round_uuid;

    return jsonb_build_object(
      'success', false,
      'expired', true,
      'score', 0
    );
  end if;

  if jsonb_typeof(answers) <> 'array'
     or jsonb_array_length(answers) <> 3 then
    raise exception 'Exactly three answers are required.';
  end if;

  expected_ids := r.question_ids;

  for item in
    select value
    from jsonb_array_elements(answers)
  loop
    begin
      qid := (item->>'question_id')::uuid;
      idx := (item->>'option_index')::integer;
    exception when others then
      raise exception 'Invalid answer format.';
    end;

    if qid is null or idx is null then
      raise exception 'Invalid answer.';
    end if;

    if qid = any(seen_ids) then
      raise exception 'A question can only be answered once.';
    end if;

    if not qid = any(expected_ids) then
      raise exception 'Invalid question in this round.';
    end if;

    select value
      into q
    from jsonb_array_elements(r.question_snapshot)
    where (value->>'id')::uuid = qid;

    if q is null then
      raise exception 'Question data is unavailable for this round.';
    end if;

    if idx < 0 or idx >= jsonb_array_length(q->'options') then
      raise exception 'Invalid answer choice.';
    end if;

    correct := coalesce(
      (q->'options'->idx->>'correct')::boolean,
      false
    );

    if correct then
      v_score := v_score + 1;
    end if;

    seen_ids := array_append(seen_ids, qid);
  end loop;

  if cardinality(seen_ids) <> 3 then
    raise exception 'Exactly three distinct answers are required.';
  end if;

  if not (expected_ids <@ seen_ids and seen_ids <@ expected_ids) then
    raise exception 'All three round questions must be answered.';
  end if;

  if v_score = 3 then
    update public.blind_rounds br
    set status = 'success',
        score = 3,
        answered_at = now()
    where br.id = round_uuid;

    begin
      award := public.award_blind_match_xp(r.target_id);
    exception when others then
      award := '{}'::jsonb;
    end;

    insert into public.notifications(
      user_id,
      type,
      title,
      body,
      related_id
    )
    values (
      r.target_id,
      'blind_success',
      'Someone cracked your Blind Match 🎯',
      'Someone answered all three of your questions before the clock ran out.',
      round_uuid
    );

    return jsonb_build_object(
      'success', true,
      'score', 3,
      'expired', false,
      'progress', award->'progress',
      'xp_transaction', award->'xp_transaction',
      'badges', award->'badges'
    );
  end if;

  update public.blind_rounds br
  set status = 'failed',
      score = v_score,
      answered_at = now()
  where br.id = round_uuid;

  return jsonb_build_object(
    'success', false,
    'score', v_score,
    'expired', false
  );
end;
$$;

revoke all on function public.submit_blind_round(uuid, jsonb) from public;
grant execute on function public.submit_blind_round(uuid, jsonb) to authenticated;
