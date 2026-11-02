// Text for the library's types. Each type has nine procs named after those in `core:fmt`, with
// the type first: `bprint` writes into your buffer, `aprint` and `tprint` allocate, `caprint`
// makes a C string, and `sbprint`, `wprint`, `fprint`, `print` and `eprint` write to a builder,
// a writer, a file, standard output and standard error.
//
// They take one value, with no `args` or `sep`. They do not change what `fmt.println` prints for
// these types, which is still the struct fields.
package chrono

import "core:io"
import "core:os"
import "core:strings"

// ============================================================================
// constants: text length
// ============================================================================

// The longest `Local_Date` text: a sign, six year digits, and `-MM-DD`, like `-999999-01-01`.
LOCAL_DATE_TEXT_MAX :: 13

// The longest `Local_Time` text: `HH:MM:SS` and a dot and nine fraction digits, like
// `23:59:59.999999999`.
LOCAL_TIME_TEXT_MAX :: 18

// The longest `Local_Date_Time` text: the longest `Local_Date` text, `T` and the longest
// `Local_Time` text, like `+999999-12-31T23:59:59.999999999`.
LOCAL_DATE_TIME_TEXT_MAX :: 32

// The longest `Iso_Week_Date` text: a sign and six year digits, `-W`, two week digits, a dash
// and the weekday digit, like `-999999-W01-1`.
ISO_WEEK_DATE_TEXT_MAX :: 13

// The longest `Zone_Offset` text: a sign and `HH:MM:SS`, like `-17:59:59`.
ZONE_OFFSET_TEXT_MAX :: 9

// The longest `Duration` text: `PT`, an 11 digit hour count, `59M` and `59`, a dot and nine
// fraction digits and `S`, with a minus before every number, like
// `PT-17531631215H-59M-59.999999999S`.
DURATION_TEXT_MAX :: 33

// The longest `Instant` text: the longest `Local_Date` text, `T`, the longest `Local_Time` text
// and `Z`, like `+999999-12-31T23:59:59.999999999Z`.
INSTANT_TEXT_MAX :: 33

// The longest `Period` text: `P` and the three fields at their caps, all negative, like
// `P-1999998Y-23999976M-730484633D`.
PERIOD_TEXT_MAX :: 31

// ============================================================================
// procs: shared digit writers
// ============================================================================

// Writes `value` in decimal at the start of `buffer` and returns the digit count. No padding.
@(private = "file")
text_write_unsigned :: proc(buffer: []u8, value: u64) -> int {
	digit_count := 1
	for remaining := value; remaining >= 10; remaining /= 10 {
		digit_count += 1
	}
	assert(digit_count <= 20)
	assert(len(buffer) >= digit_count)

	remaining := value
	for index := digit_count - 1; index >= 0; index -= 1 {
		buffer[index] = u8('0' + remaining % 10)
		remaining /= 10
	}

	return digit_count
}

// Writes `magnitude` in decimal at the start of `buffer`, after a minus sign when `is_negative`,
// and returns the byte count. The sign is separate so that a negative zero part can still show
// its sign, as `PT-0.5S` does.
@(private = "file")
text_write_integer :: proc(buffer: []u8, is_negative: bool, magnitude: u64) -> int {
	length := 0
	if is_negative {
		buffer[length] = '-'
		length += 1
	}

	return length + text_write_unsigned(buffer[length:], magnitude)
}

// Writes a year as the date formats do and returns the byte count: 4 to 7 bytes. Years 0 to
// 9999 are exactly 4 digits, so year 5 is `0005`. Other years get a sign and at least 4 digits:
// year -5 is `-0005` and year 10000 is `+10000`. The year must be within `YEAR_MIN..YEAR_MAX`.
@(private = "file")
text_write_year :: proc(buffer: []u8, year: Year) -> int {
	assert(year_is_valid(year))
	assert(len(buffer) >= 7)

	length := 0
	magnitude := i64(year)
	if magnitude < 0 || magnitude > 9999 {
		buffer[length] = '-' if magnitude < 0 else '+'
		length += 1
		magnitude = abs(magnitude)
	}

	// The year has 4 to 6 digits, written from the last digit backwards.
	digit_count: int = 4
	for limit: i64 = 10_000; magnitude >= limit; limit *= 10 {
		digit_count += 1
	}
	assert(digit_count <= 6)
	for index := digit_count - 1; index >= 0; index -= 1 {
		buffer[length + index] = u8('0' + magnitude % 10)
		magnitude /= 10
	}

	return length + digit_count
}

// Writes a dot and the nanoseconds as digits at the start of `buffer`, with the trailing zeros
// trimmed, and returns the byte count: 1 to 10. Only those bytes are written, so the rest of
// the caller's buffer stays untouched. `nanoseconds` must not be zero.
@(private = "file")
text_write_fraction :: proc(buffer: []u8, nanoseconds: u32) -> int {
	assert(nanoseconds > 0 && nanoseconds < NANOSECONDS_PER_SECOND)
	assert(len(buffer) >= 10)

	remaining := nanoseconds
	digit_count := 9
	for remaining % 10 == 0 {
		remaining /= 10
		digit_count -= 1
	}
	assert(digit_count >= 1)

	buffer[0] = '.'
	for index := digit_count; index >= 1; index -= 1 {
		buffer[index] = u8('0' + remaining % 10)
		remaining /= 10
	}
	assert(remaining == 0)

	return 1 + digit_count
}

