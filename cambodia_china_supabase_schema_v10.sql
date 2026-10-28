-- Cambodia–China Export Business Management System — V9 database foundation
-- Apply to a TEST Supabase project first. This is a migration foundation, not a substitute for acceptance testing.
-- Browser apps must use only the project publishable/anon key with RLS. NEVER place service-role/secret keys in HTML.

create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Organization and membership: provision memberships only from trusted SQL/admin tooling.
-- ---------------------------------------------------------------------------
create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.workspace_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','sales_manager','procurement_manager','operations_manager','finance_manager','compliance_officer','editor','viewer')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create or replace function private.ccx_is_org_member(p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.workspace_members wm
    where wm.organization_id = p_org and wm.user_id = (select auth.uid())
  );
$$;

create or replace function private.ccx_has_org_role(p_org uuid, p_roles text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.workspace_members wm
    where wm.organization_id = p_org
      and wm.user_id = (select auth.uid())
      and wm.role = any(p_roles)
  );
$$;

create or replace function private.ccx_can_read_module(p_org uuid, p_module text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.workspace_members wm
    where wm.organization_id = p_org and wm.user_id = (select auth.uid())
      and (
        wm.role in ('owner','admin','viewer')
        or (wm.role = 'editor' and p_module not in ('users','journals'))
        or (wm.role = 'sales_manager' and p_module = any(array['buyers','quotes','orders','contracts','samples','marketIntel']))
        or (wm.role = 'procurement_manager' and p_module = any(array['suppliers','inventory','quality','orders']))
        or (wm.role = 'operations_manager' and p_module = any(array['inventory','quality','orders','shipments','shipmentProfitability','contracts']))
        or (wm.role = 'finance_manager' and p_module = any(array['quotes','orders','transactions','shipmentProfitability','journals','contracts','risks']))
        or (wm.role = 'compliance_officer' and p_module = any(array['inventory','quality','shipments','compliance','risks']))
      )
  );
$$;

create or replace function private.ccx_can_write_module(p_org uuid, p_module text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.workspace_members wm
    where wm.organization_id = p_org and wm.user_id = (select auth.uid())
      and (
        wm.role in ('owner','admin')
        or (wm.role = 'editor' and p_module not in ('users','journals'))
        or (wm.role = 'sales_manager' and p_module = any(array['buyers','quotes','orders','contracts','samples','marketIntel']))
        or (wm.role = 'procurement_manager' and p_module = any(array['suppliers','inventory','quality','orders']))
        or (wm.role = 'operations_manager' and p_module = any(array['inventory','quality','orders','shipments','shipmentProfitability','contracts']))
        or (wm.role = 'finance_manager' and p_module = any(array['quotes','orders','transactions','shipmentProfitability','journals','contracts','risks']))
        or (wm.role = 'compliance_officer' and p_module = any(array['inventory','quality','shipments','compliance','risks']))
      )
  );
$$;

revoke all on function private.ccx_is_org_member(uuid) from public, anon;
revoke all on function private.ccx_has_org_role(uuid,text[]) from public, anon;
revoke all on function private.ccx_can_read_module(uuid,text) from public, anon;
revoke all on function private.ccx_can_write_module(uuid,text) from public, anon;
grant execute on function private.ccx_is_org_member(uuid) to authenticated;
grant execute on function private.ccx_has_org_role(uuid,text[]) to authenticated;
grant execute on function private.ccx_can_read_module(uuid,text) to authenticated;
grant execute on function private.ccx_can_write_module(uuid,text) to authenticated;

alter table public.organizations enable row level security;
alter table public.workspace_members enable row level security;
revoke all on table public.organizations from anon, authenticated;
revoke all on table public.workspace_members from anon, authenticated;
grant select on table public.organizations, public.workspace_members to authenticated;
drop policy if exists ccx_v8_org_read_member on public.organizations;
create policy ccx_v8_org_read_member on public.organizations for select to authenticated
  using ((select private.ccx_is_org_member(id)));
drop policy if exists ccx_v8_members_read_member on public.workspace_members;
create policy ccx_v8_members_read_member on public.workspace_members for select to authenticated
  using (user_id = (select auth.uid()) or (select private.ccx_is_org_member(organization_id)));
-- No client-side INSERT/UPDATE/DELETE grant exists for workspace_members. Owner provisioning is trusted-admin-only.

-- ---------------------------------------------------------------------------
-- V9 incremental cloud-sync bridge: each business record has its own revision.
-- This replaces the V7 one-row JSON snapshot for supported existing HTML modules.
-- ---------------------------------------------------------------------------
create table if not exists public.ccx_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  module_key text not null check (module_key in ('buyers','quotes','suppliers','inventory','quality','orders','shipments','shipmentProfitability','transactions','compliance','contracts','samples','risks','users','marketIntel','journals')),
  record_key text not null check (length(trim(record_key)) > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  revision integer not null default 1 check (revision > 0),
  deleted_at timestamptz,
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, module_key, record_key)
);

create table if not exists public.ccx_plan_documents (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_key text not null default 'main' check (document_key = 'main'),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  revision integer not null default 1 check (revision > 0),
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, document_key)
);

create table if not exists public.ccx_audit_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_user_id uuid references auth.users(id),
  entity_table text not null,
  module_key text not null,
  record_key text not null,
  operation text not null check (operation in ('INSERT','UPDATE','DELETE')),
  revision integer,
  event_at timestamptz not null default now()
);
-- V9 migration: allow shipment profitability records in the record-level sync bridge.
-- Safe to run on a fresh V9 install or an existing V9 install.
alter table public.ccx_records drop constraint if exists ccx_records_module_key_check;
alter table public.ccx_records add constraint ccx_records_module_key_check check (module_key in ('buyers','quotes','suppliers','inventory','quality','orders','shipments','shipmentProfitability','transactions','compliance','contracts','samples','risks','users','marketIntel','journals'));

