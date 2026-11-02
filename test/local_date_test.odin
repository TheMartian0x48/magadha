package chrono_test

import "core:testing"

import chrono "../"

ROUND_TRIP_DAYS :: 1_000_000

@(test)
test_make_rejects_invalid :: proc(t: ^testing.T) {
	_, ok := chrono.local_date_make(2026, .february, 29)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_make(2026, .april, 31)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_make(2026, .april, 0)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_make(2026, chrono.Month(0), 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_make(2026, chrono.Month(13), 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_make(chrono.YEAR_MAX + 1, .january, 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_make(chrono.YEAR_MIN - 1, .january, 1)
	testing.expect(t, !ok)
}

@(test)
test_make_accepts_valid :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_make(2024, .february, 29)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2024, .february, 29})
	_, ok = chrono.local_date_make(chrono.YEAR_MAX, .december, 31)
	testing.expect(t, ok)
	_, ok = chrono.local_date_make(chrono.YEAR_MIN, .january, 1)
	testing.expect(t, ok)
}

@(test)
test_to_epoch_day_known_values :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.local_date_to_epoch_day({1970, .january, 1}), 0)
	testing.expect_value(t, chrono.local_date_to_epoch_day({1970, .january, 2}), 1)
	testing.expect_value(t, chrono.local_date_to_epoch_day({1969, .december, 31}), -1)
	testing.expect_value(t, chrono.local_date_to_epoch_day({2000, .march, 1}), 11_017)
	testing.expect_value(t, chrono.local_date_to_epoch_day({2026, .november, 1}), 20_758)
	testing.expect_value(t, chrono.local_date_to_epoch_day({0, .january, 1}), -719_528)
}

@(test)
test_from_epoch_day_known_values :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_from_epoch_day(0)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{1970, .january, 1})

	date, ok = chrono.local_date_from_epoch_day(-1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{1969, .december, 31})

	date, ok = chrono.local_date_from_epoch_day(11_017)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2000, .march, 1})

	date, ok = chrono.local_date_from_epoch_day(20_758)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .november, 1})
}

@(test)
test_from_epoch_day_out_of_range :: proc(t: ^testing.T) {
	max_date := chrono.Local_Date{chrono.YEAR_MAX, .december, 31}
	min_date := chrono.Local_Date{chrono.YEAR_MIN, .january, 1}
	max_day := chrono.local_date_to_epoch_day(max_date)
	min_day := chrono.local_date_to_epoch_day(min_date)

	_, ok := chrono.local_date_from_epoch_day(max_day)
	testing.expect(t, ok)
	_, ok = chrono.local_date_from_epoch_day(min_day)
	testing.expect(t, ok)
	_, ok = chrono.local_date_from_epoch_day(max_day + 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_epoch_day(min_day - 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_epoch_day(max(chrono.Epoch_Day))
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_epoch_day(min(chrono.Epoch_Day))
	testing.expect(t, !ok)
}

// Every day in the window must round trip and advance by exactly one calendar day.
@(test)
test_epoch_day_round_trip :: proc(t: ^testing.T) {
	previous: chrono.Local_Date
	for epoch_day in chrono.Epoch_Day(-ROUND_TRIP_DAYS) ..= ROUND_TRIP_DAYS {
		date, ok := chrono.local_date_from_epoch_day(epoch_day)
		testing.expect(t, ok)
		testing.expect_value(t, chrono.local_date_to_epoch_day(date), epoch_day)

		if epoch_day > -ROUND_TRIP_DAYS {
			testing.expect_value(
				t,
				chrono.local_date_compare(previous, date),
				chrono.Ordering.less,
			)
		}
		previous = date
	}
}

@(test)
test_weekday :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.local_date_weekday({1970, .january, 1}),
		chrono.Weekday.thursday,
	)
	testing.expect_value(
		t,
		chrono.local_date_weekday({2000, .january, 1}),
		chrono.Weekday.saturday,
	)
	testing.expect_value(t, chrono.local_date_weekday({2026, .november, 1}), chrono.Weekday.sunday)
	testing.expect_value(t, chrono.local_date_weekday({2026, .november, 2}), chrono.Weekday.monday)
	testing.expect_value(
		t,
		chrono.local_date_weekday({1969, .december, 31}),
		chrono.Weekday.wednesday,
	)
}

