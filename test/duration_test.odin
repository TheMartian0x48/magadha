package chrono_test

import "core:testing"

import chrono "../"

@(test)
test_duration_bounds_hold_every_instant_difference :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.DURATION_SECONDS_MAX,
		chrono.INSTANT_SECONDS_MAX - chrono.INSTANT_SECONDS_MIN,
	)
	testing.expect_value(t, chrono.DURATION_SECONDS_MIN, -chrono.DURATION_SECONDS_MAX - 1)
}

@(test)
test_duration_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, chrono.duration_is_valid({0, 0}))
	testing.expect(t, chrono.duration_is_valid({-1, 500_000_000}))
	testing.expect(t, chrono.duration_is_valid({chrono.DURATION_SECONDS_MAX, 999_999_999}))
	testing.expect(t, chrono.duration_is_valid({chrono.DURATION_SECONDS_MIN, 0}))
	testing.expect(t, !chrono.duration_is_valid({chrono.DURATION_SECONDS_MAX + 1, 0}))
	testing.expect(t, !chrono.duration_is_valid({chrono.DURATION_SECONDS_MIN - 1, 0}))
	testing.expect(t, !chrono.duration_is_valid({0, chrono.NANOSECONDS_PER_SECOND}))
	testing.expect(t, !chrono.duration_is_valid({0, max(u32)}))
}

@(test)
test_duration_make :: proc(t: ^testing.T) {
	duration, ok := chrono.duration_make(90, 5)
	testing.expect(t, ok)
	testing.expect_value(t, duration, chrono.Duration{90, 5})

	_, ok = chrono.duration_make(0, chrono.NANOSECONDS_PER_SECOND)
	testing.expect(t, !ok)
	_, ok = chrono.duration_make(chrono.DURATION_SECONDS_MAX + 1, 0)
	testing.expect(t, !ok)
}

@(test)
test_duration_negate :: proc(t: ^testing.T) {
	negated, ok := chrono.duration_negate({90, 0})
	testing.expect(t, ok)
	testing.expect_value(t, negated, chrono.Duration{-90, 0})

	negated, ok = chrono.duration_negate({0, 0})
	testing.expect(t, ok)
	testing.expect_value(t, negated, chrono.Duration{0, 0})

	// Half a second forward is {0, 500_000_000}; half a second back is {-1, 500_000_000}.
	negated, ok = chrono.duration_negate({0, 500_000_000})
	testing.expect(t, ok)
	testing.expect_value(t, negated, chrono.Duration{-1, 500_000_000})

	negated, ok = chrono.duration_negate({-1, 500_000_000})
	testing.expect(t, ok)
	testing.expect_value(t, negated, chrono.Duration{0, 500_000_000})

	// 1.25 seconds back is -2 + 0.75.
	negated, ok = chrono.duration_negate({1, 250_000_000})
	testing.expect(t, ok)
	testing.expect_value(t, negated, chrono.Duration{-2, 750_000_000})
}

@(test)
test_duration_negate_range_edges :: proc(t: ^testing.T) {
	// The most negative Duration has no positive counterpart.
	_, ok := chrono.duration_negate({chrono.DURATION_SECONDS_MIN, 0})
	testing.expect(t, !ok)

	// One nanosecond above it does.
	negated, negate_ok := chrono.duration_negate({chrono.DURATION_SECONDS_MIN, 1})
	testing.expect(t, negate_ok)
	testing.expect_value(
		t,
		negated,
		chrono.Duration{-chrono.DURATION_SECONDS_MIN - 1, 999_999_999},
	)

	negated, negate_ok = chrono.duration_negate({chrono.DURATION_SECONDS_MAX, 0})
	testing.expect(t, negate_ok)
	testing.expect_value(t, negated, chrono.Duration{-chrono.DURATION_SECONDS_MAX, 0})
}

