package chrono_test

import "core:io"
import "core:os"
import "core:strings"
import "core:testing"

import chrono "../"

Offset_Text_Case :: struct {
	offset: chrono.Zone_Offset,
	text:   string,
}

// Every text here is what Java's ZoneOffset.toString() writes, checked against Java itself.
ZONE_OFFSET_TEXT_CASES :: [?]Offset_Text_Case {
	{{0}, "Z"},
	{{19_800}, "+05:30"},
	{{-19_800}, "-05:30"},
	{{3_600}, "+01:00"},
	{{-3_600}, "-01:00"},
	{{-28_800}, "-08:00"},
	{{50_400}, "+14:00"},
	{{20_700}, "+05:45"},
	{{43_200}, "+12:00"},
	{{-43_200}, "-12:00"},
	// Seconds appear only when they are not zero.
	{{1}, "+00:00:01"},
	{{-1}, "-00:00:01"},
	{{45}, "+00:00:45"},
	{{90}, "+00:01:30"},
	{{-90}, "-00:01:30"},
	{{3_661}, "+01:01:01"},
	{{-3_661}, "-01:01:01"},
	{{19_801}, "+05:30:01"},
	{{59}, "+00:00:59"},
	{{60}, "+00:01"},
	// Minutes without hours.
	{{1_800}, "+00:30"},
	{{-1_800}, "-00:30"},
	// The two ends of the range.
	{chrono.ZONE_OFFSET_MAX, "+18:00"},
	{chrono.ZONE_OFFSET_MIN, "-18:00"},
	{{64_799}, "+17:59:59"},
	{{-64_799}, "-17:59:59"},
	{{64_740}, "+17:59"},
}

@(test)
test_zone_offset_bprint_known_values :: proc(t: ^testing.T) {
	for entry in ZONE_OFFSET_TEXT_CASES {
		buffer: [chrono.ZONE_OFFSET_TEXT_MAX]u8
		testing.expect_value(t, chrono.zone_offset_bprint(buffer[:], entry.offset), entry.text)
	}
}

@(test)
test_zone_offset_utc_is_always_z :: proc(t: ^testing.T) {
	buffer: [chrono.ZONE_OFFSET_TEXT_MAX]u8
	testing.expect_value(t, chrono.zone_offset_bprint(buffer[:], chrono.ZONE_OFFSET_UTC), "Z")
	testing.expect_value(t, chrono.zone_offset_bprint(buffer[:], {}), "Z")

	// No other offset prints as Z, and no offset prints as +00:00 or -00:00.
	for seconds in i32(-chrono.ZONE_OFFSET_SECONDS_MAX) ..= chrono.ZONE_OFFSET_SECONDS_MAX {
		text := chrono.zone_offset_bprint(buffer[:], {seconds})
		testing.expect_value(t, text == "Z", seconds == 0)
		testing.expect(t, text != "+00:00" && text != "-00:00")
	}
}

// Every valid offset: the text is built from the parts of the value, has the sign of the value,
// has seconds exactly when the offset is not a whole minute, and fits the limit.
@(test)
test_zone_offset_bprint_over_the_whole_range :: proc(t: ^testing.T) {
	buffer: [chrono.ZONE_OFFSET_TEXT_MAX]u8
	longest := 0
	for seconds in i32(-chrono.ZONE_OFFSET_SECONDS_MAX) ..= chrono.ZONE_OFFSET_SECONDS_MAX {
		text := chrono.zone_offset_bprint(buffer[:], {seconds})
		longest = max(longest, len(text))
		if seconds == 0 {
			continue
		}

		magnitude := abs(seconds)
		expected_sign: u8 = '-' if seconds < 0 else '+'
		testing.expect_value(t, text[0], expected_sign)

		hours := u8(magnitude / 3_600)
		minutes := u8(magnitude % 3_600 / 60)
		remaining := u8(magnitude % 60)
		testing.expect_value(t, text[1], '0' + hours / 10)
		testing.expect_value(t, text[2], '0' + hours % 10)
		testing.expect_value(t, text[3], ':')
		testing.expect_value(t, text[4], '0' + minutes / 10)
		testing.expect_value(t, text[5], '0' + minutes % 10)
		if remaining == 0 {
			testing.expect_value(t, len(text), 6)
		} else {
			testing.expect_value(t, len(text), 9)
			testing.expect_value(t, text[6], ':')
			testing.expect_value(t, text[7], '0' + remaining / 10)
			testing.expect_value(t, text[8], '0' + remaining % 10)
		}
	}
	testing.expect_value(t, longest, chrono.ZONE_OFFSET_TEXT_MAX)
}

