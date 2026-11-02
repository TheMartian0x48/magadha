package chrono_test

import "core:io"
import "core:os"
import "core:strings"
import "core:testing"

import chrono "../"

Iso_Text_Case :: struct {
	date: chrono.Local_Date,
	iso:  chrono.Iso_Week_Date,
	text: string,
}

// Expected texts come from Python's isocalendar(), and Java's ISO_WEEK_DATE formatter writes the
// same text for every one of them.
ISO_WEEK_DATE_TEXT_CASES :: [?]Iso_Text_Case {
	{{2026, .november, 1}, {2026, 44, .sunday}, "2026-W44-7"},
	{{2026, .november, 2}, {2026, 45, .monday}, "2026-W45-1"},
	{{1970, .january, 1}, {1970, 1, .thursday}, "1970-W01-4"},
	{{2000, .january, 1}, {1999, 52, .saturday}, "1999-W52-6"},
	{{1900, .january, 1}, {1900, 1, .monday}, "1900-W01-1"},
	{{2024, .january, 1}, {2024, 1, .monday}, "2024-W01-1"},
	// The days that belong to a neighbouring year's weeks.
	{{2021, .january, 1}, {2020, 53, .friday}, "2020-W53-5"},
	{{2027, .january, 1}, {2026, 53, .friday}, "2026-W53-5"},
	{{2024, .december, 31}, {2025, 1, .tuesday}, "2025-W01-2"},
	{{2025, .december, 31}, {2026, 1, .wednesday}, "2026-W01-3"},
	{{2016, .january, 3}, {2015, 53, .sunday}, "2015-W53-7"},
	{{2008, .december, 29}, {2009, 1, .monday}, "2009-W01-1"},
	// Ends of 53 and 52 week years: the week is always two digits.
	{{2020, .december, 31}, {2020, 53, .thursday}, "2020-W53-4"},
	{{2026, .december, 31}, {2026, 53, .thursday}, "2026-W53-4"},
	{{2027, .december, 31}, {2027, 52, .friday}, "2027-W52-5"},
	{{2016, .january, 4}, {2016, 1, .monday}, "2016-W01-1"},
	// Week years padded to 4 digits and signed outside 0 to 9999. The week year can differ from the
	// date's year: 0000-01-01 is in week 52 of year -1, and +10000-01-01 is still in year 9999.
	{{1, .january, 1}, {1, 1, .monday}, "0001-W01-1"},
	{{0, .january, 1}, {-1, 52, .saturday}, "-0001-W52-6"},
	{{0, .december, 31}, {0, 52, .sunday}, "0000-W52-7"},
	{{-1, .december, 31}, {-1, 52, .friday}, "-0001-W52-5"},
	{{-5, .march, 7}, {-5, 10, .tuesday}, "-0005-W10-2"},
	{{9999, .december, 31}, {9999, 52, .friday}, "9999-W52-5"},
	{{10_000, .january, 1}, {9999, 52, .saturday}, "9999-W52-6"},
	{{12_345, .june, 15}, {12_345, 24, .friday}, "+12345-W24-5"},
	{{-12_345, .june, 15}, {-12_345, 24, .tuesday}, "-12345-W24-2"},
	// Both ends of the supported range.
	{chrono.LOCAL_DATE_MIN, {chrono.YEAR_MIN, 1, .monday}, "-999999-W01-1"},
	{{chrono.YEAR_MIN, .january, 7}, {chrono.YEAR_MIN, 1, .sunday}, "-999999-W01-7"},
	{chrono.LOCAL_DATE_MAX, {chrono.YEAR_MAX, 52, .friday}, "+999999-W52-5"},
	{{chrono.YEAR_MAX, .december, 25}, {chrono.YEAR_MAX, 51, .saturday}, "+999999-W51-6"},
}

@(test)
test_iso_week_date_bprint_known_values :: proc(t: ^testing.T) {
	for entry in ISO_WEEK_DATE_TEXT_CASES {
		buffer: [chrono.ISO_WEEK_DATE_TEXT_MAX]u8
		testing.expect_value(t, chrono.iso_week_date_bprint(buffer[:], entry.iso), entry.text)
	}
}

// The table's date and week date must agree, so the text really is the date's week date.
@(test)
test_iso_week_date_text_cases_agree_with_the_date_conversion :: proc(t: ^testing.T) {
	for entry in ISO_WEEK_DATE_TEXT_CASES {
		testing.expect_value(t, chrono.local_date_to_iso_week_date(entry.date), entry.iso)
		buffer: [chrono.ISO_WEEK_DATE_TEXT_MAX]u8
		testing.expect_value(
			t,
			chrono.iso_week_date_bprint(buffer[:], chrono.local_date_to_iso_week_date(entry.date)),
			entry.text,
		)
	}
}

