package chrono_test

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:testing"

import chrono "../"

Duration_Text_Case :: struct {
	duration: chrono.Duration,
	text:     string,
}

// Every text here is what Java's Duration.toString() writes, checked against Java itself. A
// negative duration puts the minus on every part.
DURATION_TEXT_CASES :: [?]Duration_Text_Case {
	{{0, 0}, "PT0S"},
	{{1, 0}, "PT1S"},
	{{59, 0}, "PT59S"},
	{{60, 0}, "PT1M"},
	{{61, 0}, "PT1M1S"},
	{{90, 0}, "PT1M30S"},
	{{3_599, 0}, "PT59M59S"},
	{{3_600, 0}, "PT1H"},
	{{3_601, 0}, "PT1H1S"},
	{{3_605, 0}, "PT1H5S"},
	{{5_400, 0}, "PT1H30M"},
	{{3_661, 0}, "PT1H1M1S"},
	{{86_399, 0}, "PT23H59M59S"},
	// Hours only: a day is not always 24 hours.
	{{86_400, 0}, "PT24H"},
	{{172_800, 0}, "PT48H"},
	// Fractions: trailing zeros trimmed, a zero second part still shows before a fraction.
	{{0, 500_000_000}, "PT0.5S"},
	{{0, 120_000_000}, "PT0.12S"},
	{{1, 500_000_000}, "PT1.5S"},
	{{0, 1}, "PT0.000000001S"},
	{{0, 999_999_999}, "PT0.999999999S"},
	{{3_661, 1}, "PT1H1M1.000000001S"},
	{{60, 500_000_000}, "PT1M0.5S"},
	{{3_600, 500_000_000}, "PT1H0.5S"},
	// Negative: the minus goes on every part.
	{{-1, 0}, "PT-1S"},
	{{-60, 0}, "PT-1M"},
	{{-3_600, 0}, "PT-1H"},
	{{-5_400, 0}, "PT-1H-30M"},
	{{-86_400, 0}, "PT-24H"},
	// Minus half a second is stored as {-1, 500_000_000}.
	{{-1, 500_000_000}, "PT-0.5S"},
	{{-1, 750_000_000}, "PT-0.25S"},
	{{-1, 999_999_999}, "PT-0.000000001S"},
	{{-2, 750_000_000}, "PT-1.25S"},
	{{-90, 250_000_000}, "PT-1M-29.75S"},
	{{-61, 500_000_000}, "PT-1M-0.5S"},
	// The two extremes.
	{{chrono.DURATION_SECONDS_MAX, 999_999_999}, "PT17531631215H59M59.999999999S"},
	{{chrono.DURATION_SECONDS_MAX, 0}, "PT17531631215H59M59S"},
	{{chrono.DURATION_SECONDS_MIN, 0}, "PT-17531631216H"},
	{{chrono.DURATION_SECONDS_MIN, 1}, "PT-17531631215H-59M-59.999999999S"},
}

@(test)
test_duration_bprint_known_values :: proc(t: ^testing.T) {
	for entry in DURATION_TEXT_CASES {
		buffer: [chrono.DURATION_TEXT_MAX]u8
		testing.expect_value(t, chrono.duration_bprint(buffer[:], entry.duration), entry.text)
	}
}

