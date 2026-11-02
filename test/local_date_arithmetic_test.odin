package chrono_test

import "core:testing"

import chrono "../"

// Steps one month at a time, clamping the original day to each month's length: the slow
// reference for local_date_plus_months in the forward direction. It clamps against the
// original day, not the previous step's day, so Jan 31 plus 2 months is Mar 31, not Mar 28.
reference_plus_months :: proc(date: chrono.Local_Date, months: i32) -> chrono.Local_Date {
	result := date
	for _ in 0 ..< months {
		next_month := chrono.month_plus(result.month, 1)
		next_year := result.year + (1 if result.month == .december else 0)
		result = {
			next_year,
			next_month,
			min(date.day, chrono.days_in_month(next_year, next_month)),
		}
	}
	return result
}

@(test)
test_plus_days :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_plus_days({2026, .november, 1}, 30)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .december, 1})

	date, ok = chrono.local_date_plus_days({2026, .january, 1}, -1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2025, .december, 31})

	date, ok = chrono.local_date_plus_days({2024, .february, 28}, 1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2024, .february, 29})

	date, ok = chrono.local_date_plus_days({2026, .february, 28}, 1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .march, 1})

	date, ok = chrono.local_date_plus_days({2026, .march, 5}, 0)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .march, 5})

	// A full 400 year cycle is 146097 days and lands on the same month and day.
	date, ok = chrono.local_date_plus_days({2000, .february, 29}, 146_097)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2400, .february, 29})
}

@(test)
test_plus_days_range_edges :: proc(t: ^testing.T) {
	first := chrono.Local_Date{chrono.YEAR_MIN, .january, 1}
	last := chrono.Local_Date{chrono.YEAR_MAX, .december, 31}

	_, ok := chrono.local_date_plus_days(last, 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_days(first, -1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_days(last, max(i64))
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_days(first, min(i64))
	testing.expect(t, !ok)

	date, plus_ok := chrono.local_date_plus_days(last, -i64(chrono.PERIOD_DAYS_MAX))
	testing.expect(t, plus_ok)
	testing.expect_value(t, date, first)
}

@(test)
test_plus_months_clamps_the_day :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_plus_months({2026, .january, 31}, 1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .february, 28})

	date, ok = chrono.local_date_plus_months({2024, .january, 31}, 1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2024, .february, 29})

	date, ok = chrono.local_date_plus_months({2026, .march, 31}, 1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .april, 30})

	date, ok = chrono.local_date_plus_months({2026, .march, 31}, -1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .february, 28})

	date, ok = chrono.local_date_plus_months({2026, .march, 15}, 0)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .march, 15})
}

@(test)
test_plus_months_crosses_years :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_plus_months({2026, .november, 15}, 2)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2027, .january, 15})

	date, ok = chrono.local_date_plus_months({2026, .january, 15}, -1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2025, .december, 15})

	date, ok = chrono.local_date_plus_months({2026, .june, 15}, 24)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2028, .june, 15})

	// Across year zero: month arithmetic must floor, not truncate.
	date, ok = chrono.local_date_plus_months({1, .january, 31}, -2)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{0, .november, 30})

	date, ok = chrono.local_date_plus_months({0, .january, 15}, -1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{-1, .december, 15})

	date, ok = chrono.local_date_plus_months({-1, .december, 15}, 1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{0, .january, 15})
}

@(test)
test_plus_months_matches_reference :: proc(t: ^testing.T) {
	starts := [?]chrono.Local_Date {
		{2026, .january, 31},
		{2024, .january, 31},
		{2024, .february, 29},
		{2026, .august, 31},
		{2026, .december, 1},
		{-4, .february, 29},
	}
	for start in starts {
		for months in i32(0) ..= 60 {
			actual, ok := chrono.local_date_plus_months(start, i64(months))
			testing.expect(t, ok)
			testing.expect_value(t, actual, reference_plus_months(start, months))
		}
	}
}

@(test)
test_plus_months_is_not_reversible :: proc(t: ^testing.T) {
	forward, forward_ok := chrono.local_date_plus_months({2026, .january, 31}, 1)
	testing.expect(t, forward_ok)
	back, back_ok := chrono.local_date_plus_months(forward, -1)
	testing.expect(t, back_ok)
	testing.expect_value(t, back, chrono.Local_Date{2026, .january, 28})
}

