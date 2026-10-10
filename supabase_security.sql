-- ============================================================================
-- TECHTRIX 2026 PORTAL — SECURITY MIGRATION
-- Run this ONCE in the Supabase SQL Editor, AFTER supabase_schema.sql.
-- (Do NOT re-run supabase_schema.sql afterwards — this drops password_hash.)
--
-- What it does:
--   1. portal_users  -> every account gets a real Supabase Auth user;
--      password_hash column is DROPPED (no more readable hashes, no more
--      client-side password comparison).
--   2. Role-based RLS on portal_users / portal_tasks / portal_outputs /
--      portal_posts: only authenticated sessions, access enforced per role
--      (admin / head / member) at the database level. Anon is fully locked out.
--   3. portal_metrics view: deliverable counts are computed by the database
--      from RLS-authorized task records — the browser can no longer submit
--      arbitrary completion numbers.
--
-- The 9 seed accounts below keep their existing passwords (they are recreated
-- as Supabase Auth users). Members you added through the old portal cannot be
-- migrated automatically (only their SHA-256 hashes are stored, not plaintext):
--   select create_member('<id>', '<Full Name>', '<password>', '<dept>');
-- ----------------------------------------------------------------------------

create extension if not exists pgcrypto;

-- ============================================================================
-- 1. SUPABASE AUTH
-- ============================================================================

-- Link column: portal_users row <-> auth.users row
alter table portal_users
  add column if not exists auth_id uuid unique references auth.users(id) on delete cascade;

-- Helper used only from this SQL file (postgres/SQL Editor context).
create or replace function portal_seed_auth(p_id text, p_password text)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_uid   uuid;
  v_email text := p_id || '@techtrix.local';
begin
  if not exists (select 1 from portal_users where id = p_id) then
    return null; -- seed only users that actually exist
  end if;

  select id into v_uid from auth.users where email = v_email;

  if v_uid is null then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
      'authenticated', 'authenticated', v_email,
      crypt(p_password, gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{}', now(), now()
    )
    returning id into v_uid;
  else
    update auth.users
      set encrypted_password = crypt(p_password, gen_salt('bf')),
          email_confirmed_at = coalesce(email_confirmed_at, now())
      where id = v_uid;
  end if;

  update portal_users set auth_id = v_uid where id = p_id;
  return v_uid;
end $$;

-- Recreate the 9 seed accounts with their existing passwords
select portal_seed_auth('admin1',         'Sr#4827');
select portal_seed_auth('admin2',         'An#9153');
select portal_seed_auth('creative.head',  'Vg#6204');
select portal_seed_auth('vp1.head',       'Ym#3719');
select portal_seed_auth('vp2.head',       'Dp#8452');
select portal_seed_auth('pr.head',        'Vt#5036');
select portal_seed_auth('adm.head',       'Pg#7261');
select portal_seed_auth('sr.head',        'As#1948');
select portal_seed_auth('member.demo',    'Mb#2580');