// Different offsets never share a text, so the text can stand for the value.
@(test)
test_zone_offset_text_is_unique_for_every_offset :: proc(t: ^testing.T) {
	seen := make(map[string]i32)
	defer {
		for text in seen {
			delete(text)
		}
		delete(seen)
	}
	buffer: [chrono.ZONE_OFFSET_TEXT_MAX]u8
	duplicates := 0
	for seconds in i32(-chrono.ZONE_OFFSET_SECONDS_MAX) ..= chrono.ZONE_OFFSET_SECONDS_MAX {
		text := chrono.zone_offset_bprint(buffer[:], {seconds})
		if text in seen {
			duplicates += 1
		} else {
			seen[strings.clone(text)] = seconds
		}
	}
	testing.expect_value(t, duplicates, 0)
	testing.expect_value(t, len(seen), 129_601)
}

@(test)
test_zone_offset_text_max_is_the_longest_text :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.ZONE_OFFSET_TEXT_MAX, 9)
	buffer: [chrono.ZONE_OFFSET_TEXT_MAX]u8
	testing.expect_value(t, len(chrono.zone_offset_bprint(buffer[:], {-64_799})), 9)
	testing.expect_value(t, len(chrono.zone_offset_bprint(buffer[:], {64_799})), 9)
}

// Text order is not offset order, so nobody should sort offsets by their text. This pins down
// the ways it fails: Z sorts last, and a negative offset's text sorts the wrong way.
@(test)
test_zone_offset_text_order_is_not_offset_order :: proc(t: ^testing.T) {
	buffer_a: [chrono.ZONE_OFFSET_TEXT_MAX]u8
	buffer_b: [chrono.ZONE_OFFSET_TEXT_MAX]u8

	utc := chrono.zone_offset_bprint(buffer_a[:], chrono.ZONE_OFFSET_UTC)
	east := chrono.zone_offset_bprint(buffer_b[:], {19_800})
	testing.expect(t, utc > east) // "Z" > "+05:30" as text
	testing.expect_value(
		t,
		chrono.zone_offset_compare(chrono.ZONE_OFFSET_UTC, {19_800}),
		chrono.Ordering.less,
	)

	// -05:30 is a later offset than -08:00, but its text sorts earlier.
	minus_five := chrono.zone_offset_bprint(buffer_a[:], {-19_800})
	minus_eight := chrono.zone_offset_bprint(buffer_b[:], {-28_800})
	testing.expect(t, minus_five < minus_eight)
	testing.expect_value(
		t,
		chrono.zone_offset_compare({-19_800}, {-28_800}),
		chrono.Ordering.greater,
	)
}

@(test)
test_zone_offset_bprint_leaves_the_rest_of_the_buffer_alone :: proc(t: ^testing.T) {
	buffer: [20]u8
	for &byte in buffer {
		byte = '#'
	}
	text := chrono.zone_offset_bprint(buffer[:], {19_800})
	testing.expect_value(t, text, "+05:30")
	for byte in buffer[len(text):] {
		testing.expect_value(t, byte, '#')
	}

	for &byte in buffer {
		byte = '#'
	}
	text = chrono.zone_offset_bprint(buffer[:], chrono.ZONE_OFFSET_UTC)
	testing.expect_value(t, text, "Z")
	for byte in buffer[1:] {
		testing.expect_value(t, byte, '#')
	}
}

@(test)
test_zone_offset_bprint_accepts_a_buffer_of_exactly_the_maximum :: proc(t: ^testing.T) {
	buffer: [chrono.ZONE_OFFSET_TEXT_MAX]u8
	testing.expect_value(t, chrono.zone_offset_bprint(buffer[:], {-64_799}), "-17:59:59")
	testing.expect_value(t, chrono.zone_offset_bprint(buffer[:], {}), "Z")
}

// Building an offset from hours and minutes and printing it gives back those same parts.
@(test)
test_zone_offset_make_hours_minutes_prints_as_written :: proc(t: ^testing.T) {
	buffer: [chrono.ZONE_OFFSET_TEXT_MAX]u8
	cases := [?]struct {
		hours, minutes: i32,
		text:           string,
	} {
		{5, 30, "+05:30"},
		{-5, -30, "-05:30"},
		{0, 30, "+00:30"},
		{0, -30, "-00:30"},
		{18, 0, "+18:00"},
		{-18, 0, "-18:00"},
		{0, 0, "Z"},
		{5, 45, "+05:45"},
	}
	for entry in cases {
		offset, ok := chrono.zone_offset_make_hours_minutes(entry.hours, entry.minutes)
		testing.expect(t, ok)
		testing.expect_value(t, chrono.zone_offset_bprint(buffer[:], offset), entry.text)
	}
}

@(test)
test_zone_offset_aprint :: proc(t: ^testing.T) {
	for entry in ZONE_OFFSET_TEXT_CASES {
		text := chrono.zone_offset_aprint(entry.offset)
		defer delete(text)
		testing.expect_value(t, text, entry.text)
	}
}

