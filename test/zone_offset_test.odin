package chrono_test

import "core:testing"

import chrono "../"

@(test)
test_zone_offset_constants :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.ZONE_OFFSET_SECONDS_MAX, 64_800)
	testing.expect_value(t, chrono.ZONE_OFFSET_UTC, chrono.Zone_Offset{0})
	testing.expect_value(t, chrono.ZONE_OFFSET_MIN, chrono.Zone_Offset{-64_800})
	testing.expect_value(t, chrono.ZONE_OFFSET_MAX, chrono.Zone_Offset{64_800})
	testing.expect(t, chrono.zone_offset_is_valid(chrono.ZONE_OFFSET_UTC))
	testing.expect(t, chrono.zone_offset_is_valid(chrono.ZONE_OFFSET_MIN))
	testing.expect(t, chrono.zone_offset_is_valid(chrono.ZONE_OFFSET_MAX))
}

@(test)
test_zone_offset_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, chrono.zone_offset_is_valid({}))
	testing.expect(t, chrono.zone_offset_is_valid({19_800}))
	testing.expect(t, chrono.zone_offset_is_valid({-28_800}))
	testing.expect(t, chrono.zone_offset_is_valid({64_800}))
	testing.expect(t, chrono.zone_offset_is_valid({-64_800}))
	testing.expect(t, !chrono.zone_offset_is_valid({64_801}))
	testing.expect(t, !chrono.zone_offset_is_valid({-64_801}))
	testing.expect(t, !chrono.zone_offset_is_valid({min(i32)}))
	testing.expect(t, !chrono.zone_offset_is_valid({max(i32)}))
}

@(test)
test_zone_offset_make :: proc(t: ^testing.T) {
	offset, ok := chrono.zone_offset_make(19_800)
	testing.expect(t, ok)
	testing.expect_value(t, offset, chrono.Zone_Offset{19_800})

	_, ok = chrono.zone_offset_make(64_801)
	testing.expect(t, !ok)
	_, ok = chrono.zone_offset_make(min(i32))
	testing.expect(t, !ok)
}

@(test)
test_zone_offset_make_hours_minutes :: proc(t: ^testing.T) {
	offset, ok := chrono.zone_offset_make_hours_minutes(5, 30)
	testing.expect(t, ok)
	testing.expect_value(t, offset, chrono.Zone_Offset{19_800})

	// West of UTC both parts are negative.
	offset, ok = chrono.zone_offset_make_hours_minutes(-5, -30)
	testing.expect(t, ok)
	testing.expect_value(t, offset, chrono.Zone_Offset{-19_800})

	offset, ok = chrono.zone_offset_make_hours_minutes(0, 0)
	testing.expect(t, ok)
	testing.expect_value(t, offset, chrono.ZONE_OFFSET_UTC)

	// A zero hour part takes the sign from the minutes: +00:30 and -00:30.
	offset, ok = chrono.zone_offset_make_hours_minutes(0, 30)
	testing.expect(t, ok)
	testing.expect_value(t, offset, chrono.Zone_Offset{1_800})
	offset, ok = chrono.zone_offset_make_hours_minutes(0, -30)
	testing.expect(t, ok)
	testing.expect_value(t, offset, chrono.Zone_Offset{-1_800})

	offset, ok = chrono.zone_offset_make_hours_minutes(8, 0)
	testing.expect(t, ok)
	testing.expect_value(t, offset, chrono.Zone_Offset{28_800})
	offset, ok = chrono.zone_offset_make_hours_minutes(-12, 0)
	testing.expect(t, ok)
	testing.expect_value(t, offset, chrono.Zone_Offset{-43_200})
	offset, ok = chrono.zone_offset_make_hours_minutes(5, 45)
	testing.expect(t, ok)
	testing.expect_value(t, offset, chrono.Zone_Offset{20_700})
}

@(test)
test_zone_offset_make_hours_minutes_rejects_mixed_signs :: proc(t: ^testing.T) {
	// (-5, 30) would silently mean -04:30, so it is rejected.
	_, ok := chrono.zone_offset_make_hours_minutes(-5, 30)
	testing.expect(t, !ok)
	_, ok = chrono.zone_offset_make_hours_minutes(5, -30)
	testing.expect(t, !ok)
}

