# magadha

Dates, times and time zone offsets for Odin, without `core:time`.

The pure calendar and clock arithmetic needs nothing from the operating system. The only system
calls are in `clock_posix.odin`: `clock_gettime` for the current moment and `localtime_r` for the
machine's zone offset. `magadha.odin` imports only `base:intrinsics`. `format.odin` imports
`core:io`, `core:os` and `core:strings`, for the print procs that write to files and writers.
Nothing is imported from `core:time`, `vendor:` or any third party package.

## Daylight saving time is not handled

**This library has no time zone database and does not know about DST.** It works with fixed
offsets such as `+05:30`, not with zones such as `America/New_York`.

A fixed offset never changes, but a real zone does: New York is `-05:00` in winter and `-04:00` in
summer. Everything that depends on a zone's rules is missing:

- **Days are not always 24 hours.** In New York, 2026-03-08 has 23 hours and 2026-11-01 has 25.
  Here a day is always 24 hours.
- **Some local times do not exist.** 2026-03-08 02:30 in New York never happens, because the
  clocks jump from 02:00 to 03:00. A `Local_Date_Time` can hold it, and nothing warns you.
- **Some local times happen twice.** 2026-11-01 01:30 in New York is both `-04:00` and
  `-05:00`. A fixed offset picks one without telling you there were two.
- **`Period` and `Duration` give the same answer.** In a real zone, noon on 2026-03-07 plus one
  calendar day is noon on 03-08, but plus 24 hours is 13:00 on 03-08. With a fixed offset both
  land on noon, so the difference between them cannot show up. See the comment on `Period`.
- **Rules change over time.** A zone's offset in 1970 or 2006 can differ from today's. A database
  records that history, and this library has none.

What does work:

- **Instant to local time, in the machine's zone.** `zone_offset_system_at(instant)` asks the C
  library for the offset the machine's zone has at that moment, DST included, and
  `instant_to_local_date_time` applies it. For one known moment the answer is correct.
- **Anything in UTC or at a fixed offset.** Moments, durations, dates and calendar arithmetic are
  all exact there.

What is not supported: turning a local time in a named zone into a moment, arithmetic that crosses
a DST change, and any zone other than the machine's. Setting `TZ` to reach another zone changes
the whole process, so it is not a way to get one.

If you schedule things in a named zone, such as "every day at 09:00 in New York", do not store a
fixed offset. It will be wrong for half the year. Store the instant, or use a library with a zone
database.

## Types

| Type | What it is |
|---|---|
| `Instant` | A point on the timeline, seconds and nanoseconds since 1970-01-01T00:00:00Z. |
| `Duration` | An exact span of seconds and nanoseconds. Always the same length. |
| `Period` | Years, months and days. Its length depends on the date it is applied to. |
| `Local_Date` | A calendar date, like 2026-11-01. No time, no zone. |
| `Local_Time` | A time of day, like 14:30:00.5. No date, no zone. |
| `Local_Date_Time` | A date and a time of day together. No zone, so not a moment. |
| `Zone_Offset` | A fixed difference from UTC, up to 18 hours either way. |
| `Offset_Date_Time` | A `Local_Date_Time` plus a `Zone_Offset`. Names one real moment. |
| `Iso_Week_Date` | A date as ISO week, week year and weekday, like 2026-W44-7. |

Elapsed time is a `Duration`, and a calendar step such as "next month" is a `Period`. Keeping them
apart matters, because a month is not a fixed number of days.

### ISO weeks

`local_date_to_iso_week_date` gives the ISO 8601 week of a date. Weeks start on Monday, week 1 is
the week that holds January 4th, and a year has 52 or 53 weeks (`year_iso_week_count`).

The week year is not always the calendar year. 2021-01-01 is in week 53 of 2020, and 2024-12-31 is
in week 1 of 2025, so always keep `week_year` together with `week`. These are ISO weeks only. The
US convention, with Sunday-first weeks and week 1 holding January 1st, numbers some dates
differently. The last Saturday and Sunday of `YEAR_MAX`'s final week fall in the next calendar
year, past the supported range, so they have no `Iso_Week_Date`.

