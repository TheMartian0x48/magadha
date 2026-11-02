package chrono_test

import "core:fmt"
import "core:io"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

import chrono "../"

Time_Text_Case :: struct {
	time: chrono.Local_Time,
	text: string,
}

// Expected texts were produced by an independent implementation in Python.
TIME_TEXT_CASES :: [?]Time_Text_Case {
	{{0, 0, 0, 0}, "00:00:00"},
	{{12, 0, 0, 0}, "12:00:00"},
	{{14, 30, 0, 0}, "14:30:00"},
	{{23, 59, 59, 0}, "23:59:59"},
	{{9, 5, 7, 0}, "09:05:07"},
	// A fraction shows only when it is non-zero, with the trailing zeros trimmed.
	{{14, 30, 0, 500_000_000}, "14:30:00.5"},
	{{14, 30, 0, 120_000_000}, "14:30:00.12"},
	{{1, 2, 3, 100_000_000}, "01:02:03.1"},
	{{1, 2, 3, 999_999_990}, "01:02:03.99999999"},
	{{1, 2, 3, 10}, "01:02:03.00000001"},
	{{1, 2, 3, 1}, "01:02:03.000000001"},
	{{0, 0, 0, 1}, "00:00:00.000000001"},
	{{23, 59, 59, 999_999_999}, "23:59:59.999999999"},
	// The two ends of the day.
	{chrono.LOCAL_TIME_MIN, "00:00:00"},
	{chrono.LOCAL_TIME_MAX, "23:59:59.999999999"},
}

@(test)
test_local_time_bprint_known_values :: proc(t: ^testing.T) {
	for entry in TIME_TEXT_CASES {
		buffer: [chrono.LOCAL_TIME_TEXT_MAX]u8
		testing.expect_value(t, chrono.local_time_bprint(buffer[:], entry.time), entry.text)
	}
}

// Every power of ten from 1 ns to 100 ms, and every digit count with a non-zero last digit.
@(test)
test_local_time_bprint_fractions :: proc(t: ^testing.T) {
	powers := [?]string {
		"00:00:00.000000001",
		"00:00:00.00000001",
		"00:00:00.0000001",
		"00:00:00.000001",
		"00:00:00.00001",
		"00:00:00.0001",
		"00:00:00.001",
		"00:00:00.01",
		"00:00:00.1",
	}
	nanoseconds := u32(1)
	for expected in powers {
		buffer: [chrono.LOCAL_TIME_TEXT_MAX]u8
		testing.expect_value(
			t,
			chrono.local_time_bprint(buffer[:], {0, 0, 0, nanoseconds}),
			expected,
		)
		nanoseconds *= 10
	}

	sevens := [?]string {
		"00:00:00.7",
		"00:00:00.07",
		"00:00:00.007",
		"00:00:00.0007",
		"00:00:00.00007",
		"00:00:00.000007",
		"00:00:00.0000007",
		"00:00:00.00000007",
		"00:00:00.000000007",
	}
	nanoseconds = 700_000_000
	for expected in sevens {
		buffer: [chrono.LOCAL_TIME_TEXT_MAX]u8
		testing.expect_value(
			t,
			chrono.local_time_bprint(buffer[:], {0, 0, 0, nanoseconds}),
			expected,
		)
		nanoseconds /= 10
	}
}

@(test)
test_local_time_text_max_is_the_longest_text :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.LOCAL_TIME_TEXT_MAX, 18)

	buffer: [chrono.LOCAL_TIME_TEXT_MAX]u8
	testing.expect_value(t, len(chrono.local_time_bprint(buffer[:], chrono.LOCAL_TIME_MAX)), 18)

	// No time is longer: every second of the day with the longest and a few other fractions.
	for second_of_day in chrono.Second_Of_Day(0) ..= chrono.SECOND_OF_DAY_MAX {
		for nanoseconds in ([?]u32{0, 1, 123_456_789, 999_999_999}) {
			time, ok := chrono.local_time_from_second_of_day(second_of_day, nanoseconds)
			testing.expect(t, ok)
			text := chrono.local_time_bprint(buffer[:], time)
			testing.expect(t, len(text) <= chrono.LOCAL_TIME_TEXT_MAX)
		}
	}
}

