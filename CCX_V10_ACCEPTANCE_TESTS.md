# CCX V10 — Acceptance & Release Checklist

**Build:** Cambodia–China Export Business Management System V10 — Smart Export ERP & Business Automation

## Before business use
- [ ] Confirm current local data is backed up outside the computer.
- [ ] Complete an acceptance run using fake/sample records only.
- [ ] Review English, Khmer and Simplified Chinese screens and printed documents with qualified speakers.
- [ ] Confirm export-document templates are treated as drafts and not as official certificates.
- [ ] Verify product-specific compliance requirements with the relevant authorities/importer.

## V10 document center
- [ ] Generate English quotation and print to PDF.
- [ ] Generate Chinese pro forma invoice from a saved sales order.
- [ ] Generate Khmer document and review font rendering.
- [ ] Generate bilingual English–Chinese and English–Khmer documents.
- [ ] Check user-entered text, logo and special characters in print output.
- [ ] Confirm draft history is included in a full V10 backup.

## Procurement planning
- [ ] Add approved supplier pricing and lead time.
- [ ] Enter open orders and passed inventory batches.
- [ ] Confirm draft/cancelled/shipped/completed orders are excluded from open demand.
- [ ] Confirm non-passed inventory is excluded from available stock.
- [ ] Verify different units are not combined into one misleading quantity.
- [ ] Save procurement draft and export CSV; verify amounts manually.

## Batch QR traceability
- [ ] Create batch with 1–12 alphanumeric characters.
- [ ] Scan printed QR with a camera/QR app and confirm it reads only `CCX:<batch reference>`.
- [ ] Confirm no supplier price/customer data is encoded in QR.
- [ ] Import existing inventory batches and investigate duplicates/truncation before use.
- [ ] Confirm rejected/on-hold batches are not represented as approved.

## Buyer credit review
- [ ] Create buyer with credit limit and corresponding receivable records.
- [ ] Confirm outstanding balance equals total less paid amount.
- [ ] Confirm overdue balances require due dates and unpaid balances.
- [ ] Review open order value separately from invoiced receivables to avoid double counting.
- [ ] Confirm the credit report is treated as a screening aid rather than a credit decision.

## Backup & recovery
- [ ] Download full V10 backup.
- [ ] Validate file and review record counts.
- [ ] Perform restore into a separate test browser profile/test copy.
- [ ] Confirm the automatic pre-restore backup is downloaded.
- [ ] Confirm logo data, orders and V10 custom records recover as expected.
- [ ] Back up cloud database and uploaded files separately when those services are connected.

## Translation quality
- [ ] Run the Translation Coverage Audit in Khmer.
- [ ] Run the Translation Coverage Audit in Chinese.
- [ ] Review untranslated UI phrases; exclude proper nouns only after review.
- [ ] Check dynamic forms, table headers, dialogs, notifications and dropdown options.
- [ ] Review all printed layouts in all three languages.

## Production database and security — NOT COMPLETED by the standalone HTML
- [ ] Apply V9 base SQL then V10 migration to a separate Supabase test project.
- [ ] Create an owner account and least-privilege users.
- [ ] Test Row Level Security across all roles using separate accounts.
- [ ] Wire V10 pages to normalized tables / transactional backend functions.
- [ ] Test concurrent writes, stale revision rejection and idempotent payment behavior.
- [ ] Test server-side permission enforcement; do not rely on client-side role previews.
- [ ] Test scheduled backups, uploaded-file backups and restoration.
- [ ] Complete a security review and accountant / export specialist review.

## Approval queue
- [ ] Create a local approval request with a record reference and justification.
- [ ] Confirm an approver can record a decision note for an open request.
- [ ] Confirm non-owner preview roles have disabled decision controls.
- [ ] Confirm decisions do not execute or post any underlying payment, shipment or journal action.
- [ ] Verify approval requests are included in the full V10 backup and restore.

**Release status:** V10 is a local-first application update with a database migration foundation. Cloud integration, production security validation and live-browser review must be completed in the target environment before multi-user production use.