@(test)
test_day_of_year :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.local_date_day_of_year({2026, .january, 1}), 1)
	testing.expect_value(t, chrono.local_date_day_of_year({2026, .december, 31}), 365)
	testing.expect_value(t, chrono.local_date_day_of_year({2024, .december, 31}), 366)
	testing.expect_value(t, chrono.local_date_day_of_year({2024, .march, 1}), 61)
	testing.expect_value(t, chrono.local_date_day_of_year({2026, .march, 1}), 60)
}

@(test)
test_compare :: proc(t: ^testing.T) {
	base := chrono.Local_Date{2026, .june, 15}
	testing.expect_value(t, chrono.local_date_compare(base, base), chrono.Ordering.equal)
	testing.expect_value(
		t,
		chrono.local_date_compare(base, {2026, .june, 16}),
		chrono.Ordering.less,
	)
	testing.expect_value(
		t,
		chrono.local_date_compare(base, {2026, .july, 1}),
		chrono.Ordering.less,
	)
	testing.expect_value(
		t,
		chrono.local_date_compare(base, {2027, .january, 1}),
		chrono.Ordering.less,
	)
	testing.expect_value(
		t,
		chrono.local_date_compare({2026, .june, 16}, base),
		chrono.Ordering.greater,
	)
	testing.expect_value(
		t,
		chrono.local_date_compare({2026, .july, 1}, base),
		chrono.Ordering.greater,
	)
	testing.expect_value(
		t,
		chrono.local_date_compare({2027, .january, 1}, base),
		chrono.Ordering.greater,
	)
}

@(test)
test_is_before_and_is_after :: proc(t: ^testing.T) {
	base := chrono.Local_Date{2026, .june, 15}
	later := chrono.Local_Date{2026, .june, 16}

	testing.expect(t, chrono.local_date_is_before(base, later))
	testing.expect(t, !chrono.local_date_is_before(later, base))
	testing.expect(t, !chrono.local_date_is_before(base, base))

	testing.expect(t, chrono.local_date_is_after(later, base))
	testing.expect(t, !chrono.local_date_is_after(base, later))
	testing.expect(t, !chrono.local_date_is_after(base, base))

	// Year decides before month, month before day.
	testing.expect(t, chrono.local_date_is_before({2025, .december, 31}, {2026, .january, 1}))
	testing.expect(t, chrono.local_date_is_after({2026, .march, 1}, {2026, .february, 28}))
}

@(test)
test_first_day_of_month :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.local_date_first_day_of_month({2026, .november, 17}),
		chrono.Local_Date{2026, .november, 1},
	)
	testing.expect_value(
		t,
		chrono.local_date_first_day_of_month({2026, .november, 1}),
		chrono.Local_Date{2026, .november, 1},
	)
	testing.expect_value(
		t,
		chrono.local_date_first_day_of_month({chrono.YEAR_MAX, .december, 31}),
		chrono.Local_Date{chrono.YEAR_MAX, .december, 1},
	)
}

@(test)
test_last_day_of_month :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.local_date_last_day_of_month({2026, .january, 1}),
		chrono.Local_Date{2026, .january, 31},
	)
	testing.expect_value(
		t,
		chrono.local_date_last_day_of_month({2026, .february, 10}),
		chrono.Local_Date{2026, .february, 28},
	)
	testing.expect_value(
		t,
		chrono.local_date_last_day_of_month({2024, .february, 10}),
		chrono.Local_Date{2024, .february, 29},
	)
	testing.expect_value(
		t,
		chrono.local_date_last_day_of_month({2026, .april, 30}),
		chrono.Local_Date{2026, .april, 30},
	)
	testing.expect_value(
		t,
		chrono.local_date_last_day_of_month({chrono.YEAR_MIN, .february, 1}),
		chrono.Local_Date{chrono.YEAR_MIN, .february, 28},
	)
}

@(test)
test_first_and_last_day_stay_in_the_same_month :: proc(t: ^testing.T) {
	for epoch_day in chrono.Epoch_Day(-800) ..= 800 {
		date, ok := chrono.local_date_from_epoch_day(epoch_day)
		testing.expect(t, ok)
		first := chrono.local_date_first_day_of_month(date)
		last := chrono.local_date_last_day_of_month(date)
		testing.expect(t, chrono.local_date_is_valid(first))
		testing.expect(t, chrono.local_date_is_valid(last))
		testing.expect_value(t, first.month, date.month)
		testing.expect_value(t, last.month, date.month)
		testing.expect(t, !chrono.local_date_is_after(first, date))
		testing.expect(t, !chrono.local_date_is_before(last, date))
		// The day after the last day starts the next month.
		next, next_ok := chrono.local_date_plus_days(last, 1)
		testing.expect(t, next_ok)
		testing.expect_value(t, next.day, 1)
	}
}