@(test)
test_duration_text_max_is_the_longest_text :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.DURATION_TEXT_MAX, 33)

	// -(max seconds) plus one nanosecond has a magnitude of max - 1 seconds and 999_999_999 ns,
	// which prints with 59 minutes, 58 seconds and the longest fraction.
	buffer: [chrono.DURATION_TEXT_MAX]u8
	text := chrono.duration_bprint(buffer[:], {-chrono.DURATION_SECONDS_MAX, 1})
	testing.expect_value(t, text, "PT-17531631215H-59M-58.999999999S")

	// The longest text is the most negative duration with a one nanosecond fraction: 11 hour
	// digits, 59 minutes, 59 seconds, 9 fraction digits, and a minus before each of the three.
	text = chrono.duration_bprint(buffer[:], {chrono.DURATION_SECONDS_MIN, 1})
	testing.expect_value(t, text, "PT-17531631215H-59M-59.999999999S")
	testing.expect_value(t, len(text), chrono.DURATION_TEXT_MAX)

	// Nothing is longer: try the extreme seconds near both ends with every kind of fraction.
	fractions := [?]u32{0, 1, 10, 500_000_000, 999_999_999}
	for offset in i64(0) ..< 3_700 {
		for fraction in fractions {
			for seconds in ([?]i64{chrono.DURATION_SECONDS_MAX - offset, chrono.DURATION_SECONDS_MIN + offset}) {
				duration := chrono.Duration{seconds, fraction}
				if chrono.duration_is_valid(duration) {
					testing.expect(
						t,
						len(chrono.duration_bprint(buffer[:], duration)) <=
						chrono.DURATION_TEXT_MAX,
					)
				}
			}
		}
	}
}

// A negative text is the text of the negated duration with a minus put before every number.
@(test)
test_duration_negative_text_has_a_minus_before_every_number :: proc(t: ^testing.T) {
	seconds_list := [?]i64{0, 1, 59, 60, 3_599, 3_600, 86_400, 1_000_000, 987_654_321}
	nanoseconds_list := [?]u32{0, 1, 500_000_000, 999_999_999, 120_000_000}
	for seconds in seconds_list {
		for nanoseconds in nanoseconds_list {
			positive := chrono.Duration{seconds, nanoseconds}
			if positive == {} {
				continue
			}
			negated, ok := chrono.duration_negate(positive)
			testing.expect(t, ok)

			positive_buffer: [chrono.DURATION_TEXT_MAX]u8
			negated_buffer: [chrono.DURATION_TEXT_MAX]u8
			positive_text := chrono.duration_bprint(positive_buffer[:], positive)
			negated_text := chrono.duration_bprint(negated_buffer[:], negated)

			// Build the expectation from the positive text: "PT" stays, then each number
			// (a run of digits and dots) gets a minus in front.
			expected_builder: strings.Builder
			strings.builder_init(&expected_builder)
			defer strings.builder_destroy(&expected_builder)
			previous_was_number := false
			for character in positive_text {
				is_number_character := (character >= '0' && character <= '9') || character == '.'
				if is_number_character && !previous_was_number {
					strings.write_byte(&expected_builder, '-')
				}
				strings.write_rune(&expected_builder, character)
				previous_was_number = is_number_character
			}
			testing.expect_value(t, negated_text, strings.to_string(expected_builder))
		}
	}
}

@(test)
test_duration_bprint_zero_has_no_sign_and_no_parts :: proc(t: ^testing.T) {
	buffer: [chrono.DURATION_TEXT_MAX]u8
	testing.expect_value(t, chrono.duration_bprint(buffer[:], {}), "PT0S")
	// Just under zero is a tiny negative amount, not zero.
	testing.expect_value(
		t,
		chrono.duration_bprint(buffer[:], {-1, 999_999_999}),
		"PT-0.000000001S",
	)
}

// The unit boundaries are where parts appear and disappear.
@(test)
test_duration_bprint_unit_boundaries :: proc(t: ^testing.T) {
	boundaries := [?]Duration_Text_Case {
		{{59, 999_999_999}, "PT59.999999999S"},
		{{60, 0}, "PT1M"},
		{{3_599, 999_999_999}, "PT59M59.999999999S"},
		{{3_600, 0}, "PT1H"},
		{{86_399, 999_999_999}, "PT23H59M59.999999999S"},
		{{86_400, 0}, "PT24H"},
	}
	for entry in boundaries {
		buffer: [chrono.DURATION_TEXT_MAX]u8
		testing.expect_value(t, chrono.duration_bprint(buffer[:], entry.duration), entry.text)
	}
}