@(test)
test_iso_week_date_text_max_is_the_longest_text :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.ISO_WEEK_DATE_TEXT_MAX, 13)

	buffer: [chrono.ISO_WEEK_DATE_TEXT_MAX]u8
	testing.expect_value(
		t,
		len(chrono.iso_week_date_bprint(buffer[:], {chrono.YEAR_MIN, 1, .monday})),
		13,
	)
	testing.expect_value(
		t,
		len(chrono.iso_week_date_bprint(buffer[:], {chrono.YEAR_MAX, 52, .friday})),
		13,
	)

	// Nothing is longer: walk 20 000 days from each end of the range.
	for offset in i64(0) ..< 20_000 {
		first, first_ok := chrono.local_date_plus_days(chrono.LOCAL_DATE_MIN, offset)
		last, last_ok := chrono.local_date_plus_days(chrono.LOCAL_DATE_MAX, -offset)
		testing.expect(t, first_ok && last_ok)
		for date in ([?]chrono.Local_Date{first, last}) {
			iso := chrono.local_date_to_iso_week_date(date)
			testing.expect(
				t,
				len(chrono.iso_week_date_bprint(buffer[:], iso)) <= chrono.ISO_WEEK_DATE_TEXT_MAX,
			)
		}
	}
}

// The week is two digits and the weekday one, in the same places every time.
@(test)
test_iso_week_date_bprint_has_a_fixed_layout :: proc(t: ^testing.T) {
	buffer: [chrono.ISO_WEEK_DATE_TEXT_MAX]u8
	for week in u8(1) ..= 53 {
		for weekday in chrono.Weekday.monday ..= chrono.Weekday.sunday {
			// 2026 has 53 weeks, so every week from 1 to 53 exists there.
			text := chrono.iso_week_date_bprint(buffer[:], {2026, week, weekday})
			testing.expect_value(t, len(text), 10)
			testing.expect_value(t, text[:6], "2026-W")
			testing.expect_value(t, text[8], '-')
			testing.expect_value(t, text[6], '0' + week / 10)
			testing.expect_value(t, text[7], '0' + week % 10)
			testing.expect_value(t, text[9], '0' + u8(weekday))
		}
	}
}

// Every day of several years, including the 53 week ones: the text must read back to the date.
@(test)
test_iso_week_date_text_over_many_days_names_a_valid_week_date :: proc(t: ^testing.T) {
	for epoch_day in chrono.Epoch_Day(-4_000) ..= 4_800 {
		date, ok := chrono.local_date_from_epoch_day(epoch_day)
		testing.expect(t, ok)
		iso := chrono.local_date_to_iso_week_date(date)

		buffer: [chrono.ISO_WEEK_DATE_TEXT_MAX]u8
		text := chrono.iso_week_date_bprint(buffer[:], iso)
		testing.expect_value(t, len(text), 10)
		testing.expect_value(t, text[4], '-')
		testing.expect_value(t, text[5], 'W')
		testing.expect_value(t, text[8], '-')
	}
}

@(test)
test_iso_week_date_bprint_leaves_the_rest_of_the_buffer_alone :: proc(t: ^testing.T) {
	buffer: [30]u8
	for &byte in buffer {
		byte = '#'
	}
	text := chrono.iso_week_date_bprint(buffer[:], {2026, 44, .sunday})
	testing.expect_value(t, text, "2026-W44-7")
	for byte in buffer[len(text):] {
		testing.expect_value(t, byte, '#')
	}
}

@(test)
test_iso_week_date_bprint_accepts_a_buffer_of_exactly_the_maximum :: proc(t: ^testing.T) {
	buffer: [chrono.ISO_WEEK_DATE_TEXT_MAX]u8
	testing.expect_value(
		t,
		chrono.iso_week_date_bprint(buffer[:], {chrono.YEAR_MIN, 1, .monday}),
		"-999999-W01-1",
	)
}

@(test)
test_iso_week_date_aprint :: proc(t: ^testing.T) {
	for entry in ISO_WEEK_DATE_TEXT_CASES {
		text := chrono.iso_week_date_aprint(entry.iso)
		defer delete(text)
		testing.expect_value(t, text, entry.text)
	}
}

@(test)
test_iso_week_date_tprint :: proc(t: ^testing.T) {
	for entry in ISO_WEEK_DATE_TEXT_CASES {
		testing.expect_value(t, chrono.iso_week_date_tprint(entry.iso), entry.text)
	}
	free_all(context.temp_allocator)
}

@(test)
test_iso_week_date_caprint :: proc(t: ^testing.T) {
	for entry in ISO_WEEK_DATE_TEXT_CASES {
		text := chrono.iso_week_date_caprint(entry.iso)
		defer delete(text)
		testing.expect_value(t, string(text), entry.text)
		testing.expect_value(t, (cast([^]u8)text)[len(entry.text)], 0)
	}
}

