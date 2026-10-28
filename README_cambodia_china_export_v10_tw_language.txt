# Cambodia–China Export Business Management System — V10 (TW Language Update)

## Main application
- `cambodia_china_export_business_management_system_v10_tw_language.html`: standalone local-first application with four interface languages: US English, Khmer, Simplified Chinese, and Traditional Chinese (Taiwan).

## Included setup files
- `cambodia_china_supabase_schema_v10.sql`: V9 schema plus V10 migration, for a fresh test project.
- `cambodia_china_v10_migration_only.sql`: V10 extension, for a project that already has V9 schema applied.
- `cambodia_china_v10_schema_smoke_test.sql`: non-destructive schema/RLS catalogue check.
- `CCX_V10_ACCEPTANCE_TESTS.md`: acceptance and release checklist.
- `CCX_V10_TW_LANGUAGE_UPDATE.md`: details of this language update and validation performed.

## Language update
- Added a round Taiwan flag icon (TW) to the flag-only language menu.
- Added Traditional Chinese (Taiwan, `zh-TW`) to the whole-project UI translation engine and saved language preference.
- Converted the Simplified Chinese dictionary entries to Traditional Chinese and applied common Taiwan terminology choices for UI wording.
- Added Traditional Chinese to the Translation Coverage Audit.
- Added Traditional Chinese and English + Traditional Chinese output options to the Export Document Center.
- Added a Traditional Chinese font stack for the main app and generated documents.

Traditional Chinese text is generated from the existing Simplified Chinese dictionary with character conversion and common terminology substitutions. Have a Taiwan Traditional Chinese reviewer check legal, regulatory, contractual, and buyer-facing material before issuing it externally.

## Local use
Open the HTML file in a current version of Chrome or Edge. The app stores operational data in the current browser profile. Use V10 Backup & Recovery to export a full local JSON backup. Keep backups and any separately uploaded files outside this device.

## Important cloud limitation
This release is still local-first. The supplied SQL is a migration foundation. The UI forms are not all wired directly to the normalized cloud tables. No live Supabase project was configured or credentials supplied. Do not treat this as a secured multi-user production ERP until the database adapter, server-side authorization, conflict handling, backup/restore, and acceptance tests are completed.

## Database setup
- For a fresh test project: run `cambodia_china_supabase_schema_v10.sql` in the Supabase SQL editor.
- If the project already has V9 schema: run `cambodia_china_v10_migration_only.sql` only.
- Then run `cambodia_china_v10_schema_smoke_test.sql`.
- Verify security using separate test users/roles; RLS test results are environment-specific.
- Never place Supabase service-role or secret keys inside the HTML. Only publishable/anon credentials can be present in browser code, and only with correctly enforced RLS.

## Business controls
- Export documents are drafts. They do not replace government-issued certificates, permits, or legal advice.
- Procurement suggestions are not purchase orders.
- Credit ratings are management screening aids, not credit decisions.
- QR code carries only a batch reference; it is not an online traceability service until a hosted endpoint is configured.
- Check exact product eligibility, HS classification, supplier and establishment eligibility, and required documents with competent authorities and the Chinese importer/broker before shipping.

Review `CCX_V10_ACCEPTANCE_TESTS.md` before live business use.