// ============================================================================
// procs: local date text
// ============================================================================

// Writes the date as ISO 8601 text, `YYYY-MM-DD`, into `buffer` and returns the written part.
// Years 0 to 9999 have exactly 4 digits, so year 5 is `0005`. Other years get a sign and at
// least 4 digits: year -5 is `-0005` and year 10000 is `+10000`.
//
// Text order is date order only for years 0 to 9999: `+10000` sorts before `0000`, and `-0001`
// sorts before `-0005` though it is later.
//
// It never allocates and cannot fail. `buffer` must hold `LOCAL_DATE_TEXT_MAX` bytes, which is
// asserted, so size it as `[LOCAL_DATE_TEXT_MAX]u8`. `fmt.bprint` instead truncates silently,
// which would turn `2026-11-01` into `2026`.
local_date_bprint :: proc(buffer: []u8, date: Local_Date) -> string {
	assert(len(buffer) >= LOCAL_DATE_TEXT_MAX)
	assert(local_date_is_valid(date))

	length := text_write_year(buffer, date.year)

	buffer[length] = '-'
	buffer[length + 1] = u8('0' + u8(date.month) / 10)
	buffer[length + 2] = u8('0' + u8(date.month) % 10)
	buffer[length + 3] = '-'
	buffer[length + 4] = u8('0' + date.day / 10)
	buffer[length + 5] = u8('0' + date.day % 10)
	length += 6
	assert(length <= LOCAL_DATE_TEXT_MAX)

	return string(buffer[:length])
}

// The text from `local_date_bprint`, in a new string. Free it with `delete` and the same
// allocator. Returns an empty string if the allocation fails.
local_date_aprint :: proc(date: Local_Date, allocator := context.allocator) -> string {
	buffer: [LOCAL_DATE_TEXT_MAX]u8
	text, _ := strings.clone(local_date_bprint(buffer[:], date), allocator)

	return text
}

// The text from `local_date_bprint`, in a new string from `context.temp_allocator`. It is freed
// with the rest of the temporary memory, not individually.
local_date_tprint :: proc(date: Local_Date) -> string {
	return local_date_aprint(date, context.temp_allocator)
}

// The text from `local_date_bprint` as a null terminated C string in a new allocation. Free it
// with `delete` and the same allocator. Returns an empty string if the allocation fails.
local_date_caprint :: proc(date: Local_Date, allocator := context.allocator) -> cstring {
	buffer: [LOCAL_DATE_TEXT_MAX]u8
	text, _ := strings.clone_to_cstring(local_date_bprint(buffer[:], date), allocator)

	return text
}

// Appends the text to the builder and returns the text that was appended, not the whole
// builder. That differs from `fmt.sbprint`, which returns everything in the builder.
local_date_sbprint :: proc(builder: ^strings.Builder, date: Local_Date) -> string {
	buffer: [LOCAL_DATE_TEXT_MAX]u8
	text := local_date_bprint(buffer[:], date)
	start := len(builder.buf)
	strings.write_string(builder, text)

	return string(builder.buf[start:])
}

// Writes the text to the writer and returns the number of bytes written. A write error stops
// the write, and the count is then what was written before it.
local_date_wprint :: proc(writer: io.Writer, date: Local_Date) -> int {
	buffer: [LOCAL_DATE_TEXT_MAX]u8
	written, _ := io.write_string(writer, local_date_bprint(buffer[:], date))

	return written
}

// Writes the text to the file and returns the number of bytes written.
local_date_fprint :: proc(file: ^os.File, date: Local_Date) -> int {
	buffer: [LOCAL_DATE_TEXT_MAX]u8
	written, _ := os.write_string(file, local_date_bprint(buffer[:], date))

	return written
}

// Writes the text to standard output and returns the number of bytes written.
local_date_print :: proc(date: Local_Date) -> int {
	return local_date_fprint(os.stdout, date)
}

// Writes the text to standard error and returns the number of bytes written.
local_date_eprint :: proc(date: Local_Date) -> int {
	return local_date_fprint(os.stderr, date)
}

// ============================================================================
// procs: local time text
// ============================================================================

// Writes the time as ISO 8601 text, `HH:MM:SS`, into `buffer` and returns the written part. A
// non-zero fraction follows a dot as nanosecond digits with the trailing zeros trimmed:
// `14:30:00` has none, `14:30:00.5` is half a second, and `00:00:00.000000001` is one
// nanosecond. A whole second never shows a fraction.
//
// Every time has exactly one text, and the text sorts as the time does, so sorted texts are
// sorted times. The seconds are always written, where Java drops zero ones and writes `14:30`.
//
// It never allocates and cannot fail. `buffer` must hold `LOCAL_TIME_TEXT_MAX` bytes, which is
// asserted, so size it as `[LOCAL_TIME_TEXT_MAX]u8`.
local_time_bprint :: proc(buffer: []u8, time: Local_Time) -> string {
	assert(len(buffer) >= LOCAL_TIME_TEXT_MAX)
	assert(local_time_is_valid(time))

	buffer[0] = u8('0' + time.hour / 10)
	buffer[1] = u8('0' + time.hour % 10)
	buffer[2] = ':'
	buffer[3] = u8('0' + time.minute / 10)
	buffer[4] = u8('0' + time.minute % 10)
	buffer[5] = ':'
	buffer[6] = u8('0' + time.second / 10)
	buffer[7] = u8('0' + time.second % 10)
	length := 8

	if time.nanoseconds != 0 {
		length += text_write_fraction(buffer[length:], time.nanoseconds)
	}
	assert(length <= LOCAL_TIME_TEXT_MAX)

	return string(buffer[:length])
}

