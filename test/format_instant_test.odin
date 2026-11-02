package chrono_test

import "core:io"
import "core:os"
import "core:strings"
import "core:testing"

import chrono "../"

Instant_Text_Case :: struct {
	instant: chrono.Instant,
	text:    string,
}

// Expected texts were built from Python's calendar, and Java's Instant.parse reads every one
// back to the same seconds and nanoseconds.
INSTANT_TEXT_CASES :: [?]Instant_Text_Case {
	{{0, 0}, "1970-01-01T00:00:00Z"},
	{{1, 0}, "1970-01-01T00:00:01Z"},
	{{86_399, 0}, "1970-01-01T23:59:59Z"},
	{{86_400, 0}, "1970-01-02T00:00:00Z"},
	{{1_793_474_051, 660_596_000}, "2026-10-31T19:14:11.660596Z"},
	{{1_793_543_400, 500_000_000}, "2026-11-01T14:30:00.5Z"},
	{{951_782_400, 0}, "2000-02-29T00:00:00Z"},
	{{951_868_800, 0}, "2000-03-01T00:00:00Z"},
	// Fractions: trailing zeros trimmed.
	{{0, 500_000_000}, "1970-01-01T00:00:00.5Z"},
	{{0, 120_000_000}, "1970-01-01T00:00:00.12Z"},
	{{0, 1_000_000}, "1970-01-01T00:00:00.001Z"},
	{{0, 1_000}, "1970-01-01T00:00:00.000001Z"},
	{{0, 1}, "1970-01-01T00:00:00.000000001Z"},
	// One nanosecond before the epoch is the last instant of 1969.
	{{-1, 999_999_999}, "1969-12-31T23:59:59.999999999Z"},
	// Years around 0 and the 4 digit limit.
	{{-62_135_596_800, 0}, "0001-01-01T00:00:00Z"},
	{{-62_167_219_200, 0}, "0000-01-01T00:00:00Z"},
	{{-62_167_219_201, 0}, "-0001-12-31T23:59:59Z"},
	{{253_402_300_799, 999_999_999}, "9999-12-31T23:59:59.999999999Z"},
	{{253_402_300_800, 0}, "+10000-01-01T00:00:00Z"},
	// Both ends of the supported range, the longest texts there are.
	{{chrono.INSTANT_SECONDS_MIN, 0}, "-999999-01-01T00:00:00Z"},
	{{chrono.INSTANT_SECONDS_MIN, 1}, "-999999-01-01T00:00:00.000000001Z"},
	{{chrono.INSTANT_SECONDS_MAX, 0}, "+999999-12-31T23:59:59Z"},
	{{chrono.INSTANT_SECONDS_MAX, 999_999_999}, "+999999-12-31T23:59:59.999999999Z"},
}

@(test)
test_instant_bprint_known_values :: proc(t: ^testing.T) {
	for entry in INSTANT_TEXT_CASES {
		buffer: [chrono.INSTANT_TEXT_MAX]u8
		testing.expect_value(t, chrono.instant_bprint(buffer[:], entry.instant), entry.text)
	}
}

@(test)
test_instant_text_max_is_the_longest_text :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.INSTANT_TEXT_MAX, 33)
	testing.expect_value(
		t,
		chrono.INSTANT_TEXT_MAX,
		chrono.LOCAL_DATE_TEXT_MAX + 1 + chrono.LOCAL_TIME_TEXT_MAX + 1,
	)

	buffer: [chrono.INSTANT_TEXT_MAX]u8
	longest := chrono.instant_bprint(buffer[:], {chrono.INSTANT_SECONDS_MAX, 999_999_999})
	testing.expect_value(t, len(longest), 33)

	// Nothing is longer: the first and last days with every kind of fraction.
	fractions := [?]u32{0, 1, 500_000_000, 999_999_999}
	for offset in i64(0) ..< 90_000 {
		for fraction in fractions {
			for seconds in ([?]i64{chrono.INSTANT_SECONDS_MIN + offset, chrono.INSTANT_SECONDS_MAX - offset}) {
				text := chrono.instant_bprint(buffer[:], {seconds, fraction})
				testing.expect(t, len(text) <= chrono.INSTANT_TEXT_MAX)
			}
		}
	}
}