@(test)
test_iso_week_date_sbprint_returns_only_what_it_appended :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "a ")
	first := chrono.iso_week_date_sbprint(&builder, chrono.Iso_Week_Date{2026, 44, .sunday})
	testing.expect_value(t, first, "2026-W44-7")
	strings.write_string(&builder, " b ")
	second := chrono.iso_week_date_sbprint(&builder, chrono.Iso_Week_Date{2020, 53, .friday})
	testing.expect_value(t, second, "2020-W53-5")
	expected := strings.concatenate(
		{"a ", "2026-W44-7", " b ", "2020-W53-5"},
		context.temp_allocator,
	)
	testing.expect_value(t, strings.to_string(builder), expected)
	free_all(context.temp_allocator)
}

@(test)
test_iso_week_date_wprint :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	writer := strings.to_writer(&builder)
	testing.expect_value(
		t,
		chrono.iso_week_date_wprint(writer, chrono.Iso_Week_Date{2026, 44, .sunday}),
		len("2026-W44-7"),
	)
	testing.expect_value(
		t,
		chrono.iso_week_date_wprint(writer, chrono.Iso_Week_Date{2020, 53, .friday}),
		len("2020-W53-5"),
	)
	expected := strings.concatenate({"2026-W44-7", "2020-W53-5"}, context.temp_allocator)
	testing.expect_value(t, strings.to_string(builder), expected)
	free_all(context.temp_allocator)
}

@(test)
test_iso_week_date_wprint_reports_what_was_written_when_the_writer_fails :: proc(t: ^testing.T) {
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
	written := chrono.iso_week_date_wprint(writer, chrono.Iso_Week_Date{2026, 44, .sunday})
	testing.expect_value(t, written, 4)
	testing.expect_value(t, string(storage[:]), "2026-W44-7"[:4])
}

@(test)
test_iso_week_date_fprint_writes_to_the_file :: proc(t: ^testing.T) {
	file, create_error := os.create_temp_file("", "chrono_format_iso_week_date_*")
	testing.expect_value(t, create_error, nil)
	if create_error != nil {
		return
	}
	name := strings.clone(os.name(file))
	defer delete(name)
	defer os.remove(name)

	testing.expect_value(
		t,
		chrono.iso_week_date_fprint(file, chrono.Iso_Week_Date{2026, 44, .sunday}),
		len("2026-W44-7"),
	)
	testing.expect_value(
		t,
		chrono.iso_week_date_fprint(file, chrono.Iso_Week_Date{2020, 53, .friday}),
		len("2020-W53-5"),
	)
	testing.expect_value(t, os.close(file), nil)

	data, read_error := os.read_entire_file(name, context.allocator)
	defer delete(data)
	testing.expect_value(t, read_error, nil)
	expected := strings.concatenate({"2026-W44-7", "2020-W53-5"}, context.temp_allocator)
	testing.expect_value(t, string(data), expected)
	free_all(context.temp_allocator)
}

// Standard output and error cannot be captured here, so only the count is checked.
@(test)
test_iso_week_date_print_and_eprint_return_the_length :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		chrono.iso_week_date_print(chrono.Iso_Week_Date{2026, 44, .sunday}),
		len("2026-W44-7"),
	)
	testing.expect_value(
		t,
		chrono.iso_week_date_eprint(chrono.Iso_Week_Date{2020, 53, .friday}),
		len("2020-W53-5"),
	)
}

@(test)
test_iso_week_date_every_print_proc_produces_the_same_text :: proc(t: ^testing.T) {
	for entry in ISO_WEEK_DATE_TEXT_CASES {
		buffer: [chrono.ISO_WEEK_DATE_TEXT_MAX]u8
		expected := chrono.iso_week_date_bprint(buffer[:], entry.iso)

		allocated := chrono.iso_week_date_aprint(entry.iso)
		defer delete(allocated)
		testing.expect_value(t, allocated, expected)
		testing.expect_value(t, chrono.iso_week_date_tprint(entry.iso), expected)

		c_text := chrono.iso_week_date_caprint(entry.iso)
		defer delete(c_text)
		testing.expect_value(t, string(c_text), expected)

		builder: strings.Builder
		strings.builder_init(&builder)
		defer strings.builder_destroy(&builder)
		testing.expect_value(t, chrono.iso_week_date_sbprint(&builder, entry.iso), expected)
		testing.expect_value(
			t,
			chrono.iso_week_date_wprint(strings.to_writer(&builder), entry.iso),
			len(expected),
		)
	}
	free_all(context.temp_allocator)
}