// The text from `local_time_bprint`, in a new string. Free it with `delete` and the same
// allocator. Returns an empty string if the allocation fails.
local_time_aprint :: proc(time: Local_Time, allocator := context.allocator) -> string {
	buffer: [LOCAL_TIME_TEXT_MAX]u8
	text, _ := strings.clone(local_time_bprint(buffer[:], time), allocator)

	return text
}

// The text from `local_time_bprint`, in a new string from `context.temp_allocator`. It is freed
// with the rest of the temporary memory, not individually.
local_time_tprint :: proc(time: Local_Time) -> string {
	return local_time_aprint(time, context.temp_allocator)
}

// The text from `local_time_bprint` as a null terminated C string in a new allocation. Free it
// with `delete` and the same allocator. Returns an empty string if the allocation fails.
local_time_caprint :: proc(time: Local_Time, allocator := context.allocator) -> cstring {
	buffer: [LOCAL_TIME_TEXT_MAX]u8
	text, _ := strings.clone_to_cstring(local_time_bprint(buffer[:], time), allocator)

	return text
}

// Appends the text to the builder and returns the text that was appended, not the whole
// builder. That differs from `fmt.sbprint`, which returns everything in the builder.
local_time_sbprint :: proc(builder: ^strings.Builder, time: Local_Time) -> string {
	buffer: [LOCAL_TIME_TEXT_MAX]u8
	text := local_time_bprint(buffer[:], time)
	start := len(builder.buf)
	strings.write_string(builder, text)

	return string(builder.buf[start:])
}

// Writes the text to the writer and returns the number of bytes written. A write error stops
// the write, and the count is then what was written before it.
local_time_wprint :: proc(writer: io.Writer, time: Local_Time) -> int {
	buffer: [LOCAL_TIME_TEXT_MAX]u8
	written, _ := io.write_string(writer, local_time_bprint(buffer[:], time))

	return written
}

// Writes the text to the file and returns the number of bytes written.
local_time_fprint :: proc(file: ^os.File, time: Local_Time) -> int {
	buffer: [LOCAL_TIME_TEXT_MAX]u8
	written, _ := os.write_string(file, local_time_bprint(buffer[:], time))

	return written
}

// Writes the text to standard output and returns the number of bytes written.
local_time_print :: proc(time: Local_Time) -> int {
	return local_time_fprint(os.stdout, time)
}

// Writes the text to standard error and returns the number of bytes written.
local_time_eprint :: proc(time: Local_Time) -> int {
	return local_time_fprint(os.stderr, time)
}

// ============================================================================
// procs: duration text
// ============================================================================

// Writes the duration as ISO 8601 text into `buffer` and returns the written part: `PT1H30M`
// for an hour and a half, `PT1M30S` for 90 seconds, `PT0.5S` for half a second, and `PT0S` for
// nothing. There are only hours, minutes and seconds, never days: 48 hours is `PT48H`, because
// a day is not always 24 hours. A part that is zero is left out.
//
// A negative duration puts the minus on every part, like `PT-1H-30M` and `PT-0.5S`, which is
// what Java's `Duration.toString` writes, and the form `Period` uses. The fraction is the
// nanoseconds with the trailing zeros trimmed.
//
// Text order is not duration order: `PT1M` sorts before `PT2S`. It never allocates and cannot
// fail. `buffer` must hold `DURATION_TEXT_MAX` bytes, which is asserted, so size it as
// `[DURATION_TEXT_MAX]u8`.
duration_bprint :: proc(buffer: []u8, duration: Duration) -> string {
	assert(len(buffer) >= DURATION_TEXT_MAX)
	assert(duration_is_valid(duration))

	// The text shows the magnitude. A negative duration keeps its nanoseconds counting forward,
	// so minus 1.25 seconds is {-2, 750_000_000}: the magnitude is one second less than the
	// negated seconds, plus the nanoseconds that are missing from a whole second.
	is_negative := duration.seconds < 0
	magnitude_seconds := u64(duration.seconds)
	magnitude_nanoseconds := duration.nanoseconds
	if is_negative {
		if duration.nanoseconds == 0 {
			magnitude_seconds = u64(-duration.seconds)
		} else {
			magnitude_seconds = u64(-duration.seconds - 1)
			magnitude_nanoseconds = NANOSECONDS_PER_SECOND - duration.nanoseconds
		}
	}

	hours := magnitude_seconds / SECONDS_PER_HOUR
	minutes := magnitude_seconds % SECONDS_PER_HOUR / SECONDS_PER_MINUTE
	seconds := magnitude_seconds % SECONDS_PER_MINUTE

	length := 0
	buffer[length] = 'P'
	buffer[length + 1] = 'T'
	length += 2

	if magnitude_seconds == 0 && magnitude_nanoseconds == 0 {
		buffer[length] = '0'
		buffer[length + 1] = 'S'
		length += 2
	} else {
		if hours != 0 {
			length += text_write_integer(buffer[length:], is_negative, hours)
			buffer[length] = 'H'
			length += 1
		}
		if minutes != 0 {
			length += text_write_integer(buffer[length:], is_negative, minutes)
			buffer[length] = 'M'
			length += 1
		}
		if seconds != 0 || magnitude_nanoseconds != 0 {
			length += text_write_integer(buffer[length:], is_negative, seconds)
			if magnitude_nanoseconds != 0 {
				length += text_write_fraction(buffer[length:], magnitude_nanoseconds)
			}
			buffer[length] = 'S'
			length += 1
		}
	}
	assert(length <= DURATION_TEXT_MAX)

	return string(buffer[:length])
}

