package chrono_test

import "core:slice"
import "core:testing"

import chrono "../"

// One moment, 2026-06-15 12:00:00 UTC, written at three offsets.
MOMENT_AT_PLUS_ONE :: chrono.Offset_Date_Time{{{2026, .june, 15}, {13, 0, 0, 0}}, {3_600}}
MOMENT_AT_UTC :: chrono.Offset_Date_Time{{{2026, .june, 15}, {12, 0, 0, 0}}, {0}}
MOMENT_AT_MINUS_FIVE :: chrono.Offset_Date_Time{{{2026, .june, 15}, {7, 0, 0, 0}}, {-18_000}}

@(test)
test_offset_date_time_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, chrono.offset_date_time_is_valid(MOMENT_AT_UTC))
	testing.expect(t, chrono.offset_date_time_is_valid(MOMENT_AT_PLUS_ONE))
	testing.expect(t, chrono.offset_date_time_is_valid(MOMENT_AT_MINUS_FIVE))

	// A zeroed value is invalid, because a zeroed date is: month 0 does not exist.
	testing.expect(t, !chrono.offset_date_time_is_valid({}))

	// Each part invalid in turn.
	testing.expect(t, !chrono.offset_date_time_is_valid({{{2026, .february, 29}, {}}, {}}))
	testing.expect(t, !chrono.offset_date_time_is_valid({{{2026, .june, 15}, {24, 0, 0, 0}}, {}}))
	testing.expect(t, !chrono.offset_date_time_is_valid({{{2026, .june, 15}, {}}, {64_801}}))
	testing.expect(t, !chrono.offset_date_time_is_valid({{{2026, .june, 15}, {}}, {min(i32)}}))
}

// The first date time reads as a moment inside the range only at an offset at or west of UTC.
@(test)
test_offset_date_time_is_valid_checks_the_instant_range :: proc(t: ^testing.T) {
	testing.expect(t, chrono.offset_date_time_is_valid({chrono.LOCAL_DATE_TIME_MIN, {0}}))
	testing.expect(t, chrono.offset_date_time_is_valid({chrono.LOCAL_DATE_TIME_MIN, {-3_600}}))
	testing.expect(t, !chrono.offset_date_time_is_valid({chrono.LOCAL_DATE_TIME_MIN, {3_600}}))
	testing.expect(
		t,
		!chrono.offset_date_time_is_valid({chrono.LOCAL_DATE_TIME_MIN, chrono.ZONE_OFFSET_MAX}),
	)

	testing.expect(t, chrono.offset_date_time_is_valid({chrono.LOCAL_DATE_TIME_MAX, {0}}))
	testing.expect(t, chrono.offset_date_time_is_valid({chrono.LOCAL_DATE_TIME_MAX, {3_600}}))
	testing.expect(t, !chrono.offset_date_time_is_valid({chrono.LOCAL_DATE_TIME_MAX, {-3_600}}))
	testing.expect(
		t,
		!chrono.offset_date_time_is_valid({chrono.LOCAL_DATE_TIME_MAX, chrono.ZONE_OFFSET_MIN}),
	)
}

@(test)
test_offset_date_time_make :: proc(t: ^testing.T) {
	value, ok := chrono.offset_date_time_make({{2026, .june, 15}, {12, 0, 0, 0}}, {0})
	testing.expect(t, ok)
	testing.expect_value(t, value, MOMENT_AT_UTC)

	_, ok = chrono.offset_date_time_make({{2026, .february, 29}, {}}, {0})
	testing.expect(t, !ok)
	_, ok = chrono.offset_date_time_make({{2026, .june, 15}, {}}, {64_801})
	testing.expect(t, !ok)
	_, ok = chrono.offset_date_time_make(chrono.LOCAL_DATE_TIME_MIN, {3_600})
	testing.expect(t, !ok)
}

