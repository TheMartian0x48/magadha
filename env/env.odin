// Package env reads dotenv files into an Env, a map from key to value, and looks values up
// as strings or as typed numbers and flags.
//
// Each line is KEY=VALUE, optionally prefixed with `export` and a space or tab. Blank lines
// and lines starting with `#` are skipped, as are lines with no `=` or an empty key.
// Whitespace around the key and value is trimmed. A value wrapped in matching single or
// double quotes keeps its inner text as is; otherwise a trailing ` #` comment is removed.
// Later duplicates of a key replace earlier ones. Values are literal: `${VAR}` is not
// expanded and a backslash is not an escape.
//
// load and parse allocate every key and value with the given allocator; free the result with
// destroy, which also overwrites the values, because they often hold secrets.
//
// How much input is accepted is the application's decision. A Limits bounds the size of
// the text and of a line; the package limits start as LIMITS_DEFAULT, the application can
// set its own once at startup with limits_set, and any call can pass its own instead.
// The package limits are plain package state: set them before other threads use the
// package, and not while they do.
package env

import "base:runtime"
import "core:crypto"
import "core:io"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"

// ============================================================================
// constants: default limits and read size
// ============================================================================

// The limits until limits_set changes them. A dotenv file becomes the process environment,
// which the system bounds: ARG_MAX is 1 MiB on macOS, and Linux limits a single string
// to 128 KiB. Both numbers are the system's, not this package's choice. The number of
// keys needs no limit of its own: a line is at least 4 bytes, so it is bounded by the file.
LIMITS_DEFAULT :: Limits {
	file_bytes_max = 1024 * 1024,
	line_bytes_max = 128 * 1024,
}

// Editors on Windows put this at the start of a file. It is not part of the first key.
@(private)
UTF8_BOM :: "\xef\xbb\xbf"

// A file is read in pieces of this size.
@(private)
READ_CHUNK_BYTES :: 4096

// ============================================================================
// enums: failures and lookup results
// ============================================================================

// Reasons load and parse can fail.
Error :: enum {
	None,
	Not_Found, // load: the file does not exist
	Permission_Denied, // load: the file cannot be opened
	Unreadable, // load: the path is not a readable file
	Too_Large, // the text is over limits.file_bytes_max
	Line_Too_Long, // a line is over limits.line_bytes_max
	Out_Of_Memory,
}

// What a typed lookup found.
Lookup :: enum {
	Found,
	Missing, // there is no such key
	Invalid, // the key exists but its value is not a T
}

// ============================================================================
// types: environment and limits
// ============================================================================

// Env is the keys and values of a dotenv file. Free it with destroy.
Env :: distinct map[string]string

// How much input load and parse accept. Valid when 1 <= line_bytes_max <= file_bytes_max.
Limits :: struct {
	file_bytes_max: u32,
	line_bytes_max: u32,
}

// ============================================================================
// procs: limits
// ============================================================================

@(private)
limits_package := LIMITS_DEFAULT

// True if 1 <= line_bytes_max <= file_bytes_max.
limits_valid :: proc(limits: Limits) -> bool {
	return 1 <= limits.line_bytes_max && limits.line_bytes_max <= limits.file_bytes_max
}

// Replaces the package limits. limits must be valid (asserted).
// Call it before other threads use the package, and not while they do.
limits_set :: proc(limits: Limits) {
	assert(limits_valid(limits))
	limits_package = limits
}

// The package limits now in effect.
limits_get :: proc() -> Limits {
	return limits_package
}

// ============================================================================
// procs: error messages
// ============================================================================

error_to_string :: proc(err: Error) -> string {
	switch err {
	case .None:
		return "no error"
	case .Not_Found:
		return "env file does not exist"
	case .Permission_Denied:
		return "env file cannot be opened: permission denied"
	case .Unreadable:
		return "env path is not a readable file"
	case .Too_Large:
		return "env text is over the size limit"
	case .Line_Too_Long:
		return "env text has a line over the line length limit"
	case .Out_Of_Memory:
		return "out of memory while reading env"
	}
	unreachable()
}

// ============================================================================
// procs: loading and parsing
// ============================================================================

