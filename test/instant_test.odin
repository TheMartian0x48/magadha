package chrono_test

import "core:testing"

import chrono "../"

@(test)
test_instant_bounds_match_date_bounds :: proc(t: ^testing.T) {
	first, first_ok := chrono.local_date_from_epoch_day(
		chrono.Epoch_Day(chrono.INSTANT_SECONDS_MIN / chrono.SECONDS_PER_DAY),
	)
	testing.expect(t, first_ok)
	testing.expect_value(t, first, chrono.Local_Date{chrono.YEAR_MIN, .january, 1})
	testing.expect_value(t, chrono.INSTANT_SECONDS_MIN %% chrono.SECONDS_PER_DAY, 0)

	last, last_ok := chrono.local_date_from_epoch_day(
		chrono.Epoch_Day(chrono.INSTANT_SECONDS_MAX / chrono.SECONDS_PER_DAY),
	)
	testing.expect(t, last_ok)
	testing.expect_value(t, last, chrono.Local_Date{chrono.YEAR_MAX, .december, 31})
	testing.expect_value(
		t,
		chrono.INSTANT_SECONDS_MAX %% chrono.SECONDS_PER_DAY,
		chrono.SECONDS_PER_DAY - 1,
	)
}

@(test)
test_instant_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, chrono.instant_is_valid({0, 0}))
	testing.expect(t, chrono.instant_is_valid({-1, 999_999_999}))
	testing.expect(t, chrono.instant_is_valid({chrono.INSTANT_SECONDS_MIN, 0}))
	testing.expect(t, chrono.instant_is_valid({chrono.INSTANT_SECONDS_MAX, 999_999_999}))
	testing.expect(t, !chrono.instant_is_valid({chrono.INSTANT_SECONDS_MIN - 1, 0}))
	testing.expect(t, !chrono.instant_is_valid({chrono.INSTANT_SECONDS_MAX + 1, 0}))
	testing.expect(t, !chrono.instant_is_valid({0, chrono.NANOSECONDS_PER_SECOND}))
	testing.expect(t, !chrono.instant_is_valid({min(i64), 0}))
	testing.expect(t, !chrono.instant_is_valid({max(i64), 0}))
}

@(test)
test_instant_make :: proc(t: ^testing.T) {
	instant, ok := chrono.instant_make(1_793_474_051, 660_596_000)
	testing.expect(t, ok)
	testing.expect_value(t, instant, chrono.Instant{1_793_474_051, 660_596_000})

	_, ok = chrono.instant_make(0, chrono.NANOSECONDS_PER_SECOND)
	testing.expect(t, !ok)
	_, ok = chrono.instant_make(chrono.INSTANT_SECONDS_MAX + 1, 0)
	testing.expect(t, !ok)
}

@(test)
test_instant_compare :: proc(t: ^testing.T) {
	base := chrono.Instant{100, 500}
	testing.expect_value(t, chrono.instant_compare(base, base), chrono.Ordering.equal)
	testing.expect_value(t, chrono.instant_compare(base, {100, 501}), chrono.Ordering.less)
	testing.expect_value(t, chrono.instant_compare(base, {101, 0}), chrono.Ordering.less)
	testing.expect_value(t, chrono.instant_compare({101, 0}, base), chrono.Ordering.greater)
	testing.expect_value(t, chrono.instant_compare({100, 501}, base), chrono.Ordering.greater)
	// Seconds decide before nanoseconds: just before the epoch is earlier than the epoch.
	testing.expect_value(
		t,
		chrono.instant_compare({-1, 999_999_999}, {0, 0}),
		chrono.Ordering.less,
	)
}

@(test)
test_instant_plus :: proc(t: ^testing.T) {
	result, ok := chrono.instant_plus({100, 0}, {50, 0})
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Instant{150, 0})

	// Nanoseconds carry into seconds.
	result, ok = chrono.instant_plus({100, 600_000_000}, {0, 600_000_000})
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Instant{101, 200_000_000})

	result, ok = chrono.instant_plus({100, 999_999_999}, {0, 1})
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Instant{101, 0})

	// A negative Duration moves backwards: 100.25 minus 0.5 is 99.75.
	result, ok = chrono.instant_plus({100, 250_000_000}, {-1, 500_000_000})
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Instant{99, 750_000_000})

	// Crossing the epoch: 0.25 minus 0.5 is -1 + 0.75.
	result, ok = chrono.instant_plus({0, 250_000_000}, {-1, 500_000_000})
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Instant{-1, 750_000_000})
}