@(test)
test_offset_date_time_the_same_moment_has_many_readings :: proc(t: ^testing.T) {
	expected := chrono.Instant{1_781_524_800, 0}
	testing.expect_value(t, chrono.offset_date_time_to_instant(MOMENT_AT_PLUS_ONE), expected)
	testing.expect_value(t, chrono.offset_date_time_to_instant(MOMENT_AT_UTC), expected)
	testing.expect_value(t, chrono.offset_date_time_to_instant(MOMENT_AT_MINUS_FIVE), expected)

	// compare says they are the same moment; == says the fields differ.
	testing.expect_value(
		t,
		chrono.offset_date_time_compare(MOMENT_AT_PLUS_ONE, MOMENT_AT_UTC),
		chrono.Ordering.equal,
	)
	testing.expect_value(
		t,
		chrono.offset_date_time_compare(MOMENT_AT_UTC, MOMENT_AT_MINUS_FIVE),
		chrono.Ordering.equal,
	)
	testing.expect(t, MOMENT_AT_PLUS_ONE != MOMENT_AT_UTC)
	testing.expect(t, MOMENT_AT_UTC != MOMENT_AT_MINUS_FIVE)
}

@(test)
test_offset_date_time_from_instant_known_values :: proc(t: ^testing.T) {
	instant := chrono.Instant{1_793_474_051, 660_596_000}

	value, ok := chrono.offset_date_time_from_instant(instant, {0})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		value,
		chrono.Offset_Date_Time{{{2026, .october, 31}, {19, 14, 11, 660_596_000}}, {0}},
	)

	// +05:30 is already the next day.
	value, ok = chrono.offset_date_time_from_instant(instant, {19_800})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		value,
		chrono.Offset_Date_Time{{{2026, .november, 1}, {0, 44, 11, 660_596_000}}, {19_800}},
	)

	value, ok = chrono.offset_date_time_from_instant(instant, {-28_800})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		value,
		chrono.Offset_Date_Time{{{2026, .october, 31}, {11, 14, 11, 660_596_000}}, {-28_800}},
	)
}

@(test)
test_offset_date_time_from_instant_range_edges :: proc(t: ^testing.T) {
	earliest := chrono.Instant{chrono.INSTANT_SECONDS_MIN, 0}
	latest := chrono.Instant{chrono.INSTANT_SECONDS_MAX, 999_999_999}

	_, ok := chrono.offset_date_time_from_instant(earliest, chrono.ZONE_OFFSET_MIN)
	testing.expect(t, !ok)
	_, ok = chrono.offset_date_time_from_instant(latest, chrono.ZONE_OFFSET_MAX)
	testing.expect(t, !ok)

	value, ok2 := chrono.offset_date_time_from_instant(earliest, {0})
	testing.expect(t, ok2)
	testing.expect_value(t, value.date_time, chrono.LOCAL_DATE_TIME_MIN)
	value, ok2 = chrono.offset_date_time_from_instant(latest, {0})
	testing.expect(t, ok2)
	testing.expect_value(t, value.date_time, chrono.LOCAL_DATE_TIME_MAX)
}

// Every instant that converts must convert back, for the same grid the plain conversions use.
@(test)
test_offset_date_time_round_trip :: proc(t: ^testing.T) {
	instants := [?]chrono.Instant {
		{chrono.INSTANT_SECONDS_MIN, 0},
		{chrono.INSTANT_SECONDS_MIN + 64_800, 1},
		{-62_135_596_800, 0},
		{-86_401, 999_999_999},
		{-1, 999_999_999},
		{0, 0},
		{0, 1},
		{86_399, 0},
		{1_793_474_051, 660_596_000},
		{253_402_300_799, 999_999_999},
		{chrono.INSTANT_SECONDS_MAX - 64_800, 0},
		{chrono.INSTANT_SECONDS_MAX, 999_999_999},
	}
	offsets := [?]chrono.Zone_Offset {
		chrono.ZONE_OFFSET_MIN,
		{-43_200},
		{-28_800},
		{-1},
		chrono.ZONE_OFFSET_UTC,
		{1},
		{19_800},
		{20_700},
		{50_400},
		chrono.ZONE_OFFSET_MAX,
	}
	converted := 0
	for instant in instants {
		for offset in offsets {
			value, ok := chrono.offset_date_time_from_instant(instant, offset)
			if !ok {
				continue
			}
			converted += 1
			testing.expect(t, chrono.offset_date_time_is_valid(value))
			testing.expect_value(t, value.offset, offset)
			testing.expect_value(t, chrono.offset_date_time_to_instant(value), instant)
		}
	}
	// The same 9 pairs are skipped as in the plain conversion test.
	testing.expect_value(t, converted, len(instants) * len(offsets) - 9)
}