// The text is the date, a T, the time and a Z: the same pieces the two formatters write alone.
@(test)
test_instant_bprint_is_the_date_and_time_text_joined :: proc(t: ^testing.T) {
	instants := [?]chrono.Instant {
		{0, 0},
		{1_793_474_051, 660_596_000},
		{-1, 999_999_999},
		{253_402_300_800, 5},
		{chrono.INSTANT_SECONDS_MIN, 0},
	}
	for instant in instants {
		date_time, ok := chrono.instant_to_local_date_time(instant, chrono.ZONE_OFFSET_UTC)
		testing.expect(t, ok)

		buffer: [chrono.INSTANT_TEXT_MAX]u8
		date_buffer: [chrono.LOCAL_DATE_TEXT_MAX]u8
		time_buffer: [chrono.LOCAL_TIME_TEXT_MAX]u8
		expected := strings.concatenate(
			{
				chrono.local_date_bprint(date_buffer[:], date_time.date),
				"T",
				chrono.local_time_bprint(time_buffer[:], date_time.time),
				"Z",
			},
			context.temp_allocator,
		)
		testing.expect_value(t, chrono.instant_bprint(buffer[:], instant), expected)
	}
	free_all(context.temp_allocator)
}

// For years 0 to 9999 text order is instant order. Outside that range it is not, which is the
// reason the doc comment warns about it, so this pins down both halves.
@(test)
test_instant_text_order_matches_instant_order_only_for_years_0_to_9999 :: proc(t: ^testing.T) {
	buffer_a: [chrono.INSTANT_TEXT_MAX]u8
	buffer_b: [chrono.INSTANT_TEXT_MAX]u8
	seconds_list := [?]i64 {
		-62_167_219_200,
		-1,
		0,
		1,
		86_400,
		951_782_400,
		1_793_543_400,
		253_402_300_799,
	}
	for first in seconds_list {
		for second in seconds_list {
			text_a := chrono.instant_bprint(buffer_a[:], {first, 0})
			text_b := chrono.instant_bprint(buffer_b[:], {second, 0})
			text_order: chrono.Ordering =
				.less if text_a < text_b else (.greater if text_a > text_b else .equal)
			testing.expect_value(t, text_order, chrono.instant_compare({first, 0}, {second, 0}))
		}
	}

	// Signed years break it: +10000 sorts before 0000, and -0001 sorts before -0005.
	plus := chrono.instant_bprint(buffer_a[:], {253_402_300_800, 0})
	zero := chrono.instant_bprint(buffer_b[:], {-62_167_219_200, 0})
	testing.expect(t, plus < zero)
	testing.expect(t, chrono.instant_is_after({253_402_300_800, 0}, {-62_167_219_200, 0}))
}

@(test)
test_instant_bprint_leaves_the_rest_of_the_buffer_alone :: proc(t: ^testing.T) {
	buffer: [50]u8
	for &byte in buffer {
		byte = '#'
	}
	text := chrono.instant_bprint(buffer[:], {1_793_543_400, 500_000_000})
	testing.expect_value(t, text, "2026-11-01T14:30:00.5Z")
	for byte in buffer[len(text):] {
		testing.expect_value(t, byte, '#')
	}
}

@(test)
test_instant_aprint :: proc(t: ^testing.T) {
	for entry in INSTANT_TEXT_CASES {
		text := chrono.instant_aprint(entry.instant)
		defer delete(text)
		testing.expect_value(t, text, entry.text)
	}
}

@(test)
test_instant_tprint :: proc(t: ^testing.T) {
	for entry in INSTANT_TEXT_CASES {
		testing.expect_value(t, chrono.instant_tprint(entry.instant), entry.text)
	}
	free_all(context.temp_allocator)
}

@(test)
test_instant_caprint :: proc(t: ^testing.T) {
	for entry in INSTANT_TEXT_CASES {
		text := chrono.instant_caprint(entry.instant)
		defer delete(text)
		testing.expect_value(t, string(text), entry.text)
		testing.expect_value(t, (cast([^]u8)text)[len(entry.text)], 0)
	}
}