@(test)
test_from_year_day_known_values :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_from_year_day(2026, 1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .january, 1})

	date, ok = chrono.local_date_from_year_day(2026, 60)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .march, 1})

	date, ok = chrono.local_date_from_year_day(2024, 60)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2024, .february, 29})

	date, ok = chrono.local_date_from_year_day(2026, 365)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .december, 31})

	date, ok = chrono.local_date_from_year_day(2024, 366)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2024, .december, 31})
}

@(test)
test_from_year_day_rejects_invalid :: proc(t: ^testing.T) {
	_, ok := chrono.local_date_from_year_day(2026, 0)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_year_day(2026, 366)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_year_day(2024, 367)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_year_day(2026, max(u16))
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_year_day(chrono.YEAR_MAX + 1, 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_year_day(chrono.YEAR_MIN - 1, 1)
	testing.expect(t, !ok)
}

@(test)
test_from_year_day_range_edges :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_from_year_day(chrono.YEAR_MIN, 1)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{chrono.YEAR_MIN, .january, 1})

	date, ok = chrono.local_date_from_year_day(
		chrono.YEAR_MAX,
		chrono.year_day_count(chrono.YEAR_MAX),
	)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{chrono.YEAR_MAX, .december, 31})
}

// Every day of a leap year, a common year, year zero, a negative year and a century year must
// round trip through day_of_year.
@(test)
test_from_year_day_inverts_day_of_year :: proc(t: ^testing.T) {
	years := [?]chrono.Year{2024, 2026, 1900, 2000, 0, -1, -4, chrono.YEAR_MIN, chrono.YEAR_MAX}
	for year in years {
		for day_of_year in u16(1) ..= chrono.year_day_count(year) {
			date, ok := chrono.local_date_from_year_day(year, day_of_year)
			testing.expect(t, ok)
			testing.expect_value(t, date.year, year)
			testing.expect_value(t, chrono.local_date_day_of_year(date), day_of_year)
		}
	}
}

@(test)
test_local_date_min_and_max :: proc(t: ^testing.T) {
	testing.expect(t, chrono.local_date_is_valid(chrono.LOCAL_DATE_MIN))
	testing.expect(t, chrono.local_date_is_valid(chrono.LOCAL_DATE_MAX))
	testing.expect_value(t, chrono.LOCAL_DATE_MIN, chrono.Local_Date{chrono.YEAR_MIN, .january, 1})
	testing.expect_value(
		t,
		chrono.LOCAL_DATE_MAX,
		chrono.Local_Date{chrono.YEAR_MAX, .december, 31},
	)

	// They are exactly the ends of the epoch day range, so nothing valid lies outside them.
	testing.expect_value(
		t,
		chrono.local_date_to_epoch_day(chrono.LOCAL_DATE_MIN),
		chrono.EPOCH_DAY_MIN,
	)
	testing.expect_value(
		t,
		chrono.local_date_to_epoch_day(chrono.LOCAL_DATE_MAX),
		chrono.EPOCH_DAY_MAX,
	)
	testing.expect_value(
		t,
		chrono.local_date_compare(chrono.LOCAL_DATE_MIN, chrono.LOCAL_DATE_MAX),
		chrono.Ordering.less,
	)

	_, ok := chrono.local_date_plus_days(chrono.LOCAL_DATE_MAX, 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_plus_days(chrono.LOCAL_DATE_MIN, -1)
	testing.expect(t, !ok)

	// Every other date sits between them.
	today := chrono.Local_Date{2026, .november, 1}
	testing.expect(t, chrono.local_date_is_after(today, chrono.LOCAL_DATE_MIN))
	testing.expect(t, chrono.local_date_is_before(today, chrono.LOCAL_DATE_MAX))
}

@(test)
test_first_and_last_day_of_year :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.local_date_first_day_of_year({2026, .november, 17}),
		chrono.Local_Date{2026, .january, 1},
	)
	testing.expect_value(
		t,
		chrono.local_date_last_day_of_year({2026, .november, 17}),
		chrono.Local_Date{2026, .december, 31},
	)
	testing.expect_value(
		t,
		chrono.local_date_first_day_of_year({2024, .february, 29}),
		chrono.Local_Date{2024, .january, 1},
	)
	testing.expect_value(
		t,
		chrono.local_date_last_day_of_year({2024, .february, 29}),
		chrono.Local_Date{2024, .december, 31},
	)
	testing.expect_value(
		t,
		chrono.local_date_first_day_of_year(chrono.LOCAL_DATE_MIN),
		chrono.LOCAL_DATE_MIN,
	)
	testing.expect_value(
		t,
		chrono.local_date_last_day_of_year(chrono.LOCAL_DATE_MAX),
		chrono.LOCAL_DATE_MAX,
	)
}