@(test)
test_offset_date_time_with_offset :: proc(t: ^testing.T) {
	india, ok := chrono.offset_date_time_with_offset(MOMENT_AT_UTC, {19_800})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		india,
		chrono.Offset_Date_Time{{{2026, .june, 15}, {17, 30, 0, 0}}, {19_800}},
	)

	back, back_ok := chrono.offset_date_time_with_offset(india, {0})
	testing.expect(t, back_ok)
	testing.expect_value(t, back, MOMENT_AT_UTC)

	// The three readings of one moment convert into each other.
	converted, converted_ok := chrono.offset_date_time_with_offset(MOMENT_AT_MINUS_FIVE, {3_600})
	testing.expect(t, converted_ok)
	testing.expect_value(t, converted, MOMENT_AT_PLUS_ONE)

	// Same offset: unchanged.
	same, same_ok := chrono.offset_date_time_with_offset(MOMENT_AT_UTC, {0})
	testing.expect(t, same_ok)
	testing.expect_value(t, same, MOMENT_AT_UTC)
}

@(test)
test_offset_date_time_with_offset_changes_the_date :: proc(t: ^testing.T) {
	// 00:44:11 on Nov 1 at +05:30 is 19:14:11 on Oct 31 at UTC.
	east := chrono.Offset_Date_Time{{{2026, .november, 1}, {0, 44, 11, 0}}, {19_800}}
	utc, ok := chrono.offset_date_time_with_offset(east, {0})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		utc,
		chrono.Offset_Date_Time{{{2026, .october, 31}, {19, 14, 11, 0}}, {0}},
	)

	west, west_ok := chrono.offset_date_time_with_offset(east, {-28_800})
	testing.expect(t, west_ok)
	testing.expect_value(
		t,
		west,
		chrono.Offset_Date_Time{{{2026, .october, 31}, {11, 14, 11, 0}}, {-28_800}},
	)
}

@(test)
test_offset_date_time_with_offset_fails_at_the_edge :: proc(t: ^testing.T) {
	// The first date time at UTC would read before YEAR_MIN at -18:00.
	first := chrono.Offset_Date_Time{chrono.LOCAL_DATE_TIME_MIN, {0}}
	_, ok := chrono.offset_date_time_with_offset(first, chrono.ZONE_OFFSET_MIN)
	testing.expect(t, !ok)
	// Any offset west of UTC reads as the day before YEAR_MIN, even by one second.
	_, ok = chrono.offset_date_time_with_offset(first, {-1})
	testing.expect(t, !ok)
	_, ok = chrono.offset_date_time_with_offset(first, {-3_600})
	testing.expect(t, !ok)
	// UTC itself and every offset east of it are fine.
	_, ok = chrono.offset_date_time_with_offset(first, {0})
	testing.expect(t, ok)
	_, ok = chrono.offset_date_time_with_offset(first, {1})
	testing.expect(t, ok)
	_, ok = chrono.offset_date_time_with_offset(first, chrono.ZONE_OFFSET_MAX)
	testing.expect(t, ok)

	last := chrono.Offset_Date_Time{chrono.LOCAL_DATE_TIME_MAX, {0}}
	_, ok = chrono.offset_date_time_with_offset(last, chrono.ZONE_OFFSET_MAX)
	testing.expect(t, !ok)
	_, ok = chrono.offset_date_time_with_offset(last, chrono.ZONE_OFFSET_MIN)
	testing.expect(t, ok)
}

