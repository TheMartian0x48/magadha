package email_test

import "core:strings"
import "core:testing"

import email "../../email"

repeat :: proc(text: string, count: int) -> string {
	result, _ := strings.repeat(text, count, context.temp_allocator)
	return result
}

// Domain of exactly `bytes` bytes made of full 63 byte labels plus a remainder label.
domain_of :: proc(bytes: int) -> string {
	label := repeat("a", 63)
	return strings.concatenate({label, ".", label, ".", label, ".", repeat("a", bytes - 63 * 3 - 3)}, context.temp_allocator)
}

@(test)
test_parse_valid :: proc(t: ^testing.T) {
	for s in ([?]string {
			"user@example.com",
			"user.name+tag@sub.example.co.uk",
			"a@b.co",
			"a@b.c",
			"123@test.org",
			"hello_world%foo-bar@example.com",
			"A@Example.COM",
			"user@a-b.com",
			"user@xn--bcher-kva.example",
			"user@1.example.com",
		}) {
		e, err := email.parse(s)
		testing.expectf(t, err == .None, "parse(%q) error = %v, want None", s, err)
		testing.expectf(t, string(e) == s, "parse(%q) = %q", s, e)
		testing.expectf(t, email.is_valid(email.Email(s)), "is_valid(%q) = false, want true", s)
	}
}

@(test)
test_parse_errors :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	Case :: struct {
		input: string,
		want:  email.Error,
	}
	cases := []Case {
		{"", .Missing_At},
		{"no-at", .Missing_At},
		{"@local", .Empty_Local},
		{"local@", .Empty_Domain},
		{"@", .Empty_Local},
		{"bad!char@domain.com", .Invalid_Local},
		{"space in@local.com", .Invalid_Local},
		{"o'brien@example.com", .Invalid_Local},
		{"é@example.com", .Invalid_Local},
		{"\x00@example.com", .Invalid_Local},
		// dots in the local part
		{"a..b@example.com", .Invalid_Local},
		{".a@example.com", .Invalid_Local},
		{"a.@example.com", .Invalid_Local},
		{".@example.com", .Invalid_Local},
		// domain
		{"user@nodot", .Invalid_Domain},
		{"user@.dot-start", .Invalid_Domain},
		{"user@dot-end.", .Invalid_Domain},
		{"user@a..com", .Invalid_Domain},
		{"user@bad!.com", .Invalid_Domain},
		{"user@-a.com", .Invalid_Domain},
		{"user@a-.com", .Invalid_Domain},
		{"user@a.-b.com", .Invalid_Domain},
		{"user@a.b-.com", .Invalid_Domain},
		{"a@b@c.com", .Invalid_Domain}, // a second '@' is not a domain character
		{"user@example.com\n", .Invalid_Domain},
		{"user@1.2", .Invalid_Domain}, // all-digit last label
		{"user@127.0.0.1", .Invalid_Domain},
		{"user@example.123", .Invalid_Domain},
		{"user@é.com", .Invalid_Domain},
	}
	for c in cases {
		_, err := email.parse(c.input)
		testing.expectf(t, err == c.want, "parse(%q) error = %v, want %v", c.input, err, c.want)
		testing.expectf(t, !email.is_valid(email.Email(c.input)), "is_valid(%q) = true, want false", c.input)
	}
}

@(test)
test_parse_length_limits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	Case :: struct {
		input: string,
		want:  email.Error,
	}
	cases := []Case {
		// local part: 64 ok, 65 too long
		{strings.concatenate({repeat("a", 64), "@x.com"}, context.temp_allocator), .None},
		{strings.concatenate({repeat("a", 65), "@x.com"}, context.temp_allocator), .Too_Long},
		// label: 63 ok, 64 too long
		{strings.concatenate({"u@", repeat("a", 63), ".com"}, context.temp_allocator), .None},
		{strings.concatenate({"u@", repeat("a", 64), ".com"}, context.temp_allocator), .Too_Long},
		// whole address: 254 ok (1 + '@' + 252), 255 too long
		{strings.concatenate({"u@", domain_of(252)}, context.temp_allocator), .None},
		{strings.concatenate({"u@", domain_of(253)}, context.temp_allocator), .Too_Long},
		// length is checked before the structure, so a long text without '@' is Too_Long
		{repeat("a", 255), .Too_Long},
	}
	for c in cases {
		_, err := email.parse(c.input)
		testing.expectf(t, err == c.want, "parse(%d bytes) error = %v, want %v", len(c.input), err, c.want)
	}
}

@(test)
test_local_and_domain :: proc(t: ^testing.T) {
	e1, _ := email.parse("user@example.com")
	testing.expect_value(t, email.local(e1), "user")
	testing.expect_value(t, email.domain(e1), "example.com")

	e2, _ := email.parse("user.name+tag@sub.example.co.uk")
	testing.expect_value(t, email.local(e2), "user.name+tag")
	testing.expect_value(t, email.domain(e2), "sub.example.co.uk")
}

@(test)
test_equality :: proc(t: ^testing.T) {
	a, _ := email.parse("alice@example.com")
	b, _ := email.parse("alice@example.com")
	c, _ := email.parse("bob@example.com")
	testing.expect(t, a == b, "same email: got not equal")
	testing.expect(t, a != c, "different email: got equal")
}

@(test)
test_error_to_string :: proc(t: ^testing.T) {
	for err in email.Error {
		testing.expectf(t, len(email.error_to_string(err)) > 0, "no message for %v", err)
	}
	testing.expect_value(t, email.error_to_string(.Missing_At), "email is missing an @ sign")
	testing.expect_value(t, email.error_to_string(.Empty_Local), "email local part is empty")
}