-- create_member: heads/admins add members through this RPC from the portal.
-- The password is stored as a bcrypt hash in auth.users — never in portal_users.
create or replace function create_member(
  p_id text, p_name text, p_pw text, p_dept text
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_role  text;
  v_dept  text;
  v_uid   uuid;
  v_email text := lower(p_id) || '@techtrix.local';
begin
  -- Client calls (PostgREST) must be an admin, or a head of the same dept.
  -- SQL Editor calls carry no auth.uid() and run as the trusted postgres role.
  if auth.uid() is not null then
    select role, dept into v_role, v_dept
      from portal_users where auth_id = auth.uid();
    if v_role is null or v_role = 'member'
       or not (v_role = 'admin' or (v_role = 'head' and p_dept = v_dept)) then
      raise exception 'not allowed';
    end if;
  end if;

  if p_id is null or p_id !~ '^[a-z0-9._]{3,20}$' then
    raise exception 'invalid user id';
  end if;
  if p_name is null or length(trim(p_name)) < 2 then
    raise exception 'invalid name';
  end if;
  if p_pw is null or length(p_pw) < 6 then
    raise exception 'password must be at least 6 characters';
  end if;
  if p_dept is null or p_dept not in
     ('Creative','Vice President 1','Vice President 2',
      'PR & Relations','Administration','Student Relations') then
    raise exception 'invalid department';
  end if;
  if exists (select 1 from portal_users where lower(id) = lower(p_id)) then
    raise exception 'user id already exists';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
    'authenticated', 'authenticated', v_email,
    crypt(p_pw, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  )
  returning id into v_uid;

  insert into portal_users (id, name, role, dept, auth_id)
  values (lower(p_id), trim(p_name), 'member', p_dept, v_uid);
end $$;

revoke execute on function create_member(text, text, text, text) from public, anon;
grant  execute on function create_member(text, text, text, text) to authenticated;
revoke execute on function portal_seed_auth(text, text) from public, anon, authenticated;

-- Password hashes are no longer stored by the app at all: drop the column so
-- they can never be read again, by anon, authenticated or anyone else.
alter table portal_users drop column if exists password_hash;

-- ============================================================================
-- 2. ROLE HELPERS + ROLE-BASED RLS
-- ============================================================================

-- Defense in depth: ensure RLS is on for every exposed table (no-op when
-- supabase_schema.sql already enabled it). Note the real table names —
-- there is no public.tasks or public.feedback; they are portal_tasks and
-- portal_posts.
alter table portal_users  enable row level security;
alter table portal_tasks  enable row level security;
alter table portal_outputs enable row level security;
alter table portal_posts  enable row level security;

create or replace function portal_role() returns text
  language sql stable security definer set search_path=public as $$
  select role from portal_users where auth_id = auth.uid() $$;

create or replace function portal_dept() returns text
  language sql stable security definer set search_path=public as $$
  select dept from portal_users where auth_id = auth.uid() $$;

create or replace function portal_self_id() returns text
  language sql stable security definer set search_path=public as $$
  select id from portal_users where auth_id = auth.uid() $$;

-- ---- drop every old demo policy ----
drop policy if exists "demo read users"        on portal_users;
drop policy if exists "demo insert users"      on portal_users;
drop policy if exists "demo update users"      on portal_users;
drop policy if exists "demo read tasks"        on portal_tasks;
drop policy if exists "demo insert tasks"      on portal_tasks;
drop policy if exists "demo update tasks"      on portal_tasks;
drop policy if exists "demo read outputs"      on portal_outputs;
drop policy if exists "demo insert outputs"    on portal_outputs;
drop policy if exists "demo update outputs"    on portal_outputs;
drop policy if exists "demo read posts"        on portal_posts;
drop policy if exists "demo insert posts"      on portal_posts;
drop policy if exists "demo update posts"      on portal_posts;
drop policy if exists "demo delete posts"      on portal_posts;

-- ---- portal_users: profiles are readable by signed-in users only ----
create policy "users read" on portal_users
  for select to authenticated using (true);

create policy "users update admin" on portal_users
  for update to authenticated
  using (portal_role() = 'admin') with check (portal_role() = 'admin');

create policy "users delete admin" on portal_users
  for delete to authenticated using (portal_role() = 'admin');
-- No INSERT policy: rows are only created by create_member() (definer rights).
-- password_hash column no longer exists.

-- ---- portal_tasks ----
create policy "tasks read" on portal_tasks
  for select to authenticated using (
    portal_role() = 'admin'
    or (portal_role() = 'head'  and dept = portal_dept())
    or (portal_role() = 'member' and assignee_id = portal_self_id()));

create policy "tasks insert" on portal_tasks
  for insert to authenticated with check (
    portal_role() = 'admin'
    or (portal_role() = 'head' and dept = portal_dept()));

create policy "tasks update" on portal_tasks
  for update to authenticated
  using (
    portal_role() = 'admin'
    or (portal_role() = 'head'  and dept = portal_dept())
    or (portal_role() = 'member' and assignee_id = portal_self_id()))
  with check (
    portal_role() = 'admin'
    or (portal_role() = 'head'  and dept = portal_dept())
    or (portal_role() = 'member' and assignee_id = portal_self_id()));

create policy "tasks delete admin" on portal_tasks
  for delete to authenticated using (portal_role() = 'admin');

-- Row policies cannot limit columns: members may only move their own task
-- through the workflow, never edit title / assignee / due date / priority.
create or replace function portal_task_guard() returns trigger
  language plpgsql as $$
begin
  if portal_role() = 'member' then
    if new.title is distinct from old.title
       or new.dept is distinct from old.dept
       or new.assignee_id is distinct from old.assignee_id
       or new.due is distinct from old.due
       or new.priority is distinct from old.priority then
      raise exception 'members may only update task status';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists task_guard on portal_tasks;
create trigger task_guard before update on portal_tasks
  for each row execute function portal_task_guard();

-- ---- portal_posts (feedback) ----
create policy "posts read" on portal_posts
  for select to authenticated using (
    portal_role() = 'admin'
    or (portal_role() = 'head' and dept = portal_dept())
    or by_user_id = portal_self_id());

create policy "posts insert" on portal_posts
  for insert to authenticated with check (
    by_user_id = portal_self_id()
    and (portal_role() = 'admin' or dept = portal_dept()));

create policy "posts delete" on portal_posts
  for delete to authenticated using (
    by_user_id = portal_self_id() or portal_role() = 'admin');
-- No UPDATE policy: feedback is immutable.

-- ---- portal_outputs ----
create policy "outputs read admin" on portal_outputs
  for select to authenticated using (portal_role() = 'admin');
create policy "outputs insert admin" on portal_outputs
  for insert to authenticated with check (portal_role() = 'admin');
create policy "outputs update admin" on portal_outputs
  for update to authenticated
  using (portal_role() = 'admin') with check (portal_role() = 'admin');

-- ---- anon: no access at all ----
revoke all on portal_users, portal_tasks, portal_outputs, portal_posts from anon;

-- ============================================================================
-- 3. SERVER-COMPUTED DELIVERABLE METRICS
-- ============================================================================

-- Counts are aggregated in the database from task rows the caller is allowed
-- to see (security_invoker = RLS of the requesting user applies). The browser
-- only ever reads these numbers; it never sends them.
drop view if exists portal_metrics;
create view portal_metrics with (security_invoker = on) as
  select dept,
         count(*)::int                              as total,
         count(*) filter (where status='done')::int as completed
  from portal_tasks
  group by dept;

revoke all on portal_metrics from anon;
grant select on portal_metrics to authenticated;
