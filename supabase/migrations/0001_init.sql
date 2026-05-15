-- ════════════════════════════════════════════════════════════════════
-- Salud Visual — initial schema (Supabase Postgres)
-- Multi-tenant, RLS-enforced, offline-friendly.
-- ════════════════════════════════════════════════════════════════════

create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm";
create extension if not exists "uuid-ossp";

-- ── Helper: current clinic from JWT ────────────────────────────────
create or replace function public.current_clinic()
returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb->>'clinic_id','')::uuid
$$;

-- ── Tenants ────────────────────────────────────────────────────────
create table clinics (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  phone         text,
  address       text,
  timezone      text default 'America/Monterrey',
  currency      text default 'MXN',
  created_at    timestamptz default now()
);

-- ── Users & roles ──────────────────────────────────────────────────
create table profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  full_name         text,
  initials          text,                    -- e.g. BH, AM
  avatar_url        text,
  calendar_provider text check (calendar_provider in ('google','outlook','none')) default 'none',
  calendar_refresh  text,                    -- encrypted refresh token
  default_clinic    uuid references clinics(id),
  created_at        timestamptz default now()
);

create type member_role as enum ('owner','optometrist','promoter','receptionist','viewer');

create table memberships (
  clinic_id  uuid references clinics(id) on delete cascade,
  user_id    uuid references profiles(id) on delete cascade,
  role       member_role not null default 'viewer',
  created_at timestamptz default now(),
  primary key (clinic_id, user_id)
);

-- ── Clients (patients) ─────────────────────────────────────────────
create table clients (
  id          uuid primary key default gen_random_uuid(),
  clinic_id   uuid not null references clinics(id) on delete cascade,
  name        text not null,
  phone       text,
  age         int,
  email       text,
  -- address
  street      text,
  between     text,        -- "entre calles"
  colonia     text,
  municipio   text,
  reference   text,
  lat         double precision,
  lng         double precision,
  geocoded_at timestamptz,
  -- medical flags
  diabetes    boolean default false,
  hypertension boolean default false,
  notes       text,
  face_shape  text,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);
create index on clients (clinic_id);
create index on clients using gin (name gin_trgm_ops);
create index on clients (clinic_id, lat, lng);

-- ── Prescriptions (Rx history) ─────────────────────────────────────
create table prescriptions (
  id            uuid primary key default gen_random_uuid(),
  clinic_id     uuid not null references clinics(id) on delete cascade,
  client_id     uuid not null references clients(id) on delete cascade,
  taken_at      date not null default current_date,
  optometrist_id uuid references profiles(id),
  -- OD
  od_esf        text, od_cyl text, od_eje text, od_add text,
  -- OI
  oi_esf        text, oi_cyl text, oi_eje text, oi_add text,
  dip           text, alt text,
  -- previous / current as recorded on paper
  ant_od        text, ant_oi text, act_od text, act_oi text,
  -- observations
  observations  text,
  created_at    timestamptz default now()
);
create index on prescriptions (client_id, taken_at desc);

-- ── Orders (Orden de Pedido) ───────────────────────────────────────
create type pay_form as enum ('CONTADO','CREDITO');
create type vision_type as enum ('MONO','BIFOCAL','PROGRESIVO');
create type lens_material as enum ('BLANCO','POLI','HI');
create type ar_type as enum ('NO','AR','AR_BLUE');

create table orders (
  id              uuid primary key default gen_random_uuid(),
  clinic_id       uuid not null references clinics(id) on delete cascade,
  client_id       uuid not null references clients(id) on delete cascade,
  prescription_id uuid references prescriptions(id),
  folio           text not null,             -- MAR-1-26
  ordered_on      date not null default current_date,
  promoter_id     uuid references profiles(id),
  optometrist_id  uuid references profiles(id),
  -- lens config
  material        lens_material,
  design          vision_type,
  ar              ar_type default 'NO',
  photochromic    boolean default false,
  filter          text,
  -- frame
  frame_model     text,
  frame_color     text,
  aro_mm          int, puente_mm int, varilla_mm int,
  -- payment
  cost            numeric(10,2) default 0,
  pay_form        pay_form,
  down_payment    numeric(10,2) default 0,
  weekly_payment  numeric(10,2) default 0,
  delivery_date   date,
  pay_day         text,
  -- lab
  lab             text,
  lab_folio       text,
  cost_micas      numeric(10,2) default 0,
  cost_bisel      numeric(10,2) default 0,
  cost_maq        numeric(10,2) default 0,
  -- printable snapshot (frozen at save time)
  rx_snapshot     jsonb,
  created_at      timestamptz default now(),
  unique (clinic_id, folio)
);
create index on orders (clinic_id, ordered_on desc);
create index on orders (client_id, ordered_on desc);