@(test)
test_offset_date_time_compare_orders_by_moment :: proc(t: ^testing.T) {
	// Equal clock readings: the one further east is the earlier moment.
	noon_east := chrono.Offset_Date_Time{{{2026, .june, 15}, {12, 0, 0, 0}}, {3_600}}
	noon_utc := chrono.Offset_Date_Time{{{2026, .june, 15}, {12, 0, 0, 0}}, {0}}
	noon_west := chrono.Offset_Date_Time{{{2026, .june, 15}, {12, 0, 0, 0}}, {-3_600}}

	testing.expect_value(
		t,
		chrono.offset_date_time_compare(noon_east, noon_utc),
		chrono.Ordering.less,
	)
	testing.expect_value(
		t,
		chrono.offset_date_time_compare(noon_utc, noon_west),
		chrono.Ordering.less,
	)
	testing.expect_value(
		t,
		chrono.offset_date_time_compare(noon_west, noon_east),
		chrono.Ordering.greater,
	)
	testing.expect(t, chrono.offset_date_time_is_before(noon_east, noon_west))
	testing.expect(t, chrono.offset_date_time_is_after(noon_west, noon_east))
	testing.expect(t, !chrono.offset_date_time_is_before(MOMENT_AT_UTC, MOMENT_AT_PLUS_ONE))
	testing.expect(t, !chrono.offset_date_time_is_after(MOMENT_AT_UTC, MOMENT_AT_PLUS_ONE))

	// A later date can still be an earlier moment: 00:30 on Nov 2 at +14:00 is Nov 1 10:30 UTC.
	later_date := chrono.Offset_Date_Time{{{2026, .november, 2}, {0, 30, 0, 0}}, {50_400}}
	earlier_date := chrono.Offset_Date_Time{{{2026, .november, 1}, {12, 0, 0, 0}}, {0}}
	testing.expect(t, chrono.offset_date_time_is_before(later_date, earlier_date))
}

@(test)
test_offset_date_time_sorts_by_moment :: proc(t: ^testing.T) {
	values := [4]chrono.Offset_Date_Time {
		{{{2026, .june, 15}, {12, 0, 0, 0}}, {0}},
		{{{2026, .june, 15}, {12, 0, 0, 0}}, {3_600}},
		{{{2026, .june, 15}, {12, 0, 0, 0}}, {-3_600}},
		{{{2026, .june, 15}, {23, 0, 0, 0}}, {43_200}},
	}
	slice.sort_by(values[:], chrono.offset_date_time_is_before)

	// 23:00 at +12:00 is 11:00 UTC, then 12:00 at +01:00 is 11:00... checked by instant below.
	for i in 1 ..< len(values) {
		before := chrono.offset_date_time_to_instant(values[i - 1])
		after := chrono.offset_date_time_to_instant(values[i])
		testing.expect(t, !chrono.instant_is_after(before, after))
	}
	testing.expect_value(t, values[0].offset, chrono.Zone_Offset{43_200})
	testing.expect_value(t, values[3].offset, chrono.Zone_Offset{-3_600})
}

@(test)
test_offset_date_time_plus_duration :: proc(t: ^testing.T) {
	result, ok := chrono.offset_date_time_plus_duration(MOMENT_AT_UTC, {3_600, 0})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		result,
		chrono.Offset_Date_Time{{{2026, .june, 15}, {13, 0, 0, 0}}, {0}},
	)

	// The offset is kept: one hour on from 13:00 at +01:00 is 14:00 at +01:00.
	result, ok = chrono.offset_date_time_plus_duration(MOMENT_AT_PLUS_ONE, {3_600, 0})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		result,
		chrono.Offset_Date_Time{{{2026, .june, 15}, {14, 0, 0, 0}}, {3_600}},
	)

	// Across midnight and a month end, at a half hour offset.
	start := chrono.Offset_Date_Time{{{2026, .january, 31}, {23, 30, 0, 0}}, {19_800}}
	result, ok = chrono.offset_date_time_plus_duration(start, {3_600, 0})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		result,
		chrono.Offset_Date_Time{{{2026, .february, 1}, {0, 30, 0, 0}}, {19_800}},
	)

	result, ok = chrono.offset_date_time_plus_duration(MOMENT_AT_UTC, {-43_200, 0})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		result,
		chrono.Offset_Date_Time{{{2026, .june, 15}, {0, 0, 0, 0}}, {0}},
	)
}