// The text from `duration_bprint`, in a new string. Free it with `delete` and the same
// allocator. Returns an empty string if the allocation fails.
duration_aprint :: proc(duration: Duration, allocator := context.allocator) -> string {
	buffer: [DURATION_TEXT_MAX]u8
	text, _ := strings.clone(duration_bprint(buffer[:], duration), allocator)

	return text
}

// The text from `duration_bprint`, in a new string from `context.temp_allocator`. It is freed
// with the rest of the temporary memory, not individually.
duration_tprint :: proc(duration: Duration) -> string {
	return duration_aprint(duration, context.temp_allocator)
}

// The text from `duration_bprint` as a null terminated C string in a new allocation. Free it
// with `delete` and the same allocator. Returns an empty string if the allocation fails.
duration_caprint :: proc(duration: Duration, allocator := context.allocator) -> cstring {
	buffer: [DURATION_TEXT_MAX]u8
	text, _ := strings.clone_to_cstring(duration_bprint(buffer[:], duration), allocator)

	return text
}

// Appends the text to the builder and returns the text that was appended, not the whole
// builder. That differs from `fmt.sbprint`, which returns everything in the builder.
duration_sbprint :: proc(builder: ^strings.Builder, duration: Duration) -> string {
	buffer: [DURATION_TEXT_MAX]u8
	text := duration_bprint(buffer[:], duration)
	start := len(builder.buf)
	strings.write_string(builder, text)

	return string(builder.buf[start:])
}

// Writes the text to the writer and returns the number of bytes written. A write error stops
// the write, and the count is then what was written before it.
duration_wprint :: proc(writer: io.Writer, duration: Duration) -> int {
	buffer: [DURATION_TEXT_MAX]u8
	written, _ := io.write_string(writer, duration_bprint(buffer[:], duration))

	return written
}

// Writes the text to the file and returns the number of bytes written.
duration_fprint :: proc(file: ^os.File, duration: Duration) -> int {
	buffer: [DURATION_TEXT_MAX]u8
	written, _ := os.write_string(file, duration_bprint(buffer[:], duration))

	return written
}

// Writes the text to standard output and returns the number of bytes written.
duration_print :: proc(duration: Duration) -> int {
	return duration_fprint(os.stdout, duration)
}

// Writes the text to standard error and returns the number of bytes written.
duration_eprint :: proc(duration: Duration) -> int {
	return duration_fprint(os.stderr, duration)
}

// ============================================================================
// procs: instant text
// ============================================================================

// Writes the moment as ISO 8601 text in UTC into `buffer` and returns the written part:
// `2026-11-01T14:30:00Z`, with a fraction only when it is not zero, like
// `2026-11-01T14:30:00.5Z`. The date follows `local_date_bprint`, the time follows
// `local_time_bprint`, and the `Z` says it is UTC, so there is no offset to write. To show the
// moment at another offset, convert it with `instant_to_local_date_time` and print that.
//
// The fraction is the nanoseconds with the trailing zeros trimmed. Java groups it in threes, so
// it writes `.500Z` where this writes `.5Z`, and its parser reads both. Text order is the
// instant order only for years 0 to 9999: `+10000` sorts before `0000`, and `-0001` sorts
// before `-0005` though it is later.
//
// It never allocates and cannot fail. `buffer` must hold `INSTANT_TEXT_MAX` bytes, which is
// asserted, so size it as `[INSTANT_TEXT_MAX]u8`.
instant_bprint :: proc(buffer: []u8, instant: Instant) -> string {
	assert(len(buffer) >= INSTANT_TEXT_MAX)
	assert(instant_is_valid(instant))

	// An instant at UTC always lands on a supported date, so this cannot fail.
	date_time, ok := instant_to_local_date_time(instant, ZONE_OFFSET_UTC)
	assert(ok)

	length := len(local_date_bprint(buffer, date_time.date))
	buffer[length] = 'T'
	length += 1
	length += len(local_time_bprint(buffer[length:], date_time.time))
	buffer[length] = 'Z'
	length += 1
	assert(length <= INSTANT_TEXT_MAX)

	return string(buffer[:length])
}

