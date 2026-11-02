package chrono_test

import "core:testing"

import chrono "../"

@(test)
test_weekday_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, !chrono.weekday_is_valid(chrono.Weekday(0)))
	testing.expect(t, chrono.weekday_is_valid(.monday))
	testing.expect(t, chrono.weekday_is_valid(.sunday))
	testing.expect(t, !chrono.weekday_is_valid(chrono.Weekday(8)))
	testing.expect(t, !chrono.weekday_is_valid(chrono.Weekday(255)))
}

@(test)
test_weekday_plus_wraps :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.weekday_plus(.sunday, 1), chrono.Weekday.monday)
	testing.expect_value(t, chrono.weekday_plus(.monday, -1), chrono.Weekday.sunday)
	testing.expect_value(t, chrono.weekday_plus(.friday, 0), chrono.Weekday.friday)
	testing.expect_value(t, chrono.weekday_plus(.friday, 7), chrono.Weekday.friday)
	testing.expect_value(t, chrono.weekday_plus(.friday, -7), chrono.Weekday.friday)
	testing.expect_value(t, chrono.weekday_plus(.friday, 3), chrono.Weekday.monday)
	testing.expect_value(t, chrono.weekday_plus(.tuesday, -3), chrono.Weekday.saturday)
	testing.expect_value(t, chrono.weekday_plus(.monday, 7 * 1000 + 2), chrono.Weekday.wednesday)
}

@(test)
test_weekday_plus_extreme_offsets :: proc(t: ^testing.T) {
	testing.expect(t, chrono.weekday_is_valid(chrono.weekday_plus(.sunday, max(i64))))
	testing.expect(t, chrono.weekday_is_valid(chrono.weekday_plus(.monday, min(i64))))
}

@(test)
test_weekday_plus_every_pair :: proc(t: ^testing.T) {
	for start in chrono.Weekday.monday ..= chrono.Weekday.sunday {
		for offset in i64(-30) ..= 30 {
			result := chrono.weekday_plus(start, offset)
			testing.expect_value(t, chrono.weekday_plus(result, -offset), start)
		}
	}
}
