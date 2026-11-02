package phone_test

import "core:testing"

import phone "../../phone"

@(test)
test_country_code :: proc(t: ^testing.T) {
	Case :: struct {
		input: phone.Phone,
		want:  phone.Country_Code,
	}
	cases := []Case {
		{12_025_550_123, 1}, // US, 1 digit
		{74_951_234_567, 7}, // Russia, 1 digit
		{442_071_838_750, 44}, // UK, 2 digits
		{4_915_112_345_678, 49}, // Germany, 2 digits
		{919_876_543_210, 91}, // India, 2 digits
		{353_851_234_567, 353}, // Ireland, 3 digits
		{971_501_234_567, 971}, // UAE, 3 digits
		{2_348_012_345_678, 234}, // Nigeria, 3 digits
	}
	for c in cases {
		testing.expectf(
			t,
			phone.country_code(c.input) == c.want,
			"country_code(%d) = %d, want %d",
			c.input,
			phone.country_code(c.input),
			c.want,
		)
	}
}

@(test)
test_valid :: proc(t: ^testing.T) {
	testing.expect(t, phone.valid(phone.Phone(4_915_112_345_678)))
	testing.expect(t, phone.valid(phone.Phone(1_234_567)), "7 digits is the minimum")
	testing.expect(t, phone.valid(phone.Phone(123_456_789_012_345)), "15 digits is the maximum")
	testing.expect(t, !phone.valid(phone.Phone(0)))
	testing.expect(t, !phone.valid(phone.Phone(123_456)), "6 digits")
	testing.expect(t, !phone.valid(phone.Phone(1_234_567_890_123_456)), "16 digits")
	testing.expect(t, !phone.valid(phone.Phone(999_123_456)), "unknown country code")
}

@(test)
test_country_codes_added :: proc(t: ^testing.T) {
	for code in ([?]u16{500, 800, 808, 878, 888, 979}) {
		n := u64(code) * 10_000_000 + 1_234_567
		testing.expectf(t, phone.valid(phone.Phone(n)), "country code %d not recognised", code)
		testing.expect_value(t, phone.country_code(phone.Phone(n)), phone.Country_Code(code))
	}
}

@(test)
test_national_leading_zero :: proc(t: ^testing.T) {
	got := phone.national(phone.Phone(39_061_234_567))
	defer delete(got)
	testing.expect_value(t, got, "061234567")
}

@(test)
test_bprint :: proc(t: ^testing.T) {
	buf: [phone.E164_BUFFER_BYTES]u8
	testing.expect_value(t, phone.bprint_e164(buf[:], phone.Phone(4_915_112_345_678)), "+4915112345678")
	testing.expect_value(t, phone.bprint_national(buf[:], phone.Phone(39_061_234_567)), "061234567")
}

@(test)
test_national :: proc(t: ^testing.T) {
	Case :: struct {
		input: phone.Phone,
		want:  string,
	}
	cases := []Case {
		{12_025_550_123, "2025550123"},
		{4_915_112_345_678, "15112345678"},
		{353_851_234_567, "851234567"},
	}
	for c in cases {
		got := phone.national(c.input)
		defer delete(got)
		testing.expectf(t, got == c.want, "national(%d) = %q, want %q", c.input, got, c.want)
	}
}

@(test)
test_to_string :: proc(t: ^testing.T) {
	s := phone.to_string(phone.Phone(4_915_112_345_678))
	defer delete(s)
	testing.expect_value(t, s, "+4915112345678")
}

@(test)
test_make_phone_valid :: proc(t: ^testing.T) {
	Case :: struct {
		input: string,
		want:  phone.Phone,
	}
	cases := []Case {
		{"+12025550123", 12_025_550_123},
		{"+4915112345678", 4_915_112_345_678},
		{"+3538512345", 3_538_512_345},
		{"+1234567", 1_234_567}, // 7 digits, the minimum
		{"+123456789012345", 123_456_789_012_345}, // 15 digits, the maximum
	}
	for c in cases {
		p, err := phone.make_phone(c.input)
		testing.expectf(t, err == nil, "make_phone(%q) error = %v", c.input, err)
		testing.expectf(t, p == c.want, "make_phone(%q) = %d, want %d", c.input, p, c.want)
	}
}

@(test)
test_make_phone_invalid :: proc(t: ^testing.T) {
	Case :: struct {
		input: string,
		want:  phone.Error,
	}
	cases := []Case {
		{"", .Invalid_Format},
		{"4915112345678", .Invalid_Format}, // no '+'
		{"++4915112345678", .Invalid_Format},
		{"+49 151 1234567", .Invalid_Format}, // spaces
		{"+4915112345x78", .Invalid_Format},
		{"+49-1511-234567", .Invalid_Format},
		{"+", .Too_Short},
		{"+123456", .Too_Short}, // 6 digits
		{"+1234567890123456", .Too_Long}, // 16 digits
		{"+0123456789", .Unknown_Country_Code}, // no code starts with 0
		{"+0abcdefgh", .Invalid_Format}, // characters are checked before the leading zero
		{"+9991234567", .Unknown_Country_Code},
	}
	for c in cases {
		_, err := phone.make_phone(c.input)
		testing.expectf(
			t,
			err == c.want,
			"make_phone(%q) error = %v, want %v",
			c.input,
			err,
			c.want,
		)
	}
}

@(test)
test_make_phone_roundtrip :: proc(t: ^testing.T) {
	p, err := phone.make_phone("+4915112345678")
	testing.expect_value(t, err, phone.Error.None)
	testing.expect_value(t, phone.country_code(p), phone.Country_Code(49))

	s := phone.to_string(p)
	defer delete(s)
	testing.expect_value(t, s, "+4915112345678")
}

@(test)
test_error_to_string :: proc(t: ^testing.T) {
	for err in phone.Error {
		testing.expectf(t, len(phone.error_to_string(err)) > 0, "no message for %v", err)
	}
	testing.expect_value(t, phone.error_to_string(.Too_Short), "phone number has fewer than 7 digits")
}
