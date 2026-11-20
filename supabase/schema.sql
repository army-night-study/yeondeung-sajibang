-- 사이버지식정보방 연등 · Supabase schema for the monthly records (월간 베스트 부대)
-- Paste this whole file into Supabase → SQL Editor → Run. It is safe to run again.
--
-- Each browser signs in as an anonymous Supabase user (no email, no personal data). The page never
-- writes the table directly: it calls report_time() about once a minute with the minutes it counted
-- since the last report, and the server only accepts as many minutes as real time has passed, only
-- between 19:00 and 06:00 (Korea time). month_ranking() returns the totals per 소속 and the top 20,
-- without anyone's user id.

create table if not exists public.daily_time (
  uid        uuid        not null references auth.users (id) on delete cascade,
  day        date        not null,                       -- the 연등 day: before 06:00 counts as the day before
  corps      text        not null,
  name       text        not null default '',
  minutes    int         not null default 0 check (minutes between 0 and 720),
  updated_at timestamptz not null default now(),
  primary key (uid, day)
);
create index if not exists daily_time_day on public.daily_time (day);

-- Row level security on, and no policies: nobody can read or write the table directly with the
-- public key. Only the two functions below (security definer) touch it.
alter table public.daily_time enable row level security;
revoke all on public.daily_time from anon, authenticated;

create or replace function public.report_time(p_day date, p_add int, p_corps text, p_name text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  me       uuid := auth.uid();
  kst      timestamp := now() at time zone 'Asia/Seoul';
  today    date := (kst - interval '6 hours')::date;
  hr       int := extract(hour from kst);
  prev_min int;
  prev_at  timestamptz;
  allowed  int;
  total    int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_day is null or p_day not in (today, today - 1) then raise exception 'bad day'; end if;
  if p_corps is null or p_corps not in ('c1','c2','c3','c5','c7','cs','op2','cdc','sw','adr','navy','af','mc','mnd') then
    raise exception 'bad corps';
  end if;
  p_name := left(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]]', '', 'g'), 20);
  p_add := greatest(coalesce(p_add, 0), 0);
  if hr between 6 and 18 then p_add := 0; end if;          -- the record runs 19:00–06:00 only

  select minutes, updated_at into prev_min, prev_at
    from daily_time where uid = me and day = p_day for update;

  if not found then
    allowed := least(p_add, 2);                             -- the page reports every minute
    insert into daily_time (uid, day, corps, name, minutes) values (me, p_day, p_corps, p_name, allowed);
    return allowed;
  end if;

  -- no more minutes than real time has passed since the last report (plus one for timer drift)
  allowed := least(p_add, ceil(extract(epoch from now() - prev_at) / 60)::int + 1);
  total := least(prev_min + allowed, 720);
  update daily_time set minutes = total, corps = p_corps, name = p_name, updated_at = now()
    where uid = me and day = p_day;
  return total;
end;
$$;

create or replace function public.month_ranking(p_month date default null)
returns json
language sql
stable
security definer
set search_path = public
as $$
  with m as (
    select date_trunc('month', coalesce(p_month, ((now() at time zone 'Asia/Seoul') - interval '6 hours')::date))::date as s
  ),
  r as (
    select d.* from daily_time d, m
     where d.day >= m.s and d.day < (m.s + interval '1 month')::date and d.minutes > 0
  ),
  per_user as (
    select uid,
           (array_agg(name order by day desc))[1]  as name,
           (array_agg(corps order by day desc))[1] as corps,
           sum(minutes)::int as minutes
      from r group by uid
  )
  select json_build_object(
    'month', (select to_char(s, 'YYYY-MM') from m),
    'corps', coalesce((
      select json_agg(c order by c.minutes desc)
        from (select corps, sum(minutes)::int as minutes, count(distinct uid)::int as people from r group by corps) c
    ), '[]'::json),
    'top', coalesce((
      select json_agg(u order by u.minutes desc)
        from (select name, corps, minutes, (uid = auth.uid()) as me from per_user order by minutes desc limit 20) u
    ), '[]'::json),
    'mine', (select coalesce(sum(minutes), 0)::int from r where uid = auth.uid())
  );
$$;

revoke execute on function public.report_time(date, int, text, text) from public, anon;
grant  execute on function public.report_time(date, int, text, text) to authenticated;
revoke execute on function public.month_ranking(date) from public;
grant  execute on function public.month_ranking(date) to anon, authenticated;
