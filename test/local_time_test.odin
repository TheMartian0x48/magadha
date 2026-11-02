package chrono_test

import "core:testing"

import chrono "../"

@(test)
test_local_time_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, chrono.local_time_is_valid({}))
	testing.expect(t, chrono.local_time_is_valid({23, 59, 59, 999_999_999}))
	testing.expect(t, chrono.local_time_is_valid(chrono.LOCAL_TIME_MIDNIGHT))
	testing.expect(t, chrono.local_time_is_valid(chrono.LOCAL_TIME_NOON))
	testing.expect(t, !chrono.local_time_is_valid({24, 0, 0, 0}))
	testing.expect(t, !chrono.local_time_is_valid({0, 60, 0, 0}))
	testing.expect(t, !chrono.local_time_is_valid({0, 0, 60, 0}))
	testing.expect(t, !chrono.local_time_is_valid({0, 0, 0, chrono.NANOSECONDS_PER_SECOND}))
	testing.expect(t, !chrono.local_time_is_valid({max(u8), 0, 0, 0}))
	testing.expect(t, !chrono.local_time_is_valid({0, max(u8), 0, 0}))
	testing.expect(t, !chrono.local_time_is_valid({0, 0, max(u8), 0}))
	testing.expect(t, !chrono.local_time_is_valid({0, 0, 0, max(u32)}))
}

@(test)
test_local_time_constants :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.LOCAL_TIME_MIDNIGHT, chrono.Local_Time{0, 0, 0, 0})
	testing.expect_value(t, chrono.LOCAL_TIME_NOON, chrono.Local_Time{12, 0, 0, 0})
	testing.expect_value(t, chrono.SECOND_OF_DAY_MAX, chrono.Second_Of_Day(86_399))
}

@(test)
test_local_time_make :: proc(t: ^testing.T) {
	time, ok := chrono.local_time_make(13, 45, 30, 123_456_789)
	testing.expect(t, ok)
	testing.expect_value(t, time, chrono.Local_Time{13, 45, 30, 123_456_789})

	_, ok = chrono.local_time_make(24, 0, 0, 0)
	testing.expect(t, !ok)
	_, ok = chrono.local_time_make(0, 0, 60, 0)
	testing.expect(t, !ok)
	_, ok = chrono.local_time_make(0, 0, 0, chrono.NANOSECONDS_PER_SECOND)
	testing.expect(t, !ok)
}

@(test)
test_local_time_compare :: proc(t: ^testing.T) {
	base := chrono.Local_Time{10, 30, 15, 500}
	testing.expect_value(t, chrono.local_time_compare(base, base), chrono.Ordering.equal)
	testing.expect_value(
		t,
		chrono.local_time_compare(base, {10, 30, 15, 501}),
		chrono.Ordering.less,
	)
	testing.expect_value(t, chrono.local_time_compare(base, {10, 30, 16, 0}), chrono.Ordering.less)
	testing.expect_value(t, chrono.local_time_compare(base, {10, 31, 0, 0}), chrono.Ordering.less)
	testing.expect_value(t, chrono.local_time_compare(base, {11, 0, 0, 0}), chrono.Ordering.less)
	testing.expect_value(
		t,
		chrono.local_time_compare({11, 0, 0, 0}, base),
		chrono.Ordering.greater,
	)
	testing.expect_value(
		t,
		chrono.local_time_compare({10, 30, 15, 501}, base),
		chrono.Ordering.greater,
	)
	// Higher fields decide before lower ones, whatever the lower ones hold.
	testing.expect_value(
		t,
		chrono.local_time_compare({9, 59, 59, 999_999_999}, {10, 0, 0, 0}),
		chrono.Ordering.less,
	)
}

@(test)
test_local_time_is_before_and_is_after :: proc(t: ^testing.T) {
	morning := chrono.Local_Time{9, 0, 0, 0}
	evening := chrono.Local_Time{18, 0, 0, 0}
	testing.expect(t, chrono.local_time_is_before(morning, evening))
	testing.expect(t, !chrono.local_time_is_before(evening, morning))
	testing.expect(t, !chrono.local_time_is_before(morning, morning))
	testing.expect(t, chrono.local_time_is_after(evening, morning))
	testing.expect(t, !chrono.local_time_is_after(morning, evening))
	testing.expect(t, !chrono.local_time_is_after(morning, morning))
}

