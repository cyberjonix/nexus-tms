-- ═══════════════════════════════════════════════════════════════════════
-- NEXUS TMS — Data Imports Tables (EZ Pass + Fuel Card)
-- Run in Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════════

-- ── EZ Pass transactions ──────────────────────────────────────────────
create table if not exists ezpass_transactions (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid references organizations(id) not null,
  tag_id       text not null,
  exit_date    timestamptz not null,
  plaza        text,
  agency       text,
  amount       numeric not null default 0,
  -- dedup key: same tag + same exit_date + same plaza = same transaction
  dedup_key    text generated always as (tag_id || '|' || exit_date::text || '|' || coalesce(plaza,'')) stored,
  imported_at  timestamptz default now()
);

-- Unique constraint for deduplication
create unique index if not exists ezpass_dedup
  on ezpass_transactions(org_id, dedup_key);

-- Index for fast lookup by tag
create index if not exists ezpass_tag_idx
  on ezpass_transactions(org_id, tag_id);

alter table ezpass_transactions enable row level security;
create policy "ezpass_own_org" on ezpass_transactions
  for all to authenticated
  using (org_id = get_org_id())
  with check (org_id = get_org_id());

-- ── Fuel transactions ─────────────────────────────────────────────────
create table if not exists fuel_transactions (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid references organizations(id) not null,
  card_num     text not null,
  tran_date    date not null,
  invoice      text,
  unit         text,
  location     text,
  fees         numeric default 0,
  amt          numeric not null default 0,
  total        numeric default 0,
  -- dedup key: same card + same invoice number = same transaction
  dedup_key    text generated always as (card_num || '|' || coalesce(invoice,'') || '|' || tran_date::text) stored,
  imported_at  timestamptz default now()
);

create unique index if not exists fuel_dedup
  on fuel_transactions(org_id, dedup_key);

create index if not exists fuel_card_idx
  on fuel_transactions(org_id, card_num);

alter table fuel_transactions enable row level security;
create policy "fuel_own_org" on fuel_transactions
  for all to authenticated
  using (org_id = get_org_id())
  with check (org_id = get_org_id());
