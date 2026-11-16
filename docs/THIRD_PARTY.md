# Third party material

## Nepali calendar (removed)

The Nepali calendar screen and its Bikram Sambat month table were removed from the source tree on Nov 16 2026 because the table's licence and data provenance could not be confirmed. The table is not republished here. Earlier commits in the git history still contain it. Status: feature removed, replacement open and tracked as unfinished. A replacement needs month lengths from a source with clear permission, with complete month boundaries checked against dated official notices.

## Phosphor Icons

App icons are Phosphor Icons (https://github.com/phosphor-icons/core), MIT licence, copyright 2023 Phosphor Icons. The SVG files used are copied to app/assets/icons with the licence text (LICENSE.txt), which also appears on the in-app licences page. Checked Nov 16 2026. The app also uses the flutter_svg package (to draw them).

## Noto Sans Devanagari

Noto Sans Devanagari variable font, copyright 2022 The Noto Project Authors, SIL Open Font License 1.1. Source checked November 17, 2026: https://raw.githubusercontent.com/google/fonts/main/ofl/notosansdevanagari/OFL.txt . The unmodified font and OFL notice are in app/assets/fonts. The notice is included in the app licences page. This bundled fallback makes Nepali text/wordmark rendering independent of optional test-machine fonts.