@(test)
test_local_time_to_second_of_day :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.local_time_to_second_of_day({0, 0, 0, 0}),
		chrono.Second_Of_Day(0),
	)
	testing.expect_value(
		t,
		chrono.local_time_to_second_of_day({0, 0, 1, 0}),
		chrono.Second_Of_Day(1),
	)
	testing.expect_value(
		t,
		chrono.local_time_to_second_of_day({0, 1, 0, 0}),
		chrono.Second_Of_Day(60),
	)
	testing.expect_value(
		t,
		chrono.local_time_to_second_of_day({1, 0, 0, 0}),
		chrono.Second_Of_Day(3_600),
	)
	testing.expect_value(
		t,
		chrono.local_time_to_second_of_day({12, 0, 0, 0}),
		chrono.Second_Of_Day(43_200),
	)
	testing.expect_value(
		t,
		chrono.local_time_to_second_of_day({23, 59, 59, 0}),
		chrono.SECOND_OF_DAY_MAX,
	)
	// Nanoseconds are dropped, not rounded.
	testing.expect_value(
		t,
		chrono.local_time_to_second_of_day({23, 59, 59, 999_999_999}),
		chrono.SECOND_OF_DAY_MAX,
	)
}

@(test)
test_local_time_from_second_of_day_rejects_invalid :: proc(t: ^testing.T) {
	_, ok := chrono.local_time_from_second_of_day(chrono.SECOND_OF_DAY_MAX + 1, 0)
	testing.expect(t, !ok)
	_, ok = chrono.local_time_from_second_of_day(max(chrono.Second_Of_Day), 0)
	testing.expect(t, !ok)
	_, ok = chrono.local_time_from_second_of_day(0, chrono.NANOSECONDS_PER_SECOND)
	testing.expect(t, !ok)
	_, ok = chrono.local_time_from_second_of_day(0, max(u32))
	testing.expect(t, !ok)
}

// Every one of the 86,400 seconds of a day must round trip, with and without nanoseconds.
@(test)
test_local_time_second_of_day_round_trip :: proc(t: ^testing.T) {
	for second_of_day in chrono.Second_Of_Day(0) ..= chrono.SECOND_OF_DAY_MAX {
		for nanoseconds in ([?]u32{0, 1, 999_999_999}) {
			time, ok := chrono.local_time_from_second_of_day(second_of_day, nanoseconds)
			testing.expect(t, ok)
			testing.expect(t, chrono.local_time_is_valid(time))
			testing.expect_value(t, time.nanoseconds, nanoseconds)
			testing.expect_value(t, chrono.local_time_to_second_of_day(time), second_of_day)
		}
	}
}

@(test)
test_local_time_plus_duration_within_a_day :: proc(t: ^testing.T) {
	time, carry := chrono.local_time_plus_duration({10, 0, 0, 0}, {90, 0})
	testing.expect_value(t, time, chrono.Local_Time{10, 1, 30, 0})
	testing.expect_value(t, carry, 0)

	time, carry = chrono.local_time_plus_duration({10, 0, 0, 0}, {-90, 0})
	testing.expect_value(t, time, chrono.Local_Time{9, 58, 30, 0})
	testing.expect_value(t, carry, 0)

	time, carry = chrono.local_time_plus_duration({10, 0, 0, 900_000_000}, {0, 200_000_000})
	testing.expect_value(t, time, chrono.Local_Time{10, 0, 1, 100_000_000})
	testing.expect_value(t, carry, 0)
}

@(test)
test_local_time_plus_duration_carries_across_midnight :: proc(t: ^testing.T) {
	time, carry := chrono.local_time_plus_duration({23, 0, 0, 0}, {2 * 3_600, 0})
	testing.expect_value(t, time, chrono.Local_Time{1, 0, 0, 0})
	testing.expect_value(t, carry, 1)

	time, carry = chrono.local_time_plus_duration({1, 0, 0, 0}, {-2 * 3_600, 0})
	testing.expect_value(t, time, chrono.Local_Time{23, 0, 0, 0})
	testing.expect_value(t, carry, -1)

	// One nanosecond past the last instant of the day is midnight of the next.
	time, carry = chrono.local_time_plus_duration({23, 59, 59, 999_999_999}, {0, 1})
	testing.expect_value(t, time, chrono.LOCAL_TIME_MIDNIGHT)
	testing.expect_value(t, carry, 1)

	// One nanosecond back from midnight is the last instant of the previous day.
	time, carry = chrono.local_time_plus_duration(chrono.LOCAL_TIME_MIDNIGHT, {-1, 999_999_999})
	testing.expect_value(t, time, chrono.Local_Time{23, 59, 59, 999_999_999})
	testing.expect_value(t, carry, -1)
}

