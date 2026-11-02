package chrono_test

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:testing"

import chrono "../"

Text_Case :: struct {
	date: chrono.Local_Date,
	text: string,
}

TEXT_CASES :: [?]Text_Case {
	{{2026, .november, 1}, "2026-11-01"},
	{{2026, .february, 28}, "2026-02-28"},
	{{2024, .february, 29}, "2024-02-29"},
	{{1970, .january, 1}, "1970-01-01"},
	{{2000, .december, 31}, "2000-12-31"},
	// Years under 1000 are padded to 4 digits.
	{{5, .march, 7}, "0005-03-07"},
	{{0, .january, 1}, "0000-01-01"},
	{{999, .september, 9}, "0999-09-09"},
	{{9999, .december, 31}, "9999-12-31"},
	// Outside 0 to 9999 the year gets a sign.
	{{-1, .december, 31}, "-0001-12-31"},
	{{-5, .march, 7}, "-0005-03-07"},
	{{-1000, .october, 10}, "-1000-10-10"},
	{{10_000, .january, 1}, "+10000-01-01"},
	{{12_345, .june, 15}, "+12345-06-15"},
	{{-12_345, .june, 15}, "-12345-06-15"},
	// Both ends of the supported range, the longest texts there are.
	{chrono.LOCAL_DATE_MIN, "-999999-01-01"},
	{chrono.LOCAL_DATE_MAX, "+999999-12-31"},
}

@(test)
test_local_date_bprint_known_values :: proc(t: ^testing.T) {
	for entry in TEXT_CASES {
		buffer: [chrono.LOCAL_DATE_TEXT_MAX]u8
		testing.expect_value(t, chrono.local_date_bprint(buffer[:], entry.date), entry.text)
	}
}

@(test)
test_local_date_text_max_is_the_longest_text :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.LOCAL_DATE_TEXT_MAX, 13)

	buffer: [chrono.LOCAL_DATE_TEXT_MAX]u8
	testing.expect_value(t, len(chrono.local_date_bprint(buffer[:], chrono.LOCAL_DATE_MIN)), 13)
	testing.expect_value(t, len(chrono.local_date_bprint(buffer[:], chrono.LOCAL_DATE_MAX)), 13)

	// No date over a wide span is longer.
	for epoch_day in chrono.Epoch_Day(-800_000) ..= 800_000 {
		date, ok := chrono.local_date_from_epoch_day(epoch_day)
		testing.expect(t, ok)
		testing.expect(
			t,
			len(chrono.local_date_bprint(buffer[:], date)) <= chrono.LOCAL_DATE_TEXT_MAX,
		)
	}
}

// For years 0 to 9999 the hand written digits must equal what fmt produces. Every 7th day is
// compared, which still hits every month, every day of the month and every year's padding.
@(test)
test_local_date_bprint_matches_fmt_for_years_0_to_9999 :: proc(t: ^testing.T) {
	first := chrono.local_date_to_epoch_day({0, .january, 1})
	last := chrono.local_date_to_epoch_day({9999, .december, 31})
	for epoch_day := first; epoch_day <= last; epoch_day += 7 {
		date, ok := chrono.local_date_from_epoch_day(epoch_day)
		testing.expect(t, ok)

		mine: [chrono.LOCAL_DATE_TEXT_MAX]u8
		theirs: [32]u8
		expected := fmt.bprintf(theirs[:], "%04d-%02d-%02d", date.year, int(date.month), date.day)
		if chrono.local_date_bprint(mine[:], date) != expected {
			testing.expect_value(t, chrono.local_date_bprint(mine[:], date), expected)
			return
		}
	}
}

@(test)
test_local_date_bprint_leaves_the_rest_of_the_buffer_alone :: proc(t: ^testing.T) {
	buffer: [20]u8
	for &byte in buffer {
		byte = '#'
	}
	text := chrono.local_date_bprint(buffer[:], {2026, .november, 1})
	testing.expect_value(t, text, "2026-11-01")
	testing.expect_value(t, text, string(buffer[:10]))
	for byte in buffer[10:] {
		testing.expect_value(t, byte, '#')
	}
}

@(test)
test_local_date_bprint_accepts_a_buffer_of_exactly_the_maximum :: proc(t: ^testing.T) {
	buffer: [chrono.LOCAL_DATE_TEXT_MAX]u8
	testing.expect_value(
		t,
		chrono.local_date_bprint(buffer[:], chrono.LOCAL_DATE_MAX),
		"+999999-12-31",
	)
}