create index if not exists ccx_records_org_module_idx on public.ccx_records(organization_id,module_key);
create index if not exists ccx_audit_org_event_idx on public.ccx_audit_events(organization_id,event_at desc);

create or replace function private.ccx_touch_versioned_row()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce((select auth.uid()), new.created_by);
    new.updated_by := coalesce((select auth.uid()), new.updated_by);
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := now();
    new.revision := 1;
  else
    new.updated_by := coalesce((select auth.uid()), new.updated_by);
    new.updated_at := now();
    new.revision := old.revision + 1;
  end if;
  return new;
end;
$$;
revoke all on function private.ccx_touch_versioned_row() from public, anon, authenticated;

drop trigger if exists ccx_records_version on public.ccx_records;
create trigger ccx_records_version before insert or update on public.ccx_records
for each row execute function private.ccx_touch_versioned_row();
drop trigger if exists ccx_plan_version on public.ccx_plan_documents;
create trigger ccx_plan_version before insert or update on public.ccx_plan_documents
for each row execute function private.ccx_touch_versioned_row();

create or replace function private.ccx_audit_versioned_row()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_org uuid;
  v_record text;
  v_revision integer;
  v_module text;
begin
  if tg_op = 'DELETE' then
    v_org := old.organization_id;
    v_record := old.module_key || ':' || old.record_key;
    v_revision := old.revision;
    v_module := old.module_key;
  else
    v_org := new.organization_id;
    v_record := new.module_key || ':' || new.record_key;
    v_revision := new.revision;
    v_module := new.module_key;
  end if;
  insert into public.ccx_audit_events(organization_id,actor_user_id,entity_table,module_key,record_key,operation,revision)
  values (v_org, (select auth.uid()), tg_table_name, v_module, v_record, tg_op, v_revision);
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function private.ccx_audit_versioned_row() from public, anon, authenticated;
drop trigger if exists ccx_records_audit on public.ccx_records;
create trigger ccx_records_audit after insert or update or delete on public.ccx_records
for each row execute function private.ccx_audit_versioned_row();

alter table public.ccx_records enable row level security;
alter table public.ccx_plan_documents enable row level security;
alter table public.ccx_audit_events enable row level security;
revoke all on table public.ccx_records, public.ccx_plan_documents, public.ccx_audit_events from anon, authenticated;
grant select, insert, update on public.ccx_records to authenticated;
grant select, insert, update on public.ccx_plan_documents to authenticated;
grant select on public.ccx_audit_events to authenticated;
drop policy if exists ccx_v8_records_select on public.ccx_records;
create policy ccx_v8_records_select on public.ccx_records for select to authenticated
  using ((select private.ccx_can_read_module(organization_id,module_key)));
drop policy if exists ccx_v8_records_insert on public.ccx_records;
create policy ccx_v8_records_insert on public.ccx_records for insert to authenticated
  with check ((select private.ccx_can_write_module(organization_id,module_key)) and created_by=(select auth.uid()) and updated_by=(select auth.uid()) and deleted_at is null);
drop policy if exists ccx_v8_records_update on public.ccx_records;
create policy ccx_v8_records_update on public.ccx_records for update to authenticated
  using ((select private.ccx_can_write_module(organization_id,module_key)))
  with check ((select private.ccx_can_write_module(organization_id,module_key)) and updated_by=(select auth.uid()) and (deleted_at is null or (select private.ccx_has_org_role(organization_id,array['owner','admin']))));
drop policy if exists ccx_v8_plan_select on public.ccx_plan_documents;
create policy ccx_v8_plan_select on public.ccx_plan_documents for select to authenticated
  using ((select private.ccx_is_org_member(organization_id)));
drop policy if exists ccx_v8_plan_insert on public.ccx_plan_documents;
create policy ccx_v8_plan_insert on public.ccx_plan_documents for insert to authenticated
  with check ((select private.ccx_has_org_role(organization_id,array['owner','admin'])) and created_by=(select auth.uid()) and updated_by=(select auth.uid()));
drop policy if exists ccx_v8_plan_update on public.ccx_plan_documents;
create policy ccx_v8_plan_update on public.ccx_plan_documents for update to authenticated
  using ((select private.ccx_has_org_role(organization_id,array['owner','admin'])))
  with check ((select private.ccx_has_org_role(organization_id,array['owner','admin'])) and updated_by=(select auth.uid()));
drop policy if exists ccx_v8_audit_select on public.ccx_audit_events;
create policy ccx_v8_audit_select on public.ccx_audit_events for select to authenticated
  using ((select private.ccx_is_org_member(organization_id)));
-- There is deliberately no client insert/update/delete grant on audit events. Triggered database events are authoritative.