// The text from `instant_bprint`, in a new string. Free it with `delete` and the same
// allocator. Returns an empty string if the allocation fails.
instant_aprint :: proc(instant: Instant, allocator := context.allocator) -> string {
	buffer: [INSTANT_TEXT_MAX]u8
	text, _ := strings.clone(instant_bprint(buffer[:], instant), allocator)

	return text
}

// The text from `instant_bprint`, in a new string from `context.temp_allocator`. It is freed
// with the rest of the temporary memory, not individually.
instant_tprint :: proc(instant: Instant) -> string {
	return instant_aprint(instant, context.temp_allocator)
}

// The text from `instant_bprint` as a null terminated C string in a new allocation. Free it
// with `delete` and the same allocator. Returns an empty string if the allocation fails.
instant_caprint :: proc(instant: Instant, allocator := context.allocator) -> cstring {
	buffer: [INSTANT_TEXT_MAX]u8
	text, _ := strings.clone_to_cstring(instant_bprint(buffer[:], instant), allocator)

	return text
}

// Appends the text to the builder and returns the text that was appended, not the whole
// builder. That differs from `fmt.sbprint`, which returns everything in the builder.
instant_sbprint :: proc(builder: ^strings.Builder, instant: Instant) -> string {
	buffer: [INSTANT_TEXT_MAX]u8
	text := instant_bprint(buffer[:], instant)
	start := len(builder.buf)
	strings.write_string(builder, text)

	return string(builder.buf[start:])
}

// Writes the text to the writer and returns the number of bytes written. A write error stops
// the write, and the count is then what was written before it.
instant_wprint :: proc(writer: io.Writer, instant: Instant) -> int {
	buffer: [INSTANT_TEXT_MAX]u8
	written, _ := io.write_string(writer, instant_bprint(buffer[:], instant))

	return written
}

// Writes the text to the file and returns the number of bytes written.
instant_fprint :: proc(file: ^os.File, instant: Instant) -> int {
	buffer: [INSTANT_TEXT_MAX]u8
	written, _ := os.write_string(file, instant_bprint(buffer[:], instant))

	return written
}

// Writes the text to standard output and returns the number of bytes written.
instant_print :: proc(instant: Instant) -> int {
	return instant_fprint(os.stdout, instant)
}

// Writes the text to standard error and returns the number of bytes written.
instant_eprint :: proc(instant: Instant) -> int {
	return instant_fprint(os.stderr, instant)
}

// ============================================================================
// procs: period text
// ============================================================================

// Writes the period as ISO 8601 text into `buffer` and returns the written part: `P1Y2M3D` for a
// year, two months and three days, `P14M` for fourteen months, and `P0D` for nothing. A field
// that is zero is left out, and nothing is carried between fields, so 14 months stays `P14M`.
//
// Each field has its own sign: `P1Y-2M` is a year forward and two months back, so a single sign
// in front could not say it. A negative field puts the minus before its number, like Java's
// `Period.toString`, which writes `P-1Y-3D`. A `Period` has no order, so the text has none.
//
// It never allocates and cannot fail. `buffer` must hold `PERIOD_TEXT_MAX` bytes, which is
// asserted, so size it as `[PERIOD_TEXT_MAX]u8`.
period_bprint :: proc(buffer: []u8, period: Period) -> string {
	assert(len(buffer) >= PERIOD_TEXT_MAX)
	assert(period_is_valid(period))

	buffer[0] = 'P'
	length := 1
	if period == {} {
		buffer[length] = '0'
		buffer[length + 1] = 'D'
		length += 2
	} else {
		fields := [3]i32{period.years, period.months, period.days}
		units := [3]u8{'Y', 'M', 'D'}
		for field, index in fields {
			if field == 0 {
				continue
			}
			length += text_write_integer(buffer[length:], field < 0, u64(abs(i64(field))))
			buffer[length] = units[index]
			length += 1
		}
	}
	assert(length <= PERIOD_TEXT_MAX)

	return string(buffer[:length])
}

// The text from `period_bprint`, in a new string. Free it with `delete` and the same
// allocator. Returns an empty string if the allocation fails.
period_aprint :: proc(period: Period, allocator := context.allocator) -> string {
	buffer: [PERIOD_TEXT_MAX]u8
	text, _ := strings.clone(period_bprint(buffer[:], period), allocator)

	return text
}

// The text from `period_bprint`, in a new string from `context.temp_allocator`. It is freed
// with the rest of the temporary memory, not individually.
period_tprint :: proc(period: Period) -> string {
	return period_aprint(period, context.temp_allocator)
}

// The text from `period_bprint` as a null terminated C string in a new allocation. Free it
// with `delete` and the same allocator. Returns an empty string if the allocation fails.
period_caprint :: proc(period: Period, allocator := context.allocator) -> cstring {
	buffer: [PERIOD_TEXT_MAX]u8
	text, _ := strings.clone_to_cstring(period_bprint(buffer[:], period), allocator)

	return text
}