@(test)
test_local_date_aprint :: proc(t: ^testing.T) {
	for entry in TEXT_CASES {
		text := chrono.local_date_aprint(entry.date)
		defer delete(text)
		testing.expect_value(t, text, entry.text)
	}

	// An explicit allocator is used, and the text is a copy: it owns exactly its own bytes.
	text := chrono.local_date_aprint({2026, .november, 1}, context.allocator)
	defer delete(text)
	testing.expect_value(t, len(text), 10)
}

@(test)
test_local_date_tprint :: proc(t: ^testing.T) {
	for entry in TEXT_CASES {
		testing.expect_value(t, chrono.local_date_tprint(entry.date), entry.text)
	}
	free_all(context.temp_allocator)
}

@(test)
test_local_date_caprint :: proc(t: ^testing.T) {
	for entry in TEXT_CASES {
		text := chrono.local_date_caprint(entry.date)
		defer delete(text)
		testing.expect_value(t, string(text), entry.text)
		testing.expect_value(t, len(text), len(entry.text))

		// The byte after the text is the terminator.
		terminator := (cast([^]u8)text)[len(entry.text)]
		testing.expect_value(t, terminator, 0)
	}
}

@(test)
test_local_date_sbprint_returns_only_what_it_appended :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "from ")
	first := chrono.local_date_sbprint(&builder, {2026, .january, 1})
	testing.expect_value(t, first, "2026-01-01")
	strings.write_string(&builder, " to ")
	second := chrono.local_date_sbprint(&builder, {2026, .december, 31})
	testing.expect_value(t, second, "2026-12-31")
	testing.expect_value(t, strings.to_string(builder), "from 2026-01-01 to 2026-12-31")
}

@(test)
test_local_date_wprint :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	writer := strings.to_writer(&builder)
	written := chrono.local_date_wprint(writer, {5, .march, 7})
	testing.expect_value(t, written, 10)
	written = chrono.local_date_wprint(writer, chrono.LOCAL_DATE_MIN)
	testing.expect_value(t, written, 13)
	testing.expect_value(t, strings.to_string(builder), "0005-03-07-999999-01-01")
}

@(test)
test_local_date_wprint_reports_what_was_written_when_the_writer_fails :: proc(t: ^testing.T) {
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
	written := chrono.local_date_wprint(writer, {2026, .november, 1})
	testing.expect_value(t, written, 4)
	testing.expect_value(t, string(storage[:]), "2026")
}

@(test)
test_local_date_fprint_writes_to_the_file :: proc(t: ^testing.T) {
	file, create_error := os.create_temp_file("", "chrono_format_*")
	testing.expect_value(t, create_error, nil)
	if create_error != nil {
		return
	}
	name := strings.clone(os.name(file))
	defer delete(name)
	defer os.remove(name)

	written := chrono.local_date_fprint(file, {2026, .november, 1})
	testing.expect_value(t, written, 10)
	written = chrono.local_date_fprint(file, chrono.LOCAL_DATE_MAX)
	testing.expect_value(t, written, 13)
	testing.expect_value(t, os.close(file), nil)

	data, read_error := os.read_entire_file(name, context.allocator)
	defer delete(data)
	testing.expect_value(t, read_error, nil)
	testing.expect_value(t, string(data), "2026-11-01+999999-12-31")
}

// Standard output and error cannot be captured here, so only the count is checked.
@(test)
test_local_date_print_and_eprint_return_the_length :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.local_date_print({2026, .november, 1}), 10)
	testing.expect_value(t, chrono.local_date_eprint({-5, .march, 7}), 11)
}

// All nine procs must agree on the text, for every case.
@(test)
test_local_date_every_print_proc_produces_the_same_text :: proc(t: ^testing.T) {
	for entry in TEXT_CASES {
		buffer: [chrono.LOCAL_DATE_TEXT_MAX]u8
		expected := chrono.local_date_bprint(buffer[:], entry.date)

		allocated := chrono.local_date_aprint(entry.date)
		defer delete(allocated)
		testing.expect_value(t, allocated, expected)
		testing.expect_value(t, chrono.local_date_tprint(entry.date), expected)

		c_text := chrono.local_date_caprint(entry.date)
		defer delete(c_text)
		testing.expect_value(t, string(c_text), expected)

		builder: strings.Builder
		strings.builder_init(&builder)
		defer strings.builder_destroy(&builder)
		testing.expect_value(t, chrono.local_date_sbprint(&builder, entry.date), expected)
		testing.expect_value(
			t,
			chrono.local_date_wprint(strings.to_writer(&builder), entry.date),
			len(expected),
		)
	}
	free_all(context.temp_allocator)
}