@(test)
test_plus_months_range_edges :: proc(t: ^testing.T) {
	_, ok := chrono.local_date_plus_months({chrono.YEAR_MAX, .december, 31}, 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_months({chrono.YEAR_MIN, .january, 1}, -1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_months({0, .january, 1}, max(i64))
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_months({0, .january, 1}, min(i64))
	testing.expect(t, !ok)

	date, plus_ok := chrono.local_date_plus_months({chrono.YEAR_MAX, .december, 31}, 0)
	testing.expect(t, plus_ok)
	testing.expect_value(t, date, chrono.Local_Date{chrono.YEAR_MAX, .december, 31})

	date, plus_ok = chrono.local_date_plus_months({chrono.YEAR_MIN, .january, 31}, 11)
	testing.expect(t, plus_ok)
	testing.expect_value(t, date, chrono.Local_Date{chrono.YEAR_MIN, .december, 31})

	date, plus_ok = chrono.local_date_plus_months(
		{chrono.YEAR_MIN, .january, 1},
		i64(chrono.PERIOD_MONTHS_MAX) + 11,
	)
	testing.expect(t, plus_ok)
	testing.expect_value(t, date, chrono.Local_Date{chrono.YEAR_MAX, .december, 1})

	_, ok = chrono.local_date_plus_months(
		{chrono.YEAR_MIN, .january, 1},
		i64(chrono.PERIOD_MONTHS_MAX) + 12,
	)
	testing.expect(t, !ok)
}

@(test)
test_plus_years :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_plus_years({2026, .november, 1}, 5)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2031, .november, 1})

	// Feb 29 clamps to Feb 28 unless the target year is also a leap year.
	date, ok = chrono.local_date_plus_years({2024, .february, 29}, 1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2025, .february, 28})

	date, ok = chrono.local_date_plus_years({2024, .february, 29}, 4)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2028, .february, 29})

	date, ok = chrono.local_date_plus_years({2024, .february, 29}, -4)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2020, .february, 29})

	date, ok = chrono.local_date_plus_years({2000, .february, 29}, 100)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2100, .february, 28})
}

@(test)
test_plus_years_range_edges :: proc(t: ^testing.T) {
	_, ok := chrono.local_date_plus_years({chrono.YEAR_MAX, .june, 1}, 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_years({chrono.YEAR_MIN, .june, 1}, -1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_years({0, .june, 1}, max(i64))
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_years({0, .june, 1}, min(i64))
	testing.expect(t, !ok)

	date, plus_ok := chrono.local_date_plus_years(
		{chrono.YEAR_MIN, .june, 1},
		i64(chrono.PERIOD_YEARS_MAX),
	)
	testing.expect(t, plus_ok)
	testing.expect_value(t, date, chrono.Local_Date{chrono.YEAR_MAX, .june, 1})
}

@(test)
test_plus_years_equals_twelve_times_months :: proc(t: ^testing.T) {
	starts := [?]chrono.Local_Date {
		{2024, .february, 29},
		{2026, .january, 31},
		{2026, .december, 31},
	}
	for start in starts {
		for years in i64(-50) ..= 50 {
			by_years, years_ok := chrono.local_date_plus_years(start, years)
			by_months, months_ok := chrono.local_date_plus_months(start, years * 12)
			testing.expect(t, years_ok)
			testing.expect(t, months_ok)
			testing.expect_value(t, by_years, by_months)
		}
	}
}

@(test)
test_days_between :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.local_date_days_between({2026, .january, 1}, {2026, .january, 1}),
		0,
	)
	testing.expect_value(
		t,
		chrono.local_date_days_between({2026, .january, 1}, {2026, .january, 31}),
		30,
	)
	testing.expect_value(
		t,
		chrono.local_date_days_between({2026, .january, 31}, {2026, .january, 1}),
		-30,
	)
	testing.expect_value(
		t,
		chrono.local_date_days_between({2026, .january, 1}, {2027, .january, 1}),
		365,
	)
	testing.expect_value(
		t,
		chrono.local_date_days_between({2024, .january, 1}, {2025, .january, 1}),
		366,
	)
	testing.expect_value(
		t,
		chrono.local_date_days_between({1970, .january, 1}, {2026, .november, 1}),
		20_758,
	)
}