// The span from the first to the last day of a year is year_day_count - 1 days, so the
// two procs must agree with day_of_year for leap, common, century, zero and negative years.
@(test)
test_first_and_last_day_of_year_span_the_whole_year :: proc(t: ^testing.T) {
	years := [?]chrono.Year{2024, 2026, 1900, 2000, 0, -1, -4, chrono.YEAR_MIN, chrono.YEAR_MAX}
	for year in years {
		any_day := chrono.Local_Date{year, .june, 15}
		first := chrono.local_date_first_day_of_year(any_day)
		last := chrono.local_date_last_day_of_year(any_day)
		testing.expect_value(t, chrono.local_date_day_of_year(first), 1)
		testing.expect_value(t, chrono.local_date_day_of_year(last), chrono.year_day_count(year))
		testing.expect_value(
			t,
			chrono.local_date_days_between(first, last),
			i64(chrono.year_day_count(year)) - 1,
		)
		// The day after the last day starts the next year, unless this is the final year.
		next, ok := chrono.local_date_plus_days(last, 1)
		if year == chrono.YEAR_MAX {
			testing.expect(t, !ok)
		} else {
			testing.expect(t, ok)
			testing.expect_value(t, next, chrono.Local_Date{year + 1, .january, 1})
		}
	}
}

@(test)
test_local_date_earlier_and_later :: proc(t: ^testing.T) {
	older := chrono.Local_Date{2025, .december, 31}
	newer := chrono.Local_Date{2026, .january, 1}

	testing.expect_value(t, chrono.local_date_earlier(older, newer), older)
	testing.expect_value(t, chrono.local_date_earlier(newer, older), older)
	testing.expect_value(t, chrono.local_date_later(older, newer), newer)
	testing.expect_value(t, chrono.local_date_later(newer, older), newer)

	testing.expect_value(t, chrono.local_date_earlier(older, older), older)
	testing.expect_value(t, chrono.local_date_later(older, older), older)

	// Year decides before month, month before day.
	testing.expect_value(
		t,
		chrono.local_date_earlier({2026, .march, 1}, {2026, .february, 28}),
		chrono.Local_Date{2026, .february, 28},
	)
	testing.expect_value(
		t,
		chrono.local_date_later({2026, .february, 28}, {2026, .february, 27}),
		chrono.Local_Date{2026, .february, 28},
	)
}

@(test)
test_local_date_earlier_and_later_clamp_to_the_supported_range :: proc(t: ^testing.T) {
	today := chrono.Local_Date{2026, .november, 1}

	testing.expect_value(t, chrono.local_date_later(chrono.LOCAL_DATE_MIN, today), today)
	testing.expect_value(t, chrono.local_date_earlier(chrono.LOCAL_DATE_MAX, today), today)
	testing.expect_value(
		t,
		chrono.local_date_earlier(chrono.LOCAL_DATE_MIN, today),
		chrono.LOCAL_DATE_MIN,
	)
	testing.expect_value(
		t,
		chrono.local_date_later(chrono.LOCAL_DATE_MAX, today),
		chrono.LOCAL_DATE_MAX,
	)
}

// Over a run of consecutive days, the earlier of two dates is the one with the smaller epoch
// day and the later the one with the larger, in both argument orders.
@(test)
test_local_date_earlier_and_later_agree_with_epoch_days :: proc(t: ^testing.T) {
	for first_day in chrono.Epoch_Day(-40) ..= 40 {
		for second_day in chrono.Epoch_Day(-40) ..= 40 {
			first, first_ok := chrono.local_date_from_epoch_day(first_day)
			second, second_ok := chrono.local_date_from_epoch_day(second_day)
			testing.expect(t, first_ok && second_ok)

			earlier := chrono.local_date_earlier(first, second)
			later := chrono.local_date_later(first, second)
			testing.expect_value(
				t,
				chrono.local_date_to_epoch_day(earlier),
				min(first_day, second_day),
			)
			testing.expect_value(
				t,
				chrono.local_date_to_epoch_day(later),
				max(first_day, second_day),
			)
		}
	}
}
