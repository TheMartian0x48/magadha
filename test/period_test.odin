package chrono_test

import "core:testing"

import chrono "../"

@(test)
test_period_caps_cover_the_whole_calendar :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.PERIOD_YEARS_MAX, i32(1_999_998))
	testing.expect_value(t, chrono.PERIOD_MONTHS_MAX, chrono.PERIOD_YEARS_MAX * 12)
	testing.expect_value(t, chrono.PERIOD_DAYS_MAX, i32(730_484_633))

	// The widest legal period takes the earliest date to the latest and back.
	first := chrono.Local_Date{chrono.YEAR_MIN, .january, 1}
	last := chrono.Local_Date{chrono.YEAR_MAX, .december, 31}
	moved, ok := chrono.local_date_plus_days(first, i64(chrono.PERIOD_DAYS_MAX))
	testing.expect(t, ok)
	testing.expect_value(t, moved, last)
}

@(test)
test_period_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, chrono.period_is_valid({}))
	testing.expect(t, chrono.period_is_valid({1, -14, 30}))
	testing.expect(t, chrono.period_is_valid({chrono.PERIOD_YEARS_MAX, 0, 0}))
	testing.expect(t, chrono.period_is_valid({-chrono.PERIOD_YEARS_MAX, 0, 0}))
	testing.expect(t, chrono.period_is_valid({0, chrono.PERIOD_MONTHS_MAX, 0}))
	testing.expect(t, chrono.period_is_valid({0, 0, -chrono.PERIOD_DAYS_MAX}))
	testing.expect(t, !chrono.period_is_valid({chrono.PERIOD_YEARS_MAX + 1, 0, 0}))
	testing.expect(t, !chrono.period_is_valid({-chrono.PERIOD_YEARS_MAX - 1, 0, 0}))
	testing.expect(t, !chrono.period_is_valid({0, chrono.PERIOD_MONTHS_MAX + 1, 0}))
	testing.expect(t, !chrono.period_is_valid({0, 0, chrono.PERIOD_DAYS_MAX + 1}))
	// min(i32) is the case that abs() would get wrong.
	testing.expect(t, !chrono.period_is_valid({min(i32), 0, 0}))
	testing.expect(t, !chrono.period_is_valid({0, min(i32), 0}))
	testing.expect(t, !chrono.period_is_valid({0, 0, min(i32)}))
	testing.expect(t, !chrono.period_is_valid({max(i32), 0, 0}))
}

@(test)
test_period_make :: proc(t: ^testing.T) {
	period, ok := chrono.period_make(1, 2, 3)
	testing.expect(t, ok)
	testing.expect_value(t, period, chrono.Period{1, 2, 3})

	_, ok = chrono.period_make(chrono.PERIOD_YEARS_MAX + 1, 0, 0)
	testing.expect(t, !ok)
	_, ok = chrono.period_make(0, 0, min(i32))
	testing.expect(t, !ok)
}

@(test)
test_period_is_zero :: proc(t: ^testing.T) {
	testing.expect(t, chrono.period_is_zero({}))
	testing.expect(t, !chrono.period_is_zero({1, 0, 0}))
	testing.expect(t, !chrono.period_is_zero({0, 1, 0}))
	testing.expect(t, !chrono.period_is_zero({0, 0, 1}))
	// Fields are independent, so a year and minus twelve months is not the zero period.
	testing.expect(t, !chrono.period_is_zero({1, -12, 0}))
}

@(test)
test_period_negate :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.period_negate({1, -2, 3}), chrono.Period{-1, 2, -3})
	testing.expect_value(t, chrono.period_negate({}), chrono.Period{})

	// Every cap is symmetric, so the extremes negate without overflow.
	widest := chrono.Period {
		chrono.PERIOD_YEARS_MAX,
		-chrono.PERIOD_MONTHS_MAX,
		chrono.PERIOD_DAYS_MAX,
	}
	testing.expect(t, chrono.period_is_valid(chrono.period_negate(widest)))
	testing.expect_value(t, chrono.period_negate(chrono.period_negate(widest)), widest)
}

@(test)
test_period_plus :: proc(t: ^testing.T) {
	sum, ok := chrono.period_plus({1, 2, 3}, {10, -5, -1})
	testing.expect(t, ok)
	testing.expect_value(t, sum, chrono.Period{11, -3, 2})

	// Fields never carry into each other.
	sum, ok = chrono.period_plus({0, 11, 0}, {0, 11, 0})
	testing.expect(t, ok)
	testing.expect_value(t, sum, chrono.Period{0, 22, 0})

	_, ok = chrono.period_plus({chrono.PERIOD_YEARS_MAX, 0, 0}, {1, 0, 0})
	testing.expect(t, !ok)
	_, ok = chrono.period_plus({0, 0, -chrono.PERIOD_DAYS_MAX}, {0, 0, -1})
	testing.expect(t, !ok)
	_, ok = chrono.period_plus(
		{chrono.PERIOD_YEARS_MAX, chrono.PERIOD_MONTHS_MAX, chrono.PERIOD_DAYS_MAX},
		{chrono.PERIOD_YEARS_MAX, chrono.PERIOD_MONTHS_MAX, chrono.PERIOD_DAYS_MAX},
	)
	testing.expect(t, !ok)
}

@(test)
test_period_normalized :: proc(t: ^testing.T) {
	normalized, ok := chrono.period_normalized({0, 14, 5})
	testing.expect(t, ok)
	testing.expect_value(t, normalized, chrono.Period{1, 2, 5})

	normalized, ok = chrono.period_normalized({1, 11, 0})
	testing.expect(t, ok)
	testing.expect_value(t, normalized, chrono.Period{1, 11, 0})

	normalized, ok = chrono.period_normalized({2, -3, 0})
	testing.expect(t, ok)
	testing.expect_value(t, normalized, chrono.Period{1, 9, 0})

	// Years and months end up with the same sign.
	normalized, ok = chrono.period_normalized({-1, 3, 0})
	testing.expect(t, ok)
	testing.expect_value(t, normalized, chrono.Period{0, -9, 0})

	normalized, ok = chrono.period_normalized({0, -14, 0})
	testing.expect(t, ok)
	testing.expect_value(t, normalized, chrono.Period{-1, -2, 0})

	// Days are never folded into months.
	normalized, ok = chrono.period_normalized({0, 0, 400})
	testing.expect(t, ok)
	testing.expect_value(t, normalized, chrono.Period{0, 0, 400})
}

@(test)
test_period_normalized_keeps_total_months :: proc(t: ^testing.T) {
	for years in i32(-3) ..= 3 {
		for months in i32(-30) ..= 30 {
			period := chrono.Period{years, months, 7}
			normalized, ok := chrono.period_normalized(period)
			testing.expect(t, ok)
			testing.expect_value(t, normalized.years * 12 + normalized.months, years * 12 + months)
			testing.expect_value(t, normalized.days, 7)
			testing.expect(t, abs(normalized.months) < 12)
		}
	}
}
