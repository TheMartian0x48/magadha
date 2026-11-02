package chrono_test

import "core:testing"

import chrono "../"

@(test)
test_year_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, chrono.year_is_valid(chrono.YEAR_MIN))
	testing.expect(t, chrono.year_is_valid(0))
	testing.expect(t, chrono.year_is_valid(chrono.YEAR_MAX))
	testing.expect(t, !chrono.year_is_valid(chrono.YEAR_MIN - 1))
	testing.expect(t, !chrono.year_is_valid(chrono.YEAR_MAX + 1))
	testing.expect(t, !chrono.year_is_valid(min(chrono.Year)))
	testing.expect(t, !chrono.year_is_valid(max(chrono.Year)))
}

@(test)
test_year_is_leap :: proc(t: ^testing.T) {
	testing.expect(t, chrono.year_is_leap(2024))
	testing.expect(t, chrono.year_is_leap(2000))
	testing.expect(t, chrono.year_is_leap(0))
	testing.expect(t, chrono.year_is_leap(-4))
	testing.expect(t, !chrono.year_is_leap(1900))
	testing.expect(t, !chrono.year_is_leap(2100))
	testing.expect(t, !chrono.year_is_leap(2026))
	testing.expect(t, !chrono.year_is_leap(-1))
}

@(test)
test_year_day_count :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.year_day_count(2024), 366)
	testing.expect_value(t, chrono.year_day_count(2026), 365)
	testing.expect_value(t, chrono.year_day_count(1900), 365)
	testing.expect_value(t, chrono.year_day_count(2000), 366)
	testing.expect_value(t, chrono.year_day_count(0), 366)
	testing.expect_value(t, chrono.year_day_count(-1), 365)
}

@(test)
test_year_plus :: proc(t: ^testing.T) {
	year, ok := chrono.year_plus(2026, 10)
	testing.expect(t, ok)
	testing.expect_value(t, year, chrono.Year(2036))

	year, ok = chrono.year_plus(2026, -2027)
	testing.expect(t, ok)
	testing.expect_value(t, year, chrono.Year(-1))

	year, ok = chrono.year_plus(2026, 0)
	testing.expect(t, ok)
	testing.expect_value(t, year, chrono.Year(2026))
}

@(test)
test_year_plus_bounds :: proc(t: ^testing.T) {
	year, ok := chrono.year_plus(chrono.YEAR_MAX, 0)
	testing.expect(t, ok)
	testing.expect_value(t, year, chrono.YEAR_MAX)

	_, ok = chrono.year_plus(chrono.YEAR_MAX, 1)
	testing.expect(t, !ok)
	_, ok = chrono.year_plus(chrono.YEAR_MIN, -1)
	testing.expect(t, !ok)

	year, ok = chrono.year_plus(chrono.YEAR_MIN, i64(chrono.YEAR_MAX) - i64(chrono.YEAR_MIN))
	testing.expect(t, ok)
	testing.expect_value(t, year, chrono.YEAR_MAX)

	_, ok = chrono.year_plus(0, max(i64))
	testing.expect(t, !ok)
	_, ok = chrono.year_plus(0, min(i64))
	testing.expect(t, !ok)
	_, ok = chrono.year_plus(chrono.YEAR_MAX, max(i64))
	testing.expect(t, !ok)
	_, ok = chrono.year_plus(chrono.YEAR_MIN, min(i64))
	testing.expect(t, !ok)
}
