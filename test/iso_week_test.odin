package chrono_test

import "core:testing"

import chrono "../"

// Dates checked against an independent ISO 8601 calendar (Python's date.isocalendar()).
Iso_Case :: struct {
	date: chrono.Local_Date,
	iso:  chrono.Iso_Week_Date,
}

ISO_CASES :: [?]Iso_Case {
	// The four days that belong to a neighbouring year's weeks.
	{{2021, .january, 1}, {2020, 53, .friday}},
	{{2027, .january, 1}, {2026, 53, .friday}},
	{{2024, .december, 31}, {2025, 1, .tuesday}},
	{{2025, .december, 31}, {2026, 1, .wednesday}},
	// Ordinary dates.
	{{2026, .november, 1}, {2026, 44, .sunday}},
	{{2026, .november, 2}, {2026, 45, .monday}},
	{{1970, .january, 1}, {1970, 1, .thursday}},
	{{2000, .january, 1}, {1999, 52, .saturday}},
	{{1900, .january, 1}, {1900, 1, .monday}},
	{{2024, .january, 1}, {2024, 1, .monday}},
	{{2026, .january, 1}, {2026, 1, .thursday}},
	// Ends of 53 and 52 week years.
	{{2020, .december, 31}, {2020, 53, .thursday}},
	{{2026, .december, 31}, {2026, 53, .thursday}},
	{{2027, .december, 31}, {2027, 52, .friday}},
	{{2015, .december, 31}, {2015, 53, .thursday}},
	{{2016, .january, 3}, {2015, 53, .sunday}},
	{{2016, .january, 4}, {2016, 1, .monday}},
	{{2008, .december, 29}, {2009, 1, .monday}},
	{{2010, .january, 3}, {2009, 53, .sunday}},
	// Year 1 and a far year.
	{{1, .january, 1}, {1, 1, .monday}},
	{{9999, .december, 31}, {9999, 52, .friday}},
}

@(test)
test_iso_week_date_known_values :: proc(t: ^testing.T) {
	for entry in ISO_CASES {
		testing.expect_value(t, chrono.local_date_to_iso_week_date(entry.date), entry.iso)

		date, ok := chrono.local_date_from_iso_week_date(entry.iso)
		testing.expect(t, ok)
		testing.expect_value(t, date, entry.date)
	}
}

@(test)
test_iso_week_year_is_not_always_the_calendar_year :: proc(t: ^testing.T) {
	// Early January in the previous week year, late December in the next one.
	testing.expect_value(
		t,
		chrono.local_date_to_iso_week_date({2021, .january, 1}).week_year,
		chrono.Year(2020),
	)
	testing.expect_value(
		t,
		chrono.local_date_to_iso_week_date({2024, .december, 31}).week_year,
		chrono.Year(2025),
	)

	// Pairing the calendar year with the week number names a different date, or none at all.
	_, ok := chrono.local_date_from_iso_week_date({2021, 53, .friday})
	testing.expect(t, !ok)
}

@(test)
test_year_iso_week_count :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.year_iso_week_count(2026), 53)
	testing.expect_value(t, chrono.year_iso_week_count(2020), 53)
	testing.expect_value(t, chrono.year_iso_week_count(2015), 53)
	testing.expect_value(t, chrono.year_iso_week_count(2025), 52)
	testing.expect_value(t, chrono.year_iso_week_count(2024), 52)
	testing.expect_value(t, chrono.year_iso_week_count(2008), 52)
	// January 1st on a Wednesday gives 53 weeks only in a leap year.
	testing.expect_value(t, chrono.year_iso_week_count(2020), 53)
	testing.expect_value(t, chrono.year_iso_week_count(2025), 52)
}

@(test)
test_year_iso_week_count_matches_the_known_53_week_years :: proc(t: ^testing.T) {
	// 1900 to 2100, from an independent calendar. 36 years in this window have 53 weeks.
	expected := [?]chrono.Year {
		1903,
		1908,
		1914,
		1920,
		1925,
		1931,
		1936,
		1942,
		1948,
		1953,
		1959,
		1964,
		1970,
		1976,
		1981,
		1987,
		1992,
		1998,
		2004,
		2009,
		2015,
		2020,
		2026,
		2032,
		2037,
		2043,
		2048,
		2054,
		2060,
		2065,
		2071,
		2076,
		2082,
		2088,
		2093,
		2099,
	}
	next := 0
	for year in chrono.Year(1900) ..= 2100 {
		has_53 := chrono.year_iso_week_count(year) == 53
		is_expected := next < len(expected) && expected[next] == year
		testing.expect_value(t, has_53, is_expected)
		if is_expected {
			next += 1
		}
	}
	testing.expect_value(t, next, len(expected))
}

// The Gregorian calendar repeats every 400 years, a whole number of weeks, so exactly 71 of
// every 400 years have 53 weeks, whichever 400 years you look at.
@(test)
test_year_iso_week_count_repeats_every_400_years :: proc(t: ^testing.T) {
	windows := [?]chrono.Year{1, 1601, -399, chrono.YEAR_MIN, chrono.YEAR_MAX - 399}
	for start in windows {
		long_years := 0
		for offset in chrono.Year(0) ..< 400 {
			if chrono.year_iso_week_count(start + offset) == 53 {
				long_years += 1
			}
		}
		testing.expect_value(t, long_years, 71)
	}
	for year in chrono.Year(1) ..= 400 {
		testing.expect_value(
			t,
			chrono.year_iso_week_count(year),
			chrono.year_iso_week_count(year + 400),
		)
	}
}

