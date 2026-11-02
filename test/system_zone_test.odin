#+build darwin, linux
package chrono_test

import "core:testing"

import chrono "../"

foreign import libc "system:c"

foreign libc {
	setenv :: proc(name: cstring, value: cstring, overwrite: i32) -> i32 ---
	unsetenv :: proc(name: cstring) -> i32 ---
}

// 2026-01-15 12:00 UTC and 2026-07-15 12:00 UTC: northern winter and summer.
WINTER :: chrono.Instant{1_768_478_400, 0}
SUMMER :: chrono.Instant{1_784_116_800, 0}

expect_offsets :: proc(
	t: ^testing.T,
	zone: cstring,
	winter, summer: i32,
	loc := #caller_location,
) {
	testing.expect_value(t, setenv("TZ", zone, 1), 0, loc)

	offset, ok := chrono.zone_offset_system_at(WINTER)
	testing.expect(t, ok, loc = loc)
	testing.expect_value(t, offset.seconds, winter, loc)

	offset, ok = chrono.zone_offset_system_at(SUMMER)
	testing.expect(t, ok, loc = loc)
	testing.expect_value(t, offset.seconds, summer, loc)
}

test_system_zone_follows_the_tz_variable :: proc(t: ^testing.T) {
	expect_offsets(t, "UTC", 0, 0)
	expect_offsets(t, "Asia/Kolkata", 19_800, 19_800)
	expect_offsets(t, "Pacific/Kiritimati", 50_400, 50_400)

	// Daylight saving moves the offset by an hour in summer for New York...
	expect_offsets(t, "America/New_York", -18_000, -14_400)
	// ...and Lord Howe, which is in the southern hemisphere, switches the other way and by 30 minutes.
	expect_offsets(t, "Australia/Lord_Howe", 39_600, 37_800)

	testing.expect_value(t, unsetenv("TZ"), 0)
}

test_system_zone_switches_exactly_at_the_dst_boundary :: proc(t: ^testing.T) {
	testing.expect_value(t, setenv("TZ", "America/New_York", 1), 0)
	defer unsetenv("TZ")

	// Spring forward: 2026-03-08 07:00:00 UTC, the second before is still standard time.
	offset, ok := chrono.zone_offset_system_at({1_772_953_199, 0})
	testing.expect(t, ok)
	testing.expect_value(t, offset.seconds, -18_000)
	offset, ok = chrono.zone_offset_system_at({1_772_953_200, 0})
	testing.expect(t, ok)
	testing.expect_value(t, offset.seconds, -14_400)

	// Fall back: 2026-11-01 06:00:00 UTC.
	offset, ok = chrono.zone_offset_system_at({1_793_512_799, 0})
	testing.expect(t, ok)
	testing.expect_value(t, offset.seconds, -14_400)
	offset, ok = chrono.zone_offset_system_at({1_793_512_800, 0})
	testing.expect(t, ok)
	testing.expect_value(t, offset.seconds, -18_000)
}

test_system_zone_rejects_offsets_beyond_the_cap :: proc(t: ^testing.T) {
	// A POSIX TZ string with a sign flipped: "XXX-24" is 24 hours EAST of UTC, past the 18 hour cap.
	testing.expect_value(t, setenv("TZ", "XXX-24", 1), 0)
	defer unsetenv("TZ")

	_, ok := chrono.zone_offset_system_at(WINTER)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_time_now()
	testing.expect(t, !ok)
	_, ok = chrono.local_date_now()
	testing.expect(t, !ok)
	_, ok = chrono.local_time_now()
	testing.expect(t, !ok)
}

test_system_zone_at_the_ends_of_the_instant_range :: proc(t: ^testing.T) {
	testing.expect_value(t, setenv("TZ", "America/New_York", 1), 0)
	defer unsetenv("TZ")

	// The C library may refuse a moment this far out, which is a false result; if it answers, the
	// answer has to be a valid offset. Either way it must not crash.
	offset, ok := chrono.zone_offset_system_at({chrono.INSTANT_SECONDS_MIN, 0})
	testing.expect(t, !ok || chrono.zone_offset_is_valid(offset))
	offset, ok = chrono.zone_offset_system_at({chrono.INSTANT_SECONDS_MAX, 999_999_999})
	testing.expect(t, !ok || chrono.zone_offset_is_valid(offset))
}

// Reads the clock around the call, so the result must lie between the two readings, shifted by
// the zone's offset. This also checks that all three procs agree on one moment.
test_local_date_time_now_lies_between_two_clock_readings :: proc(t: ^testing.T) {
	zones := [?]cstring{"UTC", "Asia/Kolkata", "America/New_York", "Pacific/Kiritimati"}
	for zone in zones {
		testing.expect_value(t, setenv("TZ", zone, 1), 0)

		before := chrono.clock_wall_read()
		now, ok := chrono.local_date_time_now()
		after := chrono.clock_wall_read()
		testing.expect(t, ok)

		offset, offset_ok := chrono.zone_offset_system_at(before)
		testing.expect(t, offset_ok)
		moment, moment_ok := chrono.local_date_time_to_instant(now, offset)
		testing.expect(t, moment_ok)
		testing.expect(t, !chrono.instant_is_before(moment, before))
		testing.expect(t, !chrono.instant_is_after(moment, after))
	}
	testing.expect_value(t, unsetenv("TZ"), 0)
}

test_local_date_now_and_local_time_now_are_the_parts_of_one_reading :: proc(t: ^testing.T) {
	testing.expect_value(t, setenv("TZ", "Asia/Kolkata", 1), 0)
	defer unsetenv("TZ")

	date, date_ok := chrono.local_date_now()
	time, time_ok := chrono.local_time_now()
	testing.expect(t, date_ok && time_ok)
	testing.expect(t, chrono.local_date_is_valid(date))
	testing.expect(t, chrono.local_time_is_valid(time))
	testing.expect(t, chrono.local_date_is_after(date, chrono.Local_Date{2020, .january, 1}))
	testing.expect(t, chrono.local_date_is_before(date, chrono.Local_Date{2100, .january, 1}))
}

// TZ is one process wide setting and Odin runs tests on several threads, so tests that each set
// it overwrite one another. Every check that changes TZ is a plain proc above, and this single
// test runs them one after the other.
@(test)
test_system_zone :: proc(t: ^testing.T) {
	test_system_zone_follows_the_tz_variable(t)
	test_system_zone_switches_exactly_at_the_dst_boundary(t)
	test_system_zone_rejects_offsets_beyond_the_cap(t)
	test_system_zone_at_the_ends_of_the_instant_range(t)
	test_local_date_time_now_lies_between_two_clock_readings(t)
	test_local_date_now_and_local_time_now_are_the_parts_of_one_reading(t)
}