// The hour, minute and second digits must match fmt for every second of a day.
@(test)
test_local_time_bprint_matches_fmt_for_every_second :: proc(t: ^testing.T) {
	for second_of_day in chrono.Second_Of_Day(0) ..= chrono.SECOND_OF_DAY_MAX {
		time, ok := chrono.local_time_from_second_of_day(second_of_day, 0)
		testing.expect(t, ok)

		mine: [chrono.LOCAL_TIME_TEXT_MAX]u8
		theirs: [32]u8
		expected := fmt.bprintf(theirs[:], "%02d:%02d:%02d", time.hour, time.minute, time.second)
		if chrono.local_time_bprint(mine[:], time) != expected {
			testing.expect_value(t, chrono.local_time_bprint(mine[:], time), expected)
			return
		}
	}
}

// The fraction digits must match fmt's nine digit form with the zeros trimmed by hand.
@(test)
test_local_time_bprint_fraction_matches_a_reference :: proc(t: ^testing.T) {
	for nanoseconds := u32(1);
	    nanoseconds < chrono.NANOSECONDS_PER_SECOND;
	    nanoseconds += 100_003 {
		mine: [chrono.LOCAL_TIME_TEXT_MAX]u8
		theirs: [32]u8
		digits := fmt.bprintf(theirs[:], "%09d", nanoseconds)
		trimmed := strings.trim_right(digits, "0")
		expected_buffer: [32]u8
		expected := fmt.bprintf(expected_buffer[:], "10:20:30.%s", trimmed)

		testing.expect_value(
			t,
			chrono.local_time_bprint(mine[:], {10, 20, 30, nanoseconds}),
			expected,
		)
	}
}

// Because the fields are fixed width and the fraction trails, text order is time order.
@(test)
test_local_time_text_sorts_like_the_time :: proc(t: ^testing.T) {
	Entry :: struct {
		time: chrono.Local_Time,
		text: string,
	}
	entries: [dynamic]Entry
	defer {
		for entry in entries {
			delete(entry.text)
		}
		delete(entries)
	}
	state := u64(0x9E3779B97F4A7C15)
	for _ in 0 ..< 3_000 {
		state ~= state << 13
		state ~= state >> 7
		state ~= state << 17
		// Mix whole seconds, short fractions and full nanoseconds so the trimming is exercised.
		fraction: u32
		switch state % 4 {
		case 0:
			fraction = 0
		case 1:
			fraction = u32((state >> 8) % 10) * 100_000_000
		case 2:
			fraction = u32((state >> 8) % 1_000) * 1_000_000
		case 3:
			fraction = u32((state >> 8) % chrono.NANOSECONDS_PER_SECOND)
		}
		time := chrono.Local_Time {
			hour        = u8((state >> 16) % 24),
			minute      = u8((state >> 24) % 60),
			second      = u8((state >> 32) % 60),
			nanoseconds = fraction,
		}
		append(&entries, Entry{time, chrono.local_time_aprint(time)})
	}

	slice.sort_by(entries[:], proc(left, right: Entry) -> bool {
		return left.text < right.text
	})
	for index in 1 ..< len(entries) {
		order := chrono.local_time_compare(entries[index - 1].time, entries[index].time)
		testing.expect(t, order != .greater)
	}
}

@(test)
test_local_time_bprint_leaves_the_rest_of_the_buffer_alone :: proc(t: ^testing.T) {
	buffer: [30]u8
	for &byte in buffer {
		byte = '#'
	}
	text := chrono.local_time_bprint(buffer[:], {14, 30, 0, 500_000_000})
	testing.expect_value(t, text, "14:30:00.5")
	for byte in buffer[len(text):] {
		testing.expect_value(t, byte, '#')
	}
}

@(test)
test_local_time_aprint :: proc(t: ^testing.T) {
	for entry in TIME_TEXT_CASES {
		text := chrono.local_time_aprint(entry.time)
		defer delete(text)
		testing.expect_value(t, text, entry.text)
	}
}