@(test)
test_offset_date_time_plus_duration_then_negation_returns_original :: proc(t: ^testing.T) {
	starts := [?]chrono.Offset_Date_Time{MOMENT_AT_UTC, MOMENT_AT_PLUS_ONE, MOMENT_AT_MINUS_FIVE}
	durations := [?]chrono.Duration {
		{0, 0},
		{0, 1},
		{1, 0},
		{86_399, 999_999_999},
		{4_000_000, 7},
		{-1, 999_999_999},
		{-86_401, 5},
	}
	for start in starts {
		for duration in durations {
			moved, moved_ok := chrono.offset_date_time_plus_duration(start, duration)
			testing.expect(t, moved_ok)
			negated, negate_ok := chrono.duration_negate(duration)
			testing.expect(t, negate_ok)
			back, back_ok := chrono.offset_date_time_plus_duration(moved, negated)
			testing.expect(t, back_ok)
			testing.expect_value(t, back, start)
		}
	}
}

@(test)
test_offset_date_time_plus_duration_range_edges :: proc(t: ^testing.T) {
	last := chrono.Offset_Date_Time{chrono.LOCAL_DATE_TIME_MAX, {0}}
	first := chrono.Offset_Date_Time{chrono.LOCAL_DATE_TIME_MIN, {0}}

	_, ok := chrono.offset_date_time_plus_duration(last, {0, 1})
	testing.expect(t, !ok)
	_, ok = chrono.offset_date_time_plus_duration(first, {-1, 999_999_999})
	testing.expect(t, !ok)

	// Moving onto the last moment works, one nanosecond further does not.
	value, value_ok := chrono.offset_date_time_plus_duration(
		first,
		{chrono.DURATION_SECONDS_MAX, 999_999_999},
	)
	testing.expect(t, value_ok)
	testing.expect_value(t, value, last)

	// At +18:00 the reading passes YEAR_MAX 18 hours before the moment passes the end of the
	// Instant range. From 17:00 on the last date, 7 hours less a nanosecond still reads as the
	// last date time, and 7 hours reads as the next day, which cannot be written.
	east_end := chrono.Offset_Date_Time {
		{{chrono.YEAR_MAX, .december, 31}, {17, 0, 0, 0}},
		chrono.ZONE_OFFSET_MAX,
	}
	testing.expect(t, chrono.offset_date_time_is_valid(east_end))
	_, ok = chrono.offset_date_time_plus_duration(east_end, {chrono.SECONDS_PER_HOUR, 0})
	testing.expect(t, ok)
	value, value_ok = chrono.offset_date_time_plus_duration(
		east_end,
		{7 * chrono.SECONDS_PER_HOUR - 1, 999_999_999},
	)
	testing.expect(t, value_ok)
	testing.expect_value(t, value.date_time, chrono.LOCAL_DATE_TIME_MAX)
	_, ok = chrono.offset_date_time_plus_duration(east_end, {7 * chrono.SECONDS_PER_HOUR, 0})
	testing.expect(t, !ok)
}

