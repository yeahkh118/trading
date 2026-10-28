# V10 Update — Traditional Chinese (Taiwan)

## Changes
- Added a fourth flag option: TW (Taiwan), using a custom inline SVG round flag rather than a platform-dependent emoji.
- Added `tw` to the language engine, `zh-TW` document language metadata, saved language preferences, page title, and Taiwan-specific font fallbacks.
- Added a Traditional Chinese dictionary layer for all current English-to-Simplified-Chinese dictionary entries. It uses ICU Simplified-to-Traditional conversion, then applies common Taiwan UI terminology choices where appropriate.
- Added Traditional Chinese support to the Translation Coverage Audit and its CSV export.
- Added Traditional Chinese and English + Traditional Chinese options to the Export Document Center, with Traditional Chinese business-document labels.
- Retained English (US), Khmer, and Simplified Chinese options and existing local data/settings behavior.

## Validation performed
- Compiled all six embedded JavaScript blocks with Node.js: no syntax errors found.
- Checked that the four-language picker metadata, TW SVG branch, `zh-TW` locale, translation dictionary layer, document language options, Traditional Chinese audit metrics, and export fields are present.
- Loaded the translation dictionary programmatically and confirmed 2,419 normalized English phrase keys have a Traditional Chinese value; 2,170 dictionary entries differ from their Simplified Chinese output, as expected after conversion and Taiwan terminology substitutions.
- Confirmed the five product portfolio subtitles have Traditional Chinese outputs through the same translation layer.

## Review note
The TW text is generated from the existing Simplified Chinese translations using character conversion and common Taiwan terminology substitutions. This is broad UI localization, not a substitute for native-language proofreading. Have a Taiwan Traditional Chinese reviewer confirm legal, regulatory, tax, contractual, technical, and customer-facing text before use.

## Limitations unchanged
- The app remains local-first. Cloud schema files are supplied as a foundation, but this update does not connect all UI records to a live shared Supabase database.
- Automated syntax and dictionary checks do not guarantee visual correctness in every browser layout. Please review the language menu and key screens in your local Chrome or Edge browser.