-- ---------------------------------------------------------------------------
-- Normalized relational foundation for the next screen-to-table migration.
-- Existing V9 HTML screens currently synchronize via ccx_records while adapters are migrated.
-- ---------------------------------------------------------------------------
create table if not exists public.ccx_products (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  sku text not null, name text not null, category text not null, hs_code text, base_unit text not null default 'MT',
  is_active boolean not null default true, notes text not null default '', created_by uuid not null default auth.uid() references auth.users(id),
  updated_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id, sku), unique (organization_id, id)
);
create table if not exists public.ccx_buyers (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  company_name text not null, country text not null default 'China', contact_name text, email text, phone_wechat text,
  payment_terms text, credit_limit_usd numeric(18,2) not null default 0 check (credit_limit_usd >= 0), status text not null default 'active',
  created_by uuid not null default auth.uid() references auth.users(id), updated_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (organization_id,id)
);
create table if not exists public.ccx_suppliers (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  company_name text not null, contact_name text, email text, phone text, payment_terms text, status text not null default 'under_evaluation',
  created_by uuid not null default auth.uid() references auth.users(id), updated_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (organization_id,id)
);
create table if not exists public.ccx_inventory_lots (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null, supplier_id uuid, batch_code text not null, warehouse text, unit text not null default 'MT',
  qty_on_hand numeric(18,3) not null default 0 check (qty_on_hand >= 0), qty_reserved numeric(18,3) not null default 0 check (qty_reserved >= 0 and qty_reserved <= qty_on_hand),
  quality_status text not null default 'Pending Inspection' check (quality_status in ('Pending Inspection','Passed','On Hold','Rejected')),
  received_date date, best_before date, notes text not null default '',
  created_by uuid not null default auth.uid() references auth.users(id), updated_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,product_id,batch_code),
  foreign key (organization_id,product_id) references public.ccx_products(organization_id,id),
  foreign key (organization_id,supplier_id) references public.ccx_suppliers(organization_id,id)
);
create table if not exists public.ccx_inventory_movements (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  lot_id uuid not null, movement_type text not null check (movement_type in ('RECEIPT','RESERVATION','RELEASE','ADJUSTMENT')),
  on_hand_delta numeric(18,3) not null default 0, reserved_delta numeric(18,3) not null default 0,
  reference text not null, reason text not null, actor_user_id uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(),
  foreign key (organization_id,lot_id) references public.ccx_inventory_lots(organization_id,id)
);
create table if not exists public.ccx_sales_orders (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  order_ref text not null, buyer_id uuid not null, status text not null default 'draft' check (status in ('draft','confirmed','procurement','qc_hold','ready_to_ship','shipped','delivered','completed','cancelled')),
  currency text not null default 'USD' check (currency in ('USD','KHR','CNY')), incoterm text, order_date date, required_delivery_date date, notes text not null default '',
  created_by uuid not null default auth.uid() references auth.users(id), updated_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (organization_id,id), unique (organization_id,order_ref),
  foreign key (organization_id,buyer_id) references public.ccx_buyers(organization_id,id)
);
create table if not exists public.ccx_sales_order_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  sales_order_id uuid not null, product_id uuid not null, inventory_lot_id uuid, quantity numeric(18,3) not null check (quantity > 0),
  unit text not null default 'MT', unit_price_usd numeric(18,4) not null check (unit_price_usd >= 0), purchase_unit_cost_usd numeric(18,4) not null default 0 check (purchase_unit_cost_usd >= 0),
  created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(),
  foreign key (organization_id,sales_order_id) references public.ccx_sales_orders(organization_id,id),
  foreign key (organization_id,product_id) references public.ccx_products(organization_id,id),
  foreign key (organization_id,inventory_lot_id) references public.ccx_inventory_lots(organization_id,id)
);
create table if not exists public.ccx_shipments (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  shipment_ref text not null, sales_order_id uuid, status text not null default 'planned', docs_status text not null default 'incomplete' check (docs_status in ('incomplete','under_review','complete')),
  origin text, destination text, carrier text, container_no text, seal_no text, planned_departure date, actual_departure date, estimated_arrival date, actual_arrival date,
  created_by uuid not null default auth.uid() references auth.users(id), updated_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,shipment_ref), foreign key (organization_id,sales_order_id) references public.ccx_sales_orders(organization_id,id)
);
create table if not exists public.ccx_invoices (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_no text not null, buyer_id uuid not null, sales_order_id uuid, issue_date date not null default current_date, due_date date,
  currency text not null default 'USD' check (currency in ('USD','KHR','CNY')), exchange_rate_to_usd numeric(18,8) not null default 1 check (exchange_rate_to_usd > 0),
  total_amount numeric(18,2) not null check (total_amount >= 0), status text not null default 'issued' check (status in ('draft','issued','part_paid','paid','void','disputed')),
  created_by uuid not null default auth.uid() references auth.users(id), updated_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,invoice_no), foreign key (organization_id,buyer_id) references public.ccx_buyers(organization_id,id), foreign key (organization_id,sales_order_id) references public.ccx_sales_orders(organization_id,id)
);
create table if not exists public.ccx_payments (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  payment_ref text not null, payment_date date not null default current_date, currency text not null default 'USD' check (currency in ('USD','KHR','CNY')),
  amount numeric(18,2) not null check (amount > 0), exchange_rate_to_usd numeric(18,8) not null default 1 check (exchange_rate_to_usd > 0), amount_usd numeric(18,2) not null check (amount_usd > 0),
  method text, bank_reference text, notes text not null default '', created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,payment_ref)
);
create table if not exists public.ccx_invoice_allocations (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null, payment_id uuid not null, allocated_amount numeric(18,2) not null check (allocated_amount > 0),
  actor_user_id uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(),
  unique (organization_id,invoice_id,payment_id),
  foreign key (organization_id,invoice_id) references public.ccx_invoices(organization_id,id),
  foreign key (organization_id,payment_id) references public.ccx_payments(organization_id,id)
);
create table if not exists public.ccx_chart_of_accounts (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  account_code text not null, account_name text not null, account_type text not null check (account_type in ('asset','liability','equity','revenue','expense','contra_asset','other_income','other_expense')),
  is_active boolean not null default true, created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), unique (organization_id,id), unique (organization_id,account_code)
);
create table if not exists public.ccx_journal_entries (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  journal_ref text not null, journal_date date not null default current_date, description text not null,
  currency text not null default 'USD' check (currency in ('USD','KHR','CNY')), exchange_rate_to_usd numeric(18,8) not null default 1 check (exchange_rate_to_usd > 0),
  status text not null default 'draft' check (status in ('draft','posted','reversed')), posted_by uuid references auth.users(id), posted_at timestamptz,
  created_by uuid not null default auth.uid() references auth.users(id), updated_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,journal_ref)
);
create table if not exists public.ccx_journal_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  journal_entry_id uuid not null, line_no integer not null check (line_no > 0), account_id uuid not null,
  description text, debit_usd numeric(18,2) not null default 0 check (debit_usd >= 0), credit_usd numeric(18,2) not null default 0 check (credit_usd >= 0),
  created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(),
  check ((debit_usd > 0 and credit_usd = 0) or (credit_usd > 0 and debit_usd = 0)), unique (organization_id,journal_entry_id,line_no),
  foreign key (organization_id,journal_entry_id) references public.ccx_journal_entries(organization_id,id),
  foreign key (organization_id,account_id) references public.ccx_chart_of_accounts(organization_id,id)
);