@(test)
test_duration_bprint_leaves_the_rest_of_the_buffer_alone :: proc(t: ^testing.T) {
	buffer: [40]u8
	for &byte in buffer {
		byte = '#'
	}
	text := chrono.duration_bprint(buffer[:], {-90, 250_000_000})
	testing.expect_value(t, text, "PT-1M-29.75S")
	for byte in buffer[len(text):] {
		testing.expect_value(t, byte, '#')
	}
}

@(test)
test_duration_bprint_accepts_a_buffer_of_exactly_the_maximum :: proc(t: ^testing.T) {
	buffer: [chrono.DURATION_TEXT_MAX]u8
	text := chrono.duration_bprint(buffer[:], {chrono.DURATION_SECONDS_MAX, 999_999_999})
	testing.expect_value(t, text, "PT17531631215H59M59.999999999S")
}

// The magnitude arithmetic is what could go wrong, so check the text against a second
// computation from the same duration, with the units rebuilt from the printed numbers.
@(test)
test_duration_text_rebuilds_the_duration :: proc(t: ^testing.T) {
	durations := [?]chrono.Duration {
		{3_661, 1},
		{-3_661, 1},
		{-1, 1},
		{-1, 999_999_999},
		{987_654_321, 123_456_789},
		{-987_654_321, 123_456_789},
		{chrono.DURATION_SECONDS_MAX, 999_999_999},
		{chrono.DURATION_SECONDS_MIN, 1},
	}
	for duration in durations {
		buffer: [chrono.DURATION_TEXT_MAX]u8
		text := chrono.duration_bprint(buffer[:], duration)

		// The minus is before every number, so one minus anywhere means the whole duration is
		// negative. Strip them all and read the magnitude.
		negative := strings.contains_rune(text, '-')
		unsigned_text, _ := strings.remove_all(text, "-", context.temp_allocator)
		body := unsigned_text[2:] // after "PT"
		hours, minutes, seconds, nanoseconds: u64
		rest := body
		if index := strings.index_byte(rest, 'H'); index >= 0 {
			hours = parse_digits(rest[:index])
			rest = rest[index + 1:]
		}
		if index := strings.index_byte(rest, 'M'); index >= 0 {
			minutes = parse_digits(rest[:index])
			rest = rest[index + 1:]
		}
		if index := strings.index_byte(rest, 'S'); index >= 0 {
			number := rest[:index]
			if dot := strings.index_byte(number, '.'); dot >= 0 {
				seconds = parse_digits(number[:dot])
				fraction := number[dot + 1:]
				nanoseconds = parse_digits(fraction)
				for _ in len(fraction) ..< 9 {
					nanoseconds *= 10
				}
			} else {
				seconds = parse_digits(number)
			}
		}

		magnitude_seconds := i64(hours * 3_600 + minutes * 60 + seconds)
		rebuilt := chrono.Duration{magnitude_seconds, u32(nanoseconds)}
		if negative {
			rebuilt, _ = chrono.duration_negate(rebuilt)
		}
		testing.expect_value(t, rebuilt, duration)
	}
}

parse_digits :: proc(digits: string) -> u64 {
	value: u64
	for character in digits {
		value = value * 10 + u64(character - '0')
	}
	return value
}

@(test)
test_duration_aprint :: proc(t: ^testing.T) {
	for entry in DURATION_TEXT_CASES {
		text := chrono.duration_aprint(entry.duration)
		defer delete(text)
		testing.expect_value(t, text, entry.text)
	}
}

@(test)
test_duration_tprint :: proc(t: ^testing.T) {
	for entry in DURATION_TEXT_CASES {
		testing.expect_value(t, chrono.duration_tprint(entry.duration), entry.text)
	}
	free_all(context.temp_allocator)
}

@(test)
test_duration_caprint :: proc(t: ^testing.T) {
	for entry in DURATION_TEXT_CASES {
		text := chrono.duration_caprint(entry.duration)
		defer delete(text)
		testing.expect_value(t, string(text), entry.text)
		testing.expect_value(t, (cast([^]u8)text)[len(entry.text)], 0)
	}
}