// Reads the dotenv file at `path` into a new Env, within `limits`, which default to the
// package limits; limits must be valid (asserted). The file is read in pieces and never
// holds more than limits.file_bytes_max bytes, so a path to an endless file such as
// /dev/zero fails with Too_Large instead of reading forever. The bytes read are
// allocated with `allocator`, overwritten and freed before returning.
load :: proc(
	path: string,
	allocator := context.allocator,
	limits := limits_package,
) -> (
	Env,
	Error,
) {
	assert(limits_valid(limits))
	file, open_err := os.open(path)
	if open_err != nil {
		return {}, error_from_os(open_err)
	}
	defer os.close(file)

	data, data_err := make([dynamic]u8, 0, 0, allocator)
	if data_err != nil {
		return {}, .Out_Of_Memory
	}
	defer {
		crypto.zero_explicit(raw_data(data), len(data))
		delete(data)
	}
	chunk: [READ_CHUNK_BYTES]u8
	defer crypto.zero_explicit(&chunk, size_of(chunk))

	// One read per chunk of the largest accepted file, plus the read that finds the end.
	reads_max := u64(limits.file_bytes_max) / READ_CHUNK_BYTES + 2
	finished := false
	for _ in 0 ..< reads_max {
		n, read_err := os.read(file, chunk[:])
		if n > 0 {
			if u64(len(data)) + u64(n) > u64(limits.file_bytes_max) {
				return {}, .Too_Large
			}
			if _, append_err := append(&data, ..chunk[:n]); append_err != nil {
				return {}, .Out_Of_Memory
			}
		}
		if read_err != nil {
			if end, is_io := read_err.(io.Error); is_io && end == .EOF {
				finished = true
				break
			}
			return {}, error_from_os(read_err)
		}
		if n == 0 {
			finished = true
			break
		}
	}
	if !finished {
		return {}, .Too_Large
	}
	return parse(string(data[:]), allocator, limits)
}

// Parses dotenv text into a new Env, within `limits`, which default to the package limits;
// limits must be valid (asserted). Free the result with destroy. Nothing is left allocated
// when it fails.
parse :: proc(
	text: string,
	allocator := context.allocator,
	limits := limits_package,
) -> (
	Env,
	Error,
) {
	assert(limits_valid(limits))
	if u64(len(text)) > u64(limits.file_bytes_max) {
		return {}, .Too_Large
	}

	e := make(Env, allocator)
	rest := strings.trim_prefix(text, UTF8_BOM)
	for raw_line in strings.split_lines_iterator(&rest) {
		if u64(len(raw_line)) > u64(limits.line_bytes_max) {
			destroy(&e)
			return {}, .Line_Too_Long
		}
		line := strings.trim_space(raw_line)
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		line = trim_export(line)

		eq := strings.index_byte(line, '=')
		if eq < 0 {
			continue
		}
		key := strings.trim_space(line[:eq])
		if len(key) == 0 {
			continue
		}
		value := parse_value(strings.trim_space(line[eq + 1:]))

		if !insert(&e, key, value, allocator) {
			destroy(&e)
			return {}, .Out_Of_Memory
		}
	}
	return e, .None
}

// Frees an Env made by load or parse, with the allocator it was made with. The values are
// overwritten before they are freed. The Env is empty afterwards.
destroy :: proc(e: ^Env) {
	allocator := e.allocator
	for key, value in e^ {
		delete(key, allocator)
		erase(value, allocator)
	}
	delete(e^)
	e^ = {}
}

// Adds key and value to e as copies, replacing an earlier value for the same key.
// False if an allocation failed; e is still valid and holds no half-made entry.
@(private)
insert :: proc(e: ^Env, key, value: string, allocator: runtime.Allocator) -> bool {
	assert(len(key) > 0)
	key_copy, key_err := strings.clone(key, allocator)
	if key_err != nil {
		return false
	}
	_, value_slot, just_inserted, map_err := map_entry(e, key_copy)
	if map_err != nil {
		delete(key_copy, allocator)
		return false
	}
	value_copy, value_err := strings.clone(value, allocator)
	if value_err != nil {
		if just_inserted {
			value_slot^ = "" // the key is in the map, so give it a value that frees cleanly
		} else {
			delete(key_copy, allocator)
		}
		return false
	}
	if !just_inserted {
		delete(key_copy, allocator) // the map keeps the key it already has
		erase(value_slot^, allocator)
	}
	value_slot^ = value_copy
	return true
}