// Every day for about 24 years: it converts to a valid ISO date and back to itself, the weekday
// agrees with local_date_weekday, and each Monday starts a new week.
@(test)
test_iso_week_date_round_trip_over_many_days :: proc(t: ^testing.T) {
	previous: chrono.Iso_Week_Date
	for epoch_day in chrono.Epoch_Day(-4_000) ..= 4_800 {
		date, date_ok := chrono.local_date_from_epoch_day(epoch_day)
		testing.expect(t, date_ok)

		iso := chrono.local_date_to_iso_week_date(date)
		testing.expect(t, chrono.iso_week_date_is_valid(iso))
		testing.expect_value(t, iso.weekday, chrono.local_date_weekday(date))
		testing.expect(t, iso.week >= 1 && iso.week <= chrono.year_iso_week_count(iso.week_year))

		back, back_ok := chrono.local_date_from_iso_week_date(iso)
		testing.expect(t, back_ok)
		testing.expect_value(t, back, date)

		if epoch_day > -4_000 {
			if iso.weekday == .monday {
				// A Monday starts the next week, or week 1 of the next week year.
				same_year := iso.week_year == previous.week_year
				testing.expect(
					t,
					(same_year && iso.week == previous.week + 1) || (!same_year && iso.week == 1),
				)
			} else {
				// Any other day stays in the same week.
				testing.expect_value(t, iso.week_year, previous.week_year)
				testing.expect_value(t, iso.week, previous.week)
			}
		}
		previous = iso
	}
}

@(test)
test_local_date_from_iso_week_date_rejects_invalid :: proc(t: ^testing.T) {
	// Week 0 and weeks past the count.
	_, ok := chrono.local_date_from_iso_week_date({2026, 0, .monday})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_iso_week_date({2026, 54, .monday})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_iso_week_date({2026, max(u8), .monday})
	testing.expect(t, !ok)

	// 2026 has 53 weeks, 2025 has 52.
	_, ok = chrono.local_date_from_iso_week_date({2026, 53, .monday})
	testing.expect(t, ok)
	_, ok = chrono.local_date_from_iso_week_date({2025, 53, .monday})
	testing.expect(t, !ok)

	// A weekday that does not exist.
	_, ok = chrono.local_date_from_iso_week_date({2026, 1, chrono.Weekday(0)})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_iso_week_date({2026, 1, chrono.Weekday(8)})
	testing.expect(t, !ok)

	// A week year out of range.
	_, ok = chrono.local_date_from_iso_week_date({chrono.YEAR_MAX + 1, 1, .monday})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_iso_week_date({chrono.YEAR_MIN - 1, 1, .monday})
	testing.expect(t, !ok)

	// A zeroed value is invalid: week 0 and weekday 0.
	testing.expect(t, !chrono.iso_week_date_is_valid({}))
}

@(test)
test_iso_week_date_at_the_ends_of_the_range :: proc(t: ^testing.T) {
	// The first date is a Monday and starts week 1, so nothing comes before it.
	first := chrono.local_date_to_iso_week_date(chrono.LOCAL_DATE_MIN)
	testing.expect_value(t, first, chrono.Iso_Week_Date{chrono.YEAR_MIN, 1, .monday})
	back, ok := chrono.local_date_from_iso_week_date(first)
	testing.expect(t, ok)
	testing.expect_value(t, back, chrono.LOCAL_DATE_MIN)

	// The last date is a Friday in the final week of its year.
	last := chrono.local_date_to_iso_week_date(chrono.LOCAL_DATE_MAX)
	testing.expect_value(t, last.week_year, chrono.YEAR_MAX)
	testing.expect_value(t, last.week, chrono.year_iso_week_count(chrono.YEAR_MAX))
	testing.expect_value(t, last.weekday, chrono.Weekday.friday)
	back, ok = chrono.local_date_from_iso_week_date(last)
	testing.expect(t, ok)
	testing.expect_value(t, back, chrono.LOCAL_DATE_MAX)

	// The Saturday and Sunday of that week are in the next calendar year, past the range, so
	// they cannot be built, while the Friday before them can.
	saturday := chrono.Iso_Week_Date{last.week_year, last.week, .saturday}
	sunday := chrono.Iso_Week_Date{last.week_year, last.week, .sunday}
	testing.expect(t, !chrono.iso_week_date_is_valid(saturday))
	testing.expect(t, !chrono.iso_week_date_is_valid(sunday))
	testing.expect(t, chrono.iso_week_date_is_valid(last))
}

// Walks the last 20 days and first 20 days of the range: the conversions must stay valid
// and invert each other right up to both edges.
@(test)
test_iso_week_date_near_the_range_ends :: proc(t: ^testing.T) {
	for offset in i64(0) ..< 20 {
		for edge in ([?]chrono.Local_Date{chrono.LOCAL_DATE_MIN, chrono.LOCAL_DATE_MAX}) {
			sign: i64 = 1 if edge == chrono.LOCAL_DATE_MIN else -1
			date, date_ok := chrono.local_date_plus_days(edge, sign * offset)
			testing.expect(t, date_ok)

			iso := chrono.local_date_to_iso_week_date(date)
			testing.expect(t, chrono.iso_week_date_is_valid(iso))
			back, back_ok := chrono.local_date_from_iso_week_date(iso)
			testing.expect(t, back_ok)
			testing.expect_value(t, back, date)
		}
	}
}