## Example

Put this directory next to your code, or add it as a collection, and import it:

```odin
package main

import "core:fmt"

import "magadha"

main :: proc() {
	// Build a checked date. Jan 31 plus one month clamps to the end of February.
	date, date_ok := magadha.local_date_make(2026, .january, 31)
	assert(date_ok)
	next, _ := magadha.local_date_plus_months(date, 1)
	fmt.println(next) // year 2026, month february, day 28

	// The current moment, shown at +05:30.
	instant := magadha.clock_wall_read()
	offset, _ := magadha.zone_offset_make_hours_minutes(5, 30)
	local, ok := magadha.instant_to_local_date_time(instant, offset)
	assert(ok)
	fmt.println(local.date, local.time)

	// Exact elapsed time.
	one_hour, _ := magadha.duration_from_hours(1)
	later, _ := magadha.instant_plus(instant, one_hour)
	fmt.println(magadha.instant_between(instant, later)) // seconds 3600

	// The machine's own zone, with its DST offset for this moment.
	now, now_ok := magadha.local_date_time_now()
	fmt.println(now, now_ok)
}
```

## Conventions

- **Failure is a `bool`.** Anything that can fail returns `(value, bool)`, and `false` means the
  result is out of range or not a real date. Nothing panics on valid input.
- **Invalid input is a bug.** Procs assert that their arguments are valid, so passing a bad
  `Local_Date` to one is a programmer error. Build values with the `_make` procs when the input
  is not already known to be good.
- **Zero is invalid for `Month`, `Weekday` and `Local_Date`**, so an uninitialized value is caught
  instead of silently meaning January or Monday. Zero is valid for `Local_Time` (midnight),
  `Zone_Offset` (UTC) and `Ordering` (`equal`).
- **Ranges are bounded.** Years run from -999,999 to 999,999, and a `Zone_Offset` from -18:00 to
  +18:00. Near the ends of the range a conversion can return `false`.
- **Leap seconds are ignored**, as POSIX does. Seconds run 0 to 59, and there is no 23:59:60.
- **Nanoseconds count forward.** In a `Duration` or `Instant`, minus half a second is
  `{seconds = -1, nanoseconds = 500_000_000}`, never a negative nanosecond count.
- **Compare with the procs, not `==`.** `offset_date_time_compare` orders by moment, so
  12:00 at +01:00 and 11:00 at +00:00 are equal. `==` compares the fields and says they differ.
- **Adding a month clamps and does not reverse.** Jan 31 plus one month is Feb 28, and minus one
  month from there is Jan 28.

## Platforms

`clock_posix.odin` builds on **darwin and linux** only, and assumes a 64 bit target. It has been
run on macOS. There is no Windows clock and no monotonic clock yet. The calendar and arithmetic
code in `magadha.odin` has no platform dependency.

`clock_wall_read` is wall clock time and can jump when the system clock is set, so it is wrong
for measuring how long something took.

`local_date_now`, `local_time_now` and `local_date_time_now` read the machine's zone from the
`TZ` variable or the system setting. That is process wide state, so they are not deterministic.
`local_date_now` and `local_time_now` read the clock separately, so near midnight they can
disagree. Use `local_date_time_now` when you need both.

## Not implemented

- Named time zones and DST, see the section above.
- Parsing, and text for `Offset_Date_Time`.
- Windows, and a monotonic clock for timing.

## Development

```
make test        # run the tests in test/
make fmt         # format every file with odinfmt
make fmt-check   # fail if any file is not formatted
make clean       # remove built binaries
```

`make fmt` uses `odinfmt`, the formatter that `ols` uses. The tests that change `TZ` run inside
one test, because the setting is shared by every thread.

The coding rules the library follows are in `claude.md`.
