package chrono_test

import "core:slice"
import "core:testing"

import chrono "../"

@(test)
test_local_date_time_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, chrono.local_date_time_is_valid({{2026, .november, 1}, {14, 30, 0, 0}}))
	testing.expect(t, chrono.local_date_time_is_valid(chrono.LOCAL_DATE_TIME_MIN))
	testing.expect(t, chrono.local_date_time_is_valid(chrono.LOCAL_DATE_TIME_MAX))

	// Either part being invalid makes the whole value invalid.
	testing.expect(t, !chrono.local_date_time_is_valid({{2026, .february, 29}, {14, 30, 0, 0}}))
	testing.expect(t, !chrono.local_date_time_is_valid({{2026, .november, 1}, {24, 0, 0, 0}}))
	testing.expect(t, !chrono.local_date_time_is_valid({{2026, .november, 1}, {0, 0, 60, 0}}))
	testing.expect(t, !chrono.local_date_time_is_valid({{chrono.YEAR_MAX + 1, .january, 1}, {}}))

	// A zeroed value is invalid, because a zeroed date is: month 0 does not exist.
	testing.expect(t, !chrono.local_date_time_is_valid({}))
}

@(test)
test_local_date_time_make :: proc(t: ^testing.T) {
	date_time, ok := chrono.local_date_time_make({2026, .november, 1}, {14, 30, 15, 500})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		date_time,
		chrono.Local_Date_Time{{2026, .november, 1}, {14, 30, 15, 500}},
	)

	_, ok = chrono.local_date_time_make({2026, .february, 29}, {})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_time_make({2026, .november, 1}, {24, 0, 0, 0})
	testing.expect(t, !ok)
}

@(test)
test_local_date_time_min_and_max :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.LOCAL_DATE_TIME_MIN,
		chrono.Local_Date_Time{{chrono.YEAR_MIN, .january, 1}, {0, 0, 0, 0}},
	)
	testing.expect_value(
		t,
		chrono.LOCAL_DATE_TIME_MAX,
		chrono.Local_Date_Time{{chrono.YEAR_MAX, .december, 31}, {23, 59, 59, 999_999_999}},
	)

	// Nothing valid lies outside them: one nanosecond past either end fails.
	_, ok := chrono.local_date_time_plus_duration(chrono.LOCAL_DATE_TIME_MAX, {0, 1})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_time_plus_duration(chrono.LOCAL_DATE_TIME_MIN, {-1, 999_999_999})
	testing.expect(t, !ok)
}

// The widest span between two date times must be exactly the Duration range, in both directions.
@(test)
test_local_date_time_span_equals_the_duration_range :: proc(t: ^testing.T) {
	forward := chrono.local_date_time_between(
		chrono.LOCAL_DATE_TIME_MIN,
		chrono.LOCAL_DATE_TIME_MAX,
	)
	testing.expect_value(t, forward, chrono.Duration{chrono.DURATION_SECONDS_MAX, 999_999_999})

	backward := chrono.local_date_time_between(
		chrono.LOCAL_DATE_TIME_MAX,
		chrono.LOCAL_DATE_TIME_MIN,
	)
	testing.expect_value(t, backward, chrono.Duration{chrono.DURATION_SECONDS_MIN, 1})

	testing.expect(t, chrono.duration_is_valid(forward))
	testing.expect(t, chrono.duration_is_valid(backward))
}

@(test)
test_local_date_time_midnight_of :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.local_date_time_midnight_of({2026, .november, 1}),
		chrono.Local_Date_Time{{2026, .november, 1}, chrono.LOCAL_TIME_MIDNIGHT},
	)
	testing.expect_value(
		t,
		chrono.local_date_time_midnight_of(chrono.LOCAL_DATE_MIN),
		chrono.LOCAL_DATE_TIME_MIN,
	)
}

