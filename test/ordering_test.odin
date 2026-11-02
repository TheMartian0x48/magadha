package chrono_test

import "core:slice"
import "core:testing"

import chrono "../"

@(test)
test_ordering_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, chrono.ordering_is_valid(.less))
	testing.expect(t, chrono.ordering_is_valid(.equal))
	testing.expect(t, chrono.ordering_is_valid(.greater))
	testing.expect(t, !chrono.ordering_is_valid(chrono.Ordering(-2)))
	testing.expect(t, !chrono.ordering_is_valid(chrono.Ordering(2)))
	testing.expect(t, !chrono.ordering_is_valid(chrono.Ordering(127)))
}

@(test)
test_ordering_reverse :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.ordering_reverse(.less), chrono.Ordering.greater)
	testing.expect_value(t, chrono.ordering_reverse(.equal), chrono.Ordering.equal)
	testing.expect_value(t, chrono.ordering_reverse(.greater), chrono.Ordering.less)

	for ordering in chrono.Ordering {
		testing.expect_value(
			t,
			chrono.ordering_reverse(chrono.ordering_reverse(ordering)),
			ordering,
		)
	}
}

@(test)
test_ordering_compare :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.ordering_compare(1, 2), chrono.Ordering.less)
	testing.expect_value(t, chrono.ordering_compare(2, 2), chrono.Ordering.equal)
	testing.expect_value(t, chrono.ordering_compare(3, 2), chrono.Ordering.greater)
	testing.expect_value(t, chrono.ordering_compare(i64(-5), i64(5)), chrono.Ordering.less)
	testing.expect_value(
		t,
		chrono.ordering_compare(chrono.Year(-1), chrono.Year(-2)),
		chrono.Ordering.greater,
	)
	testing.expect_value(
		t,
		chrono.ordering_compare(chrono.Month.march, chrono.Month.april),
		chrono.Ordering.less,
	)
	testing.expect_value(t, chrono.ordering_compare(u8(9), u8(9)), chrono.Ordering.equal)
}

@(test)
test_ordering_then :: proc(t: ^testing.T) {
	for first in chrono.Ordering {
		for second in chrono.Ordering {
			expected := second if first == .equal else first
			testing.expect_value(t, chrono.ordering_then(first, second), expected)
		}
	}
}

// Release dates in no particular order, as they might arrive from a file.
RELEASE_DATES :: [5]chrono.Local_Date {
	{2026, .march, 9},
	{2025, .december, 31},
	{2026, .march, 2},
	{2024, .february, 29},
	{2026, .january, 15},
}

date_is_older :: proc(left, right: chrono.Local_Date) -> bool {
	return chrono.local_date_compare(left, right) == .less
}

date_is_newer :: proc(left, right: chrono.Local_Date) -> bool {
	return chrono.ordering_reverse(chrono.local_date_compare(left, right)) == .less
}

@(test)
test_sort_dates_oldest_first :: proc(t: ^testing.T) {
	dates := RELEASE_DATES
	slice.sort_by(dates[:], date_is_older)

	expected := [5]chrono.Local_Date {
		{2024, .february, 29},
		{2025, .december, 31},
		{2026, .january, 15},
		{2026, .march, 2},
		{2026, .march, 9},
	}
	testing.expect_value(t, dates, expected)
}

@(test)
test_sort_dates_newest_first :: proc(t: ^testing.T) {
	dates := RELEASE_DATES
	slice.sort_by(dates[:], date_is_newer)

	expected := [5]chrono.Local_Date {
		{2026, .march, 9},
		{2026, .march, 2},
		{2026, .january, 15},
		{2025, .december, 31},
		{2024, .february, 29},
	}
	testing.expect_value(t, dates, expected)
}

// Sorts by month then day, ignoring the year, so birthdays come out in calendar order.
// Ties on month and day fall through to the year, newest first.
Birthday :: struct {
	name: string,
	date: chrono.Local_Date,
}

birthday_is_earlier_in_year :: proc(left, right: Birthday) -> bool {
	order := chrono.ordering_then(
		chrono.ordering_compare(left.date.month, right.date.month),
		chrono.ordering_then(
			chrono.ordering_compare(left.date.day, right.date.day),
			chrono.ordering_reverse(chrono.ordering_compare(left.date.year, right.date.year)),
		),
	)

	return order == .less
}

@(test)
test_sort_birthdays_by_month_then_day_then_newest_year :: proc(t: ^testing.T) {
	birthdays := [5]Birthday {
		{"asha", {1990, .november, 3}},
		{"ben", {1985, .march, 20}},
		{"chen", {2001, .march, 20}},
		{"dara", {1999, .march, 4}},
		{"eli", {1970, .january, 30}},
	}
	slice.sort_by(birthdays[:], birthday_is_earlier_in_year)

	expected_names := [5]string{"eli", "dara", "chen", "ben", "asha"}
	for birthday, index in birthdays {
		testing.expect_value(t, birthday.name, expected_names[index])
	}
}