@(test)
test_zone_offset_make_hours_minutes_rejects_out_of_range :: proc(t: ^testing.T) {
	_, ok := chrono.zone_offset_make_hours_minutes(5, 60)
	testing.expect(t, !ok)
	_, ok = chrono.zone_offset_make_hours_minutes(-5, -60)
	testing.expect(t, !ok)
	_, ok = chrono.zone_offset_make_hours_minutes(0, 90)
	testing.expect(t, !ok)

	// 18:00 is the cap; one minute more is not allowed.
	offset, ok2 := chrono.zone_offset_make_hours_minutes(18, 0)
	testing.expect(t, ok2)
	testing.expect_value(t, offset, chrono.ZONE_OFFSET_MAX)
	_, ok = chrono.zone_offset_make_hours_minutes(18, 1)
	testing.expect(t, !ok)
	offset, ok2 = chrono.zone_offset_make_hours_minutes(-18, 0)
	testing.expect(t, ok2)
	testing.expect_value(t, offset, chrono.ZONE_OFFSET_MIN)
	_, ok = chrono.zone_offset_make_hours_minutes(-18, -1)
	testing.expect(t, !ok)
	_, ok = chrono.zone_offset_make_hours_minutes(19, 0)
	testing.expect(t, !ok)

	// Huge hours must not overflow before the range check.
	_, ok = chrono.zone_offset_make_hours_minutes(max(i32), 0)
	testing.expect(t, !ok)
	_, ok = chrono.zone_offset_make_hours_minutes(min(i32), 0)
	testing.expect(t, !ok)
	_, ok = chrono.zone_offset_make_hours_minutes(max(i32), 59)
	testing.expect(t, !ok)
	_, ok = chrono.zone_offset_make_hours_minutes(min(i32), -59)
	testing.expect(t, !ok)
}

@(test)
test_zone_offset_compare :: proc(t: ^testing.T) {
	india := chrono.Zone_Offset{19_800}
	pacific := chrono.Zone_Offset{-28_800}
	testing.expect_value(t, chrono.zone_offset_compare(india, india), chrono.Ordering.equal)
	testing.expect_value(t, chrono.zone_offset_compare(pacific, india), chrono.Ordering.less)
	testing.expect_value(t, chrono.zone_offset_compare(india, pacific), chrono.Ordering.greater)
	testing.expect_value(
		t,
		chrono.zone_offset_compare(chrono.ZONE_OFFSET_MIN, chrono.ZONE_OFFSET_MAX),
		chrono.Ordering.less,
	)
}

@(test)
test_zone_offset_negate :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.zone_offset_negate({19_800}), chrono.Zone_Offset{-19_800})
	testing.expect_value(t, chrono.zone_offset_negate({}), chrono.ZONE_OFFSET_UTC)
	testing.expect_value(
		t,
		chrono.zone_offset_negate(chrono.ZONE_OFFSET_MAX),
		chrono.ZONE_OFFSET_MIN,
	)
	testing.expect_value(
		t,
		chrono.zone_offset_negate(chrono.ZONE_OFFSET_MIN),
		chrono.ZONE_OFFSET_MAX,
	)

	for seconds in i32(-chrono.ZONE_OFFSET_SECONDS_MAX) ..= chrono.ZONE_OFFSET_SECONDS_MAX {
		offset := chrono.Zone_Offset{seconds}
		testing.expect_value(
			t,
			chrono.zone_offset_negate(chrono.zone_offset_negate(offset)),
			offset,
		)
	}
}

@(test)
test_instant_to_local_date_time_known_values :: proc(t: ^testing.T) {
	// The wall clock value from the hello example, checked against an independent calendar.
	instant := chrono.Instant{1_793_474_051, 660_596_000}

	local, ok := chrono.instant_to_local_date_time(instant, chrono.ZONE_OFFSET_UTC)
	testing.expect(t, ok)
	testing.expect_value(
		t,
		local,
		chrono.Local_Date_Time{{2026, .october, 31}, {19, 14, 11, 660_596_000}},
	)

	// +05:30 crosses midnight into the next day.
	local, ok = chrono.instant_to_local_date_time(instant, {19_800})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		local,
		chrono.Local_Date_Time{{2026, .november, 1}, {0, 44, 11, 660_596_000}},
	)

	local, ok = chrono.instant_to_local_date_time(instant, {-28_800})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		local,
		chrono.Local_Date_Time{{2026, .october, 31}, {11, 14, 11, 660_596_000}},
	)
}