@(test)
test_duration_negate_twice_returns_original :: proc(t: ^testing.T) {
	durations := [?]chrono.Duration {
		{0, 0},
		{0, 1},
		{1, 0},
		{-1, 999_999_999},
		{86_399, 123_456_789},
		{-86_400, 1},
		{chrono.DURATION_SECONDS_MAX, 999_999_999},
		{chrono.DURATION_SECONDS_MIN, 1},
	}
	for duration in durations {
		once, once_ok := chrono.duration_negate(duration)
		testing.expect(t, once_ok)
		twice, twice_ok := chrono.duration_negate(once)
		testing.expect(t, twice_ok)
		testing.expect_value(t, twice, duration)
	}
}

@(test)
test_duration_compare :: proc(t: ^testing.T) {
	base := chrono.Duration{10, 500}
	testing.expect_value(t, chrono.duration_compare(base, base), chrono.Ordering.equal)
	testing.expect_value(t, chrono.duration_compare(base, {10, 501}), chrono.Ordering.less)
	testing.expect_value(t, chrono.duration_compare(base, {11, 0}), chrono.Ordering.less)
	testing.expect_value(t, chrono.duration_compare({11, 0}, base), chrono.Ordering.greater)
	// Minus one nanosecond is {-1, 999_999_999}: earlier than zero.
	testing.expect_value(
		t,
		chrono.duration_compare({-1, 999_999_999}, {0, 0}),
		chrono.Ordering.less,
	)
}

@(test)
test_duration_plus :: proc(t: ^testing.T) {
	sum, ok := chrono.duration_plus({1, 0}, {2, 0})
	testing.expect(t, ok)
	testing.expect_value(t, sum, chrono.Duration{3, 0})

	sum, ok = chrono.duration_plus({1, 600_000_000}, {2, 600_000_000})
	testing.expect(t, ok)
	testing.expect_value(t, sum, chrono.Duration{4, 200_000_000})

	// 5.0 plus minus 0.5.
	sum, ok = chrono.duration_plus({5, 0}, {-1, 500_000_000})
	testing.expect(t, ok)
	testing.expect_value(t, sum, chrono.Duration{4, 500_000_000})
}

@(test)
test_duration_plus_range_edges :: proc(t: ^testing.T) {
	largest := chrono.Duration{chrono.DURATION_SECONDS_MAX, 999_999_999}
	smallest := chrono.Duration{chrono.DURATION_SECONDS_MIN, 0}

	sum, ok := chrono.duration_plus(largest, {0, 0})
	testing.expect(t, ok)
	testing.expect_value(t, sum, largest)

	_, ok = chrono.duration_plus(largest, {0, 1})
	testing.expect(t, !ok)
	_, ok = chrono.duration_plus(smallest, {-1, 999_999_999})
	testing.expect(t, !ok)
	_, ok = chrono.duration_plus(largest, largest)
	testing.expect(t, !ok)
	_, ok = chrono.duration_plus(smallest, smallest)
	testing.expect(t, !ok)

	// The extremes cancel to minus one nanosecond.
	sum, ok = chrono.duration_plus(largest, smallest)
	testing.expect(t, ok)
	testing.expect_value(t, sum, chrono.Duration{-1, 999_999_999})
}

@(test)
test_duration_plus_negated_is_zero :: proc(t: ^testing.T) {
	durations := [?]chrono.Duration {
		{0, 0},
		{0, 1},
		{1, 0},
		{-1, 999_999_999},
		{86_399, 123_456_789},
	}
	for duration in durations {
		negated, negate_ok := chrono.duration_negate(duration)
		testing.expect(t, negate_ok)
		sum, sum_ok := chrono.duration_plus(duration, negated)
		testing.expect(t, sum_ok)
		testing.expect_value(t, sum, chrono.Duration{0, 0})
	}
}