// Appends the text to the builder and returns the text that was appended, not the whole
// builder. That differs from `fmt.sbprint`, which returns everything in the builder.
period_sbprint :: proc(builder: ^strings.Builder, period: Period) -> string {
	buffer: [PERIOD_TEXT_MAX]u8
	text := period_bprint(buffer[:], period)
	start := len(builder.buf)
	strings.write_string(builder, text)

	return string(builder.buf[start:])
}

// Writes the text to the writer and returns the number of bytes written. A write error stops
// the write, and the count is then what was written before it.
period_wprint :: proc(writer: io.Writer, period: Period) -> int {
	buffer: [PERIOD_TEXT_MAX]u8
	written, _ := io.write_string(writer, period_bprint(buffer[:], period))

	return written
}

// Writes the text to the file and returns the number of bytes written.
period_fprint :: proc(file: ^os.File, period: Period) -> int {
	buffer: [PERIOD_TEXT_MAX]u8
	written, _ := os.write_string(file, period_bprint(buffer[:], period))

	return written
}

// Writes the text to standard output and returns the number of bytes written.
period_print :: proc(period: Period) -> int {
	return period_fprint(os.stdout, period)
}

// Writes the text to standard error and returns the number of bytes written.
period_eprint :: proc(period: Period) -> int {
	return period_fprint(os.stderr, period)
}

// ============================================================================
// procs: local date time text
// ============================================================================

// Writes the date and time as ISO 8601 text into `buffer` and returns the written part:
// `2026-11-01T14:30:00`, with a fraction only when it is not zero, like
// `2026-11-01T14:30:00.5`. It is the `local_date_bprint` text, a `T`, and the
// `local_time_bprint` text, so the year and fraction rules are theirs. There is no `Z` and no
// offset, because a `Local_Date_Time` has no zone. See `offset_date_time` for a moment.
//
// The seconds are always written. Java drops them when they are zero and writes
// `2026-11-01T14:30`, which reads back the same, but this keeps one text for every value. Text
// order is time order only for years 0 to 9999: `+10000` sorts before `0000`, and `-0001`
// sorts before `-0005` though it is later.
//
// It never allocates and cannot fail. `buffer` must hold `LOCAL_DATE_TIME_TEXT_MAX` bytes,
// which is asserted, so size it as `[LOCAL_DATE_TIME_TEXT_MAX]u8`.
local_date_time_bprint :: proc(buffer: []u8, date_time: Local_Date_Time) -> string {
	assert(len(buffer) >= LOCAL_DATE_TIME_TEXT_MAX)
	assert(local_date_time_is_valid(date_time))

	length := len(local_date_bprint(buffer, date_time.date))
	buffer[length] = 'T'
	length += 1
	length += len(local_time_bprint(buffer[length:], date_time.time))
	assert(length <= LOCAL_DATE_TIME_TEXT_MAX)

	return string(buffer[:length])
}

// The text from `local_date_time_bprint`, in a new string. Free it with `delete` and the same
// allocator. Returns an empty string if the allocation fails.
local_date_time_aprint :: proc(
	local_date_time: Local_Date_Time,
	allocator := context.allocator,
) -> string {
	buffer: [LOCAL_DATE_TIME_TEXT_MAX]u8
	text, _ := strings.clone(local_date_time_bprint(buffer[:], local_date_time), allocator)

	return text
}

// The text from `local_date_time_bprint`, in a new string from `context.temp_allocator`. It is
// freed with the rest of the temporary memory, not individually.
local_date_time_tprint :: proc(local_date_time: Local_Date_Time) -> string {
	return local_date_time_aprint(local_date_time, context.temp_allocator)
}

// The text from `local_date_time_bprint` as a null terminated C string in a new allocation. Free it
// with `delete` and the same allocator. Returns an empty string if the allocation fails.
local_date_time_caprint :: proc(
	local_date_time: Local_Date_Time,
	allocator := context.allocator,
) -> cstring {
	buffer: [LOCAL_DATE_TIME_TEXT_MAX]u8
	text, _ := strings.clone_to_cstring(
		local_date_time_bprint(buffer[:], local_date_time),
		allocator,
	)

	return text
}

// Appends the text to the builder and returns the text that was appended, not the whole
// builder. That differs from `fmt.sbprint`, which returns everything in the builder.
local_date_time_sbprint :: proc(
	builder: ^strings.Builder,
	local_date_time: Local_Date_Time,
) -> string {
	buffer: [LOCAL_DATE_TIME_TEXT_MAX]u8
	text := local_date_time_bprint(buffer[:], local_date_time)
	start := len(builder.buf)
	strings.write_string(builder, text)

	return string(builder.buf[start:])
}

// Writes the text to the writer and returns the number of bytes written. A write error stops
// the write, and the count is then what was written before it.
local_date_time_wprint :: proc(writer: io.Writer, local_date_time: Local_Date_Time) -> int {
	buffer: [LOCAL_DATE_TIME_TEXT_MAX]u8
	written, _ := io.write_string(writer, local_date_time_bprint(buffer[:], local_date_time))

	return written
}

// Writes the text to the file and returns the number of bytes written.
local_date_time_fprint :: proc(file: ^os.File, local_date_time: Local_Date_Time) -> int {
	buffer: [LOCAL_DATE_TIME_TEXT_MAX]u8
	written, _ := os.write_string(file, local_date_time_bprint(buffer[:], local_date_time))

	return written
}