-- Updated-by timestamps and immutable change log for the normalized core.
create or replace function private.ccx_touch_standard_row()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce((select auth.uid()), new.created_by);
    new.updated_by := coalesce((select auth.uid()), new.updated_by);
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := now();
  else
    new.updated_by := coalesce((select auth.uid()), new.updated_by);
    new.updated_at := now();
  end if;
  return new;
end;
$$;
revoke all on function private.ccx_touch_standard_row() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['ccx_products','ccx_buyers','ccx_suppliers','ccx_inventory_lots','ccx_sales_orders','ccx_shipments','ccx_invoices','ccx_journal_entries'] loop
    execute format('drop trigger if exists ccx_touch on public.%I',t);
    execute format('create trigger ccx_touch before insert or update on public.%I for each row execute function private.ccx_touch_standard_row()',t);
  end loop;
end $$;

create or replace function private.ccx_audit_core_row()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_id text; v_op text; v_module text;
begin
  v_op := tg_op;
  if tg_op = 'DELETE' then v_org := old.organization_id; v_id := old.id::text;
  else v_org := new.organization_id; v_id := new.id::text; end if;
  v_module := case tg_table_name when 'ccx_products' then 'products' when 'ccx_buyers' then 'buyers' when 'ccx_suppliers' then 'suppliers' when 'ccx_inventory_lots' then 'inventory' when 'ccx_inventory_movements' then 'inventory' when 'ccx_sales_orders' then 'orders' when 'ccx_sales_order_lines' then 'orders' when 'ccx_shipments' then 'shipments' when 'ccx_invoices' then 'transactions' when 'ccx_payments' then 'transactions' when 'ccx_invoice_allocations' then 'transactions' when 'ccx_chart_of_accounts' then 'journals' when 'ccx_journal_entries' then 'journals' when 'ccx_journal_lines' then 'journals' else tg_table_name end;
  insert into public.ccx_audit_events(organization_id,actor_user_id,entity_table,module_key,record_key,operation,event_at)
    values (v_org,(select auth.uid()),tg_table_name,v_module,v_id,v_op,now());
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function private.ccx_audit_core_row() from public, anon, authenticated;
do $$
declare t text;
begin
  foreach t in array array['ccx_products','ccx_buyers','ccx_suppliers','ccx_inventory_lots','ccx_inventory_movements','ccx_sales_orders','ccx_sales_order_lines','ccx_shipments','ccx_invoices','ccx_payments','ccx_invoice_allocations','ccx_chart_of_accounts','ccx_journal_entries','ccx_journal_lines'] loop
    execute format('drop trigger if exists ccx_audit on public.%I',t);
    execute format('create trigger ccx_audit after insert or update or delete on public.%I for each row execute function private.ccx_audit_core_row()',t);
  end loop;
end $$;

-- Shared RLS rules for typed normalized tables. Managers can only access their allowed modules.
-- Deletes are deliberately restricted to owner/admin; ordinary app records should be voided/soft-deleted.
do $$
declare r record; pol text;
begin
  for r in select * from (values
    ('ccx_products','products','product'),
    ('ccx_buyers','buyers','buyer'),
    ('ccx_suppliers','suppliers','supplier'),
    ('ccx_inventory_lots','inventory','lot'),
    ('ccx_inventory_movements','inventory','movement'),
    ('ccx_sales_orders','orders','order'),
    ('ccx_sales_order_lines','orders','orderline'),
    ('ccx_shipments','shipments','shipment'),
    ('ccx_invoices','transactions','invoice'),
    ('ccx_payments','transactions','payment'),
    ('ccx_invoice_allocations','transactions','allocation'),
    ('ccx_chart_of_accounts','journals','account'),
    ('ccx_journal_entries','journals','journal'),
    ('ccx_journal_lines','journals','journal_line')
  ) as t(table_name,module_key,prefix)
  loop
    execute format('alter table public.%I enable row level security',r.table_name);
    execute format('revoke all on table public.%I from anon, authenticated',r.table_name);
    execute format('grant select on table public.%I to authenticated',r.table_name);
    if r.table_name not in ('ccx_inventory_movements','ccx_invoice_allocations') then
      execute format('grant insert, update, delete on table public.%I to authenticated',r.table_name);
    end if;
    execute format('drop policy if exists %I on public.%I',left('ccx_v8_'||r.prefix||'_sel',63),r.table_name);
    execute format('create policy %I on public.%I for select to authenticated using ((select private.ccx_can_read_module(organization_id,%L)))',left('ccx_v8_'||r.prefix||'_sel',63),r.table_name,r.module_key);
    execute format('drop policy if exists %I on public.%I',left('ccx_v8_'||r.prefix||'_ins',63),r.table_name);
    if r.table_name not in ('ccx_inventory_movements','ccx_invoice_allocations') then
      execute format('create policy %I on public.%I for insert to authenticated with check ((select private.ccx_can_write_module(organization_id,%L)) and created_by=(select auth.uid()))',left('ccx_v8_'||r.prefix||'_ins',63),r.table_name,r.module_key);
    end if;
    execute format('drop policy if exists %I on public.%I',left('ccx_v8_'||r.prefix||'_upd',63),r.table_name);
    if r.table_name not in ('ccx_inventory_movements','ccx_invoice_allocations') then
      execute format('create policy %I on public.%I for update to authenticated using ((select private.ccx_can_write_module(organization_id,%L))) with check ((select private.ccx_can_write_module(organization_id,%L)))',left('ccx_v8_'||r.prefix||'_upd',63),r.table_name,r.module_key,r.module_key);
      execute format('drop policy if exists %I on public.%I',left('ccx_v8_'||r.prefix||'_del',63),r.table_name);
      execute format('create policy %I on public.%I for delete to authenticated using ((select private.ccx_has_org_role(organization_id,array[''owner'',''admin''])))',left('ccx_v8_'||r.prefix||'_del',63),r.table_name);
    end if;
  end loop;
