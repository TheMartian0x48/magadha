package chrono_test

import "core:io"
import "core:os"
import "core:strings"
import "core:testing"

import chrono "../"

Date_Time_Text_Case :: struct {
	date_time: chrono.Local_Date_Time,
	text:      string,
}

// Java's LocalDateTime.parse reads every text here back to the same value. Java's own toString
// drops zero seconds (`2026-11-01T14:30`), which this library always writes.
LOCAL_DATE_TIME_TEXT_CASES :: [?]Date_Time_Text_Case {
	{{{2026, .november, 1}, {14, 30, 0, 0}}, "2026-11-01T14:30:00"},
	{{{2026, .november, 1}, {0, 0, 0, 0}}, "2026-11-01T00:00:00"},
	{{{2026, .november, 1}, {14, 30, 5, 0}}, "2026-11-01T14:30:05"},
	{{{2026, .november, 1}, {23, 59, 59, 0}}, "2026-11-01T23:59:59"},
	{{{1970, .january, 1}, {0, 0, 0, 0}}, "1970-01-01T00:00:00"},
	{{{2024, .february, 29}, {12, 0, 0, 0}}, "2024-02-29T12:00:00"},
	// Fractions: trailing zeros trimmed.
	{{{2026, .november, 1}, {14, 30, 0, 500_000_000}}, "2026-11-01T14:30:00.5"},
	{{{2026, .november, 1}, {14, 30, 0, 120_000_000}}, "2026-11-01T14:30:00.12"},
	{{{2026, .november, 1}, {14, 30, 0, 1_000_000}}, "2026-11-01T14:30:00.001"},
	{{{2026, .november, 1}, {0, 0, 0, 1}}, "2026-11-01T00:00:00.000000001"},
	{{{2026, .november, 1}, {23, 59, 59, 999_999_999}}, "2026-11-01T23:59:59.999999999"},
	// Years: padded to 4 digits, and signed outside 0 to 9999.
	{{{5, .march, 7}, {1, 2, 3, 0}}, "0005-03-07T01:02:03"},
	{{{0, .january, 1}, {0, 0, 0, 0}}, "0000-01-01T00:00:00"},
	{{{-1, .december, 31}, {23, 59, 59, 999_999_999}}, "-0001-12-31T23:59:59.999999999"},
	{{{-5, .march, 7}, {0, 0, 0, 0}}, "-0005-03-07T00:00:00"},
	{{{9999, .december, 31}, {23, 59, 59, 0}}, "9999-12-31T23:59:59"},
	{{{10_000, .january, 1}, {0, 0, 0, 0}}, "+10000-01-01T00:00:00"},
	{{{12_345, .june, 15}, {6, 7, 8, 9}}, "+12345-06-15T06:07:08.000000009"},
	// Both ends of the supported range, the longest texts there are.
	{chrono.LOCAL_DATE_TIME_MIN, "-999999-01-01T00:00:00"},
	{chrono.LOCAL_DATE_TIME_MAX, "+999999-12-31T23:59:59.999999999"},
}

@(test)
test_local_date_time_bprint_known_values :: proc(t: ^testing.T) {
	for entry in LOCAL_DATE_TIME_TEXT_CASES {
		buffer: [chrono.LOCAL_DATE_TIME_TEXT_MAX]u8
		testing.expect_value(
			t,
			chrono.local_date_time_bprint(buffer[:], entry.date_time),
			entry.text,
		)
	}
}

@(test)
test_local_date_time_text_max_is_the_longest_text :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.LOCAL_DATE_TIME_TEXT_MAX, 32)
	testing.expect_value(
		t,
		chrono.LOCAL_DATE_TIME_TEXT_MAX,
		chrono.LOCAL_DATE_TEXT_MAX + 1 + chrono.LOCAL_TIME_TEXT_MAX,
	)

	buffer: [chrono.LOCAL_DATE_TIME_TEXT_MAX]u8
	text := chrono.local_date_time_bprint(buffer[:], chrono.LOCAL_DATE_TIME_MAX)
	testing.expect_value(t, len(text), 32)
	testing.expect_value(
		t,
		len(chrono.local_date_time_bprint(buffer[:], chrono.LOCAL_DATE_TIME_MIN)),
		22,
	)

	// Nothing is longer: the first and last days with every kind of fraction.
	fractions := [?]u32{0, 1, 500_000_000, 999_999_999}
	for offset in i64(0) ..< 3_000 {
		for fraction in fractions {
			first, first_ok := chrono.local_date_plus_days(chrono.LOCAL_DATE_MIN, offset)
			last, last_ok := chrono.local_date_plus_days(chrono.LOCAL_DATE_MAX, -offset)
			testing.expect(t, first_ok && last_ok)
			for date in ([?]chrono.Local_Date{first, last}) {
				time := chrono.Local_Time{23, 59, 59, fraction}
				testing.expect(
					t,
					len(chrono.local_date_time_bprint(buffer[:], {date, time})) <=
					chrono.LOCAL_DATE_TIME_TEXT_MAX,
				)
			}
		}
	}
}