// Writes the text to standard output and returns the number of bytes written.
local_date_time_print :: proc(local_date_time: Local_Date_Time) -> int {
	return local_date_time_fprint(os.stdout, local_date_time)
}

// Writes the text to standard error and returns the number of bytes written.
local_date_time_eprint :: proc(local_date_time: Local_Date_Time) -> int {
	return local_date_time_fprint(os.stderr, local_date_time)
}

// ============================================================================
// procs: iso week date text
// ============================================================================

// Writes the week date as ISO 8601 text into `buffer` and returns the written part:
// `2026-W44-7` is the Sunday of week 44 of 2026. The week year is written like the year of a
// date, four digits for 0 to 9999 and a sign outside that, the week is always two digits, and
// the weekday is one digit from 1 for Monday to 7 for Sunday. Only this extended form is
// written, not the compact `2026W447`.
//
// The week year is not always the calendar year: 2021-01-01 is `2020-W53-5`. Text order is
// date order only for week years 0 to 9999, as for the date text.
//
// It never allocates and cannot fail on a valid value, see `iso_week_date_is_valid`. `buffer`
// must hold `ISO_WEEK_DATE_TEXT_MAX` bytes, which is asserted, so size it as
// `[ISO_WEEK_DATE_TEXT_MAX]u8`.
iso_week_date_bprint :: proc(buffer: []u8, iso: Iso_Week_Date) -> string {
	assert(len(buffer) >= ISO_WEEK_DATE_TEXT_MAX)
	assert(iso_week_date_is_valid(iso))

	length := text_write_year(buffer, iso.week_year)
	buffer[length] = '-'
	buffer[length + 1] = 'W'
	buffer[length + 2] = u8('0' + iso.week / 10)
	buffer[length + 3] = u8('0' + iso.week % 10)
	buffer[length + 4] = '-'
	buffer[length + 5] = u8('0' + u8(iso.weekday))
	length += 6
	assert(length <= ISO_WEEK_DATE_TEXT_MAX)

	return string(buffer[:length])
}

// The text from `iso_week_date_bprint`, in a new string. Free it with `delete` and the same
// allocator. Returns an empty string if the allocation fails.
iso_week_date_aprint :: proc(
	iso_week_date: Iso_Week_Date,
	allocator := context.allocator,
) -> string {
	buffer: [ISO_WEEK_DATE_TEXT_MAX]u8
	text, _ := strings.clone(iso_week_date_bprint(buffer[:], iso_week_date), allocator)

	return text
}

// The text from `iso_week_date_bprint`, in a new string from `context.temp_allocator`. It is freed
// with the rest of the temporary memory, not individually.
iso_week_date_tprint :: proc(iso_week_date: Iso_Week_Date) -> string {
	return iso_week_date_aprint(iso_week_date, context.temp_allocator)
}

// The text from `iso_week_date_bprint` as a null terminated C string in a new allocation. Free it
// with `delete` and the same allocator. Returns an empty string if the allocation fails.
iso_week_date_caprint :: proc(
	iso_week_date: Iso_Week_Date,
	allocator := context.allocator,
) -> cstring {
	buffer: [ISO_WEEK_DATE_TEXT_MAX]u8
	text, _ := strings.clone_to_cstring(iso_week_date_bprint(buffer[:], iso_week_date), allocator)

	return text
}

// Appends the text to the builder and returns the text that was appended, not the whole
// builder. That differs from `fmt.sbprint`, which returns everything in the builder.
iso_week_date_sbprint :: proc(builder: ^strings.Builder, iso_week_date: Iso_Week_Date) -> string {
	buffer: [ISO_WEEK_DATE_TEXT_MAX]u8
	text := iso_week_date_bprint(buffer[:], iso_week_date)
	start := len(builder.buf)
	strings.write_string(builder, text)

	return string(builder.buf[start:])
}

// Writes the text to the writer and returns the number of bytes written. A write error stops
// the write, and the count is then what was written before it.
iso_week_date_wprint :: proc(writer: io.Writer, iso_week_date: Iso_Week_Date) -> int {
	buffer: [ISO_WEEK_DATE_TEXT_MAX]u8
	written, _ := io.write_string(writer, iso_week_date_bprint(buffer[:], iso_week_date))

	return written
}

// Writes the text to the file and returns the number of bytes written.
iso_week_date_fprint :: proc(file: ^os.File, iso_week_date: Iso_Week_Date) -> int {
	buffer: [ISO_WEEK_DATE_TEXT_MAX]u8
	written, _ := os.write_string(file, iso_week_date_bprint(buffer[:], iso_week_date))

	return written
}

// Writes the text to standard output and returns the number of bytes written.
iso_week_date_print :: proc(iso_week_date: Iso_Week_Date) -> int {
	return iso_week_date_fprint(os.stdout, iso_week_date)
}

// Writes the text to standard error and returns the number of bytes written.
iso_week_date_eprint :: proc(iso_week_date: Iso_Week_Date) -> int {
	return iso_week_date_fprint(os.stderr, iso_week_date)
}

