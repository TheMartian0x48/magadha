package chrono_test

import "core:io"
import "core:os"
import "core:strings"
import "core:testing"

import chrono "../"

Period_Text_Case :: struct {
	period: chrono.Period,
	text:   string,
}

// Every text here is what Java's Period.toString() writes, checked against Java itself.
PERIOD_TEXT_CASES :: [?]Period_Text_Case {
	{{0, 0, 0}, "P0D"},
	{{1, 2, 3}, "P1Y2M3D"},
	{{1, 0, 0}, "P1Y"},
	{{0, 1, 0}, "P1M"},
	{{0, 0, 1}, "P1D"},
	{{2, 0, 0}, "P2Y"},
	{{1, 0, 3}, "P1Y3D"},
	{{0, 2, 3}, "P2M3D"},
	{{1, 2, 0}, "P1Y2M"},
	// Nothing carries between fields.
	{{0, 14, 0}, "P14M"},
	{{0, 0, 365}, "P365D"},
	{{0, 12, 0}, "P12M"},
	// Each field has its own sign.
	{{-1, 0, 0}, "P-1Y"},
	{{0, -1, 0}, "P-1M"},
	{{0, 0, -1}, "P-1D"},
	{{1, -2, 0}, "P1Y-2M"},
	{{-1, 2, 0}, "P-1Y2M"},
	{{-1, 0, -3}, "P-1Y-3D"},
	{{-1, 2, -3}, "P-1Y2M-3D"},
	{{1, -2, 3}, "P1Y-2M3D"},
	{{1, -12, 0}, "P1Y-12M"},
	// The widest values, positive and negative.
	{{chrono.PERIOD_YEARS_MAX, 0, 0}, "P1999998Y"},
	{{0, chrono.PERIOD_MONTHS_MAX, 0}, "P23999976M"},
	{{0, 0, chrono.PERIOD_DAYS_MAX}, "P730484633D"},
	{
		{chrono.PERIOD_YEARS_MAX, chrono.PERIOD_MONTHS_MAX, chrono.PERIOD_DAYS_MAX},
		"P1999998Y23999976M730484633D",
	},
	{
		{-chrono.PERIOD_YEARS_MAX, -chrono.PERIOD_MONTHS_MAX, -chrono.PERIOD_DAYS_MAX},
		"P-1999998Y-23999976M-730484633D",
	},
}

@(test)
test_period_bprint_known_values :: proc(t: ^testing.T) {
	for entry in PERIOD_TEXT_CASES {
		buffer: [chrono.PERIOD_TEXT_MAX]u8
		testing.expect_value(t, chrono.period_bprint(buffer[:], entry.period), entry.text)
	}
}

@(test)
test_period_text_max_is_the_longest_text :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.PERIOD_TEXT_MAX, 31)

	buffer: [chrono.PERIOD_TEXT_MAX]u8
	widest := chrono.Period {
		-chrono.PERIOD_YEARS_MAX,
		-chrono.PERIOD_MONTHS_MAX,
		-chrono.PERIOD_DAYS_MAX,
	}
	testing.expect_value(t, len(chrono.period_bprint(buffer[:], widest)), 31)

	// No combination of the extreme values is longer.
	years := [?]i32{0, 1, -1, chrono.PERIOD_YEARS_MAX, -chrono.PERIOD_YEARS_MAX}
	months := [?]i32{0, 1, -1, chrono.PERIOD_MONTHS_MAX, -chrono.PERIOD_MONTHS_MAX}
	days := [?]i32{0, 1, -1, chrono.PERIOD_DAYS_MAX, -chrono.PERIOD_DAYS_MAX}
	for y in years {
		for m in months {
			for d in days {
				text := chrono.period_bprint(buffer[:], {y, m, d})
				testing.expect(t, len(text) <= chrono.PERIOD_TEXT_MAX)
			}
		}
	}
}

// All 27 sign combinations of a positive, zero and negative value in each field.
@(test)
test_period_bprint_all_sign_combinations :: proc(t: ^testing.T) {
	values := [?]i32{-5, 0, 5}
	for y in values {
		for m in values {
			for d in values {
				buffer: [chrono.PERIOD_TEXT_MAX]u8
				text := chrono.period_bprint(buffer[:], {y, m, d})

				expected_builder: strings.Builder
				strings.builder_init(&expected_builder)
				defer strings.builder_destroy(&expected_builder)
				strings.write_byte(&expected_builder, 'P')
				if y == 0 && m == 0 && d == 0 {
					strings.write_string(&expected_builder, "0D")
				}
				if y != 0 {
					strings.write_string(&expected_builder, "-5Y" if y < 0 else "5Y")
				}
				if m != 0 {
					strings.write_string(&expected_builder, "-5M" if m < 0 else "5M")
				}
				if d != 0 {
					strings.write_string(&expected_builder, "-5D" if d < 0 else "5D")
				}
				testing.expect_value(t, text, strings.to_string(expected_builder))
			}
		}
	}
}

@(test)
test_period_bprint_does_not_normalise :: proc(t: ^testing.T) {
	buffer: [chrono.PERIOD_TEXT_MAX]u8
	// 14 months is not 1 year 2 months, and a year with minus twelve months is not zero.
	testing.expect_value(t, chrono.period_bprint(buffer[:], {0, 14, 0}), "P14M")
	testing.expect_value(t, chrono.period_bprint(buffer[:], {1, -12, 0}), "P1Y-12M")
	testing.expect(
		t,
		chrono.period_bprint(buffer[:], {1, -12, 0}) != chrono.period_bprint(buffer[:], {}),
	)
}

