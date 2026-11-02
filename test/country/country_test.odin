package country_test

import "core:testing"

import country "../../country"

@(test)
test_from_alpha2 :: proc(t: ^testing.T) {
	c, err := country.from_alpha2("US")
	testing.expect_value(t, err, country.Error.None)
	testing.expect_value(t, country.alpha2(c), country.Alpha2("US"))
	testing.expect_value(t, country.alpha3(c), country.Alpha3("USA"))
	testing.expect_value(t, country.numeric_code(c), country.Numeric_Code(840))
	testing.expect_value(t, country.name(c), "United States of America")
}

@(test)
test_from_alpha3 :: proc(t: ^testing.T) {
	c, err := country.from_alpha3("GBR")
	testing.expect_value(t, err, country.Error.None)
	testing.expect_value(t, country.alpha2(c), country.Alpha2("GB"))
	testing.expect_value(t, country.numeric_code(c), country.Numeric_Code(826))
	testing.expect_value(t, country.name(c), "United Kingdom")
}

@(test)
test_from_numeric_code :: proc(t: ^testing.T) {
	c, err := country.from_numeric_code(276)
	testing.expect_value(t, err, country.Error.None)
	testing.expect_value(t, country.alpha2(c), country.Alpha2("DE"))
	testing.expect_value(t, country.alpha3(c), country.Alpha3("DEU"))

	c, err = country.from_numeric_code(4) // smallest code
	testing.expect_value(t, err, country.Error.None)
	testing.expect_value(t, country.alpha2(c), country.Alpha2("AF"))

	c, err = country.from_numeric_code(894) // largest code
	testing.expect_value(t, err, country.Error.None)
	testing.expect_value(t, country.alpha2(c), country.Alpha2("ZM"))
}

@(test)
test_from_name :: proc(t: ^testing.T) {
	c, err := country.from_name("Canada")
	testing.expect_value(t, err, country.Error.None)
	testing.expect_value(t, country.alpha2(c), country.Alpha2("CA"))

	c, err = country.from_name("new zealand")
	testing.expect_value(t, err, country.Error.None)
	testing.expect_value(t, country.alpha2(c), country.Alpha2("NZ"))

	c, err = country.from_name("South Georgia and the South Sandwich Islands") // longest name
	testing.expect_value(t, err, country.Error.None)
	testing.expect_value(t, country.alpha2(c), country.Alpha2("GS"))
}

@(test)
test_case_insensitive :: proc(t: ^testing.T) {
	a, _ := country.from_alpha2("fr")
	b, _ := country.from_alpha2("Fr")
	c, _ := country.from_alpha3("fra")
	testing.expect(t, a == b && b == c, "different case parsed to different countries")
}

@(test)
test_errors :: proc(t: ^testing.T) {
	Case :: struct {
		input: string,
		want:  country.Error,
	}
	alpha2_cases := []Case {
		{"", .Invalid_Format},
		{"U", .Invalid_Format},
		{"USA", .Invalid_Format},
		{"1A", .Invalid_Format},
		{"é", .Invalid_Format},
		{"ZZ", .Not_Found},
	}
	for c in alpha2_cases {
		got, err := country.from_alpha2(c.input)
		testing.expectf(
			t,
			err == c.want,
			"from_alpha2(%q) error = %v, want %v",
			c.input,
			err,
			c.want,
		)
		testing.expect(t, got == country.COUNTRY_NONE, "failed lookup must return COUNTRY_NONE")
	}

	alpha3_cases := []Case {
		{"", .Invalid_Format},
		{"US", .Invalid_Format},
		{"USAA", .Invalid_Format},
		{"U-A", .Invalid_Format},
		{"ZZZ", .Not_Found},
	}
	for c in alpha3_cases {
		got, err := country.from_alpha3(c.input)
		testing.expectf(
			t,
			err == c.want,
			"from_alpha3(%q) error = %v, want %v",
			c.input,
			err,
			c.want,
		)
		testing.expect(t, got == country.COUNTRY_NONE, "failed lookup must return COUNTRY_NONE")
	}

	_, err := country.from_numeric_code(999)
	testing.expect_value(t, err, country.Error.Not_Found)
	_, err = country.from_numeric_code(0)
	testing.expect_value(t, err, country.Error.Not_Found)
	_, err = country.from_name("Nowhere")
	testing.expect_value(t, err, country.Error.Not_Found)
	_, err = country.from_name("")
	testing.expect_value(t, err, country.Error.Invalid_Format)
}

