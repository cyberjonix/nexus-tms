-- ═══════════════════════════════════════════════════════════════════════
-- NEXUS TMS — Supabase Auth + RLS Setup
-- Run this in Supabase SQL Editor (Project: aiokbuzauuadoqrghyic)
-- ═══════════════════════════════════════════════════════════════════════

-- ── STEP 1: Add owner_id to organizations ────────────────────────────
alter table organizations
  add column if not exists owner_id uuid references auth.users(id);

-- ── STEP 2: Create auth users for each org ───────────────────────────
-- Run via Supabase Dashboard → Authentication → Users → Invite
-- OR via this SQL (requires service_role, not anon):
--
-- For ZTA Transportation:
--   Email: jnson@ya.ru
--   Password: Jun102030$%  (they can change in Account Settings)
--
-- After creating the user, link it:
-- update organizations
--   set owner_id = (select id from auth.users where email = 'jnson@ya.ru')
--   where id = '27fbeaa2-60d7-4059-9522-d6f5c291adaa';

-- ── STEP 3: Helper function — get org_id from JWT ────────────────────
create or replace function get_org_id()
returns uuid
language sql stable
as $$
  select id from organizations where owner_id = auth.uid() limit 1;
$$;

-- ── STEP 4: Enable RLS on all tables ─────────────────────────────────
alter table organizations        enable row level security;
alter table trucks               enable row level security;
alter table drivers              enable row level security;
alter table settlements          enable row level security;
alter table street_loads         enable row level security;
alter table driver_truck_history enable row level security;

-- ── STEP 5: Drop old policies ─────────────────────────────────────────
drop policy if exists "anon_orgs_select"   on organizations;
drop policy if exists "anon_orgs_update"   on organizations;
drop policy if exists "anon_trucks"        on trucks;
drop policy if exists "anon_drivers"       on drivers;
drop policy if exists "anon_settlements"   on settlements;
drop policy if exists "anon_street_loads"  on street_loads;
drop policy if exists "anon_dth"           on driver_truck_history;

-- ── STEP 6: Organizations — own row only ─────────────────────────────
create policy "org_select_own" on organizations
  for select to authenticated
  using (owner_id = auth.uid());

create policy "org_update_own" on organizations
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- Super-admin needs to see all orgs — done via service_role key (no RLS bypass needed)
-- Anon can read for login lookup (email→slug validation):
create policy "org_anon_read" on organizations
  for select to anon
  using (true);  -- limited to specific columns via API query

-- ── STEP 7: Trucks — org isolation ───────────────────────────────────
create policy "trucks_own_org" on trucks
  for all to authenticated
  using (org_id = get_org_id())
  with check (org_id = get_org_id());

-- ── STEP 8: Drivers — org isolation ──────────────────────────────────
create policy "drivers_own_org" on drivers
  for all to authenticated
  using (org_id = get_org_id())
  with check (org_id = get_org_id());

-- ── STEP 9: Settlements — org isolation ──────────────────────────────
create policy "settlements_own_org" on settlements
  for all to authenticated
  using (org_id = get_org_id())
  with check (org_id = get_org_id());

-- ── STEP 10: Street Loads — org isolation ────────────────────────────
create policy "street_loads_own_org" on street_loads
  for all to authenticated
  using (org_id = get_org_id())
  with check (org_id = get_org_id());

-- ── STEP 11: driver_truck_history table ──────────────────────────────
create table if not exists driver_truck_history (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid references organizations(id) not null,
  driver_id   uuid references drivers(id),
  driver_name text not null,
  truck_unit  text not null,
  date_from   date not null,
  date_to     date,              -- null = currently assigned
  notes       text,
  created_at  timestamptz default now()
);

create policy "dth_own_org" on driver_truck_history
  for all to authenticated
  using (org_id = get_org_id())
  with check (org_id = get_org_id());

alter table driver_truck_history enable row level security;

-- Index for fast lookups by driver + date range
create index if not exists dth_driver_date
  on driver_truck_history(org_id, driver_name, date_from, date_to);

-- ── STEP 12: Verify ──────────────────────────────────────────────────
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in ('organizations','trucks','drivers','settlements','street_loads','driver_truck_history');