@(test)
test_instant_to_local_date_time_around_the_epoch :: proc(t: ^testing.T) {
	local, ok := chrono.instant_to_local_date_time({0, 0}, chrono.ZONE_OFFSET_UTC)
	testing.expect(t, ok)
	testing.expect_value(t, local, chrono.Local_Date_Time{{1970, .january, 1}, {}})

	local, ok = chrono.instant_to_local_date_time({0, 0}, {19_800})
	testing.expect(t, ok)
	testing.expect_value(t, local, chrono.Local_Date_Time{{1970, .january, 1}, {5, 30, 0, 0}})

	// West of UTC the epoch is still the day before.
	local, ok = chrono.instant_to_local_date_time({0, 0}, {-28_800})
	testing.expect(t, ok)
	testing.expect_value(t, local, chrono.Local_Date_Time{{1969, .december, 31}, {16, 0, 0, 0}})

	// One nanosecond before the epoch needs floor division, not truncation.
	local, ok = chrono.instant_to_local_date_time({-1, 999_999_999}, chrono.ZONE_OFFSET_UTC)
	testing.expect(t, ok)
	testing.expect_value(
		t,
		local,
		chrono.Local_Date_Time{{1969, .december, 31}, chrono.LOCAL_TIME_MAX},
	)

	local, ok = chrono.instant_to_local_date_time({-1, 0}, {50_400})
	testing.expect(t, ok)
	testing.expect_value(t, local, chrono.Local_Date_Time{{1970, .january, 1}, {13, 59, 59, 0}})
}

@(test)
test_instant_to_local_date_time_at_midnight_boundaries :: proc(t: ^testing.T) {
	// At -01:00, 22:59:59 and 23:00:00 are one second apart across a UTC day boundary.
	local, ok := chrono.instant_to_local_date_time({86_399, 0}, {-3_600})
	testing.expect(t, ok)
	testing.expect_value(t, local, chrono.Local_Date_Time{{1970, .january, 1}, {22, 59, 59, 0}})

	local, ok = chrono.instant_to_local_date_time({86_400, 0}, {-3_600})
	testing.expect(t, ok)
	testing.expect_value(t, local, chrono.Local_Date_Time{{1970, .january, 1}, {23, 0, 0, 0}})

	// At +00:00 the same two instants are on different days.
	local, ok = chrono.instant_to_local_date_time({86_399, 0}, chrono.ZONE_OFFSET_UTC)
	testing.expect(t, ok)
	testing.expect_value(t, local.date, chrono.Local_Date{1970, .january, 1})
	local, ok = chrono.instant_to_local_date_time({86_400, 0}, chrono.ZONE_OFFSET_UTC)
	testing.expect(t, ok)
	testing.expect_value(t, local.date, chrono.Local_Date{1970, .january, 2})
}

