-- CCX V10 non-destructive schema smoke test. Run after V9 base + V10 migration in a test project.
select 'ccx_v10_documents' as object_name, to_regclass('public.ccx_v10_documents') is not null as exists
union all select 'ccx_v10_procurement_plans', to_regclass('public.ccx_v10_procurement_plans') is not null
union all select 'ccx_v10_batch_traceability', to_regclass('public.ccx_v10_batch_traceability') is not null
union all select 'ccx_v10_credit_assessments', to_regclass('public.ccx_v10_credit_assessments') is not null
union all select 'ccx_v10_approval_requests', to_regclass('public.ccx_v10_approval_requests') is not null;

select tablename, rowsecurity from pg_tables where schemaname='public' and tablename in (
 'ccx_v10_documents','ccx_v10_procurement_plans','ccx_v10_batch_traceability','ccx_v10_credit_assessments','ccx_v10_approval_requests'
) order by tablename;

select tablename, policyname, cmd from pg_policies where schemaname='public' and tablename like 'ccx_v10_%' order by tablename,policyname;

-- Static checks are not a substitute for running a role matrix with at least owner, sales_manager,
-- procurement_manager, operations_manager, finance_manager, compliance_officer, and viewer test accounts.