// Overwrites a string's bytes and frees it.
@(private)
erase :: proc(s: string, allocator: runtime.Allocator) {
	crypto.zero_explicit(raw_data(s), len(s))
	delete(s, allocator)
}

// Drops a leading `export` followed by a space or tab.
@(private)
trim_export :: proc(line: string) -> string {
	EXPORT :: "export"
	if len(line) > len(EXPORT) &&
	   strings.has_prefix(line, EXPORT) &&
	   (line[len(EXPORT)] == ' ' || line[len(EXPORT)] == '\t') {
		return strings.trim_left_space(line[len(EXPORT) + 1:])
	}
	return line
}

// A value wrapped in matching quotes keeps its inner text. The closing quote is
// the first one followed by nothing, or by whitespace and a `#` comment, so
// `"a # b" # note` is `a # b` and `'it's'` is `it's`. A quote that never closes,
// or text after the closing quote, leaves the value as written. Without quotes, a
// trailing ` #` comment is removed.
@(private)
parse_value :: proc(v: string) -> string {
	if len(v) >= 2 && (v[0] == '"' || v[0] == '\'') {
		for j in 1 ..< len(v) {
			if v[j] != v[0] {
				continue
			}
			rest := v[j + 1:]
			if len(rest) == 0 {
				return v[1:j]
			}
			if (rest[0] == ' ' || rest[0] == '\t') &&
			   strings.has_prefix(strings.trim_space(rest), "#") {
				return v[1:j]
			}
		}
		return v
	}
	if i := strings.index(v, " #"); i >= 0 {
		return strings.trim_space(v[:i])
	}
	return v
}

@(private)
error_from_os :: proc(err: os.Error) -> Error {
	if _, is_memory := err.(runtime.Allocator_Error); is_memory {
		return .Out_Of_Memory
	}
	if general, is_general := err.(os.General_Error); is_general && general == .Not_Exist {
		return .Not_Found
	}
	if denied, is_io := err.(io.Error); is_io && denied == .Permission_Denied {
		return .Permission_Denied
	}
	return .Unreadable
}

// ============================================================================
// procs: lookups
// ============================================================================

// value(e, key) returns the raw string and whether the key exists.
// value(e, key, T) parses it as T (bool, f32, f64, i64 or u64) and says what it found.
value :: proc {
	value_string,
	value_typed,
}

// value_or(e, key, "x") returns the string, or "x" when the key is missing.
// value_or(e, key, i64(1)) parses as i64 and returns 1 with .Missing when the key is missing.
// The typed form needs a typed default: untyped constants need a cast.
value_or :: proc {
	value_or_string,
	value_or_typed,
}

value_string :: proc(e: Env, key: string) -> (string, bool) {
	return e[key]
}

value_or_string :: proc(e: Env, key, default: string) -> string {
	if v, ok := e[key]; ok {
		return v
	}
	return default
}

// Looks up `key` and parses it as T. The value is the zero value unless .Found.
// e.g. value(e, "PORT", i64)
//
// bool accepts 1, t, true, yes and on for true, and 0, f, false, no and off for false,
// in any ASCII case. f32 and f64 take plain decimal numbers only: no nan, no inf, no hex
// floats and no `_`. Integers take an optional sign, a 0b, 0o, 0d, 0z or 0x prefix and `_`
// separators, and are Invalid if they do not fit.
value_typed :: proc(e: Env, key: string, $T: typeid) -> (T, Lookup) {
	text, found := value_string(e, key)
	if !found {
		return {}, .Missing
	}
	parsed, ok := parse_as(text, T)
	if !ok {
		return {}, .Invalid
	}
	return parsed, .Found
}

// Like value_typed, but a missing key gives `default` with .Missing. A value that is
// present and not a T is still .Invalid, and gives the zero value, not the default.
value_or_typed :: proc(e: Env, key: string, default: $T) -> (T, Lookup) {
	parsed, lookup := value_typed(e, key, T)
	if lookup == .Missing {
		return default, .Missing
	}
	return parsed, lookup
}