@(test)
test_local_time_plus_duration_whole_days :: proc(t: ^testing.T) {
	time, carry := chrono.local_time_plus_duration({12, 0, 0, 0}, {chrono.SECONDS_PER_DAY, 0})
	testing.expect_value(t, time, chrono.LOCAL_TIME_NOON)
	testing.expect_value(t, carry, 1)

	time, carry = chrono.local_time_plus_duration({12, 0, 0, 0}, {-chrono.SECONDS_PER_DAY, 0})
	testing.expect_value(t, time, chrono.LOCAL_TIME_NOON)
	testing.expect_value(t, carry, -1)

	time, carry = chrono.local_time_plus_duration(
		{12, 0, 0, 0},
		{3 * chrono.SECONDS_PER_DAY + 60, 0},
	)
	testing.expect_value(t, time, chrono.Local_Time{12, 1, 0, 0})
	testing.expect_value(t, carry, 3)
}

@(test)
test_local_time_plus_duration_extreme_durations :: proc(t: ^testing.T) {
	largest := chrono.Duration{chrono.DURATION_SECONDS_MAX, 999_999_999}
	smallest := chrono.Duration{chrono.DURATION_SECONDS_MIN, 0}

	time, carry := chrono.local_time_plus_duration(chrono.LOCAL_TIME_NOON, largest)
	testing.expect(t, chrono.local_time_is_valid(time))
	testing.expect(t, carry > 0)

	time, carry = chrono.local_time_plus_duration(chrono.LOCAL_TIME_NOON, smallest)
	testing.expect(t, chrono.local_time_is_valid(time))
	testing.expect(t, carry < 0)

	// The carry plus the remaining seconds rebuilds the total.
	time, carry = chrono.local_time_plus_duration({0, 0, 0, 0}, largest)
	rebuilt := carry * chrono.SECONDS_PER_DAY + i64(chrono.local_time_to_second_of_day(time))
	testing.expect_value(t, rebuilt, chrono.DURATION_SECONDS_MAX)
	testing.expect_value(t, time.nanoseconds, u32(999_999_999))
}

@(test)
test_local_time_plus_duration_then_negation_returns_original :: proc(t: ^testing.T) {
	times := [?]chrono.Local_Time {
		{0, 0, 0, 0},
		{0, 0, 0, 1},
		{12, 30, 15, 500_000_000},
		{23, 59, 59, 999_999_999},
	}
	durations := [?]chrono.Duration {
		{0, 0},
		{0, 1},
		{59, 999_999_999},
		{86_399, 0},
		{86_400, 1},
		{200_000, 123_456_789},
		{-1, 999_999_999},
		{-86_401, 5},
	}
	for time in times {
		for duration in durations {
			moved, carry := chrono.local_time_plus_duration(time, duration)
			negated, negate_ok := chrono.duration_negate(duration)
			testing.expect(t, negate_ok)
			back, back_carry := chrono.local_time_plus_duration(moved, negated)
			testing.expect_value(t, back, time)
			testing.expect_value(t, carry + back_carry, 0)
		}
	}
}

@(test)
test_local_time_between :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.local_time_between({10, 0, 0, 0}, {10, 0, 0, 0}),
		chrono.Duration{0, 0},
	)
	testing.expect_value(
		t,
		chrono.local_time_between({10, 0, 0, 0}, {11, 30, 0, 0}),
		chrono.Duration{5_400, 0},
	)
	testing.expect_value(
		t,
		chrono.local_time_between({11, 30, 0, 0}, {10, 0, 0, 0}),
		chrono.Duration{-5_400, 0},
	)
	testing.expect_value(
		t,
		chrono.local_time_between({10, 0, 0, 900_000_000}, {10, 0, 1, 100_000_000}),
		chrono.Duration{0, 200_000_000},
	)
	// 10:00:00.25 back to 10:00:00.00 is -0.25, stored as {-1, 750_000_000}.
	testing.expect_value(
		t,
		chrono.local_time_between({10, 0, 0, 250_000_000}, {10, 0, 0, 0}),
		chrono.Duration{-1, 750_000_000},
	)
	// The widest span in one day.
	testing.expect_value(
		t,
		chrono.local_time_between(chrono.LOCAL_TIME_MIDNIGHT, {23, 59, 59, 999_999_999}),
		chrono.Duration{86_399, 999_999_999},
	)
}

