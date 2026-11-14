-- 白菜記帳：初始資料結構（規格 v2.0 第 4 節）
-- 金額一律 BIGINT 正整數；預設貨幣 TWD、時區 Asia/Taipei；全部資料表啟用 RLS。

create extension if not exists pgcrypto;

-- ───────────────────────── profiles ─────────────────────────
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  currency text not null default 'TWD',
  timezone text not null default 'Asia/Taipei',
  auto_commit boolean not null default true,
  -- 使用者自訂的直接入帳門檻；空值代表用伺服器預設（AUTO_COMMIT_MAX）。不會高於伺服器上限。
  auto_commit_max bigint check (auto_commit_max between 1 and 1000000),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- 使用者只能改直接入帳的開關與門檻，貨幣與時區在 MVP 固定。
revoke update on public.profiles from authenticated;
grant update (auto_commit, auto_commit_max) on public.profiles to authenticated;

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────── categories ─────────────────────────
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  name text not null,
  kind text not null check (kind in ('expense', 'income')),
  icon text not null,
  sort_order integer not null default 0
);

create unique index categories_system_name on public.categories (name) where user_id is null;

alter table public.categories enable row level security;

-- 系統分類（user_id 為空）所有登入者可讀；MVP 不開放自訂分類。
create policy categories_select on public.categories
  for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));

insert into public.categories (name, kind, icon, sort_order) values
  ('飲食', 'expense', 'fork.knife', 1),
  ('交通', 'expense', 'car.fill', 2),
  ('購物', 'expense', 'bag.fill', 3),
  ('居住', 'expense', 'house.fill', 4),
  ('娛樂', 'expense', 'gamecontroller.fill', 5),
  ('醫療', 'expense', 'cross.case.fill', 6),
  ('學習', 'expense', 'book.fill', 7),
  ('訂閱', 'expense', 'repeat', 8),
  ('旅行', 'expense', 'airplane', 9),
  ('人情', 'expense', 'gift.fill', 10),
  ('其他支出', 'expense', 'ellipsis.circle.fill', 11),
  ('收入', 'income', 'banknote.fill', 12);

-- ───────────────────────── entries（原話） ─────────────────────────
create table public.entries (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  raw_text text not null check (char_length(raw_text) between 1 and 500),
  source text not null check (source in ('text', 'voice')),
  intent text check (intent in ('record', 'query', 'unclear')),
  -- 規格列的四種狀態之外，多了 processing（處理中）、unclear（看不懂）、cancelled（使用者取消確認）。
  status text not null default 'processing'
    check (status in ('processing', 'committed', 'needs_confirm', 'answered', 'unclear', 'failed', 'cancelled')),
  -- 第一次處理的結果原樣存下來，同一個 entry_id 重送時直接回傳。
  result jsonb,
  client_created_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index entries_user_created on public.entries (user_id, created_at desc);

alter table public.entries enable row level security;

create policy entries_select_own on public.entries
  for select to authenticated using (user_id = (select auth.uid()));
create policy entries_insert_own on public.entries
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy entries_update_own on public.entries
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- 原話不可修改。
create function public.entries_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.raw_text is distinct from old.raw_text
     or new.user_id is distinct from old.user_id
     or new.client_created_at is distinct from old.client_created_at then
    raise exception '原話與輸入時間不可修改' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger entries_guard before update on public.entries
  for each row execute function public.entries_guard();

-- ───────────────────────── transactions ─────────────────────────
create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  -- 預設填入呼叫者本人；RLS 另外擋掉寫到別人名下。
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  entry_id uuid references public.entries (id) on delete set null,
  type text not null check (type in ('expense', 'income')),
  amount bigint not null check (amount > 0),
  currency text not null default 'TWD',
  occurred_on date not null,
  item text not null check (char_length(item) between 1 and 100),
  merchant text,
  category_id uuid not null references public.categories (id),
  category_source text not null check (category_source in ('ai', 'rule', 'user')),
  tags text[] not null default '{}',
  nature text check (nature in ('routine', 'one_off', 'recurring')),
  payment_method text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index transactions_user_date on public.transactions (user_id, occurred_on);
create index transactions_user_category on public.transactions (user_id, category_id);
create index transactions_tags on public.transactions using gin (tags);
create index transactions_entry on public.transactions (entry_id);

alter table public.transactions enable row level security;

create policy transactions_select_own on public.transactions
  for select to authenticated using (user_id = (select auth.uid()));
create policy transactions_insert_own on public.transactions
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy transactions_update_own on public.transactions
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
-- 沒有 delete policy：使用者只能軟刪除。整批清除走 delete_all_my_data()。

-- ───────────────────────── user_rules ─────────────────────────
create table public.user_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  match_text text not null check (char_length(match_text) between 1 and 100),
  category_id uuid not null references public.categories (id),
  hits integer not null default 0,
  updated_at timestamptz not null default now(),
  unique (user_id, match_text)
);