@(test)
test_instant_plus_range_edges :: proc(t: ^testing.T) {
	latest := chrono.Instant{chrono.INSTANT_SECONDS_MAX, 999_999_999}
	earliest := chrono.Instant{chrono.INSTANT_SECONDS_MIN, 0}

	result, ok := chrono.instant_plus(latest, {0, 0})
	testing.expect(t, ok)
	testing.expect_value(t, result, latest)

	// One nanosecond past the latest instant.
	_, ok = chrono.instant_plus(latest, {0, 1})
	testing.expect(t, !ok)

	// {-1, 999_999_999} is minus one nanosecond, because nanoseconds count forward.
	// From the earliest instant that is one nanosecond out of range.
	_, ok = chrono.instant_plus(earliest, {-1, 999_999_999})
	testing.expect(t, !ok)
	_, ok = chrono.instant_plus(earliest, {-1, 0})
	testing.expect(t, !ok)

	// Zero and one nanosecond forward are fine.
	result, ok = chrono.instant_plus(earliest, {0, 0})
	testing.expect(t, ok)
	testing.expect_value(t, result, earliest)
	result, ok = chrono.instant_plus(earliest, {0, 1})
	testing.expect(t, ok)
	testing.expect_value(t, result, chrono.Instant{chrono.INSTANT_SECONDS_MIN, 1})

	// One nanosecond back from the second earliest nanosecond lands exactly on the earliest.
	result, ok = chrono.instant_plus({chrono.INSTANT_SECONDS_MIN, 1}, {-1, 999_999_999})
	testing.expect(t, ok)
	testing.expect_value(t, result, earliest)

	// The widest legal jump from the earliest lands on the latest.
	result, ok = chrono.instant_plus(earliest, {chrono.DURATION_SECONDS_MAX, 999_999_999})
	testing.expect(t, ok)
	testing.expect_value(t, result, latest)

	// The widest legal jump backwards from the latest lands on the earliest.
	result, ok = chrono.instant_plus(latest, {chrono.DURATION_SECONDS_MIN, 1})
	testing.expect(t, ok)
	testing.expect_value(t, result, earliest)
}

@(test)
test_instant_between :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.instant_between({100, 0}, {100, 0}), chrono.Duration{0, 0})
	testing.expect_value(t, chrono.instant_between({100, 0}, {150, 0}), chrono.Duration{50, 0})
	testing.expect_value(
		t,
		chrono.instant_between({100, 900_000_000}, {101, 100_000_000}),
		chrono.Duration{0, 200_000_000},
	)
	// Earlier target: 100.25 back to 99.75 is -0.5, stored as {-1, 500_000_000}.
	testing.expect_value(
		t,
		chrono.instant_between({100, 250_000_000}, {99, 750_000_000}),
		chrono.Duration{-1, 500_000_000},
	)
}

@(test)
test_instant_between_widest_span :: proc(t: ^testing.T) {
	earliest := chrono.Instant{chrono.INSTANT_SECONDS_MIN, 0}
	latest := chrono.Instant{chrono.INSTANT_SECONDS_MAX, 999_999_999}

	forward := chrono.instant_between(earliest, latest)
	testing.expect_value(t, forward, chrono.Duration{chrono.DURATION_SECONDS_MAX, 999_999_999})
	testing.expect(t, chrono.duration_is_valid(forward))

	backward := chrono.instant_between(latest, earliest)
	testing.expect(t, chrono.duration_is_valid(backward))
}

// between then plus must land on the target, and plus then between must give back the duration.
@(test)
test_instant_between_and_plus_round_trip :: proc(t: ^testing.T) {
	instants := [?]chrono.Instant {
		{0, 0},
		{0, 1},
		{-1, 999_999_999},
		{1_793_474_051, 660_596_000},
		{-62_135_596_800, 0},
		{chrono.INSTANT_SECONDS_MIN, 0},
		{chrono.INSTANT_SECONDS_MAX, 999_999_999},
	}
	for from in instants {
		for to in instants {
			duration := chrono.instant_between(from, to)
			landed, ok := chrono.instant_plus(from, duration)
			testing.expect(t, ok)
			testing.expect_value(t, landed, to)
		}
	}
}

@(test)
test_instant_plus_then_negate_returns_original :: proc(t: ^testing.T) {
	start := chrono.Instant{1_793_474_051, 660_596_000}
	durations := [?]chrono.Duration{{0, 0}, {0, 1}, {1, 0}, {86_400, 999_999_999}, {-5, 3}}
	for duration in durations {
		forward, forward_ok := chrono.instant_plus(start, duration)
		testing.expect(t, forward_ok)
		negated, negate_ok := chrono.duration_negate(duration)
		testing.expect(t, negate_ok)
		back, back_ok := chrono.instant_plus(forward, negated)
		testing.expect(t, back_ok)
		testing.expect_value(t, back, start)
	}
}

// The wall clock must produce a valid instant in the present era.
@(test)
test_clock_wall_read_is_sane :: proc(t: ^testing.T) {
	instant := chrono.clock_wall_read()
	testing.expect(t, chrono.instant_is_valid(instant))
	// After 2020-01-01 and before 2100-01-01.
	testing.expect(t, instant.seconds > 1_577_836_800)
	testing.expect(t, instant.seconds < 4_102_444_800)
}