@(test)
test_offset_date_time_between :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.offset_date_time_between(MOMENT_AT_UTC, MOMENT_AT_UTC),
		chrono.Duration{0, 0},
	)
	// The same moment at two offsets is zero apart.
	testing.expect_value(
		t,
		chrono.offset_date_time_between(MOMENT_AT_PLUS_ONE, MOMENT_AT_MINUS_FIVE),
		chrono.Duration{0, 0},
	)

	// 00:00 at +05:30 is 18:30 UTC the day before; 06:00 UTC is 11 hours 30 minutes later.
	from := chrono.Offset_Date_Time{{{2026, .june, 15}, {0, 0, 0, 0}}, {19_800}}
	to := chrono.Offset_Date_Time{{{2026, .june, 15}, {6, 0, 0, 0}}, {0}}
	testing.expect_value(t, chrono.offset_date_time_between(from, to), chrono.Duration{41_400, 0})
	testing.expect_value(t, chrono.offset_date_time_between(to, from), chrono.Duration{-41_400, 0})

	// Agrees with plus_duration: from + between(from, to) is to, at from's offset.
	landed, ok := chrono.offset_date_time_plus_duration(
		from,
		chrono.offset_date_time_between(from, to),
	)
	testing.expect(t, ok)
	testing.expect_value(t, chrono.offset_date_time_compare(landed, to), chrono.Ordering.equal)
	testing.expect_value(t, landed.offset, from.offset)
}

@(test)
test_offset_date_time_plus_period_keeps_the_clock_time_and_offset :: proc(t: ^testing.T) {
	result, ok := chrono.offset_date_time_plus_period(
		{{{2026, .november, 1}, {14, 30, 15, 500}}, {19_800}},
		{0, 0, 1},
	)
	testing.expect(t, ok)
	testing.expect_value(
		t,
		result,
		chrono.Offset_Date_Time{{{2026, .november, 2}, {14, 30, 15, 500}}, {19_800}},
	)

	// Month end clamps, as for Local_Date_Time.
	result, ok = chrono.offset_date_time_plus_period(
		{{{2026, .january, 31}, {23, 59, 59, 999_999_999}}, {-28_800}},
		{0, 1, 0},
	)
	testing.expect(t, ok)
	testing.expect_value(
		t,
		result,
		chrono.Offset_Date_Time{{{2026, .february, 28}, {23, 59, 59, 999_999_999}}, {-28_800}},
	)
}

// With a fixed offset there is no DST, so one day as a Period and 24 hours as a Duration agree.
@(test)
test_offset_date_time_one_day_period_equals_twenty_four_hours :: proc(t: ^testing.T) {
	starts := [?]chrono.Offset_Date_Time{MOMENT_AT_UTC, MOMENT_AT_PLUS_ONE, MOMENT_AT_MINUS_FIVE}
	for start in starts {
		by_period, period_ok := chrono.offset_date_time_plus_period(start, {0, 0, 1})
		by_duration, duration_ok := chrono.offset_date_time_plus_duration(
			start,
			{chrono.SECONDS_PER_DAY, 0},
		)
		testing.expect(t, period_ok && duration_ok)
		testing.expect_value(t, by_period, by_duration)
	}
}

@(test)
test_offset_date_time_plus_period_range_edges :: proc(t: ^testing.T) {
	// The date stays in range but the moment would pass the end of the Instant range.
	_, ok := chrono.offset_date_time_plus_period(
		{{{chrono.YEAR_MAX, .december, 30}, {23, 59, 59, 0}}, {-3_600}},
		{0, 0, 1},
	)
	testing.expect(t, !ok)

	// The date itself passes YEAR_MAX.
	_, ok = chrono.offset_date_time_plus_period({chrono.LOCAL_DATE_TIME_MAX, {0}}, {0, 0, 1})
	testing.expect(t, !ok)

	// Both fine one day earlier.
	value, value_ok := chrono.offset_date_time_plus_period(
		{{{chrono.YEAR_MAX, .december, 30}, {12, 0, 0, 0}}, {0}},
		{0, 0, 1},
	)
	testing.expect(t, value_ok)
	testing.expect_value(t, value.date_time.date, chrono.LOCAL_DATE_MAX)
}