@(test)
test_local_date_time_compare :: proc(t: ^testing.T) {
	base := chrono.Local_Date_Time{{2026, .june, 15}, {10, 30, 0, 0}}
	testing.expect_value(t, chrono.local_date_time_compare(base, base), chrono.Ordering.equal)

	// Same date: the time decides.
	testing.expect_value(
		t,
		chrono.local_date_time_compare(base, {{2026, .june, 15}, {10, 30, 0, 1}}),
		chrono.Ordering.less,
	)
	testing.expect_value(
		t,
		chrono.local_date_time_compare({{2026, .june, 15}, {11, 0, 0, 0}}, base),
		chrono.Ordering.greater,
	)

	// The date decides first, whatever the time is.
	testing.expect_value(
		t,
		chrono.local_date_time_compare(
			{{2026, .june, 15}, {23, 59, 59, 999_999_999}},
			{{2026, .june, 16}, {}},
		),
		chrono.Ordering.less,
	)
	testing.expect_value(
		t,
		chrono.local_date_time_compare(
			{{2026, .june, 16}, {}},
			{{2026, .june, 15}, {23, 59, 59, 999_999_999}},
		),
		chrono.Ordering.greater,
	)
}

@(test)
test_local_date_time_is_before_and_is_after :: proc(t: ^testing.T) {
	early := chrono.Local_Date_Time{{2026, .june, 15}, {9, 0, 0, 0}}
	late := chrono.Local_Date_Time{{2026, .june, 15}, {18, 0, 0, 0}}
	testing.expect(t, chrono.local_date_time_is_before(early, late))
	testing.expect(t, !chrono.local_date_time_is_before(late, early))
	testing.expect(t, !chrono.local_date_time_is_before(early, early))
	testing.expect(t, chrono.local_date_time_is_after(late, early))
	testing.expect(t, !chrono.local_date_time_is_after(early, late))
	testing.expect(t, !chrono.local_date_time_is_after(early, early))
}

@(test)
test_local_date_time_earlier_and_later :: proc(t: ^testing.T) {
	older := chrono.Local_Date_Time{{2025, .december, 31}, {23, 59, 59, 0}}
	newer := chrono.Local_Date_Time{{2026, .january, 1}, {0, 0, 0, 0}}
	testing.expect_value(t, chrono.local_date_time_earlier(older, newer), older)
	testing.expect_value(t, chrono.local_date_time_earlier(newer, older), older)
	testing.expect_value(t, chrono.local_date_time_later(older, newer), newer)
	testing.expect_value(t, chrono.local_date_time_later(newer, older), newer)
	testing.expect_value(t, chrono.local_date_time_earlier(older, older), older)
	testing.expect_value(t, chrono.local_date_time_later(older, older), older)

	testing.expect_value(t, chrono.local_date_time_later(chrono.LOCAL_DATE_TIME_MIN, newer), newer)
	testing.expect_value(
		t,
		chrono.local_date_time_earlier(chrono.LOCAL_DATE_TIME_MAX, newer),
		newer,
	)
}

@(test)
test_local_date_time_sorts_mixed_values :: proc(t: ^testing.T) {
	values := [5]chrono.Local_Date_Time {
		{{2026, .march, 2}, {0, 0, 0, 0}},
		{{2026, .march, 1}, {23, 59, 59, 999_999_999}},
		{{2026, .march, 2}, {0, 0, 0, 1}},
		{{2025, .december, 31}, {12, 0, 0, 0}},
		{{2026, .march, 1}, {0, 0, 0, 0}},
	}
	slice.sort_by(values[:], chrono.local_date_time_is_before)

	expected := [5]chrono.Local_Date_Time {
		{{2025, .december, 31}, {12, 0, 0, 0}},
		{{2026, .march, 1}, {0, 0, 0, 0}},
		{{2026, .march, 1}, {23, 59, 59, 999_999_999}},
		{{2026, .march, 2}, {0, 0, 0, 0}},
		{{2026, .march, 2}, {0, 0, 0, 1}},
	}
	testing.expect_value(t, values, expected)
}