@(test)
test_instant_to_local_date_time_range_edges :: proc(t: ^testing.T) {
	earliest := chrono.Instant{chrono.INSTANT_SECONDS_MIN, 0}
	latest := chrono.Instant{chrono.INSTANT_SECONDS_MAX, 999_999_999}

	// In UTC both ends are exactly the first and last supported date times.
	local, ok := chrono.instant_to_local_date_time(earliest, chrono.ZONE_OFFSET_UTC)
	testing.expect(t, ok)
	testing.expect_value(t, local, chrono.LOCAL_DATE_TIME_MIN)
	local, ok = chrono.instant_to_local_date_time(latest, chrono.ZONE_OFFSET_UTC)
	testing.expect(t, ok)
	testing.expect_value(t, local, chrono.LOCAL_DATE_TIME_MAX)

	// Moving the offset away from the range always works at the far end.
	_, ok = chrono.instant_to_local_date_time(earliest, chrono.ZONE_OFFSET_MAX)
	testing.expect(t, ok)
	_, ok = chrono.instant_to_local_date_time(latest, chrono.ZONE_OFFSET_MIN)
	testing.expect(t, ok)

	// Towards the edge it fails: the first 64_800 seconds at -18:00, the last at +18:00.
	_, ok = chrono.instant_to_local_date_time(earliest, chrono.ZONE_OFFSET_MIN)
	testing.expect(t, !ok)
	_, ok = chrono.instant_to_local_date_time(
		{chrono.INSTANT_SECONDS_MIN + 64_799, 999_999_999},
		chrono.ZONE_OFFSET_MIN,
	)
	testing.expect(t, !ok)
	local, ok = chrono.instant_to_local_date_time(
		{chrono.INSTANT_SECONDS_MIN + 64_800, 0},
		chrono.ZONE_OFFSET_MIN,
	)
	testing.expect(t, ok)
	testing.expect_value(t, local, chrono.LOCAL_DATE_TIME_MIN)

	_, ok = chrono.instant_to_local_date_time(latest, chrono.ZONE_OFFSET_MAX)
	testing.expect(t, !ok)
	_, ok = chrono.instant_to_local_date_time(
		{chrono.INSTANT_SECONDS_MAX - 64_799, 0},
		chrono.ZONE_OFFSET_MAX,
	)
	testing.expect(t, !ok)
	local, ok = chrono.instant_to_local_date_time(
		{chrono.INSTANT_SECONDS_MAX - 64_800, 999_999_999},
		chrono.ZONE_OFFSET_MAX,
	)
	testing.expect(t, ok)
	testing.expect_value(t, local, chrono.LOCAL_DATE_TIME_MAX)
}

@(test)
test_local_date_time_to_instant_known_values :: proc(t: ^testing.T) {
	instant, ok := chrono.local_date_time_to_instant(
		{{1970, .january, 1}, {}},
		chrono.ZONE_OFFSET_UTC,
	)
	testing.expect(t, ok)
	testing.expect_value(t, instant, chrono.Instant{0, 0})

	// 05:30 at +05:30 is the epoch.
	instant, ok = chrono.local_date_time_to_instant({{1970, .january, 1}, {5, 30, 0, 0}}, {19_800})
	testing.expect(t, ok)
	testing.expect_value(t, instant, chrono.Instant{0, 0})

	// 16:00 the day before at -08:00 is the epoch.
	instant, ok = chrono.local_date_time_to_instant(
		{{1969, .december, 31}, {16, 0, 0, 0}},
		{-28_800},
	)
	testing.expect(t, ok)
	testing.expect_value(t, instant, chrono.Instant{0, 0})

	instant, ok = chrono.local_date_time_to_instant(
		{{2026, .november, 1}, {0, 44, 11, 660_596_000}},
		{19_800},
	)
	testing.expect(t, ok)
	testing.expect_value(t, instant, chrono.Instant{1_793_474_051, 660_596_000})

	// The same wall clock reading at different offsets is different moments.
	utc, utc_ok := chrono.local_date_time_to_instant(
		{{2026, .june, 15}, {12, 0, 0, 0}},
		chrono.ZONE_OFFSET_UTC,
	)
	east, east_ok := chrono.local_date_time_to_instant({{2026, .june, 15}, {12, 0, 0, 0}}, {3_600})
	testing.expect(t, utc_ok && east_ok)
	testing.expect_value(t, chrono.instant_between(east, utc), chrono.Duration{3_600, 0})
}

@(test)
test_local_date_time_to_instant_range_edges :: proc(t: ^testing.T) {
	instant, ok := chrono.local_date_time_to_instant(
		chrono.LOCAL_DATE_TIME_MIN,
		chrono.ZONE_OFFSET_UTC,
	)
	testing.expect(t, ok)
	testing.expect_value(t, instant, chrono.Instant{chrono.INSTANT_SECONDS_MIN, 0})
	instant, ok = chrono.local_date_time_to_instant(
		chrono.LOCAL_DATE_TIME_MAX,
		chrono.ZONE_OFFSET_UTC,
	)
	testing.expect(t, ok)
	testing.expect_value(t, instant, chrono.Instant{chrono.INSTANT_SECONDS_MAX, 999_999_999})

	// The first date time reached from the west is before the Instant range, from the east after.
	_, ok = chrono.local_date_time_to_instant(chrono.LOCAL_DATE_TIME_MIN, {3_600})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_time_to_instant(chrono.LOCAL_DATE_TIME_MAX, {-3_600})
	testing.expect(t, !ok)
	_, ok = chrono.local_date_time_to_instant(chrono.LOCAL_DATE_TIME_MIN, {-3_600})
	testing.expect(t, ok)
	_, ok = chrono.local_date_time_to_instant(chrono.LOCAL_DATE_TIME_MAX, {3_600})
	testing.expect(t, ok)
}