@(test)
test_local_time_between_and_plus_duration_round_trip :: proc(t: ^testing.T) {
	times := [?]chrono.Local_Time {
		{0, 0, 0, 0},
		{0, 0, 0, 1},
		{6, 15, 30, 250_000_000},
		{12, 0, 0, 0},
		{12, 0, 0, 999_999_999},
		{23, 59, 59, 0},
		{23, 59, 59, 999_999_999},
	}
	for from in times {
		for to in times {
			duration := chrono.local_time_between(from, to)
			landed, carry := chrono.local_time_plus_duration(from, duration)
			testing.expect_value(t, landed, to)
			testing.expect_value(t, carry, 0)
		}
	}
}

@(test)
test_local_time_min_and_max :: proc(t: ^testing.T) {
	testing.expect(t, chrono.local_time_is_valid(chrono.LOCAL_TIME_MIN))
	testing.expect(t, chrono.local_time_is_valid(chrono.LOCAL_TIME_MAX))
	testing.expect_value(t, chrono.LOCAL_TIME_MIN, chrono.LOCAL_TIME_MIDNIGHT)
	testing.expect_value(t, chrono.LOCAL_TIME_MAX, chrono.Local_Time{23, 59, 59, 999_999_999})
	testing.expect_value(
		t,
		chrono.local_time_compare(chrono.LOCAL_TIME_MIN, chrono.LOCAL_TIME_MAX),
		chrono.Ordering.less,
	)
	testing.expect_value(
		t,
		chrono.local_time_to_second_of_day(chrono.LOCAL_TIME_MIN),
		chrono.Second_Of_Day(0),
	)
	testing.expect_value(
		t,
		chrono.local_time_to_second_of_day(chrono.LOCAL_TIME_MAX),
		chrono.SECOND_OF_DAY_MAX,
	)

	// Nothing valid lies outside them: one nanosecond past the max is the next day's min.
	time, carry := chrono.local_time_plus_duration(chrono.LOCAL_TIME_MAX, {0, 1})
	testing.expect_value(t, time, chrono.LOCAL_TIME_MIN)
	testing.expect_value(t, carry, 1)
	time, carry = chrono.local_time_plus_duration(chrono.LOCAL_TIME_MIN, {-1, 999_999_999})
	testing.expect_value(t, time, chrono.LOCAL_TIME_MAX)
	testing.expect_value(t, carry, -1)
}

@(test)
test_local_time_earlier_and_later :: proc(t: ^testing.T) {
	morning := chrono.Local_Time{9, 0, 0, 0}
	evening := chrono.Local_Time{18, 30, 0, 0}

	testing.expect_value(t, chrono.local_time_earlier(morning, evening), morning)
	testing.expect_value(t, chrono.local_time_earlier(evening, morning), morning)
	testing.expect_value(t, chrono.local_time_later(morning, evening), evening)
	testing.expect_value(t, chrono.local_time_later(evening, morning), evening)

	testing.expect_value(t, chrono.local_time_earlier(morning, morning), morning)
	testing.expect_value(t, chrono.local_time_later(morning, morning), morning)

	// Lower fields decide only when the higher ones tie.
	testing.expect_value(
		t,
		chrono.local_time_earlier({9, 0, 0, 1}, {9, 0, 0, 0}),
		chrono.Local_Time{9, 0, 0, 0},
	)
	testing.expect_value(
		t,
		chrono.local_time_later({9, 59, 59, 999_999_999}, {10, 0, 0, 0}),
		chrono.Local_Time{10, 0, 0, 0},
	)

	// The ends of the day clamp any time.
	testing.expect_value(t, chrono.local_time_later(chrono.LOCAL_TIME_MIN, morning), morning)
	testing.expect_value(t, chrono.local_time_earlier(chrono.LOCAL_TIME_MAX, morning), morning)
	testing.expect_value(
		t,
		chrono.local_time_earlier(chrono.LOCAL_TIME_MIN, morning),
		chrono.LOCAL_TIME_MIN,
	)
	testing.expect_value(
		t,
		chrono.local_time_later(chrono.LOCAL_TIME_MAX, morning),
		chrono.LOCAL_TIME_MAX,
	)
}

// Clamping to the day with earlier and later must keep every time of a sample unchanged.
@(test)
test_local_time_earlier_and_later_clamp_every_second :: proc(t: ^testing.T) {
	for second_of_day in chrono.Second_Of_Day(0) ..= chrono.SECOND_OF_DAY_MAX {
		time, ok := chrono.local_time_from_second_of_day(second_of_day, 123)
		testing.expect(t, ok)
		clamped := chrono.local_time_earlier(
			chrono.local_time_later(time, chrono.LOCAL_TIME_MIN),
			chrono.LOCAL_TIME_MAX,
		)
		testing.expect_value(t, clamped, time)
	}
}