@(test)
test_zone_offset_tprint :: proc(t: ^testing.T) {
	for entry in ZONE_OFFSET_TEXT_CASES {
		testing.expect_value(t, chrono.zone_offset_tprint(entry.offset), entry.text)
	}
	free_all(context.temp_allocator)
}

@(test)
test_zone_offset_caprint :: proc(t: ^testing.T) {
	for entry in ZONE_OFFSET_TEXT_CASES {
		text := chrono.zone_offset_caprint(entry.offset)
		defer delete(text)
		testing.expect_value(t, string(text), entry.text)
		testing.expect_value(t, (cast([^]u8)text)[len(entry.text)], 0)
	}
}

@(test)
test_zone_offset_sbprint_returns_only_what_it_appended :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "a ")
	first := chrono.zone_offset_sbprint(&builder, chrono.Zone_Offset{19_800})
	testing.expect_value(t, first, "+05:30")
	strings.write_string(&builder, " b ")
	second := chrono.zone_offset_sbprint(&builder, chrono.Zone_Offset{-28_800})
	testing.expect_value(t, second, "-08:00")
	expected := strings.concatenate({"a ", "+05:30", " b ", "-08:00"}, context.temp_allocator)
	testing.expect_value(t, strings.to_string(builder), expected)
	free_all(context.temp_allocator)
}

@(test)
test_zone_offset_wprint :: proc(t: ^testing.T) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	writer := strings.to_writer(&builder)
	testing.expect_value(
		t,
		chrono.zone_offset_wprint(writer, chrono.Zone_Offset{19_800}),
		len("+05:30"),
	)
	testing.expect_value(
		t,
		chrono.zone_offset_wprint(writer, chrono.Zone_Offset{-28_800}),
		len("-08:00"),
	)
	expected := strings.concatenate({"+05:30", "-08:00"}, context.temp_allocator)
	testing.expect_value(t, strings.to_string(builder), expected)
	free_all(context.temp_allocator)
}

@(test)
test_zone_offset_wprint_reports_what_was_written_when_the_writer_fails :: proc(t: ^testing.T) {
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
	written := chrono.zone_offset_wprint(writer, chrono.Zone_Offset{19_800})
	testing.expect_value(t, written, 4)
	testing.expect_value(t, string(storage[:]), "+05:30"[:4])
}

@(test)
test_zone_offset_fprint_writes_to_the_file :: proc(t: ^testing.T) {
	file, create_error := os.create_temp_file("", "chrono_format_zone_offset_*")
	testing.expect_value(t, create_error, nil)
	if create_error != nil {
		return
	}
	name := strings.clone(os.name(file))
	defer delete(name)
	defer os.remove(name)

	testing.expect_value(
		t,
		chrono.zone_offset_fprint(file, chrono.Zone_Offset{19_800}),
		len("+05:30"),
	)
	testing.expect_value(
		t,
		chrono.zone_offset_fprint(file, chrono.Zone_Offset{-28_800}),
		len("-08:00"),
	)
	testing.expect_value(t, os.close(file), nil)

	data, read_error := os.read_entire_file(name, context.allocator)
	defer delete(data)
	testing.expect_value(t, read_error, nil)
	expected := strings.concatenate({"+05:30", "-08:00"}, context.temp_allocator)
	testing.expect_value(t, string(data), expected)
	free_all(context.temp_allocator)
}

// Standard output and error cannot be captured here, so only the count is checked.
@(test)
test_zone_offset_print_and_eprint_return_the_length :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.zone_offset_print(chrono.Zone_Offset{19_800}), len("+05:30"))
	testing.expect_value(t, chrono.zone_offset_eprint(chrono.Zone_Offset{-28_800}), len("-08:00"))
}

@(test)
test_zone_offset_every_print_proc_produces_the_same_text :: proc(t: ^testing.T) {
	for entry in ZONE_OFFSET_TEXT_CASES {
		buffer: [chrono.ZONE_OFFSET_TEXT_MAX]u8
		expected := chrono.zone_offset_bprint(buffer[:], entry.offset)

		allocated := chrono.zone_offset_aprint(entry.offset)
		defer delete(allocated)
		testing.expect_value(t, allocated, expected)
		testing.expect_value(t, chrono.zone_offset_tprint(entry.offset), expected)

		c_text := chrono.zone_offset_caprint(entry.offset)
		defer delete(c_text)
		testing.expect_value(t, string(c_text), expected)

		builder: strings.Builder
		strings.builder_init(&builder)
		defer strings.builder_destroy(&builder)
		testing.expect_value(t, chrono.zone_offset_sbprint(&builder, entry.offset), expected)
		testing.expect_value(
			t,
			chrono.zone_offset_wprint(strings.to_writer(&builder), entry.offset),
			len(expected),
		)
	}
	free_all(context.temp_allocator)
}