end $$;

-- Quantity fields are changed only through atomic stock movement functions.
revoke update on table public.ccx_inventory_lots from authenticated;
grant update (product_id,supplier_id,batch_code,warehouse,unit,quality_status,received_date,best_before,notes) on public.ccx_inventory_lots to authenticated;
-- Payments are append-first records; allocated payments cannot be silently edited.
revoke update on table public.ccx_payments from authenticated;
grant update (method,bank_reference,notes) on public.ccx_payments to authenticated;
revoke update on table public.ccx_invoices from authenticated;
grant update (due_date) on public.ccx_invoices to authenticated;

-- Stock lots are created empty; opening receipts must go through ccx_receive_inventory so the ledger records the movement.
drop policy if exists ccx_v8_lot_ins on public.ccx_inventory_lots;
create policy ccx_v8_lot_ins on public.ccx_inventory_lots for insert to authenticated
  with check ((select private.ccx_can_write_module(organization_id,'inventory')) and created_by=(select auth.uid()) and qty_on_hand=0 and qty_reserved=0);

-- Financial journal headers must remain drafts until the controlled posting function runs.
revoke update on table public.ccx_journal_entries from authenticated;
grant update (journal_date,description,currency,exchange_rate_to_usd) on public.ccx_journal_entries to authenticated;
drop policy if exists ccx_v8_journal_upd on public.ccx_journal_entries;
create policy ccx_v8_journal_upd on public.ccx_journal_entries for update to authenticated
  using ((select private.ccx_can_write_module(organization_id,'journals')) and status='draft')
  with check ((select private.ccx_can_write_module(organization_id,'journals')) and status='draft');
-- Journal lines can only be changed while the parent voucher is draft.
drop policy if exists ccx_v8_journal_line_ins on public.ccx_journal_lines;
create policy ccx_v8_journal_line_ins on public.ccx_journal_lines for insert to authenticated
  with check ((select private.ccx_can_write_module(organization_id,'journals')) and created_by=(select auth.uid()) and exists (select 1 from public.ccx_journal_entries je where je.organization_id=ccx_journal_lines.organization_id and je.id=ccx_journal_lines.journal_entry_id and je.status='draft'));
drop policy if exists ccx_v8_journal_line_upd on public.ccx_journal_lines;
create policy ccx_v8_journal_line_upd on public.ccx_journal_lines for update to authenticated
  using ((select private.ccx_can_write_module(organization_id,'journals')) and exists (select 1 from public.ccx_journal_entries je where je.organization_id=ccx_journal_lines.organization_id and je.id=ccx_journal_lines.journal_entry_id and je.status='draft'))
  with check ((select private.ccx_can_write_module(organization_id,'journals')) and exists (select 1 from public.ccx_journal_entries je where je.organization_id=ccx_journal_lines.organization_id and je.id=ccx_journal_lines.journal_entry_id and je.status='draft'));
drop policy if exists ccx_v8_journal_line_del on public.ccx_journal_lines;
create policy ccx_v8_journal_line_del on public.ccx_journal_lines for delete to authenticated
  using ((select private.ccx_can_write_module(organization_id,'journals')) and exists (select 1 from public.ccx_journal_entries je where je.organization_id=ccx_journal_lines.organization_id and je.id=ccx_journal_lines.journal_entry_id and je.status='draft'));

-- Atomic stock receipt, reserve, release and adjustment functions. No direct client writes to movement ledger.
revoke insert, update, delete on table public.ccx_inventory_movements from authenticated;
create or replace function public.ccx_receive_inventory(p_org uuid,p_lot uuid,p_qty numeric,p_reference text,p_reason text default 'Stock receipt')
returns public.ccx_inventory_lots language plpgsql security definer set search_path = '' as $$
declare v_row public.ccx_inventory_lots%rowtype;
begin
  if not private.ccx_can_write_module(p_org,'inventory') then raise exception 'Not authorized for inventory module'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'Receipt quantity must be positive'; end if;
  update public.ccx_inventory_lots set qty_on_hand=qty_on_hand+p_qty, updated_by=(select auth.uid()), updated_at=now()
  where organization_id=p_org and id=p_lot returning * into v_row;
  if not found then raise exception 'Inventory lot not found in this organization'; end if;
  insert into public.ccx_inventory_movements(organization_id,lot_id,movement_type,on_hand_delta,reserved_delta,reference,reason,actor_user_id)
    values(p_org,p_lot,'RECEIPT',p_qty,0,coalesce(nullif(trim(p_reference),''),'UNREFERENCED'),coalesce(p_reason,'Stock receipt'),(select auth.uid()));
  return v_row;
end;
$$;
create or replace function public.ccx_reserve_inventory(p_org uuid,p_lot uuid,p_qty numeric,p_reference text,p_reason text default 'Sales order reservation')
returns public.ccx_inventory_lots language plpgsql security definer set search_path = '' as $$
declare v_row public.ccx_inventory_lots%rowtype;
begin
  if not private.ccx_can_write_module(p_org,'inventory') then raise exception 'Not authorized for inventory module'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'Reservation quantity must be positive'; end if;
  update public.ccx_inventory_lots set qty_reserved=qty_reserved+p_qty, updated_by=(select auth.uid()), updated_at=now()
  where organization_id=p_org and id=p_lot and quality_status='Passed' and qty_on_hand-qty_reserved>=p_qty
  returning * into v_row;
  if not found then raise exception 'Insufficient available stock or lot is not quality-released'; end if;
  insert into public.ccx_inventory_movements(organization_id,lot_id,movement_type,on_hand_delta,reserved_delta,reference,reason,actor_user_id)
    values(p_org,p_lot,'RESERVATION',0,p_qty,coalesce(nullif(trim(p_reference),''),'UNREFERENCED'),coalesce(p_reason,'Sales order reservation'),(select auth.uid()));
  return v_row;