// Every instant that converts must convert back to itself, across the range and for the whole
// set of offsets, including the extremes and a half hour and a quarter hour offset.
@(test)
test_instant_and_local_date_time_round_trip :: proc(t: ^testing.T) {
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
			local, ok := chrono.instant_to_local_date_time(instant, offset)
			if !ok {
				continue
			}
			converted += 1
			testing.expect(t, chrono.local_date_time_is_valid(local))
			back, back_ok := chrono.local_date_time_to_instant(local, offset)
			testing.expect(t, back_ok)
			testing.expect_value(t, back, instant)
		}
	}
	// Exactly 9 pairs are skipped, all at the two ends of the range: the earliest instant with
	// its 4 negative offsets, and the latest instant with its 5 positive offsets.
	testing.expect_value(t, converted, len(instants) * len(offsets) - 9)
}

// A dense sweep over a stretch of time, once per offset, to catch any off by one at midnight.
@(test)
test_instant_to_local_date_time_sweep :: proc(t: ^testing.T) {
	offsets := [?]chrono.Zone_Offset {
		chrono.ZONE_OFFSET_MIN,
		{-28_800},
		{},
		{19_800},
		chrono.ZONE_OFFSET_MAX,
	}
	for offset in offsets {
		previous: chrono.Local_Date_Time
		for seconds in i64(-200_000) ..= 200_000 {
			local, ok := chrono.instant_to_local_date_time({seconds, 0}, offset)
			testing.expect(t, ok)
			if seconds > -200_000 {
				// Each second advances the wall clock by exactly one second.
				step := chrono.local_date_time_between(previous, local)
				testing.expect_value(t, step, chrono.Duration{1, 0})
			}
			previous = local
		}
	}
}

@(test)
test_local_date_from_instant :: proc(t: ^testing.T) {
	instant := chrono.Instant{1_793_474_051, 0}

	date, ok := chrono.local_date_from_instant(instant, chrono.ZONE_OFFSET_UTC)
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .october, 31})

	// The same moment is already the next day east of UTC.
	date, ok = chrono.local_date_from_instant(instant, {19_800})
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .november, 1})

	date, ok = chrono.local_date_from_instant(instant, {-28_800})
	testing.expect(t, ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .october, 31})

	_, ok = chrono.local_date_from_instant({chrono.INSTANT_SECONDS_MAX, 0}, chrono.ZONE_OFFSET_MAX)
	testing.expect(t, !ok)
}

@(test)
test_local_date_today_is_sane :: proc(t: ^testing.T) {
	date, ok := chrono.local_date_today(chrono.ZONE_OFFSET_UTC)
	testing.expect(t, ok)
	testing.expect(t, chrono.local_date_is_valid(date))
	testing.expect(t, chrono.local_date_is_after(date, chrono.Local_Date{2020, .january, 1}))
	testing.expect(t, chrono.local_date_is_before(date, chrono.Local_Date{2100, .january, 1}))

	// Zones 28 hours apart can be at most two calendar days apart.
	east, east_ok := chrono.local_date_today({50_400})
	west, west_ok := chrono.local_date_today({-43_200})
	testing.expect(t, east_ok && west_ok)
	days := chrono.local_date_days_between(west, east)
	testing.expect(t, days >= 0 && days <= 2)
}

@(test)
test_instant_is_before_and_is_after :: proc(t: ^testing.T) {
	early := chrono.Instant{100, 0}
	late := chrono.Instant{100, 1}
	testing.expect(t, chrono.instant_is_before(early, late))
	testing.expect(t, !chrono.instant_is_before(late, early))
	testing.expect(t, !chrono.instant_is_before(early, early))
	testing.expect(t, chrono.instant_is_after(late, early))
	testing.expect(t, !chrono.instant_is_after(early, late))
	testing.expect(t, !chrono.instant_is_after(early, early))
	// Just before the epoch is earlier than the epoch.
	testing.expect(t, chrono.instant_is_before({-1, 999_999_999}, {0, 0}))
}