@(test)
test_period_bprint_leaves_the_rest_of_the_buffer_alone :: proc(t: ^testing.T) {
	buffer: [40]u8
	for &byte in buffer {
		byte = '#'
	}
	text := chrono.period_bprint(buffer[:], {1, -2, 3})
	testing.expect_value(t, text, "P1Y-2M3D")
	for byte in buffer[len(text):] {
		testing.expect_value(t, byte, '#')
	}
}

@(test)
test_period_bprint_accepts_a_buffer_of_exactly_the_maximum :: proc(t: ^testing.T) {
	buffer: [chrono.PERIOD_TEXT_MAX]u8
	widest := chrono.Period {
		-chrono.PERIOD_YEARS_MAX,
		-chrono.PERIOD_MONTHS_MAX,
		-chrono.PERIOD_DAYS_MAX,
	}
	testing.expect_value(
		t,
		chrono.period_bprint(buffer[:], widest),
		"P-1999998Y-23999976M-730484633D",
	)
}

@(test)
test_period_aprint :: proc(t: ^testing.T) {
	for entry in PERIOD_TEXT_CASES {
		text := chrono.period_aprint(entry.period)
		defer delete(text)
		testing.expect_value(t, text, entry.text)
	}
}

@(test)
test_period_tprint :: proc(t: ^testing.T) {
	for entry in PERIOD_TEXT_CASES {
		testing.expect_value(t, chrono.period_tprint(entry.period), entry.text)
	}
	free_all(context.temp_allocator)
}

@(test)
test_period_caprint :: proc(t: ^testing.T) {
	for entry in PERIOD_TEXT_CASES {
		text := chrono.period_caprint(entry.period)
		defer delete(text)
		testing.expect_value(t, string(text), entry.text)
		testing.expect_value(t, (cast([^]u8)text)[len(entry.text)], 0)
	}
}

@(test)
test_period_sbprint_returns_only_what_it_appended :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "a ")
	first := chrono.period_sbprint(&builder, {1, 2, 3})
	testing.expect_value(t, first, "P1Y2M3D")
	strings.write_string(&builder, " b ")
	second := chrono.period_sbprint(&builder, {-1, 0, -3})
	testing.expect_value(t, second, "P-1Y-3D")
	expected := strings.concatenate({"a ", "P1Y2M3D", " b ", "P-1Y-3D"}, context.temp_allocator)
	testing.expect_value(t, strings.to_string(builder), expected)
	free_all(context.temp_allocator)
}

@(test)
test_period_wprint :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	writer := strings.to_writer(&builder)
	testing.expect_value(t, chrono.period_wprint(writer, {1, 2, 3}), len("P1Y2M3D"))
	testing.expect_value(t, chrono.period_wprint(writer, {-1, 0, -3}), len("P-1Y-3D"))
	expected := strings.concatenate({"P1Y2M3D", "P-1Y-3D"}, context.temp_allocator)
	testing.expect_value(t, strings.to_string(builder), expected)
	free_all(context.temp_allocator)
}

@(test)
test_period_wprint_reports_what_was_written_when_the_writer_fails :: proc(t: ^testing.T) {
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
	written := chrono.period_wprint(writer, {1, 2, 3})
	testing.expect_value(t, written, 4)
	testing.expect_value(t, string(storage[:]), "P1Y2M3D"[:4])
}

@(test)
test_period_fprint_writes_to_the_file :: proc(t: ^testing.T) {
	file, create_error := os.create_temp_file("", "chrono_format_period_*")
	testing.expect_value(t, create_error, nil)
	if create_error != nil {
		return
	}
	name := strings.clone(os.name(file))
	defer delete(name)
	defer os.remove(name)

	testing.expect_value(t, chrono.period_fprint(file, {1, 2, 3}), len("P1Y2M3D"))
	testing.expect_value(t, chrono.period_fprint(file, {-1, 0, -3}), len("P-1Y-3D"))
	testing.expect_value(t, os.close(file), nil)

	data, read_error := os.read_entire_file(name, context.allocator)
	defer delete(data)
	testing.expect_value(t, read_error, nil)
	expected := strings.concatenate({"P1Y2M3D", "P-1Y-3D"}, context.temp_allocator)
	testing.expect_value(t, string(data), expected)
	free_all(context.temp_allocator)
}

// Standard output and error cannot be captured here, so only the count is checked.
@(test)
test_period_print_and_eprint_return_the_length :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.period_print({1, 2, 3}), len("P1Y2M3D"))
	testing.expect_value(t, chrono.period_eprint({-1, 0, -3}), len("P-1Y-3D"))
}

@(test)
test_period_every_print_proc_produces_the_same_text :: proc(t: ^testing.T) {
	for entry in PERIOD_TEXT_CASES {
		buffer: [chrono.PERIOD_TEXT_MAX]u8
		expected := chrono.period_bprint(buffer[:], entry.period)

		allocated := chrono.period_aprint(entry.period)
		defer delete(allocated)
		testing.expect_value(t, allocated, expected)
		testing.expect_value(t, chrono.period_tprint(entry.period), expected)

		c_text := chrono.period_caprint(entry.period)
		defer delete(c_text)
		testing.expect_value(t, string(c_text), expected)

		builder: strings.Builder
		strings.builder_init(&builder)
		defer strings.builder_destroy(&builder)
		testing.expect_value(t, chrono.period_sbprint(&builder, entry.period), expected)
		testing.expect_value(
			t,
			chrono.period_wprint(strings.to_writer(&builder), entry.period),
			len(expected),
		)
	}
	free_all(context.temp_allocator)
}