@(test)
test_local_time_tprint :: proc(t: ^testing.T) {
	for entry in TIME_TEXT_CASES {
		testing.expect_value(t, chrono.local_time_tprint(entry.time), entry.text)
	}
	free_all(context.temp_allocator)
}

@(test)
test_local_time_caprint :: proc(t: ^testing.T) {
	for entry in TIME_TEXT_CASES {
		text := chrono.local_time_caprint(entry.time)
		defer delete(text)
		testing.expect_value(t, string(text), entry.text)
		testing.expect_value(t, (cast([^]u8)text)[len(entry.text)], 0)
	}
}

@(test)
test_local_time_sbprint_returns_only_what_it_appended :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "from ")
	first := chrono.local_time_sbprint(&builder, {9, 0, 0, 0})
	testing.expect_value(t, first, "09:00:00")
	strings.write_string(&builder, " to ")
	second := chrono.local_time_sbprint(&builder, {17, 30, 0, 250_000_000})
	testing.expect_value(t, second, "17:30:00.25")
	testing.expect_value(t, strings.to_string(builder), "from 09:00:00 to 17:30:00.25")
}

@(test)
test_local_time_wprint :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	writer := strings.to_writer(&builder)
	testing.expect_value(t, chrono.local_time_wprint(writer, {1, 2, 3, 0}), 8)
	testing.expect_value(t, chrono.local_time_wprint(writer, chrono.LOCAL_TIME_MAX), 18)
	testing.expect_value(t, strings.to_string(builder), "01:02:0323:59:59.999999999")
}

@(test)
test_local_time_wprint_reports_what_was_written_when_the_writer_fails :: proc(t: ^testing.T) {
	// A fixed size stream that holds 5 bytes: the write stops there and the count says so.
	storage: [5]u8
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
				storage_ptr := cast(^[5]u8)stream_data
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
	written := chrono.local_time_wprint(writer, {14, 30, 15, 0})
	testing.expect_value(t, written, 5)
	testing.expect_value(t, string(storage[:]), "14:30")
}

@(test)
test_local_time_fprint_writes_to_the_file :: proc(t: ^testing.T) {
	file, create_error := os.create_temp_file("", "chrono_format_time_*")
	testing.expect_value(t, create_error, nil)
	if create_error != nil {
		return
	}
	name := strings.clone(os.name(file))
	defer delete(name)
	defer os.remove(name)

	testing.expect_value(t, chrono.local_time_fprint(file, {14, 30, 0, 0}), 8)
	testing.expect_value(t, chrono.local_time_fprint(file, {0, 0, 0, 1}), 18)
	testing.expect_value(t, os.close(file), nil)

	data, read_error := os.read_entire_file(name, context.allocator)
	defer delete(data)
	testing.expect_value(t, read_error, nil)
	testing.expect_value(t, string(data), "14:30:0000:00:00.000000001")
}

// Standard output and error cannot be captured here, so only the count is checked.
@(test)
test_local_time_print_and_eprint_return_the_length :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.local_time_print({14, 30, 0, 0}), 8)
	testing.expect_value(t, chrono.local_time_eprint({14, 30, 0, 500_000_000}), 10)
}

@(test)
test_local_time_every_print_proc_produces_the_same_text :: proc(t: ^testing.T) {
	for entry in TIME_TEXT_CASES {
		buffer: [chrono.LOCAL_TIME_TEXT_MAX]u8
		expected := chrono.local_time_bprint(buffer[:], entry.time)

		allocated := chrono.local_time_aprint(entry.time)
		defer delete(allocated)
		testing.expect_value(t, allocated, expected)
		testing.expect_value(t, chrono.local_time_tprint(entry.time), expected)

		c_text := chrono.local_time_caprint(entry.time)
		defer delete(c_text)
		testing.expect_value(t, string(c_text), expected)

		builder: strings.Builder
		strings.builder_init(&builder)
		defer strings.builder_destroy(&builder)
		testing.expect_value(t, chrono.local_time_sbprint(&builder, entry.time), expected)
		testing.expect_value(
			t,
			chrono.local_time_wprint(strings.to_writer(&builder), entry.time),
			len(expected),
		)
	}
	free_all(context.temp_allocator)
}