end;
$$;
create or replace function public.ccx_release_inventory(p_org uuid,p_lot uuid,p_qty numeric,p_reference text,p_reason text default 'Reservation release')
returns public.ccx_inventory_lots language plpgsql security definer set search_path = '' as $$
declare v_row public.ccx_inventory_lots%rowtype;
begin
  if not private.ccx_can_write_module(p_org,'inventory') then raise exception 'Not authorized for inventory module'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'Release quantity must be positive'; end if;
  update public.ccx_inventory_lots set qty_reserved=qty_reserved-p_qty, updated_by=(select auth.uid()), updated_at=now()
  where organization_id=p_org and id=p_lot and qty_reserved>=p_qty returning * into v_row;
  if not found then raise exception 'Release quantity exceeds reserved quantity or lot is not found'; end if;
  insert into public.ccx_inventory_movements(organization_id,lot_id,movement_type,on_hand_delta,reserved_delta,reference,reason,actor_user_id)
    values(p_org,p_lot,'RELEASE',0,-p_qty,coalesce(nullif(trim(p_reference),''),'UNREFERENCED'),coalesce(p_reason,'Reservation release'),(select auth.uid()));
  return v_row;
end;
$$;
revoke all on function public.ccx_receive_inventory(uuid,uuid,numeric,text,text) from public, anon;
revoke all on function public.ccx_reserve_inventory(uuid,uuid,numeric,text,text) from public, anon;
revoke all on function public.ccx_release_inventory(uuid,uuid,numeric,text,text) from public, anon;
grant execute on function public.ccx_receive_inventory(uuid,uuid,numeric,text,text) to authenticated;
grant execute on function public.ccx_reserve_inventory(uuid,uuid,numeric,text,text) to authenticated;
grant execute on function public.ccx_release_inventory(uuid,uuid,numeric,text,text) to authenticated;

-- Atomic journal posting: status can only be changed to posted by this function.
create or replace function public.ccx_post_journal_entry(p_org uuid,p_entry uuid)
returns public.ccx_journal_entries language plpgsql security definer set search_path = '' as $$
declare v_entry public.ccx_journal_entries%rowtype; v_lines integer; v_debit numeric; v_credit numeric;
begin
  if not private.ccx_can_write_module(p_org,'journals') then raise exception 'Not authorized for journals module'; end if;
  select * into v_entry from public.ccx_journal_entries where organization_id=p_org and id=p_entry for update;
  if not found then raise exception 'Journal entry not found in this organization'; end if;
  if v_entry.status <> 'draft' then raise exception 'Only draft journal entries can be posted'; end if;
  select count(*),coalesce(sum(debit_usd),0),coalesce(sum(credit_usd),0) into v_lines,v_debit,v_credit
    from public.ccx_journal_lines where organization_id=p_org and journal_entry_id=p_entry;
  if v_lines < 2 then raise exception 'A journal entry requires at least two lines'; end if;
  if abs(v_debit-v_credit) > 0.005 then raise exception 'Journal is not balanced: debits %, credits %',v_debit,v_credit; end if;
  if v_debit <= 0 or v_credit <= 0 then raise exception 'Journal total must be positive'; end if;
  update public.ccx_journal_entries set status='posted',posted_by=(select auth.uid()),posted_at=now(),updated_by=(select auth.uid()),updated_at=now()
    where organization_id=p_org and id=p_entry returning * into v_entry;
  return v_entry;
end;
$$;
revoke all on function public.ccx_post_journal_entry(uuid,uuid) from public, anon;
grant execute on function public.ccx_post_journal_entry(uuid,uuid) to authenticated;

-- Apply a payment allocation while locking both invoice and payment. Prevents over-allocation under concurrent requests.
create or replace function public.ccx_apply_invoice_payment(p_org uuid,p_invoice uuid,p_payment uuid,p_amount numeric)
returns public.ccx_invoice_allocations language plpgsql security definer set search_path = '' as $$
declare v_invoice public.ccx_invoices%rowtype; v_payment public.ccx_payments%rowtype; v_inv_alloc numeric; v_pay_alloc numeric; v_row public.ccx_invoice_allocations%rowtype;
begin
  if not private.ccx_can_write_module(p_org,'transactions') then raise exception 'Not authorized for transactions module'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Allocation must be positive'; end if;
  select * into v_invoice from public.ccx_invoices where organization_id=p_org and id=p_invoice for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_invoice.status in ('void','disputed') then raise exception 'Cannot allocate payment to a void or disputed invoice'; end if;
  select * into v_payment from public.ccx_payments where organization_id=p_org and id=p_payment for update;
  if not found then raise exception 'Payment not found'; end if;
  if v_invoice.currency <> v_payment.currency then raise exception 'Cross-currency allocation requires a reviewed conversion workflow'; end if;
  select coalesce(sum(allocated_amount),0) into v_inv_alloc from public.ccx_invoice_allocations where organization_id=p_org and invoice_id=p_invoice;
  select coalesce(sum(allocated_amount),0) into v_pay_alloc from public.ccx_invoice_allocations where organization_id=p_org and payment_id=p_payment;
  if v_inv_alloc + p_amount > v_invoice.total_amount + 0.005 then raise exception 'Allocation exceeds invoice outstanding amount'; end if;
  if v_pay_alloc + p_amount > v_payment.amount + 0.005 then raise exception 'Allocation exceeds unallocated payment amount'; end if;
  insert into public.ccx_invoice_allocations(organization_id,invoice_id,payment_id,allocated_amount,actor_user_id)
    values(p_org,p_invoice,p_payment,p_amount,(select auth.uid())) returning * into v_row;
  update public.ccx_invoices set status=case when v_inv_alloc+p_amount >= total_amount-0.005 then 'paid' else 'part_paid' end,updated_by=(select auth.uid()),updated_at=now()
    where organization_id=p_org and id=p_invoice and status not in ('void','disputed');
  return v_row;