alter table public.user_rules enable row level security;

create policy user_rules_select_own on public.user_rules
  for select to authenticated using (user_id = (select auth.uid()));
create policy user_rules_update_own on public.user_rules
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- 交易的保護與學習：
-- 1. category_source = user 的分類，任何自動流程都不得覆寫。
-- 2. 使用者手動指定分類（新增或修改）時，以 merchant（沒有就用 item）建立或更新規則。
create function public.transactions_before_update() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.category_source = 'user'
     and new.category_source <> 'user'
     and new.category_id is distinct from old.category_id then
    raise exception '使用者指定的分類不可被自動流程覆寫' using errcode = 'check_violation';
  end if;
  if old.category_source = 'user' and new.category_source <> 'user' then
    new.category_source := 'user';
  end if;
  if new.user_id is distinct from old.user_id then
    raise exception '不可變更交易的擁有者' using errcode = 'check_violation';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger transactions_before_update before update on public.transactions
  for each row execute function public.transactions_before_update();

create function public.transactions_learn_rule() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  key text;
begin
  if new.category_source = 'user'
     and (tg_op = 'INSERT' or new.category_id is distinct from old.category_id) then
    key := lower(btrim(coalesce(nullif(btrim(new.merchant), ''), new.item)));
    if key is not null and key <> '' then
      insert into public.user_rules (user_id, match_text, category_id, hits, updated_at)
      values (new.user_id, left(key, 100), new.category_id, 0, now())
      on conflict (user_id, match_text)
      do update set category_id = excluded.category_id, updated_at = now();
    end if;
  end if;
  return new;
end;
$$;

create trigger transactions_learn_rule after insert or update on public.transactions
  for each row execute function public.transactions_learn_rule();

-- ───────────────────────── ai_usage ─────────────────────────
create table public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  feature text not null check (feature in ('record', 'ask')),
  model text not null,
  input_tokens integer not null default 0,
  output_tokens integer not null default 0,
  latency_ms integer not null default 0,
  created_at timestamptz not null default now()
);

create index ai_usage_user_feature_time on public.ai_usage (user_id, feature, created_at);

alter table public.ai_usage enable row level security;

-- 只能讀自己的用量；寫入由 Edge Function 用 service role 做，使用者無法自己增刪。
create policy ai_usage_select_own on public.ai_usage
  for select to authenticated using (user_id = (select auth.uid()));

-- ───────────────────────── 查帳用的參數化查詢 ─────────────────────────
-- 全部是 security invoker：以呼叫者身分執行，RLS 與 auth.uid() 同時把關。