@(test)
test_local_date_time_plus_duration_within_a_day :: proc(t: ^testing.T) {
	result, ok := chrono.local_date_time_plus_duration(
		{{2026, .november, 1}, {10, 0, 0, 0}},
		{90, 0},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Local_Date_Time{{2026, .november, 1}, {10, 1, 30, 0}})

	result, ok = chrono.local_date_time_plus_duration(
		{{2026, .november, 1}, {10, 0, 0, 0}},
		{-90, 0},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Local_Date_Time{{2026, .november, 1}, {9, 58, 30, 0}})
}

@(test)
test_local_date_time_plus_duration_carries_into_the_date :: proc(t: ^testing.T) {
	// 23:00 plus 2 hours is 01:00 the next day.
	result, ok := chrono.local_date_time_plus_duration(
		{{2026, .november, 1}, {23, 0, 0, 0}},
		{7_200, 0},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Local_Date_Time{{2026, .november, 2}, {1, 0, 0, 0}})

	// 01:00 minus 2 hours is 23:00 the day before.
	result, ok = chrono.local_date_time_plus_duration(
		{{2026, .november, 1}, {1, 0, 0, 0}},
		{-7_200, 0},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Local_Date_Time{{2026, .october, 31}, {23, 0, 0, 0}})

	// Month end, year end and a leap day.
	result, ok = chrono.local_date_time_plus_duration(
		{{2026, .december, 31}, {23, 59, 59, 999_999_999}},
		{0, 1},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Local_Date_Time{{2027, .january, 1}, {}})

	result, ok = chrono.local_date_time_plus_duration(
		{{2024, .february, 28}, {12, 0, 0, 0}},
		{chrono.SECONDS_PER_DAY, 0},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Local_Date_Time{{2024, .february, 29}, {12, 0, 0, 0}})

	result, ok = chrono.local_date_time_plus_duration(
		{{2026, .february, 28}, {12, 0, 0, 0}},
		{chrono.SECONDS_PER_DAY, 0},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Local_Date_Time{{2026, .march, 1}, {12, 0, 0, 0}})

	// One nanosecond back from midnight is the last instant of the day before.
	result, ok = chrono.local_date_time_plus_duration({{2026, .january, 1}, {}}, {-1, 999_999_999})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		result,
		chrono.Local_Date_Time{{2025, .december, 31}, {23, 59, 59, 999_999_999}},
	)
}

@(test)
test_local_date_time_plus_duration_range_edges :: proc(t: ^testing.T) {
	result, ok := chrono.local_date_time_plus_duration(chrono.LOCAL_DATE_TIME_MAX, {0, 0})
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.LOCAL_DATE_TIME_MAX)

	_, ok = chrono.local_date_time_plus_duration(chrono.LOCAL_DATE_TIME_MAX, {0, 1})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_time_plus_duration(chrono.LOCAL_DATE_TIME_MIN, {-1, 999_999_999})
	testing.expect(t, !ok)

	// The widest legal jump from each end lands exactly on the other end.
	result, ok = chrono.local_date_time_plus_duration(
		chrono.LOCAL_DATE_TIME_MIN,
		{chrono.DURATION_SECONDS_MAX, 999_999_999},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.LOCAL_DATE_TIME_MAX)

	result, ok = chrono.local_date_time_plus_duration(
		chrono.LOCAL_DATE_TIME_MAX,
		{chrono.DURATION_SECONDS_MIN, 1},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.LOCAL_DATE_TIME_MIN)

	// One nanosecond later than the earliest start, the widest jump overshoots the end.
	one_nanosecond_after_min := chrono.Local_Date_Time{chrono.LOCAL_DATE_MIN, {0, 0, 0, 1}}
	_, ok = chrono.local_date_time_plus_duration(
		one_nanosecond_after_min,
		{chrono.DURATION_SECONDS_MAX, 999_999_999},
	)
	testing.expect(t, !ok)
}