// The text is the date text, a T and the time text: the same pieces the two formatters write alone.
@(test)
test_local_date_time_bprint_is_the_date_and_time_text_joined :: proc(t: ^testing.T) {
	values := [?]chrono.Local_Date_Time {
		{{2026, .november, 1}, {14, 30, 0, 500_000_000}},
		{{-5, .march, 7}, {0, 0, 0, 1}},
		{{10_000, .january, 1}, {23, 59, 59, 0}},
		chrono.LOCAL_DATE_TIME_MIN,
		chrono.LOCAL_DATE_TIME_MAX,
	}
	for value in values {
		buffer: [chrono.LOCAL_DATE_TIME_TEXT_MAX]u8
		date_buffer: [chrono.LOCAL_DATE_TEXT_MAX]u8
		time_buffer: [chrono.LOCAL_TIME_TEXT_MAX]u8
		expected := strings.concatenate(
			{
				chrono.local_date_bprint(date_buffer[:], value.date),
				"T",
				chrono.local_time_bprint(time_buffer[:], value.time),
			},
			context.temp_allocator,
		)
		testing.expect_value(t, chrono.local_date_time_bprint(buffer[:], value), expected)
	}
	free_all(context.temp_allocator)
}

// The seconds are written even when they are zero, so a whole minute has seconds in its text.
@(test)
test_local_date_time_bprint_always_writes_the_seconds :: proc(t: ^testing.T) {
	buffer: [chrono.LOCAL_DATE_TIME_TEXT_MAX]u8
	testing.expect_value(
		t,
		chrono.local_date_time_bprint(buffer[:], {{2026, .november, 1}, {14, 30, 0, 0}}),
		"2026-11-01T14:30:00",
	)
	testing.expect_value(
		t,
		chrono.local_date_time_bprint(buffer[:], {{2026, .november, 1}, {}}),
		"2026-11-01T00:00:00",
	)
}

@(test)
test_local_date_time_bprint_leaves_the_rest_of_the_buffer_alone :: proc(t: ^testing.T) {
	buffer: [50]u8
	for &byte in buffer {
		byte = '#'
	}
	text := chrono.local_date_time_bprint(
		buffer[:],
		{{2026, .november, 1}, {14, 30, 0, 500_000_000}},
	)
	testing.expect_value(t, text, "2026-11-01T14:30:00.5")
	for byte in buffer[len(text):] {
		testing.expect_value(t, byte, '#')
	}
}

@(test)
test_local_date_time_bprint_accepts_a_buffer_of_exactly_the_maximum :: proc(t: ^testing.T) {
	buffer: [chrono.LOCAL_DATE_TIME_TEXT_MAX]u8
	testing.expect_value(
		t,
		chrono.local_date_time_bprint(buffer[:], chrono.LOCAL_DATE_TIME_MAX),
		"+999999-12-31T23:59:59.999999999",
	)
}

@(test)
test_local_date_time_aprint :: proc(t: ^testing.T) {
	for entry in LOCAL_DATE_TIME_TEXT_CASES {
		text := chrono.local_date_time_aprint(entry.date_time)
		defer delete(text)
		testing.expect_value(t, text, entry.text)
	}
}

@(test)
test_local_date_time_tprint :: proc(t: ^testing.T) {
	for entry in LOCAL_DATE_TIME_TEXT_CASES {
		testing.expect_value(t, chrono.local_date_time_tprint(entry.date_time), entry.text)
	}
	free_all(context.temp_allocator)
}

@(test)
test_local_date_time_caprint :: proc(t: ^testing.T) {
	for entry in LOCAL_DATE_TIME_TEXT_CASES {
		text := chrono.local_date_time_caprint(entry.date_time)
		defer delete(text)
		testing.expect_value(t, string(text), entry.text)
		testing.expect_value(t, (cast([^]u8)text)[len(entry.text)], 0)
	}
}