@(test)
test_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, country.is_valid_alpha2("DE"))
	testing.expect(
		t,
		country.is_valid_alpha2("de"),
		"is_valid_alpha2 must ignore case like from_alpha2",
	)
	testing.expect(t, !country.is_valid_alpha2("XX"))
	testing.expect(t, !country.is_valid_alpha2(""))
	testing.expect(t, country.is_valid_alpha3("DEU"))
	testing.expect(t, country.is_valid_alpha3("deu"))
	testing.expect(t, !country.is_valid_alpha3("XXX"))
	testing.expect(t, country.is_valid_numeric_code(840))
	testing.expect(t, !country.is_valid_numeric_code(0))
	testing.expect(t, country.is_valid_name("Japan"))
	testing.expect(t, !country.is_valid_name("Nowhere"))
	testing.expect(t, !country.is_valid_name(""))
}

@(test)
test_valid :: proc(t: ^testing.T) {
	testing.expect(t, country.valid(country.Country(0)))
	testing.expect(t, country.valid(country.Country(country.COUNTRY_COUNT - 1)))
	testing.expect(t, !country.valid(country.Country(country.COUNTRY_COUNT)))
	testing.expect(t, !country.valid(country.COUNTRY_NONE))
}

@(test)
test_error_to_string :: proc(t: ^testing.T) {
	for err in country.Error {
		testing.expectf(t, len(country.error_to_string(err)) > 0, "no message for %v", err)
	}
}

@(test)
test_map_key :: proc(t: ^testing.T) {
	a, _ := country.from_alpha2("FR")
	b, _ := country.from_alpha2("fr")
	m := map[country.Country]int{}
	defer delete(m)
	m[a] = 1
	testing.expect_value(t, m[b], 1)
}

@(test)
test_tables_sorted :: proc(t: ^testing.T) {
	testing.expect(t, country.tables_sorted(), "table order is broken: binary search will miss entries")

	// The same invariant through the public accessors, for alpha-2.
	for i in 1 ..< country.COUNTRY_COUNT {
		before := country.alpha2(country.Country(i - 1))
		after := country.alpha2(country.Country(i))
		testing.expectf(t, before < after, "alpha2 not ascending at %d: %q, %q", i, before, after)
	}
}

// Every table entry must round-trip through every lookup, and the sorted
// indices must have found every entry (so the tables are complete and ordered).
@(test)
test_table_round_trip :: proc(t: ^testing.T) {
	for i in 0 ..< country.COUNTRY_COUNT {
		want := country.Country(i)

		got2, err2 := country.from_alpha2_code(country.alpha2(want))
		testing.expectf(
			t,
			err2 == .None && got2 == want,
			"alpha2 round-trip failed for %q",
			country.alpha2(want),
		)

		got3, err3 := country.from_alpha3_code(country.alpha3(want))
		testing.expectf(
			t,
			err3 == .None && got3 == want,
			"alpha3 round-trip failed for %q",
			country.alpha3(want),
		)

		gotc, errc := country.from_numeric_code(country.numeric_code(want))
		testing.expectf(
			t,
			errc == .None && gotc == want,
			"code round-trip failed for %d",
			country.numeric_code(want),
		)

		gotn, errn := country.from_name(country.name(want))
		testing.expectf(
			t,
			errn == .None && gotn == want,
			"name round-trip failed for %q",
			country.name(want),
		)
	}
}
