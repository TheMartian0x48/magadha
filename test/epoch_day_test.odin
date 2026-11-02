package chrono_test

import "core:testing"

import chrono "../"

// The bounds are written out as numbers, so check they are exactly the first and last
// day of the supported years and that nothing beyond them converts to a date.
@(test)
test_epoch_day_bounds_match_year_bounds :: proc(t: ^testing.T) {
	first := chrono.Local_Date{chrono.YEAR_MIN, .january, 1}
	last := chrono.Local_Date{chrono.YEAR_MAX, .december, 31}
	testing.expect_value(t, chrono.local_date_to_epoch_day(first), chrono.EPOCH_DAY_MIN)
	testing.expect_value(t, chrono.local_date_to_epoch_day(last), chrono.EPOCH_DAY_MAX)

	_, ok := chrono.local_date_from_epoch_day(chrono.EPOCH_DAY_MIN - 1)
	testing.expect(t, !ok)
	_, ok = chrono.local_date_from_epoch_day(chrono.EPOCH_DAY_MAX + 1)
	testing.expect(t, !ok)
}

@(test)
test_epoch_day_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, chrono.epoch_day_is_valid(chrono.EPOCH_DAY_MIN))
	testing.expect(t, chrono.epoch_day_is_valid(0))
	testing.expect(t, chrono.epoch_day_is_valid(chrono.EPOCH_DAY_MAX))
	testing.expect(t, !chrono.epoch_day_is_valid(chrono.EPOCH_DAY_MIN - 1))
	testing.expect(t, !chrono.epoch_day_is_valid(chrono.EPOCH_DAY_MAX + 1))
	testing.expect(t, !chrono.epoch_day_is_valid(min(chrono.Epoch_Day)))
	testing.expect(t, !chrono.epoch_day_is_valid(max(chrono.Epoch_Day)))
}

@(test)
test_epoch_day_plus :: proc(t: ^testing.T) {
	epoch_day, ok := chrono.epoch_day_plus(20_758, 30)
	testing.expect(t, ok)
	testing.expect_value(t, epoch_day, chrono.Epoch_Day(20_788))

	epoch_day, ok = chrono.epoch_day_plus(0, -1)
	testing.expect(t, ok)
	testing.expect_value(t, epoch_day, chrono.Epoch_Day(-1))

	// 2026-11-01 plus 30 days is 2026-12-01.
	date, date_ok := chrono.local_date_from_epoch_day(20_788)
	testing.expect(t, date_ok)
	testing.expect_value(t, date, chrono.Local_Date{2026, .december, 1})
}

@(test)
test_epoch_day_plus_bounds :: proc(t: ^testing.T) {
	epoch_day, ok := chrono.epoch_day_plus(chrono.EPOCH_DAY_MAX, 0)
	testing.expect(t, ok)
	testing.expect_value(t, epoch_day, chrono.EPOCH_DAY_MAX)

	_, ok = chrono.epoch_day_plus(chrono.EPOCH_DAY_MAX, 1)
	testing.expect(t, !ok)
	_, ok = chrono.epoch_day_plus(chrono.EPOCH_DAY_MIN, -1)
	testing.expect(t, !ok)

	epoch_day, ok = chrono.epoch_day_plus(
		chrono.EPOCH_DAY_MIN,
		i64(chrono.EPOCH_DAY_MAX) - i64(chrono.EPOCH_DAY_MIN),
	)
	testing.expect(t, ok)
	testing.expect_value(t, epoch_day, chrono.EPOCH_DAY_MAX)

	_, ok = chrono.epoch_day_plus(0, max(i64))
	testing.expect(t, !ok)
	_, ok = chrono.epoch_day_plus(0, min(i64))
	testing.expect(t, !ok)
	_, ok = chrono.epoch_day_plus(chrono.EPOCH_DAY_MAX, max(i64))
	testing.expect(t, !ok)
	_, ok = chrono.epoch_day_plus(chrono.EPOCH_DAY_MIN, min(i64))
	testing.expect(t, !ok)
}

@(test)
test_epoch_day_between :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.epoch_day_between(0, 0), 0)
	testing.expect_value(t, chrono.epoch_day_between(0, 10), 10)
	testing.expect_value(t, chrono.epoch_day_between(10, 0), -10)
	// 2026-11-01 to 2027-11-01 is one non-leap year.
	testing.expect_value(t, chrono.epoch_day_between(20_758, 20_758 + 365), 365)
	// The whole supported range fits an i64 without overflow.
	testing.expect_value(
		t,
		chrono.epoch_day_between(chrono.EPOCH_DAY_MIN, chrono.EPOCH_DAY_MAX),
		730_484_633,
	)
}

@(test)
test_epoch_day_weekday :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.epoch_day_weekday(0), chrono.Weekday.thursday)
	testing.expect_value(t, chrono.epoch_day_weekday(1), chrono.Weekday.friday)
	testing.expect_value(t, chrono.epoch_day_weekday(-1), chrono.Weekday.wednesday)
	testing.expect_value(t, chrono.epoch_day_weekday(20_758), chrono.Weekday.sunday)
	testing.expect(t, chrono.weekday_is_valid(chrono.epoch_day_weekday(chrono.EPOCH_DAY_MIN)))
	testing.expect(t, chrono.weekday_is_valid(chrono.epoch_day_weekday(chrono.EPOCH_DAY_MAX)))
}

// The weekday of consecutive days must advance by exactly one, wrapping Sunday to Monday.
@(test)
test_epoch_day_weekday_advances_daily :: proc(t: ^testing.T) {
	for epoch_day in chrono.Epoch_Day(-1000) ..= 1000 {
		today := chrono.epoch_day_weekday(epoch_day)
		tomorrow := chrono.epoch_day_weekday(epoch_day + 1)
		testing.expect_value(t, tomorrow, chrono.weekday_plus(today, 1))
	}
}