end;
$$;
revoke all on function public.ccx_apply_invoice_payment(uuid,uuid,uuid,numeric) from public, anon;
grant execute on function public.ccx_apply_invoice_payment(uuid,uuid,uuid,numeric) to authenticated;

-- Function-only writes for movement/allocation ledgers.
grant select on public.ccx_inventory_movements, public.ccx_invoice_allocations to authenticated;

-- BOOTSTRAP (run after creating a real user in Authentication > Users):
-- 1. Create organization and copy the returned UUID:
-- insert into public.organizations(name) values ('YOUR COMPANY LEGAL / TRADING NAME') returning id;
-- 2. Add owner (replace email and organization UUID):
-- insert into public.workspace_members(organization_id,user_id,role)
-- select 'YOUR-ORG-UUID'::uuid, id, 'owner' from auth.users where email='owner@yourcompany.com';
-- 3. Add each individual staff user with least-privilege role: admin, sales_manager, procurement_manager,
--    operations_manager, finance_manager, compliance_officer, editor or viewer.
-- insert into public.workspace_members(organization_id,user_id,role)
-- select 'YOUR-ORG-UUID'::uuid, id, 'finance_manager' from auth.users where email='finance@yourcompany.com';
-- 4. Never share one login between staff; membership changes require trusted SQL/admin tooling.
-- 5. This HTML V9 client uses ccx_records + ccx_plan_documents for incremental per-record sync.
--    The normalized ccx_* business tables and transactional RPCs are a staged migration foundation and are not yet directly wired to all existing HTML forms.
-- 6. Test all policies and functions in a separate project; see CCX_V9_PRODUCTION_ACCEPTANCE_TESTS.md.


-- ====================== V10 MIGRATION ======================
-- CCX V10 incremental migration. Apply after cambodia_china_supabase_schema_v9.sql in a TEST project.
-- This migration creates normalized V10 document, procurement, traceability, credit and approval tables.
-- Do not put service-role/secret keys in HTML. RLS and server-side authorization are required.
create extension if not exists pgcrypto;

create table if not exists public.ccx_v10_documents (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 document_ref text not null, document_type text not null check(document_type in ('quotation','proforma','invoice','po','packing','contract','spec','quality','shipment','payment')),
 language_code text not null check(language_code in ('en','km','zh','en-zh','en-km')), status text not null default 'draft' check(status in ('draft','review','issued','void')),
 payload jsonb not null check(jsonb_typeof(payload)='object'), created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(organization_id,document_ref)
);
create table if not exists public.ccx_v10_procurement_plans (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 plan_ref text not null, status text not null default 'draft' check(status in ('draft','review','approved','converted','cancelled')),
 total_estimated_usd numeric(18,2) not null default 0 check(total_estimated_usd>=0), payload jsonb not null check(jsonb_typeof(payload)='object'),
 created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(organization_id,plan_ref)
);
create table if not exists public.ccx_v10_batch_traceability (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 batch_ref text not null check(length(batch_ref) between 1 and 40), product_name text not null, supplier_name text, received_date date,
 quantity numeric(18,3) not null default 0 check(quantity>=0), unit text not null default 'MT', quality_status text not null check(quality_status in ('Pending Inspection','Passed','On Hold','Rejected')),
 grade text, warehouse_location text, purchase_order_ref text, test_ref text, origin_notes text, payload jsonb not null default '{}'::jsonb check(jsonb_typeof(payload)='object'),
 created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(organization_id,batch_ref)
);
create table if not exists public.ccx_v10_credit_assessments (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 buyer_name text not null, credit_limit_usd numeric(18,2) not null default 0 check(credit_limit_usd>=0), receivables_usd numeric(18,2) not null default 0 check(receivables_usd>=0), overdue_usd numeric(18,2) not null default 0 check(overdue_usd>=0), open_order_balance_usd numeric(18,2) not null default 0 check(open_order_balance_usd>=0), risk_rating text not null check(risk_rating in ('Low','Medium','High','Over Limit')),
 review_note text, source_snapshot jsonb not null default '{}'::jsonb check(jsonb_typeof(source_snapshot)='object'), assessed_by uuid not null default auth.uid() references auth.users(id), assessed_at timestamptz not null default now()
);
create table if not exists public.ccx_v10_approval_requests (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 module_key text not null check(module_key in ('buyers','quotes','suppliers','inventory','quality','orders','shipments','transactions','compliance','contracts','samples','risks','journals')),
 action_type text not null, record_ref text not null, status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
 request_payload jsonb not null default '{}'::jsonb check(jsonb_typeof(request_payload)='object'), requested_by uuid not null default auth.uid() references auth.users(id),
 decided_by uuid references auth.users(id), decision_note text, requested_at timestamptz not null default now(), decided_at timestamptz
);

create index if not exists ccx_v10_docs_org_created_idx on public.ccx_v10_documents(organization_id,created_at desc);
create index if not exists ccx_v10_proc_org_created_idx on public.ccx_v10_procurement_plans(organization_id,created_at desc);
create index if not exists ccx_v10_batch_org_product_idx on public.ccx_v10_batch_traceability(organization_id,product_name);
create index if not exists ccx_v10_credit_org_buyer_idx on public.ccx_v10_credit_assessments(organization_id,buyer_name,assessed_at desc);
create index if not exists ccx_v10_approval_org_status_idx on public.ccx_v10_approval_requests(organization_id,status,requested_at desc);

alter table public.ccx_v10_documents enable row level security;
alter table public.ccx_v10_procurement_plans enable row level security;
alter table public.ccx_v10_batch_traceability enable row level security;
alter table public.ccx_v10_credit_assessments enable row level security;
alter table public.ccx_v10_approval_requests enable row level security;
revoke all on public.ccx_v10_documents,public.ccx_v10_procurement_plans,public.ccx_v10_batch_traceability,public.ccx_v10_credit_assessments,public.ccx_v10_approval_requests from anon,authenticated;
grant select,insert,update,delete on public.ccx_v10_documents,public.ccx_v10_procurement_plans,public.ccx_v10_batch_traceability,public.ccx_v10_credit_assessments,public.ccx_v10_approval_requests to authenticated;