@(test)
test_duration_from_units :: proc(t: ^testing.T) {
	duration, ok := chrono.duration_from_hours(2)
	testing.expect(t, ok)
	testing.expect_value(t, duration, chrono.Duration{7_200, 0})

	duration, ok = chrono.duration_from_hours(-2)
	testing.expect(t, ok)
	testing.expect_value(t, duration, chrono.Duration{-7_200, 0})

	duration, ok = chrono.duration_from_minutes(90)
	testing.expect(t, ok)
	testing.expect_value(t, duration, chrono.Duration{5_400, 0})

	duration, ok = chrono.duration_from_seconds(-5)
	testing.expect(t, ok)
	testing.expect_value(t, duration, chrono.Duration{-5, 0})

	duration, ok = chrono.duration_from_milliseconds(1_500)
	testing.expect(t, ok)
	testing.expect_value(t, duration, chrono.Duration{1, 500_000_000})

	duration, ok = chrono.duration_from_milliseconds(0)
	testing.expect(t, ok)
	testing.expect_value(t, duration, chrono.Duration{0, 0})
}

@(test)
test_duration_from_milliseconds_negative_borrows_a_second :: proc(t: ^testing.T) {
	duration, ok := chrono.duration_from_milliseconds(-1)
	testing.expect(t, ok)
	testing.expect_value(t, duration, chrono.Duration{-1, 999_000_000})

	duration, ok = chrono.duration_from_milliseconds(-1_000)
	testing.expect(t, ok)
	testing.expect_value(t, duration, chrono.Duration{-1, 0})

	duration, ok = chrono.duration_from_milliseconds(-1_500)
	testing.expect(t, ok)
	testing.expect_value(t, duration, chrono.Duration{-2, 500_000_000})

	// A negative amount equals the negation of the same positive amount.
	for milliseconds in i64(1) ..= 3_000 {
		positive, positive_ok := chrono.duration_from_milliseconds(milliseconds)
		testing.expect(t, positive_ok)
		negative, negative_ok := chrono.duration_from_milliseconds(-milliseconds)
		testing.expect(t, negative_ok)
		negated, negate_ok := chrono.duration_negate(positive)
		testing.expect(t, negate_ok)
		testing.expect_value(t, negative, negated)
	}
}

@(test)
test_duration_from_units_range_edges :: proc(t: ^testing.T) {
	hours_max := chrono.DURATION_SECONDS_MAX / chrono.SECONDS_PER_HOUR
	_, ok := chrono.duration_from_hours(hours_max)
	testing.expect(t, ok)
	_, ok = chrono.duration_from_hours(hours_max + 1)
	testing.expect(t, !ok)
	_, ok = chrono.duration_from_hours(max(i64))
	testing.expect(t, !ok)
	_, ok = chrono.duration_from_hours(min(i64))
	testing.expect(t, !ok)

	minutes_max := chrono.DURATION_SECONDS_MAX / chrono.SECONDS_PER_MINUTE
	_, ok = chrono.duration_from_minutes(minutes_max)
	testing.expect(t, ok)
	_, ok = chrono.duration_from_minutes(minutes_max + 1)
	testing.expect(t, !ok)
	_, ok = chrono.duration_from_minutes(max(i64))
	testing.expect(t, !ok)
	_, ok = chrono.duration_from_minutes(min(i64))
	testing.expect(t, !ok)

	_, ok = chrono.duration_from_seconds(chrono.DURATION_SECONDS_MAX)
	testing.expect(t, ok)
	_, ok = chrono.duration_from_seconds(chrono.DURATION_SECONDS_MAX + 1)
	testing.expect(t, !ok)
	_, ok = chrono.duration_from_seconds(chrono.DURATION_SECONDS_MIN)
	testing.expect(t, ok)
	_, ok = chrono.duration_from_seconds(chrono.DURATION_SECONDS_MIN - 1)
	testing.expect(t, !ok)

	_, ok = chrono.duration_from_milliseconds(max(i64))
	testing.expect(t, !ok)
	_, ok = chrono.duration_from_milliseconds(min(i64))
	testing.expect(t, !ok)
}