// ============================================================================
// procs: zone offset text
// ============================================================================

// Writes the offset as ISO 8601 text into `buffer` and returns the written part: `Z` for UTC,
// otherwise a sign and `HH:MM`, like `+05:30` and `-08:00`. The seconds follow as `:SS` only
// when they are not zero, like `+00:00:01`. This is the text of Java's `ZoneOffset.toString`.
//
// Zero is always `Z`, never `+00:00` or `-00:00`, so every offset has exactly one text. The
// seconds are optional here, where `local_time_bprint` always writes them: real offsets are
// whole minutes, so `+05:30` is the shape people expect, and it cannot be mistaken for anything
// else.
//
// Text order is not offset order: `Z` sorts after `+` and `-`, and `-05:30` sorts before
// `-08:00` though it is later. Use `zone_offset_compare`. It never allocates and cannot fail.
// `buffer` must hold `ZONE_OFFSET_TEXT_MAX` bytes, which is asserted, so size it as
// `[ZONE_OFFSET_TEXT_MAX]u8`.
zone_offset_bprint :: proc(buffer: []u8, offset: Zone_Offset) -> string {
	assert(len(buffer) >= ZONE_OFFSET_TEXT_MAX)
	assert(zone_offset_is_valid(offset))

	if offset.seconds == 0 {
		buffer[0] = 'Z'
		return string(buffer[:1])
	}

	magnitude := u32(abs(offset.seconds))
	hours := magnitude / SECONDS_PER_HOUR
	minutes := magnitude % SECONDS_PER_HOUR / SECONDS_PER_MINUTE
	seconds := magnitude % SECONDS_PER_MINUTE
	assert(hours <= 18)

	buffer[0] = '-' if offset.seconds < 0 else '+'
	buffer[1] = u8('0' + hours / 10)
	buffer[2] = u8('0' + hours % 10)
	buffer[3] = ':'
	buffer[4] = u8('0' + minutes / 10)
	buffer[5] = u8('0' + minutes % 10)
	length := 6
	if seconds != 0 {
		buffer[6] = ':'
		buffer[7] = u8('0' + seconds / 10)
		buffer[8] = u8('0' + seconds % 10)
		length = 9
	}
	assert(length <= ZONE_OFFSET_TEXT_MAX)

	return string(buffer[:length])
}

// The text from `zone_offset_bprint`, in a new string. Free it with `delete` and the same
// allocator. Returns an empty string if the allocation fails.
zone_offset_aprint :: proc(zone_offset: Zone_Offset, allocator := context.allocator) -> string {
	buffer: [ZONE_OFFSET_TEXT_MAX]u8
	text, _ := strings.clone(zone_offset_bprint(buffer[:], zone_offset), allocator)

	return text
}

// The text from `zone_offset_bprint`, in a new string from `context.temp_allocator`. It is freed
// with the rest of the temporary memory, not individually.
zone_offset_tprint :: proc(zone_offset: Zone_Offset) -> string {
	return zone_offset_aprint(zone_offset, context.temp_allocator)
}

// The text from `zone_offset_bprint` as a null terminated C string in a new allocation. Free it
// with `delete` and the same allocator. Returns an empty string if the allocation fails.
zone_offset_caprint :: proc(zone_offset: Zone_Offset, allocator := context.allocator) -> cstring {
	buffer: [ZONE_OFFSET_TEXT_MAX]u8
	text, _ := strings.clone_to_cstring(zone_offset_bprint(buffer[:], zone_offset), allocator)

	return text
}

// Appends the text to the builder and returns the text that was appended, not the whole
// builder. That differs from `fmt.sbprint`, which returns everything in the builder.
zone_offset_sbprint :: proc(builder: ^strings.Builder, zone_offset: Zone_Offset) -> string {
	buffer: [ZONE_OFFSET_TEXT_MAX]u8
	text := zone_offset_bprint(buffer[:], zone_offset)
	start := len(builder.buf)
	strings.write_string(builder, text)

	return string(builder.buf[start:])
}

// Writes the text to the writer and returns the number of bytes written. A write error stops
// the write, and the count is then what was written before it.
zone_offset_wprint :: proc(writer: io.Writer, zone_offset: Zone_Offset) -> int {
	buffer: [ZONE_OFFSET_TEXT_MAX]u8
	written, _ := io.write_string(writer, zone_offset_bprint(buffer[:], zone_offset))

	return written
}

// Writes the text to the file and returns the number of bytes written.
zone_offset_fprint :: proc(file: ^os.File, zone_offset: Zone_Offset) -> int {
	buffer: [ZONE_OFFSET_TEXT_MAX]u8
	written, _ := os.write_string(file, zone_offset_bprint(buffer[:], zone_offset))

	return written
}

// Writes the text to standard output and returns the number of bytes written.
zone_offset_print :: proc(zone_offset: Zone_Offset) -> int {
	return zone_offset_fprint(os.stdout, zone_offset)
}

// Writes the text to standard error and returns the number of bytes written.
zone_offset_eprint :: proc(zone_offset: Zone_Offset) -> int {
	return zone_offset_fprint(os.stderr, zone_offset)
}
