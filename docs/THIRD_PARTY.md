# Third party material

## Bikram Sambat month lengths (app/lib/nepali_date.dart)

The table of days per month for 2000 to 2099 BS was copied from milantarami/nepali-calendar
(src/DataProvider/BS.php, https://github.com/milantarami/nepali-calendar). Its composer.json declares the MIT licence.
The repository has no LICENSE file, and its README says it is a rewrite of Nepali_Calendar.php by Amam Tuladhar, whose
licence we have not verified. Month lengths are published calendar facts and the same table appears in other
MIT licensed packages (for example SuprimKhatri77/bikram-sambat-ts and sonill/nepali-dates), but the licence chain
of this copy is not fully confirmed. Status: open. Replace the table before a public store release if that cannot
be settled.

The table is checked in test/nepali_date_test.dart against dated public holiday pairs from Nepal embassy pages
(Cairo, Canberra, Washington) for 2083 BS.

MIT licence text as declared by the source project:

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
    documentation files, to deal in the software without restriction, including the rights to use, copy, modify,
    merge, publish, distribute, sublicense, and/or sell copies, subject to including the copyright and permission
    notice in all copies. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

## Provenance review (Nov 2026)

Candidate replacement: SuprimKhatri77/bikram-sambat-ts (MIT, real LICENSE file), whose table comes from go-bs.
go-bs says BS 2000 to 2100 were read from Hamro Patro's closed source calendar data, and BS 1979 to 1999 from
amitgaru/nepali-datetime (Apache-2.0) and askbuddie/bikram-sambat (MIT). So an MIT licence on the latest repo does not
settle where the facts came from or whether Hamro Patro permits that use. Provenance gap: OPEN.

Our current table and that one differ in four years (2062, 2087, 2097, 2099), and go-bs itself calls 2085 to 2100
provisional (it has a 367 day year). Neither table is confirmed against an official panchang.

Decision: the calendar table stays a RELEASE BLOCKER for any APK or store build until the data comes from a source
with clear permission (for example an official Nepal government calendar we may reuse, or a table we build and check
ourselves from dated official notices), or is removed from the build.

## Handling (Nov 16)

The calendar screen is hidden unless a build sets --dart-define=SANJAAL_CALENDAR=true, so no distributable build offers it or ships the table (the unused code is tree-shaken out of release builds). A replacement stays tracked as unfinished work. Status: feature excluded, replacement open.