@(test)
test_instant_sbprint_returns_only_what_it_appended :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "a ")
	first := chrono.instant_sbprint(&builder, {1_793_543_400, 500_000_000})
	testing.expect_value(t, first, "2026-11-01T14:30:00.5Z")
	strings.write_string(&builder, " b ")
	second := chrono.instant_sbprint(&builder, {0, 0})
	testing.expect_value(t, second, "1970-01-01T00:00:00Z")
	expected := strings.concatenate(
		{"a ", "2026-11-01T14:30:00.5Z", " b ", "1970-01-01T00:00:00Z"},
		context.temp_allocator,
	)
	testing.expect_value(t, strings.to_string(builder), expected)
	free_all(context.temp_allocator)
}

@(test)
test_instant_wprint :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	writer := strings.to_writer(&builder)
	testing.expect_value(
		t,
		chrono.instant_wprint(writer, {1_793_543_400, 500_000_000}),
		len("2026-11-01T14:30:00.5Z"),
	)
	testing.expect_value(t, chrono.instant_wprint(writer, {0, 0}), len("1970-01-01T00:00:00Z"))
	expected := strings.concatenate(
		{"2026-11-01T14:30:00.5Z", "1970-01-01T00:00:00Z"},
		context.temp_allocator,
	)
	testing.expect_value(t, strings.to_string(builder), expected)
	free_all(context.temp_allocator)
}

@(test)
test_instant_wprint_reports_what_was_written_when_the_writer_fails :: proc(t: ^testing.T) {
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
	written := chrono.instant_wprint(writer, {1_793_543_400, 500_000_000})
	testing.expect_value(t, written, 4)
	testing.expect_value(t, string(storage[:]), "2026-11-01T14:30:00.5Z"[:4])
}

@(test)
test_instant_fprint_writes_to_the_file :: proc(t: ^testing.T) {
	file, create_error := os.create_temp_file("", "chrono_format_instant_*")
	testing.expect_value(t, create_error, nil)
	if create_error != nil {
		return
	}
	name := strings.clone(os.name(file))
	defer delete(name)
	defer os.remove(name)

	testing.expect_value(
		t,
		chrono.instant_fprint(file, {1_793_543_400, 500_000_000}),
		len("2026-11-01T14:30:00.5Z"),
	)
	testing.expect_value(t, chrono.instant_fprint(file, {0, 0}), len("1970-01-01T00:00:00Z"))
	testing.expect_value(t, os.close(file), nil)

	data, read_error := os.read_entire_file(name, context.allocator)
	defer delete(data)
	testing.expect_value(t, read_error, nil)
	expected := strings.concatenate(
		{"2026-11-01T14:30:00.5Z", "1970-01-01T00:00:00Z"},
		context.temp_allocator,
	)
	testing.expect_value(t, string(data), expected)
	free_all(context.temp_allocator)
}

// Standard output and error cannot be captured here, so only the count is checked.
@(test)
test_instant_print_and_eprint_return_the_length :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.instant_print({1_793_543_400, 500_000_000}),
		len("2026-11-01T14:30:00.5Z"),
	)
	testing.expect_value(t, chrono.instant_eprint({0, 0}), len("1970-01-01T00:00:00Z"))
}

@(test)
test_instant_every_print_proc_produces_the_same_text :: proc(t: ^testing.T) {
	for entry in INSTANT_TEXT_CASES {
		buffer: [chrono.INSTANT_TEXT_MAX]u8
		expected := chrono.instant_bprint(buffer[:], entry.instant)

		allocated := chrono.instant_aprint(entry.instant)
		defer delete(allocated)
		testing.expect_value(t, allocated, expected)
		testing.expect_value(t, chrono.instant_tprint(entry.instant), expected)

		c_text := chrono.instant_caprint(entry.instant)
		defer delete(c_text)
		testing.expect_value(t, string(c_text), expected)

		builder: strings.Builder
		strings.builder_init(&builder)
		defer strings.builder_destroy(&builder)
		testing.expect_value(t, chrono.instant_sbprint(&builder, entry.instant), expected)
		testing.expect_value(
			t,
			chrono.instant_wprint(strings.to_writer(&builder), entry.instant),
			len(expected),
		)
	}
	free_all(context.temp_allocator)
}