// ============================================================================
// procs: parsing values
// ============================================================================

@(private)
parse_as :: proc(text: string, $T: typeid) -> (T, bool) {
	when T == bool {
		return parse_bool(text)
	} else when T == i64 {
		return parse_i64(text)
	} else when T == u64 {
		return parse_u64(text)
	} else when T == f64 {
		return parse_float(text)
	} else when T == f32 {
		wide, ok := parse_float(text)
		if !ok || abs(wide) > f64(max(f32)) {
			return 0, false
		}
		return f32(wide), true
	} else {
		#panic("env: unsupported type")
	}
}

@(private)
parse_bool :: proc(text: string) -> (value: bool, ok: bool) {
	for spelling in ([?]string{"1", "t", "true", "yes", "on"}) {
		if strings.equal_fold(text, spelling) {
			return true, true
		}
	}
	for spelling in ([?]string{"0", "f", "false", "no", "off"}) {
		if strings.equal_fold(text, spelling) {
			return false, true
		}
	}
	return false, false
}

// A plain decimal number: digits, a sign, a point and an exponent. strconv also takes nan,
// inf, hex floats and `_`, none of which belong in a setting. A result that is not finite
// is rejected too.
@(private)
parse_float :: proc(text: string) -> (f64, bool) {
	if len(text) == 0 {
		return 0, false
	}
	for c in transmute([]u8)text {
		switch c {
		case '0' ..= '9', '+', '-', '.', 'e', 'E':
		case:
			return 0, false
		}
	}
	value, ok := strconv.parse_f64(text)
	if !ok || math.is_nan(value) || math.is_inf(value) {
		return 0, false
	}
	return value, true
}

// Parses an integer like strconv.parse_u64_maybe_prefixed (an optional 0b, 0o, 0d,
// 0z or 0x prefix, and `_` separators), but fails instead of wrapping around when the
// number does not fit in 64 bits, and needs at least one digit. strconv wraps around.
// The loop is bounded by the length of the text, which load and parse have already limited.
@(private)
parse_magnitude :: proc(s: string) -> (magnitude: u64, ok: bool) {
	digits := s
	base: u64 = 10
	if len(digits) > 2 && digits[0] == '0' {
		switch digits[1] {
		case 'b':
			base = 2
		case 'o':
			base = 8
		case 'd':
			base = 10
		case 'z':
			base = 12
		case 'x':
			base = 16
		}
		if base != 10 || digits[1] == 'd' {
			digits = digits[2:]
		}
	}

	digit_count := 0
	for c in transmute([]byte)digits {
		if c == '_' {
			continue
		}
		digit: u64
		switch c {
		case '0' ..= '9':
			digit = u64(c - '0')
		case 'a' ..= 'f':
			digit = u64(c - 'a') + 10
		case 'A' ..= 'F':
			digit = u64(c - 'A') + 10
		case:
			return 0, false
		}
		if digit >= base {
			return 0, false
		}
		if magnitude > (max(u64) - digit) / base {
			return 0, false // would not fit in 64 bits
		}
		magnitude = magnitude * base + digit
		digit_count += 1
	}
	assert(digit_count > 0 || magnitude == 0)
	return magnitude, digit_count > 0
}

// An unsigned integer, with an optional leading `+`. Invalid if it does not fit.
@(private)
parse_u64 :: proc(s: string) -> (value: u64, ok: bool) {
	digits := s[1:] if len(s) > 1 && s[0] == '+' else s
	return parse_magnitude(digits)
}

// A signed integer, with an optional leading `+` or `-`. Invalid if it does not fit.
@(private)
parse_i64 :: proc(s: string) -> (value: i64, ok: bool) {
	negative := len(s) > 1 && s[0] == '-'
	digits := s[1:] if len(s) > 1 && (s[0] == '-' || s[0] == '+') else s
	magnitude, magnitude_ok := parse_magnitude(digits)
	if !magnitude_ok {
		return 0, false
	}
	if negative {
		if magnitude > u64(max(i64)) + 1 {
			return 0, false
		}
		return transmute(i64)(0 - magnitude), true // -(2^63) wraps to min(i64)
	}
	if magnitude > u64(max(i64)) {
		return 0, false
	}
	return i64(magnitude), true
}
