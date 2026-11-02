package chrono_test

import "core:testing"

import chrono "../"

@(test)
test_month_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, !chrono.month_is_valid(chrono.Month(0)))
	testing.expect(t, chrono.month_is_valid(.january))
	testing.expect(t, chrono.month_is_valid(.december))
	testing.expect(t, !chrono.month_is_valid(chrono.Month(13)))
	testing.expect(t, !chrono.month_is_valid(chrono.Month(255)))
}

@(test)
test_month_plus_wraps :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.month_plus(.december, 1), chrono.Month.january)
	testing.expect_value(t, chrono.month_plus(.january, -1), chrono.Month.december)
	testing.expect_value(t, chrono.month_plus(.march, 0), chrono.Month.march)
	testing.expect_value(t, chrono.month_plus(.march, 12), chrono.Month.march)
	testing.expect_value(t, chrono.month_plus(.march, -12), chrono.Month.march)
	testing.expect_value(t, chrono.month_plus(.november, 3), chrono.Month.february)
	testing.expect_value(t, chrono.month_plus(.february, -3), chrono.Month.november)
	testing.expect_value(t, chrono.month_plus(.march, 12 * 1000 + 2), chrono.Month.may)
}

@(test)
test_month_plus_extreme_offsets :: proc(t: ^testing.T) {
	testing.expect(t, chrono.month_is_valid(chrono.month_plus(.december, max(i64))))
	testing.expect(t, chrono.month_is_valid(chrono.month_plus(.january, min(i64))))
	testing.expect_value(
		t,
		chrono.month_plus(.january, max(i64)),
		chrono.Month(1 + max(i64) %% 12),
	)
}

@(test)
test_month_plus_every_pair :: proc(t: ^testing.T) {
	for start in chrono.Month.january ..= chrono.Month.december {
		for offset in i64(-30) ..= 30 {
			result := chrono.month_plus(start, offset)
			testing.expect_value(t, chrono.month_plus(result, -offset), start)
		}
	}
}
