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