@(test)
test_local_date_time_between :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.local_date_time_between(
			{{2026, .june, 15}, {10, 0, 0, 0}},
			{{2026, .june, 15}, {10, 0, 0, 0}},
		),
		chrono.Duration{0, 0},
	)
	testing.expect_value(
		t,
		chrono.local_date_time_between(
			{{2026, .june, 15}, {10, 0, 0, 0}},
			{{2026, .june, 15}, {11, 30, 0, 0}},
		),
		chrono.Duration{5_400, 0},
	)

	// The time of day can pull the total below the day count: 23:00 to 01:00 next day is 2 hours.
	testing.expect_value(
		t,
		chrono.local_date_time_between(
			{{2026, .june, 15}, {23, 0, 0, 0}},
			{{2026, .june, 16}, {1, 0, 0, 0}},
		),
		chrono.Duration{7_200, 0},
	)
	testing.expect_value(
		t,
		chrono.local_date_time_between(
			{{2026, .june, 16}, {1, 0, 0, 0}},
			{{2026, .june, 15}, {23, 0, 0, 0}},
		),
		chrono.Duration{-7_200, 0},
	)

	// Fractions: 10:00:00.9 to the next day 10:00:00.1 is 24 hours minus 0.8 seconds.
	testing.expect_value(
		t,
		chrono.local_date_time_between(
			{{2026, .june, 15}, {10, 0, 0, 900_000_000}},
			{{2026, .june, 16}, {10, 0, 0, 100_000_000}},
		),
		chrono.Duration{chrono.SECONDS_PER_DAY - 1, 200_000_000},
	)
}

// between then plus must land on the target, over a grid that includes both ends of the range.
@(test)
test_local_date_time_between_and_plus_duration_round_trip :: proc(t: ^testing.T) {
	values := [?]chrono.Local_Date_Time {
		chrono.LOCAL_DATE_TIME_MIN,
		{{-1, .december, 31}, {23, 59, 59, 999_999_999}},
		{{0, .february, 29}, {12, 0, 0, 0}},
		{{1969, .december, 31}, {23, 59, 59, 999_999_999}},
		{{1970, .january, 1}, {}},
		{{2024, .february, 29}, {6, 15, 30, 250_000_000}},
		{{2026, .november, 1}, {14, 30, 0, 0}},
		{{2026, .november, 1}, {14, 30, 0, 1}},
		{{2100, .march, 1}, {0, 0, 0, 0}},
		chrono.LOCAL_DATE_TIME_MAX,
	}
	for from in values {
		for to in values {
			duration := chrono.local_date_time_between(from, to)
			testing.expect(t, chrono.duration_is_valid(duration))
			landed, ok := chrono.local_date_time_plus_duration(from, duration)
			testing.expect(t, ok)
			testing.expect_value(t, landed, to)
		}
	}
}

@(test)
test_local_date_time_plus_duration_then_negation_returns_original :: proc(t: ^testing.T) {
	starts := [?]chrono.Local_Date_Time {
		{{2026, .november, 1}, {14, 30, 0, 123}},
		{{2024, .february, 29}, {}},
		{{0, .january, 1}, {23, 59, 59, 999_999_999}},
	}
	durations := [?]chrono.Duration {
		{0, 0},
		{0, 1},
		{1, 0},
		{86_399, 999_999_999},
		{86_400, 1},
		{4_000_000, 7},
		{-1, 999_999_999},
		{-86_401, 5},
	}
	for start in starts {
		for duration in durations {
			moved, moved_ok := chrono.local_date_time_plus_duration(start, duration)
			testing.expect(t, moved_ok)
			negated, negate_ok := chrono.duration_negate(duration)
			testing.expect(t, negate_ok)
			back, back_ok := chrono.local_date_time_plus_duration(moved, negated)
			testing.expect(t, back_ok)
			testing.expect_value(t, back, start)
		}
	}
}