create function public.like_escape(s text) returns text
language sql immutable set search_path = '' as $$
  select replace(replace(replace(s, '\', '\\'), '%', '\%'), '_', '\_');
$$;

create function public.q_filtered(filters jsonb) returns setof public.transactions
language sql stable set search_path = '' as $$
  select t.*
  from public.transactions t
  where t.user_id = (select auth.uid())
    and t.deleted_at is null
    and (filters ->> 'date_from' is null or t.occurred_on >= (filters ->> 'date_from')::date)
    and (filters ->> 'date_to' is null or t.occurred_on <= (filters ->> 'date_to')::date)
    and (filters ->> 'type' is null or t.type = filters ->> 'type')
    and (filters ->> 'nature' is null or t.nature = filters ->> 'nature')
    and (filters ->> 'amount_min' is null or t.amount >= (filters ->> 'amount_min')::bigint)
    and (filters ->> 'amount_max' is null or t.amount <= (filters ->> 'amount_max')::bigint)
    and (
      filters -> 'categories' is null or jsonb_typeof(filters -> 'categories') <> 'array'
      or jsonb_array_length(filters -> 'categories') = 0
      or t.category_id in (
        select c.id from public.categories c
        where c.name in (select jsonb_array_elements_text(filters -> 'categories'))
      )
    )
    and (
      filters -> 'tags' is null or jsonb_typeof(filters -> 'tags') <> 'array'
      or jsonb_array_length(filters -> 'tags') = 0
      or t.tags && array(select jsonb_array_elements_text(filters -> 'tags'))
    )
    and (
      filters ->> 'merchant_contains' is null
      or t.merchant ilike '%' || public.like_escape(filters ->> 'merchant_contains') || '%'
    )
    and (
      filters ->> 'text_contains' is null
      or t.item ilike '%' || public.like_escape(filters ->> 'text_contains') || '%'
      or t.merchant ilike '%' || public.like_escape(filters ->> 'text_contains') || '%'
      or t.note ilike '%' || public.like_escape(filters ->> 'text_contains') || '%'
      or exists (
        select 1 from public.entries e
        where e.id = t.entry_id
          and e.raw_text ilike '%' || public.like_escape(filters ->> 'text_contains') || '%'
      )
    );
$$;

create function public.q_sum(filters jsonb) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'total', coalesce(sum(amount), 0),
    'count', count(*),
    'transaction_ids', coalesce(
      (select jsonb_agg(id) from (
        select id from public.q_filtered(filters) order by occurred_on desc, created_at desc limit 200
      ) s), '[]'::jsonb)
  )
  from public.q_filtered(filters);
$$;

create function public.q_group(filters jsonb, group_by text) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  result jsonb;
begin
  if group_by not in ('category', 'tag', 'merchant', 'nature', 'day', 'month') then
    raise exception 'group_by 不支援：%', group_by using errcode = 'invalid_parameter_value';
  end if;

  with base as (select * from public.q_filtered(filters)),
  keyed as (
    select
      case group_by
        when 'category' then (select c.name from public.categories c where c.id = b.category_id)
        when 'merchant' then coalesce(nullif(btrim(b.merchant), ''), '（未填商家）')
        when 'nature' then coalesce(b.nature, '（未分）')
        when 'day' then to_char(b.occurred_on, 'YYYY-MM-DD')
        when 'month' then to_char(b.occurred_on, 'YYYY-MM')
      end as key,
      b.amount
    from base b
    where group_by <> 'tag'
    union all
    select tag as key, b.amount
    from base b cross join lateral unnest(b.tags) as tag
    where group_by = 'tag'
  ),
  grouped as (
    select key, sum(amount) as total, count(*) as cnt from keyed group by key
  )
  select jsonb_build_object(
    'group_by', group_by,
    'groups', coalesce(
      (select jsonb_agg(jsonb_build_object('key', key, 'total', total, 'count', cnt) order by
         case when group_by in ('day', 'month') then key end asc,
         total desc, key asc)
       from grouped), '[]'::jsonb),
    'total', (select coalesce(sum(amount), 0) from base),
    'count', (select count(*) from base)
  ) into result;

  return result;
end;
$$;

create function public.q_list(filters jsonb, sort text default 'date_desc', max_rows integer default 20)
returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'transactions', coalesce(jsonb_agg(row_to_json(s)::jsonb), '[]'::jsonb),
    'count', count(*),
    'total', coalesce(sum(s.amount), 0)
  )
  from (
    select t.id, t.type, t.amount, t.occurred_on, t.item, t.merchant,
           (select c.name from public.categories c where c.id = t.category_id) as category,
           t.tags, t.nature
    from public.q_filtered(filters) t
    order by
      case when sort = 'amount_desc' then t.amount end desc,
      case when sort = 'amount_asc' then t.amount end asc,
      case when sort = 'date_asc' then t.occurred_on end asc,
      case when sort not in ('amount_desc', 'amount_asc', 'date_asc') then t.occurred_on end desc,
      t.created_at desc
    limit least(greatest(coalesce(max_rows, 20), 1), 20)
  ) s;
$$;

create function public.q_compare(filters jsonb, period_a jsonb, period_b jsonb) returns jsonb
language sql stable set search_path = '' as $$
  with a as (
    select coalesce(sum(amount), 0) as total, count(*) as cnt
    from public.q_filtered(filters || jsonb_build_object(
      'date_from', period_a ->> 'date_from', 'date_to', period_a ->> 'date_to'))
  ),
  b as (
    select coalesce(sum(amount), 0) as total, count(*) as cnt
    from public.q_filtered(filters || jsonb_build_object(
      'date_from', period_b ->> 'date_from', 'date_to', period_b ->> 'date_to'))
  )
  select jsonb_build_object(
    'period_a', jsonb_build_object('date_from', period_a ->> 'date_from', 'date_to', period_a ->> 'date_to',
                                   'total', a.total, 'count', a.cnt),
    'period_b', jsonb_build_object('date_from', period_b ->> 'date_from', 'date_to', period_b ->> 'date_to',
                                   'total', b.total, 'count', b.cnt),
    'difference', a.total - b.total,
    'abs_difference', abs(a.total - b.total)
  )
  from a, b;
$$;

-- ───────────────────────── 本月概覽 ─────────────────────────
create function public.monthly_overview(month date) returns jsonb
language sql stable set search_path = '' as $$
  with base as (
    select t.*
    from public.transactions t
    where t.user_id = (select auth.uid())
      and t.deleted_at is null
      and t.occurred_on >= date_trunc('month', month)::date
      and t.occurred_on < (date_trunc('month', month) + interval '1 month')::date
  )
  select jsonb_build_object(
    'month', to_char(date_trunc('month', month), 'YYYY-MM'),
    'total_expense', (select coalesce(sum(amount), 0) from base where type = 'expense'),
    'total_income', (select coalesce(sum(amount), 0) from base where type = 'income'),
    'routine_expense', (select coalesce(sum(amount), 0) from base
                        where type = 'expense' and nature is distinct from 'one_off'),
    'one_off_expense', (select coalesce(sum(amount), 0) from base
                        where type = 'expense' and nature = 'one_off'),
    'transaction_count', (select count(*) from base),
    'by_category', coalesce((
      select jsonb_agg(jsonb_build_object(
        'category_id', g.category_id, 'name', g.name, 'icon', g.icon,
        'total', g.total, 'count', g.cnt) order by g.total desc, g.name)
      from (
        select b.category_id, c.name, c.icon, sum(b.amount) as total, count(*) as cnt
        from base b join public.categories c on c.id = b.category_id
        where b.type = 'expense'
        group by b.category_id, c.name, c.icon
      ) g), '[]'::jsonb)
  );
$$;

-- ───────────────────────── 刪除所有資料 ─────────────────────────
create function public.delete_all_my_data() returns void
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception '尚未登入' using errcode = 'insufficient_privilege';
  end if;
  delete from public.transactions where user_id = uid;
  delete from public.entries where user_id = uid;
  delete from public.user_rules where user_id = uid;
  delete from public.ai_usage where user_id = uid;
  update public.profiles set auto_commit = true, auto_commit_max = null where id = uid;
end;
$$;

-- 規則命中次數 +1（由 Edge Function 以使用者身分呼叫）。
create function public.bump_rule_hits(rule_ids uuid[]) returns void
language sql set search_path = '' as $$
  update public.user_rules set hits = hits + 1
  where id = any (rule_ids) and user_id = (select auth.uid());
$$;

revoke execute on all functions in schema public from anon, public;
grant execute on function
  public.q_filtered(jsonb), public.q_sum(jsonb), public.q_group(jsonb, text),
  public.q_list(jsonb, text, integer), public.q_compare(jsonb, jsonb, jsonb),
  public.monthly_overview(date), public.delete_all_my_data(), public.bump_rule_hits(uuid[]),
  public.like_escape(text)
  to authenticated;

revoke all on all tables in schema public from anon;