-- ── Wallet ledger (append-only) ────────────────────────────────────
create type ledger_kind as enum (
  'order_charge','payment_cash','payment_transfer','payment_stripe',
  'adjustment','refund'
);

create table wallet_ledger (
  id          uuid primary key default gen_random_uuid(),
  clinic_id   uuid not null references clinics(id) on delete cascade,
  client_id   uuid not null references clients(id) on delete cascade,
  order_id    uuid references orders(id),
  kind        ledger_kind not null,
  amount      numeric(10,2) not null,         -- + charge, - payment
  note        text,
  user_id     uuid references profiles(id),
  occurred_at timestamptz default now()
);
create index on wallet_ledger (client_id, occurred_at desc);
create index on wallet_ledger (clinic_id, occurred_at desc);

-- Convenience view: client balance
create view client_balances as
  select client_id, clinic_id, sum(amount) as balance
  from wallet_ledger group by client_id, clinic_id;

-- ── Appointments ───────────────────────────────────────────────────
create type appt_status as enum ('scheduled','confirmed','done','cancelled','no_show');

create table appointments (
  id              uuid primary key default gen_random_uuid(),
  clinic_id       uuid not null references clinics(id) on delete cascade,
  client_id       uuid references clients(id) on delete set null,
  optometrist_id  uuid references profiles(id),
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  title           text,
  notes           text,
  status          appt_status default 'scheduled',
  -- external sync
  external_provider text check (external_provider in ('google','outlook')),
  external_id     text,
  external_etag   text,
  last_synced_at  timestamptz,
  created_at      timestamptz default now()
);
create index on appointments (clinic_id, starts_at);
create index on appointments (optometrist_id, starts_at);

-- ── Geocode cache (saves Nominatim quota) ──────────────────────────
create table geocode_cache (
  query       text primary key,
  lat         double precision,
  lng         double precision,
  hits        int default 1,
  cached_at   timestamptz default now()
);

-- ── Outbox (offline replay) ────────────────────────────────────────
create table outbox (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  payload     jsonb not null,
  applied_at  timestamptz,
  error       text,
  created_at  timestamptz default now()
);

-- ── Daily stats (refreshed by pg_cron) ─────────────────────────────
create materialized view stats_daily as
select
  clinic_id,
  ordered_on::date as d,
  count(*)         as orders,
  sum(cost)        as gross,
  sum(down_payment) as collected,
  sum(cost) - sum(down_payment) as outstanding
from orders
group by clinic_id, ordered_on;

create unique index on stats_daily (clinic_id, d);

-- ════════════════════════════════════════════════════════════════════
-- Row-Level Security
-- ════════════════════════════════════════════════════════════════════
alter table clinics         enable row level security;
alter table profiles        enable row level security;
alter table memberships     enable row level security;
alter table clients         enable row level security;
alter table prescriptions   enable row level security;
alter table orders          enable row level security;
alter table wallet_ledger   enable row level security;
alter table appointments    enable row level security;
alter table outbox          enable row level security;

-- Generic tenant policy (parameterised by table)
do $$
declare t text;
begin
  for t in
    select unnest(array[
      'clients','prescriptions','orders','wallet_ledger','appointments'
    ])
  loop
    execute format($f$
      create policy "%1$s_tenant_rw" on %1$s
        using      (clinic_id = current_clinic())
        with check (clinic_id = current_clinic());
    $f$, t);
  end loop;
end$$;

-- Profile: user can read self; clinic owners see members
create policy "profiles_self_rw" on profiles
  using (id = auth.uid()) with check (id = auth.uid());

-- Memberships: user can read own memberships
create policy "memberships_self_read" on memberships
  for select using (user_id = auth.uid());

-- Clinics: members can read; owner can update
create policy "clinics_member_read" on clinics
  for select using (
    id in (select clinic_id from memberships where user_id = auth.uid())
  );

-- Outbox is per-user
create policy "outbox_self" on outbox
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── Auto-update timestamps ─────────────────────────────────────────
create or replace function _touch_updated() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end$$;
create trigger trg_clients_touch before update on clients
  for each row execute function _touch_updated();

-- ── Auto-charge ledger when an order is created ────────────────────
create or replace function _charge_order() returns trigger language plpgsql as $$
begin
  insert into wallet_ledger (clinic_id, client_id, order_id, kind, amount, note)
  values (new.clinic_id, new.client_id, new.id, 'order_charge', new.cost,
          'Orden '||new.folio);
  if new.down_payment > 0 then
    insert into wallet_ledger (clinic_id, client_id, order_id, kind, amount, note)
    values (new.clinic_id, new.client_id, new.id, 'payment_cash', -new.down_payment,
            'Anticipo '||new.folio);
  end if;
  return new;
end$$;
create trigger trg_orders_charge after insert on orders
  for each row execute function _charge_order();