@(test)
test_duration_sbprint_returns_only_what_it_appended :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "took ")
	first := chrono.duration_sbprint(&builder, {5_400, 0})
	testing.expect_value(t, first, "PT1H30M")
	strings.write_string(&builder, ", then ")
	second := chrono.duration_sbprint(&builder, {-1, 500_000_000})
	testing.expect_value(t, second, "PT-0.5S")
	testing.expect_value(t, strings.to_string(builder), "took PT1H30M, then PT-0.5S")
}

@(test)
test_duration_wprint :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	writer := strings.to_writer(&builder)
	testing.expect_value(t, chrono.duration_wprint(writer, {90, 0}), 7)
	testing.expect_value(t, chrono.duration_wprint(writer, {-1, 500_000_000}), 7)
	testing.expect_value(t, strings.to_string(builder), "PT1M30SPT-0.5S")
}

@(test)
test_duration_wprint_reports_what_was_written_when_the_writer_fails :: proc(t: ^testing.T) {
	// A fixed size stream that holds 4 bytes: the write stops there and the count says so.
	storage: [4]u8
	writer := io.Writer {
		procedure = proc(
			stream_data: rawptr,
			mode: io.Stream_Mode,
			p: []byte,
			offset: i64,
			whence: io.Seek_From,
		) -> (
			n: i64,
			err: io.Error,
		) {
			if mode == .Write {
				storage_ptr := cast(^[4]u8)stream_data
				count := min(len(p), len(storage_ptr))
				copy(storage_ptr[:count], p[:count])
				if count < len(p) {
					return i64(count), .Short_Write
				}
				return i64(count), nil
			}
			return 0, .Empty
		},
		data = &storage,
	}
	written := chrono.duration_wprint(writer, {5_400, 0})
	testing.expect_value(t, written, 4)
	testing.expect_value(t, string(storage[:]), "PT1H")
}

@(test)
test_duration_fprint_writes_to_the_file :: proc(t: ^testing.T) {
	file, create_error := os.create_temp_file("", "chrono_format_duration_*")
	testing.expect_value(t, create_error, nil)
	if create_error != nil {
		return
	}
	name := strings.clone(os.name(file))
	defer delete(name)
	defer os.remove(name)

	testing.expect_value(t, chrono.duration_fprint(file, {5_400, 0}), 7)
	testing.expect_value(t, chrono.duration_fprint(file, {-1, 500_000_000}), 7)
	testing.expect_value(t, os.close(file), nil)

	data, read_error := os.read_entire_file(name, context.allocator)
	defer delete(data)
	testing.expect_value(t, read_error, nil)
	testing.expect_value(t, string(data), "PT1H30MPT-0.5S")
}

// Standard output and error cannot be captured here, so only the count is checked.
@(test)
test_duration_print_and_eprint_return_the_length :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.duration_print({5_400, 0}), 7)
	testing.expect_value(t, chrono.duration_eprint({-90, 250_000_000}), 12)
}

@(test)
test_duration_every_print_proc_produces_the_same_text :: proc(t: ^testing.T) {
	for entry in DURATION_TEXT_CASES {
		buffer: [chrono.DURATION_TEXT_MAX]u8
		expected := chrono.duration_bprint(buffer[:], entry.duration)

		allocated := chrono.duration_aprint(entry.duration)
		defer delete(allocated)
		testing.expect_value(t, allocated, expected)
		testing.expect_value(t, chrono.duration_tprint(entry.duration), expected)

		c_text := chrono.duration_caprint(entry.duration)
		defer delete(c_text)
		testing.expect_value(t, string(c_text), expected)

		builder: strings.Builder
		strings.builder_init(&builder)
		defer strings.builder_destroy(&builder)
		testing.expect_value(t, chrono.duration_sbprint(&builder, entry.duration), expected)
		testing.expect_value(
			t,
			chrono.duration_wprint(strings.to_writer(&builder), entry.duration),
			len(expected),
		)
	}
	free_all(context.temp_allocator)
}
