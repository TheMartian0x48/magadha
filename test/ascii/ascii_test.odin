package ascii_test

import "core:testing"

import ascii "../../ascii"

Case :: struct {
	input: string,
	want:  string,
}

UPPER_CASES :: []Case{{"abc", "ABC"}, {"ABC", "ABC"}, {"aBc", "ABC"}, {"z", "Z"}, {"azAZ", "AZAZ"}, {"", ""}}
LOWER_CASES :: []Case{{"ABC", "abc"}, {"abc", "abc"}, {"aBc", "abc"}, {"Z", "z"}, {"azAZ", "azaz"}, {"", ""}}

// One byte on each side of 'A'..'Z' and 'a'..'z', plus digits, punctuation and
// non-ASCII bytes, must pass through unchanged.
UNCHANGED :: [?]string{"@", "[", "`", "{", "0", "9", "-", " ", "1", "é", "\x00", "\x7f", "\xff"}

@(test)
test_upper_buffer :: proc(t: ^testing.T) {
	for c in UPPER_CASES {
		buffer: [8]u8 // larger than any input: the result is cut to len(text)
		got := ascii.upper_buffer(buffer[:], c.input)
		testing.expectf(t, got == c.want, "upper_buffer(%q) = %q, want %q", c.input, got, c.want)
		testing.expectf(t, len(got) == len(c.input), "upper_buffer(%q) has length %d", c.input, len(got))
	}
	for input in UNCHANGED {
		buffer: [8]u8
		testing.expectf(t, ascii.upper_buffer(buffer[:], input) == input, "upper_buffer(%q) changed a non-letter", input)
	}
}

@(test)
test_upper_allocated :: proc(t: ^testing.T) {
	for c in UPPER_CASES {
		got, err := ascii.upper_allocated(c.input)
		defer delete(got)
		testing.expect_value(t, err, nil)
		testing.expectf(t, got == c.want, "upper_allocated(%q) = %q, want %q", c.input, got, c.want)
	}
	for input in UNCHANGED {
		got, _ := ascii.upper_allocated(input)
		defer delete(got)
		testing.expectf(t, got == input, "upper_allocated(%q) changed a non-letter", input)
	}
}

@(test)
test_lower_buffer :: proc(t: ^testing.T) {
	for c in LOWER_CASES {
		buffer: [8]u8
		got := ascii.lower_buffer(buffer[:], c.input)
		testing.expectf(t, got == c.want, "lower_buffer(%q) = %q, want %q", c.input, got, c.want)
		testing.expectf(t, len(got) == len(c.input), "lower_buffer(%q) has length %d", c.input, len(got))
	}
	for input in UNCHANGED {
		buffer: [8]u8
		testing.expectf(t, ascii.lower_buffer(buffer[:], input) == input, "lower_buffer(%q) changed a non-letter", input)
	}
}

@(test)
test_lower_allocated :: proc(t: ^testing.T) {
	for c in LOWER_CASES {
		got, err := ascii.lower_allocated(c.input)
		defer delete(got)
		testing.expect_value(t, err, nil)
		testing.expectf(t, got == c.want, "lower_allocated(%q) = %q, want %q", c.input, got, c.want)
	}
	for input in UNCHANGED {
		got, _ := ascii.lower_allocated(input)
		defer delete(got)
		testing.expectf(t, got == input, "lower_allocated(%q) changed a non-letter", input)
	}
}

@(test)
test_is_letters :: proc(t: ^testing.T) {
	for input in ([?]string{"", "a", "Z", "abc", "aBcXyZ"}) {
		testing.expectf(t, ascii.is_letters(input), "is_letters(%q) = false, want true", input)
	}
	for input in ([?]string{"@", "[", "`", "{", "0", "9", "-", " ", "ab1", "1ab", "a-b", "é", "\x00", "\x7f", "\xff"}) {
		testing.expectf(t, !ascii.is_letters(input), "is_letters(%q) = true, want false", input)
	}
}

@(test)
test_is_digits :: proc(t: ^testing.T) {
	for input in ([?]string{"", "0", "9", "840", "0123456789"}) {
		testing.expectf(t, ascii.is_digits(input), "is_digits(%q) = false, want true", input)
	}
	// '/' and ':' are the bytes on each side of '0'..'9'.
	for input in ([?]string{"/", ":", "a", "A", "-", " ", "+1", "12a", "a12", "1 2", "٣", "\x00", "\xff"}) {
		testing.expectf(t, !ascii.is_digits(input), "is_digits(%q) = true, want false", input)
	}
}

// upper and lower are proc groups over the buffer and allocated variants.
@(test)
test_groups :: proc(t: ^testing.T) {
	buffer: [3]u8
	testing.expect_value(t, ascii.upper(buffer[:], "aBc"), "ABC")
	testing.expect_value(t, ascii.lower(buffer[:], "aBc"), "abc")

	upper, upper_err := ascii.upper("aBc")
	defer delete(upper)
	testing.expect_value(t, upper_err, nil)
	testing.expect_value(t, upper, "ABC")

	lower, lower_err := ascii.lower("aBc", context.allocator)
	defer delete(lower)
	testing.expect_value(t, lower_err, nil)
	testing.expect_value(t, lower, "abc")
}
