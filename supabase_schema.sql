-- TECHTRIX 2026 E-CELL PORTAL
-- Supabase/PostgreSQL schema
-- Run this entire file in Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists portal_users (
  id text primary key,
  name text not null,
  role text not null check (role in ('admin','head','member')),
  dept text,
  password_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists portal_tasks (
  id bigint primary key,
  title text not null,
  dept text not null,
  assignee_id text not null references portal_users(id) on update cascade,
  due date not null,
  status text not null default 'todo' check (status in ('todo','prog','review','done')),
  priority text not null default 'Med' check (priority in ('High','Med','Low')),
  created_at timestamptz not null default now()
);

create table if not exists portal_outputs (
  id bigint primary key,
  dept text not null,
  title text not null,
  target integer not null default 0,
  current_value integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists portal_posts (
  id bigint primary key,
  by_user_id text not null references portal_users(id) on update cascade,
  dept text,
  title text not null,
  body text not null,
  ts timestamptz not null default now()
);

create index if not exists idx_portal_tasks_dept on portal_tasks(dept);
create index if not exists idx_portal_tasks_assignee on portal_tasks(assignee_id);
create index if not exists idx_portal_tasks_due on portal_tasks(due);
create index if not exists idx_portal_posts_by_user on portal_posts(by_user_id);
create index if not exists idx_portal_posts_ts on portal_posts(ts desc);

insert into portal_users (id,name,role,dept,password_hash) values
('admin1','Mr. Sudhanshu Ranjan','admin',null,encode(digest('Sr#4827','sha256'),'hex')),
('admin2','Aniket Anand','admin',null,encode(digest('An#9153','sha256'),'hex')),
('creative.head','Vidit Gaur','head','Creative',encode(digest('Vg#6204','sha256'),'hex')),
('vp1.head','Yogesh Meheta','head','Vice President 1',encode(digest('Ym#3719','sha256'),'hex')),
('vp2.head','Deepak','head','Vice President 2',encode(digest('Dp#8452','sha256'),'hex')),
('pr.head','Vanshit Tyagi','head','PR & Relations',encode(digest('Vt#5036','sha256'),'hex')),
('adm.head','Pushkar Goel','head','Administration',encode(digest('Pg#7261','sha256'),'hex')),
('sr.head','Ayush Shakya','head','Student Relations',encode(digest('As#1948','sha256'),'hex')),
('member.demo','Sample Member','member','Creative',encode(digest('Mb#2580','sha256'),'hex'))
on conflict (id) do nothing;

insert into portal_outputs (id,dept,title,target,current_value) values
(1,'Creative','Key deliverables completed',10,0),
(2,'Vice President 1','Key deliverables completed',10,0),
(3,'Vice President 2','Key deliverables completed',10,0),
(4,'PR & Relations','Key deliverables completed',10,0),
(5,'Administration','Key deliverables completed',10,0),
(6,'Student Relations','Key deliverables completed',10,0)
on conflict (id) do nothing;

insert into portal_tasks (id,title,dept,assignee_id,due,status,priority) values
(1,'Design Techtrix 2026 poster','Creative','member.demo',current_date + 4,'prog','High'),
(2,'Prepare social media banners','Creative','member.demo',current_date - 1,'todo','Med')
on conflict (id) do nothing;

alter table portal_users enable row level security;
alter table portal_tasks enable row level security;
alter table portal_outputs enable row level security;
alter table portal_posts enable row level security;

create policy "demo read users" on portal_users for select using (true);
create policy "demo insert users" on portal_users for insert with check (true);
create policy "demo read tasks" on portal_tasks for select using (true);
create policy "demo insert tasks" on portal_tasks for insert with check (true);
create policy "demo update tasks" on portal_tasks for update using (true) with check (true);
create policy "demo read outputs" on portal_outputs for select using (true);
create policy "demo update outputs" on portal_outputs for update using (true) with check (true);
create policy "demo read posts" on portal_posts for select using (true);
create policy "demo insert posts" on portal_posts for insert with check (true);
create policy "demo delete posts" on portal_posts for delete using (true);

-- SECURITY NOTE:
-- This is a lightweight demo login compatible with the supplied HTML.
-- For public production deployment, migrate to Supabase Auth and auth.uid()-based RLS.
-- Never expose the service_role/secret key in the frontend.