@(test)
test_local_date_time_plus_period_keeps_the_time :: proc(t: ^testing.T) {
	result, ok := chrono.local_date_time_plus_period(
		{{2026, .november, 1}, {14, 30, 15, 500}},
		{0, 0, 1},
	)
	testing.expect(t, ok)
	testing.expect_value(
		t,
		result,
		chrono.Local_Date_Time{{2026, .november, 2}, {14, 30, 15, 500}},
	)

	result, ok = chrono.local_date_time_plus_period(
		{{2026, .november, 1}, {14, 30, 15, 500}},
		{1, 2, 3},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Local_Date_Time{{2028, .january, 4}, {14, 30, 15, 500}})

	result, ok = chrono.local_date_time_plus_period({{2026, .november, 1}, {14, 30, 15, 500}}, {})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		result,
		chrono.Local_Date_Time{{2026, .november, 1}, {14, 30, 15, 500}},
	)
}

@(test)
test_local_date_time_plus_period_clamps_the_day :: proc(t: ^testing.T) {
	result, ok := chrono.local_date_time_plus_period(
		{{2026, .january, 31}, {23, 59, 59, 999_999_999}},
		{0, 1, 0},
	)
	testing.expect(t, ok)
	testing.expect_value(
		t,
		result,
		chrono.Local_Date_Time{{2026, .february, 28}, {23, 59, 59, 999_999_999}},
	)

	result, ok = chrono.local_date_time_plus_period(
		{{2024, .february, 29}, {6, 0, 0, 0}},
		{1, 0, 0},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Local_Date_Time{{2025, .february, 28}, {6, 0, 0, 0}})

	// Months are applied before days, as in local_date_plus_period.
	result, ok = chrono.local_date_time_plus_period(
		{{2026, .january, 30}, {8, 0, 0, 0}},
		{0, 1, 2},
	)
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Local_Date_Time{{2026, .march, 2}, {8, 0, 0, 0}})
}

// With no zone involved, one day as a Period and 24 hours as a Duration land on the same value.
// They only differ once a zone with DST is applied, which is why both exist.
@(test)
test_local_date_time_one_day_period_equals_twenty_four_hours :: proc(t: ^testing.T) {
	starts := [?]chrono.Local_Date_Time {
		{{2026, .november, 1}, {14, 30, 0, 0}},
		{{2026, .december, 31}, {23, 59, 59, 999_999_999}},
		{{2024, .february, 28}, {}},
	}
	for start in starts {
		by_period, period_ok := chrono.local_date_time_plus_period(start, {0, 0, 1})
		by_duration, duration_ok := chrono.local_date_time_plus_duration(
			start,
			{chrono.SECONDS_PER_DAY, 0},
		)
		testing.expect(t, period_ok && duration_ok)
		testing.expect_value(t, by_period, by_duration)
	}
}

@(test)
test_local_date_time_plus_period_range_edges :: proc(t: ^testing.T) {
	_, ok := chrono.local_date_time_plus_period(chrono.LOCAL_DATE_TIME_MAX, {0, 0, 1})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_time_plus_period(chrono.LOCAL_DATE_TIME_MAX, {0, 1, 0})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_time_plus_period(chrono.LOCAL_DATE_TIME_MIN, {-1, 0, 0})
	testing.expect(t, !ok)

	// The widest legal period keeps the time of day while moving across the whole range.
	result, plus_ok := chrono.local_date_time_plus_period(
		chrono.LOCAL_DATE_TIME_MIN,
		{0, 0, chrono.PERIOD_DAYS_MAX},
	)
	testing.expect(t, plus_ok)
	testing.expect_value(
		t,
		result,
		chrono.Local_Date_Time{chrono.LOCAL_DATE_MAX, chrono.LOCAL_TIME_MIN},
	)
}
