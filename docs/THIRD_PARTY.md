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