create or replace function private.ccx_can_has_org_admin(p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.workspace_members wm where wm.organization_id=p_org and wm.user_id=(select auth.uid()) and wm.role in ('owner','admin'));
$$;
revoke all on function private.ccx_can_has_org_admin(uuid) from public,anon,authenticated;
grant execute on function private.ccx_can_has_org_admin(uuid) to authenticated;

-- Documents use the same role gates as sales/orders. Documents remain drafts unless authorized through business workflow.
drop policy if exists ccx_v10_docs_read on public.ccx_v10_documents;
create policy ccx_v10_docs_read on public.ccx_v10_documents for select to authenticated using ((select private.ccx_can_read_module(organization_id,'orders')) or (select private.ccx_can_read_module(organization_id,'contracts')));
drop policy if exists ccx_v10_docs_insert on public.ccx_v10_documents;
create policy ccx_v10_docs_insert on public.ccx_v10_documents for insert to authenticated with check ((select private.ccx_can_write_module(organization_id,'orders')) or (select private.ccx_can_write_module(organization_id,'contracts')));
drop policy if exists ccx_v10_docs_update on public.ccx_v10_documents;
create policy ccx_v10_docs_update on public.ccx_v10_documents for update to authenticated using ((select private.ccx_can_write_module(organization_id,'orders')) or (select private.ccx_can_write_module(organization_id,'contracts'))) with check ((select private.ccx_can_write_module(organization_id,'orders')) or (select private.ccx_can_write_module(organization_id,'contracts')));
drop policy if exists ccx_v10_docs_delete on public.ccx_v10_documents;
create policy ccx_v10_docs_delete on public.ccx_v10_documents for delete to authenticated using ((select private.ccx_can_has_org_admin(organization_id)));

-- Procurement drafts use supplier/procurement access.
drop policy if exists ccx_v10_proc_read on public.ccx_v10_procurement_plans;
create policy ccx_v10_proc_read on public.ccx_v10_procurement_plans for select to authenticated using ((select private.ccx_can_read_module(organization_id,'suppliers')));
drop policy if exists ccx_v10_proc_write on public.ccx_v10_procurement_plans;
create policy ccx_v10_proc_write on public.ccx_v10_procurement_plans for all to authenticated using ((select private.ccx_can_write_module(organization_id,'suppliers'))) with check ((select private.ccx_can_write_module(organization_id,'suppliers')));

-- Batch traceability follows inventory module permissions.
drop policy if exists ccx_v10_batch_read on public.ccx_v10_batch_traceability;
create policy ccx_v10_batch_read on public.ccx_v10_batch_traceability for select to authenticated using ((select private.ccx_can_read_module(organization_id,'inventory')));
drop policy if exists ccx_v10_batch_write on public.ccx_v10_batch_traceability;
create policy ccx_v10_batch_write on public.ccx_v10_batch_traceability for all to authenticated using ((select private.ccx_can_write_module(organization_id,'inventory'))) with check ((select private.ccx_can_write_module(organization_id,'inventory')));

-- Credit figures are restricted to owner/admin/finance_manager, separate from general buyer CRM records.
drop policy if exists ccx_v10_credit_read on public.ccx_v10_credit_assessments;
create policy ccx_v10_credit_read on public.ccx_v10_credit_assessments for select to authenticated using ((select private.ccx_has_org_role(organization_id,array['owner','admin','finance_manager']::text[])));
drop policy if exists ccx_v10_credit_insert on public.ccx_v10_credit_assessments;
create policy ccx_v10_credit_insert on public.ccx_v10_credit_assessments for insert to authenticated with check ((select private.ccx_has_org_role(organization_id,array['owner','admin','finance_manager']::text[])));
drop policy if exists ccx_v10_credit_update on public.ccx_v10_credit_assessments;
create policy ccx_v10_credit_update on public.ccx_v10_credit_assessments for update to authenticated using ((select private.ccx_has_org_role(organization_id,array['owner','admin','finance_manager']::text[]))) with check ((select private.ccx_has_org_role(organization_id,array['owner','admin','finance_manager']::text[])));
drop policy if exists ccx_v10_credit_delete on public.ccx_v10_credit_assessments;
create policy ccx_v10_credit_delete on public.ccx_v10_credit_assessments for delete to authenticated using ((select private.ccx_has_org_role(organization_id,array['owner','admin']::text[])));

-- Any module editor can request an approval; owner/admin decides to avoid self-approved sensitive actions.
drop policy if exists ccx_v10_approval_read on public.ccx_v10_approval_requests;
create policy ccx_v10_approval_read on public.ccx_v10_approval_requests for select to authenticated using ((select private.ccx_can_read_module(organization_id,module_key)));
drop policy if exists ccx_v10_approval_insert on public.ccx_v10_approval_requests;
create policy ccx_v10_approval_insert on public.ccx_v10_approval_requests for insert to authenticated with check ((select private.ccx_can_write_module(organization_id,module_key)) and requested_by=(select auth.uid()) and status='pending');
drop policy if exists ccx_v10_approval_decide on public.ccx_v10_approval_requests;
create policy ccx_v10_approval_decide on public.ccx_v10_approval_requests for update to authenticated using ((select private.ccx_has_org_role(organization_id,array['owner','admin']::text[]))) with check ((select private.ccx_has_org_role(organization_id,array['owner','admin']::text[])));
drop policy if exists ccx_v10_approval_delete on public.ccx_v10_approval_requests;
create policy ccx_v10_approval_delete on public.ccx_v10_approval_requests for delete to authenticated using ((select private.ccx_has_org_role(organization_id,array['owner','admin']::text[])));

-- Reminder: these tables are not wired to all HTML screens yet. Apply only in a test project, then integrate
-- and test every operation before production use. Existing local V10 UI remains local-first until that work is complete.
