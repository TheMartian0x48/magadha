package currency_test

import "core:testing"

import currency "../../currency"

@(test)
test_from_alpha3 :: proc(t: ^testing.T) {
	c, err := currency.from_alpha3("USD")
	testing.expect_value(t, err, currency.Error.None)
	testing.expect_value(t, currency.alpha3(c), currency.Alpha3("USD"))
	testing.expect_value(t, currency.numeric_code(c), currency.Numeric_Code(840))
	testing.expect_value(t, currency.name(c), "US Dollar")
	minor, ok := currency.minor_units(c)
	testing.expect(t, ok)
	testing.expect_value(t, minor, currency.Minor_Units(2))

	c, err = currency.from_alpha3("eur")
	testing.expect_value(t, err, currency.Error.None)
	testing.expect_value(t, currency.alpha3(c), currency.Alpha3("EUR"))
	testing.expect_value(t, currency.numeric_code(c), currency.Numeric_Code(978))
}

@(test)
test_from_numeric_code :: proc(t: ^testing.T) {
	c, err := currency.from_numeric_code(392)
	testing.expect_value(t, err, currency.Error.None)
	testing.expect_value(t, currency.alpha3(c), currency.Alpha3("JPY"))

	c, err = currency.from_numeric_code(8) // smallest code
	testing.expect_value(t, err, currency.Error.None)
	testing.expect_value(t, currency.alpha3(c), currency.Alpha3("ALL"))

	c, err = currency.from_numeric_code(999) // largest code
	testing.expect_value(t, err, currency.Error.None)
	testing.expect_value(t, currency.alpha3(c), currency.Alpha3("XXX"))
}

@(test)
test_errors :: proc(t: ^testing.T) {
	Case :: struct {
		input: string,
		want:  currency.Error,
	}
	cases := []Case {
		{"", .Invalid_Format},
		{"ABCD", .Invalid_Format},
		{"12", .Invalid_Format},
		{"1US", .Invalid_Format},
		{"U-D", .Invalid_Format},
		{"é", .Invalid_Format},
		{"ZZZ", .Not_Found},
		{"840", .Invalid_Format},
	}
	for c in cases {
		got, err := currency.from_alpha3(c.input)
		testing.expectf(t, err == c.want, "from_alpha3(%q) error = %v, want %v", c.input, err, c.want)
		testing.expect(t, got == currency.CURRENCY_NONE, "failed lookup must return CURRENCY_NONE")
	}

	_, err := currency.from_numeric_code(9999)
	testing.expect_value(t, err, currency.Error.Not_Found)
	_, err = currency.from_numeric_code(0)
	testing.expect_value(t, err, currency.Error.Not_Found)
}

@(test)
test_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, currency.is_valid_alpha3("JPY"))
	testing.expect(t, currency.is_valid_alpha3("jpy"), "is_valid_alpha3 must ignore case like from_alpha3")
	testing.expect(t, !currency.is_valid_alpha3("ZZZ"))
	testing.expect(t, !currency.is_valid_alpha3(""))
	testing.expect(t, currency.is_valid_numeric_code(840))
	testing.expect(t, !currency.is_valid_numeric_code(0))
}

@(test)
test_valid :: proc(t: ^testing.T) {
	testing.expect(t, currency.valid(currency.Currency(0)))
	testing.expect(t, currency.valid(currency.Currency(currency.CURRENCY_COUNT - 1)))
	testing.expect(t, !currency.valid(currency.Currency(currency.CURRENCY_COUNT)))
	testing.expect(t, !currency.valid(currency.CURRENCY_NONE))
}

@(test)
test_error_to_string :: proc(t: ^testing.T) {
	for err in currency.Error {
		testing.expectf(t, len(currency.error_to_string(err)) > 0, "no message for %v", err)
	}
}

@(test)
test_minor_units :: proc(t: ^testing.T) {
	Case :: struct {
		code: string,
		want: currency.Minor_Units,
	}
	cases := []Case{{"JPY", 0}, {"USD", 2}, {"BHD", 3}, {"CLF", 4}}
	for c in cases {
		cur, err := currency.from_alpha3(c.code)
		testing.expectf(t, err == .None, "from_alpha3(%q) error = %v", c.code, err)
		got, ok := currency.minor_units(cur)
		testing.expectf(t, ok && got == c.want, "minor_units(%s) = %d, %v, want %d", c.code, got, ok, c.want)
	}
}

@(test)
test_minor_units_not_applicable :: proc(t: ^testing.T) {
	for code in ([?]string{"XAU", "XAG", "XPT", "XPD", "XDR", "XTS", "XXX", "XBA", "XBB", "XBC", "XBD", "XUA", "XSU"}) {
		cur, err := currency.from_alpha3(code)
		testing.expectf(t, err == .None, "from_alpha3(%q) error = %v", code, err)
		_, ok := currency.minor_units(cur)
		testing.expectf(t, !ok, "minor_units(%s) must be not applicable", code)
	}
}

@(test)
test_map_key :: proc(t: ^testing.T) {
	a, _ := currency.from_alpha3("EUR")
	b, _ := currency.from_alpha3("eur")
	c, _ := currency.from_alpha3("USD")
	testing.expect(t, a == b, "same currency parsed with different case: not equal")
	testing.expect(t, a != c, "different currencies: equal")

	m := map[currency.Currency]int{}
	defer delete(m)
	m[a] = 1
	testing.expect_value(t, m[b], 1)
}

@(test)
test_tables_sorted :: proc(t: ^testing.T) {
	testing.expect(t, currency.tables_sorted(), "table order is broken: binary search will miss entries")
}

// Every table entry must round-trip through every lookup, have a name, and
// have a minor unit of 0 to 4 when it has one. Together with test_tables_sorted
// this also proves alpha-3 and numeric codes are unique.
@(test)
test_table_round_trip :: proc(t: ^testing.T) {
	for i in 0 ..< currency.CURRENCY_COUNT {
		want := currency.Currency(i)

		got3, err3 := currency.from_alpha3_code(currency.alpha3(want))
		testing.expectf(t, err3 == .None && got3 == want, "alpha3 round-trip failed for %q", currency.alpha3(want))

		gotc, errc := currency.from_numeric_code(currency.numeric_code(want))
		testing.expectf(t, errc == .None && gotc == want, "code round-trip failed for %d", currency.numeric_code(want))

		testing.expectf(t, len(currency.name(want)) > 0, "%q: empty name", currency.alpha3(want))
		if minor, ok := currency.minor_units(want); ok {
			testing.expectf(t, minor <= 4, "%q: minor = %d, want 0..4", currency.alpha3(want), minor)
		}
	}
}