@(test)
test_days_between_widest_span :: proc(t: ^testing.T) {
	first := chrono.Local_Date{chrono.YEAR_MIN, .january, 1}
	last := chrono.Local_Date{chrono.YEAR_MAX, .december, 31}
	testing.expect_value(
		t,
		chrono.local_date_days_between(first, last),
		i64(chrono.PERIOD_DAYS_MAX),
	)
	testing.expect_value(
		t,
		chrono.local_date_days_between(last, first),
		-i64(chrono.PERIOD_DAYS_MAX),
	)
}

@(test)
test_days_between_inverts_plus_days :: proc(t: ^testing.T) {
	start := chrono.Local_Date{2026, .november, 1}
	for days in i64(-1000) ..= 1000 {
		moved, ok := chrono.local_date_plus_days(start, days)
		testing.expect(t, ok)
		testing.expect_value(t, chrono.local_date_days_between(start, moved), days)
	}
}

@(test)
test_plus_period :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_plus_period({2026, .november, 1}, {1, 2, 3})
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2028, .january, 4})

	date, ok = chrono.local_date_plus_period({2026, .november, 1}, {})
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .november, 1})

	date, ok = chrono.local_date_plus_period({2026, .november, 1}, {-1, -2, -3})
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2025, .august, 29})
}

// Months are applied before days. Jan 30 plus 1 month clamps to Feb 28, then 2 days gives Mar 2.
// The other order would give Jan 30 plus 2 days = Feb 1, then plus 1 month = Mar 1.
@(test)
test_plus_period_applies_months_before_days :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_plus_period({2026, .january, 30}, {0, 1, 2})
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .march, 2})

	reversed, days_ok := chrono.local_date_plus_days({2026, .january, 30}, 2)
	testing.expect(t, days_ok)
	reversed, days_ok = chrono.local_date_plus_months(reversed, 1)
	testing.expect(t, days_ok)
	testing.expect_value(t, reversed, chrono.Local_Date{2026, .march, 1})
}

@(test)
test_plus_period_years_and_months_act_as_one_number_of_months :: proc(t: ^testing.T) {
	// A year and minus twelve months cancel, even though the fields are not normalized.
	date, ok := chrono.local_date_plus_period({2026, .january, 31}, {1, -12, 0})
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .january, 31})

	// Years first then months would clamp twice; as one step it clamps once.
	date, ok = chrono.local_date_plus_period({2024, .february, 29}, {1, 12, 0})
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .february, 28})
}

@(test)
test_plus_period_matches_individual_steps :: proc(t: ^testing.T) {
	start := chrono.Local_Date{2026, .january, 31}
	for years in i32(-2) ..= 2 {
		for months in i32(-14) ..= 14 {
			for days in i32(-40) ..= 40 {
				actual, ok := chrono.local_date_plus_period(start, {years, months, days})
				testing.expect(t, ok)

				stepped, step_ok := chrono.local_date_plus_months(
					start,
					i64(years) * 12 + i64(months),
				)
				testing.expect(t, step_ok)
				stepped, step_ok = chrono.local_date_plus_days(stepped, i64(days))
				testing.expect(t, step_ok)
				testing.expect_value(t, actual, stepped)
			}
		}
	}
}

@(test)
test_plus_period_range_edges :: proc(t: ^testing.T) {
	last := chrono.Local_Date{chrono.YEAR_MAX, .december, 31}
	first := chrono.Local_Date{chrono.YEAR_MIN, .january, 1}

	_, ok := chrono.local_date_plus_period(last, {0, 0, 1})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_period(last, {0, 1, 0})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_period(first, {-1, 0, 0})
	testing.expect(t, !ok)

	// The widest legal period from the first date lands on the last.
	date, plus_ok := chrono.local_date_plus_period(first, {0, 0, chrono.PERIOD_DAYS_MAX})
	testing.expect(t, plus_ok)
	testing.expect_value(t, date, last)

	// Forward by days and back by the negated period gives the original date.
	back, back_ok := chrono.local_date_plus_period(
		date,
		chrono.period_negate({0, 0, chrono.PERIOD_DAYS_MAX}),
	)
	testing.expect(t, back_ok)
	testing.expect_value(t, back, first)
}