@(test)
test_local_date_time_sbprint_returns_only_what_it_appended :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "a ")
	first := chrono.local_date_time_sbprint(
		&builder,
		chrono.Local_Date_Time{{2026, .november, 1}, {14, 30, 0, 500_000_000}},
	)
	testing.expect_value(t, first, "2026-11-01T14:30:00.5")
	strings.write_string(&builder, " b ")
	second := chrono.local_date_time_sbprint(&builder, chrono.Local_Date_Time{{-5, .march, 7}, {}})
	testing.expect_value(t, second, "-0005-03-07T00:00:00")
	expected := strings.concatenate(
		{"a ", "2026-11-01T14:30:00.5", " b ", "-0005-03-07T00:00:00"},
		context.temp_allocator,
	)
	testing.expect_value(t, strings.to_string(builder), expected)
	free_all(context.temp_allocator)
}

@(test)
test_local_date_time_wprint :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	writer := strings.to_writer(&builder)
	testing.expect_value(
		t,
		chrono.local_date_time_wprint(
			writer,
			chrono.Local_Date_Time{{2026, .november, 1}, {14, 30, 0, 500_000_000}},
		),
		len("2026-11-01T14:30:00.5"),
	)
	testing.expect_value(
		t,
		chrono.local_date_time_wprint(writer, chrono.Local_Date_Time{{-5, .march, 7}, {}}),
		len("-0005-03-07T00:00:00"),
	)
	expected := strings.concatenate(
		{"2026-11-01T14:30:00.5", "-0005-03-07T00:00:00"},
		context.temp_allocator,
	)
	testing.expect_value(t, strings.to_string(builder), expected)
	free_all(context.temp_allocator)
}

@(test)
test_local_date_time_wprint_reports_what_was_written_when_the_writer_fails :: proc(t: ^testing.T) {
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
	written := chrono.local_date_time_wprint(
		writer,
		chrono.Local_Date_Time{{2026, .november, 1}, {14, 30, 0, 500_000_000}},
	)
	testing.expect_value(t, written, 4)
	testing.expect_value(t, string(storage[:]), "2026-11-01T14:30:00.5"[:4])
}

@(test)
test_local_date_time_fprint_writes_to_the_file :: proc(t: ^testing.T) {
	file, create_error := os.create_temp_file("", "chrono_format_local_date_time_*")
	testing.expect_value(t, create_error, nil)
	if create_error != nil {
		return
	}
	name := strings.clone(os.name(file))
	defer delete(name)
	defer os.remove(name)

	testing.expect_value(
		t,
		chrono.local_date_time_fprint(
			file,
			chrono.Local_Date_Time{{2026, .november, 1}, {14, 30, 0, 500_000_000}},
		),
		len("2026-11-01T14:30:00.5"),
	)
	testing.expect_value(
		t,
		chrono.local_date_time_fprint(file, chrono.Local_Date_Time{{-5, .march, 7}, {}}),
		len("-0005-03-07T00:00:00"),
	)
	testing.expect_value(t, os.close(file), nil)

	data, read_error := os.read_entire_file(name, context.allocator)
	defer delete(data)
	testing.expect_value(t, read_error, nil)
	expected := strings.concatenate(
		{"2026-11-01T14:30:00.5", "-0005-03-07T00:00:00"},
		context.temp_allocator,
	)
	testing.expect_value(t, string(data), expected)
	free_all(context.temp_allocator)
}

// Standard output and error cannot be captured here, so only the count is checked.
@(test)
test_local_date_time_print_and_eprint_return_the_length :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.local_date_time_print(
			chrono.Local_Date_Time{{2026, .november, 1}, {14, 30, 0, 500_000_000}},
		),
		len("2026-11-01T14:30:00.5"),
	)
	testing.expect_value(
		t,
		chrono.local_date_time_eprint(chrono.Local_Date_Time{{-5, .march, 7}, {}}),
		len("-0005-03-07T00:00:00"),
	)
}

@(test)
test_local_date_time_every_print_proc_produces_the_same_text :: proc(t: ^testing.T) {
	for entry in LOCAL_DATE_TIME_TEXT_CASES {
		buffer: [chrono.LOCAL_DATE_TIME_TEXT_MAX]u8
		expected := chrono.local_date_time_bprint(buffer[:], entry.date_time)

		allocated := chrono.local_date_time_aprint(entry.date_time)
		defer delete(allocated)
		testing.expect_value(t, allocated, expected)
		testing.expect_value(t, chrono.local_date_time_tprint(entry.date_time), expected)

		c_text := chrono.local_date_time_caprint(entry.date_time)
		defer delete(c_text)
		testing.expect_value(t, string(c_text), expected)

		builder: strings.Builder
		strings.builder_init(&builder)
		defer strings.builder_destroy(&builder)
		testing.expect_value(
			t,
			chrono.local_date_time_sbprint(&builder, entry.date_time),
			expected,
		)
		testing.expect_value(
			t,
			chrono.local_date_time_wprint(strings.to_writer(&builder), entry.date_time),
			len(expected),
		)
	}
	free_all(context.temp_allocator)
}
