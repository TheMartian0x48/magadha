package env_test

import "base:runtime"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

import env "../../env"

// The default limits, passed explicitly by every test that parses or loads, so none of them
// reads the package limits that test_package_limits changes.
LIMITS :: env.LIMITS_DEFAULT

parse :: proc(text: string) -> env.Env {
	e, err := env.parse(text, limits = LIMITS)
	assert(err == .None)
	return e
}

// ============================================================================
// parsing
// ============================================================================

@(test)
test_parse :: proc(t: ^testing.T) {
	e := parse(
		`# comment
A=1
  B = two words
export C=3
D="quoted # not comment"
E='single'
F=plain # trailing
G=
=nokey
noequals
A=override
H=a=b
`,
	)
	defer env.destroy(&e)

	check :: proc(t: ^testing.T, e: env.Env, key, want: string) {
		got, ok := env.value(e, key)
		testing.expect(t, ok, key)
		testing.expect_value(t, got, want)
	}
	check(t, e, "A", "override")
	check(t, e, "B", "two words")
	check(t, e, "C", "3")
	check(t, e, "D", "quoted # not comment")
	check(t, e, "E", "single")
	check(t, e, "F", "plain")
	check(t, e, "G", "")
	check(t, e, "H", "a=b")
	testing.expect_value(t, len(e), 8)
}

@(test)
test_parse_empty :: proc(t: ^testing.T) {
	for text in ([]string{"", "\n", "# only a comment\n", "\n\n  \n", "noequals\n=nokey\n"}) {
		e := parse(text)
		testing.expectf(t, len(e) == 0, "parse(%q) has %d keys", text, len(e))
		env.destroy(&e)
	}
}

// `export` is a prefix only when a space or tab follows it, whatever follows that.
@(test)
test_export_prefix :: proc(t: ^testing.T) {
	e := parse("export A=1\nexport\tB=2\nexport   C=3\nexport \t D=4\nexport=5\nexportE=6\nexport F=\n")
	defer env.destroy(&e)

	for c in ([]struct {
			key, want: string,
		}{{"A", "1"}, {"B", "2"}, {"C", "3"}, {"D", "4"}, {"export", "5"}, {"exportE", "6"}, {"F", ""}}) {
		got, ok := env.value(e, c.key)
		testing.expectf(t, ok, "%q: not found", c.key)
		testing.expectf(t, got == c.want, "%q = %q, want %q", c.key, got, c.want)
	}
	_, found := env.value(e, "export\tB")
	testing.expect(t, !found, "a tab after export must not become part of the key")
	testing.expect_value(t, len(e), 7)
}

@(test)
test_byte_order_mark :: proc(t: ^testing.T) {
	// Editors on Windows add a BOM, which must not become part of the first key.
	e := parse("\xef\xbb\xbfA=1\nB=2\n")
	defer env.destroy(&e)
	v, ok := env.value(e, "A")
	testing.expect(t, ok, "the first key was hidden by the BOM")
	testing.expect_value(t, v, "1")
	testing.expect_value(t, len(e), 2)
}

@(test)
test_crlf_line_endings :: proc(t: ^testing.T) {
	e := parse("A=1\r\nB=two words\r\nC=\"q\"\r\n")
	defer env.destroy(&e)
	for c in ([]struct {
			key, want: string,
		}{{"A", "1"}, {"B", "two words"}, {"C", "q"}}) {
		got, _ := env.value(e, c.key)
		testing.expectf(t, got == c.want, "%q = %q, want %q", c.key, got, c.want)
	}
}

@(test)
test_quoted_value_with_comment :: proc(t: ^testing.T) {
	e := parse(
		`A="a" # comment
B='b'   # comment
C="a # b" # comment
D='it's'
E="x" y
F="unterminated
G='"
H="a"#c
`,
	)
	defer env.destroy(&e)

	for c in ([]struct {
			key, want: string,
		}{{"A", "a"}, {"B", "b"}, {"C", "a # b"}, {"D", "it's"}, {"E", `"x" y`}, {"F", `"unterminated`}, {"G", `'"`}, {"H", `"a"#c`}}) {
		got, ok := env.value(e, c.key)
		testing.expectf(t, ok, "%s: not found", c.key)
		testing.expectf(t, got == c.want, "%s = %q, want %q", c.key, got, c.want)
	}
}

// Values are literal: a backslash is not an escape and ${VAR} is not expanded.
@(test)
test_values_are_literal :: proc(t: ^testing.T) {
	e := parse("A=line1\\nline2\nB=${HOME}/x\nC=\"a\\\"b\"\n")
	defer env.destroy(&e)
	a, _ := env.value(e, "A")
	testing.expect_value(t, a, "line1\\nline2")
	b, _ := env.value(e, "B")
	testing.expect_value(t, b, "${HOME}/x")
	c, _ := env.value(e, "C")
	testing.expect_value(t, c, "a\\\"b")
}

// ============================================================================
// typed lookups
// ============================================================================

@(test)
test_lookup_results :: proc(t: ^testing.T) {
	e := parse("PORT=8080\nDBG=true\nBAD=x\nEMPTY=\n")
	defer env.destroy(&e)

	port, lookup := env.value(e, "PORT", i64)
	testing.expect_value(t, port, 8080)
	testing.expect_value(t, lookup, env.Lookup.Found)

	dbg, dbg_lookup := env.value(e, "DBG", bool)
	testing.expect(t, dbg)
	testing.expect_value(t, dbg_lookup, env.Lookup.Found)

	bad, bad_lookup := env.value(e, "BAD", i64)
	testing.expect_value(t, bad, 0)
	testing.expect_value(t, bad_lookup, env.Lookup.Invalid)

	_, empty_lookup := env.value(e, "EMPTY", i64)
	testing.expect_value(t, empty_lookup, env.Lookup.Invalid)

	missing, missing_lookup := env.value(e, "MISSING", i64)
	testing.expect_value(t, missing, 0)
	testing.expect_value(t, missing_lookup, env.Lookup.Missing)
}

// value_or tells a missing key from a bad value, which the old pair of flags could not:
// a missing key used to report found = true.
@(test)
test_value_or :: proc(t: ^testing.T) {
	e := parse("PORT=8080\nBAD=x\n")
	defer env.destroy(&e)

	port, port_lookup := env.value_or(e, "PORT", i64(1))
	testing.expect_value(t, port, 8080)
	testing.expect_value(t, port_lookup, env.Lookup.Found)

	missing, missing_lookup := env.value_or(e, "MISSING", f32(1.5))
	testing.expect_value(t, missing, 1.5)
	testing.expect_value(t, missing_lookup, env.Lookup.Missing)

	// a present but invalid value is not replaced by the default
	bad, bad_lookup := env.value_or(e, "BAD", i64(7))
	testing.expect_value(t, bad, 0)
	testing.expect_value(t, bad_lookup, env.Lookup.Invalid)

	testing.expect_value(t, env.value_or(e, "MISSING", "dflt"), "dflt")
	testing.expect_value(t, env.value_or(e, "BAD", "dflt"), "x")
}

@(test)
test_integer_overflow :: proc(t: ^testing.T) {
	e := parse(
		`I_MAX=9223372036854775807
I_OVER=9223372036854775808
I_MIN=-9223372036854775808
I_UNDER=-9223372036854775809
I_HUGE=99999999999999999999
U_MAX=18446744073709551615
U_OVER=18446744073709551616
U_HUGE=99999999999999999999999999999999999999999999
HEX_MAX=0xFFFFFFFFFFFFFFFF
HEX_OVER=0x10000000000000000
`,
	)
	defer env.destroy(&e)

	for c in ([]struct {
			key:  string,
			want: i64,
			ok:   bool,
		}{{"I_MAX", max(i64), true}, {"I_OVER", 0, false}, {"I_MIN", min(i64), true}, {"I_UNDER", 0, false}, {"I_HUGE", 0, false}}) {
		got, lookup := env.value(e, c.key, i64)
		testing.expectf(t, (lookup == .Found) == c.ok && got == c.want, "%s as i64 = %d, %v; want %d, ok %v", c.key, got, lookup, c.want, c.ok)
		testing.expectf(t, lookup != .Missing, "%s: not found", c.key)
	}

	for c in ([]struct {
			key:  string,
			want: u64,
			ok:   bool,
		}{{"U_MAX", max(u64), true}, {"U_OVER", 0, false}, {"U_HUGE", 0, false}, {"HEX_MAX", max(u64), true}, {"HEX_OVER", 0, false}}) {
		got, lookup := env.value(e, c.key, u64)
		testing.expectf(t, (lookup == .Found) == c.ok && got == c.want, "%s as u64 = %d, %v; want %d, ok %v", c.key, got, lookup, c.want, c.ok)
		testing.expectf(t, lookup != .Missing, "%s: not found", c.key)
	}

	// an overflowing value is not a usable value, so value_or reports it as invalid
	_, lookup := env.value_or(e, "I_HUGE", i64(7))
	testing.expect_value(t, lookup, env.Lookup.Invalid)
}

@(test)
test_integer_formats :: proc(t: ^testing.T) {
	e := parse("A=0x10\nB=0b101\nC=0o17\nD=+5\nE=-0\nF=1_000\nG=007\nH=\nI=-\nJ=0x\nK= \n")
	defer env.destroy(&e)

	for c in ([]struct {
			key:  string,
			want: i64,
			ok:   bool,
		}{{"A", 16, true}, {"B", 5, true}, {"C", 15, true}, {"D", 5, true}, {"E", 0, true}, {"F", 1000, true}, {"G", 7, true}, {"H", 0, false}, {"I", 0, false}, {"J", 0, false}, {"K", 0, false}}) {
		got, lookup := env.value(e, c.key, i64)
		testing.expectf(t, (lookup == .Found) == c.ok && got == c.want, "%s as i64 = %d, %v; want %d, ok %v", c.key, got, lookup, c.want, c.ok)
	}

	// u64 takes a plus sign but no minus sign
	got, lookup := env.value(e, "D", u64)
	testing.expect(t, lookup == .Found && got == 5)
	_, lookup = env.value(e, "E", u64)
	testing.expect_value(t, lookup, env.Lookup.Invalid)
}

@(test)
test_bool_spellings :: proc(t: ^testing.T) {
	e := parse("T1=1\nT2=t\nT3=TRUE\nT4=Yes\nT5=on\nT6=True\nF1=0\nF2=F\nF3=false\nF4=NO\nF5=Off\nX1=2\nX2=y\nX3=truee\nX4=\nX5=enabled\n")
	defer env.destroy(&e)

	for key in ([]string{"T1", "T2", "T3", "T4", "T5", "T6"}) {
		got, lookup := env.value(e, key, bool)
		testing.expectf(t, got && lookup == .Found, "%s: got %v, %v; want true", key, got, lookup)
	}
	for key in ([]string{"F1", "F2", "F3", "F4", "F5"}) {
		got, lookup := env.value(e, key, bool)
		testing.expectf(t, !got && lookup == .Found, "%s: got %v, %v; want false", key, got, lookup)
	}
	for key in ([]string{"X1", "X2", "X3", "X4", "X5"}) {
		_, lookup := env.value(e, key, bool)
		testing.expectf(t, lookup == .Invalid, "%s: %v, want Invalid", key, lookup)
	}
}

@(test)
test_floats :: proc(t: ^testing.T) {
	e := parse(
		"A=1.5\nB=-2\nC=1e3\nD=.5\nE=0.1\nNAN=nan\nINF=inf\nNINF=-Inf\nHEX=0x1p3\nBIG=1e999\nUND=1_0.5\nEMPTY=\nTWO=1.5.5\nWORD=abc\nF32BIG=1e39\nF32OK=3.4e38\n",
	)
	defer env.destroy(&e)

	for c in ([]struct {
			key:  string,
			want: f64,
		}{{"A", 1.5}, {"B", -2}, {"C", 1000}, {"D", 0.5}, {"E", 0.1}}) {
		got, lookup := env.value(e, c.key, f64)
		testing.expectf(t, lookup == .Found && got == c.want, "%s as f64 = %v, %v; want %v", c.key, got, lookup, c.want)
	}
	// not a setting: no nan, no infinity, no hex floats, no separators, nothing out of range
	for key in ([]string{"NAN", "INF", "NINF", "HEX", "BIG", "UND", "EMPTY", "TWO", "WORD"}) {
		got, lookup := env.value(e, key, f64)
		testing.expectf(t, lookup == .Invalid && got == 0, "%s as f64 = %v, %v; want Invalid", key, got, lookup)
		got32, lookup32 := env.value(e, key, f32)
		testing.expectf(t, lookup32 == .Invalid && got32 == 0, "%s as f32 = %v, %v; want Invalid", key, got32, lookup32)
	}
	// an f32 must fit in an f32
	_, big_lookup := env.value(e, "F32BIG", f32)
	testing.expect_value(t, big_lookup, env.Lookup.Invalid)
	_, big_lookup64 := env.value(e, "F32BIG", f64)
	testing.expect_value(t, big_lookup64, env.Lookup.Found)
	ok32, ok32_lookup := env.value(e, "F32OK", f32)
	testing.expect(t, ok32_lookup == .Found && !math.is_inf(ok32))
}

// ============================================================================
// loading
// ============================================================================

// Writes content to a new file in a new temporary directory. Remove both with remove_temp.
make_temp_file :: proc(t: ^testing.T, content: string) -> (path, dir: string) {
	dir_err: os.Error
	dir, dir_err = os.make_directory_temp("", "env_test", context.temp_allocator)
	testing.expect_value(t, dir_err, nil)
	path = strings.concatenate({dir, "/.env"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(path, content) == nil)
	return
}

remove_temp :: proc(path, dir: string) {
	os.remove(path)
	os.remove(dir)
}

@(test)
test_load :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	path, dir := make_temp_file(t, "K=v\nexport N=1\n")
	defer remove_temp(path, dir)

	e, err := env.load(path, limits = LIMITS)
	testing.expect_value(t, err, env.Error.None)
	defer env.destroy(&e)
	v, _ := env.value(e, "K")
	testing.expect_value(t, v, "v")
	n, lookup := env.value(e, "N", i64)
	testing.expect(t, lookup == .Found && n == 1)
}

// A file bigger than one read chunk exercises the read loop.
@(test)
test_load_large_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	builder := strings.builder_make(context.temp_allocator)
	for i in 0 ..< 2000 {
		strings.write_string(&builder, "KEY_")
		strings.write_int(&builder, i)
		strings.write_string(&builder, "=value_")
		strings.write_int(&builder, i)
		strings.write_byte(&builder, '\n')
	}
	content := strings.to_string(builder)
	testing.expect(t, len(content) > 4096 * 3, "the file should span several read chunks")

	path, dir := make_temp_file(t, content)
	defer remove_temp(path, dir)

	e, err := env.load(path, limits = LIMITS)
	testing.expect_value(t, err, env.Error.None)
	defer env.destroy(&e)
	testing.expect_value(t, len(e), 2000)
	first, _ := env.value(e, "KEY_0")
	testing.expect_value(t, first, "value_0")
	last, _ := env.value(e, "KEY_1999")
	testing.expect_value(t, last, "value_1999")
}

@(test)
test_load_errors :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	_, err := env.load("/nonexistent/.env", limits = LIMITS)
	testing.expect_value(t, err, env.Error.Not_Found)

	// a directory opens but cannot be read as a file
	dir, dir_err := os.make_directory_temp("", "env_test", context.temp_allocator)
	testing.expect_value(t, dir_err, nil)
	defer os.remove(dir)
	_, err = env.load(dir, limits = LIMITS)
	testing.expect_value(t, err, env.Error.Unreadable)

	// a file with no read permission, unless this process may read it anyway
	path, file_dir := make_temp_file(t, "K=v\n")
	defer remove_temp(path, file_dir)
	if os.chmod(path, {}) == nil {
		if probe, open_err := os.open(path); open_err == nil {
			os.close(probe) // running as a user who ignores permissions
		} else {
			_, err = env.load(path, limits = LIMITS)
			testing.expect_value(t, err, env.Error.Permission_Denied)
		}
	}
}

@(test)
test_load_limits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	limits := env.Limits {
		file_bytes_max = 64,
		line_bytes_max = 16,
	}

	// exactly the file limit: 4 lines of 15 bytes and a newline each
	line := "KEY=0123456789\n"
	at_limit, _ := strings.repeat(line, 4, context.temp_allocator)
	testing.expect_value(t, len(at_limit), 60)
	path, dir := make_temp_file(t, strings.concatenate({at_limit, "K=1\n"}, context.temp_allocator)) // 64 bytes
	defer remove_temp(path, dir)
	e, err := env.load(path, limits = limits)
	testing.expect_value(t, err, env.Error.None)
	env.destroy(&e)

	// one byte over
	over_path, over_dir := make_temp_file(t, strings.concatenate({at_limit, "K=12\n"}, context.temp_allocator)) // 65 bytes
	defer remove_temp(over_path, over_dir)
	_, err = env.load(over_path, limits = limits)
	testing.expect_value(t, err, env.Error.Too_Large)

	// a file that never ends is stopped by the limit, not by running out of input
	if probe, open_err := os.open("/dev/zero"); open_err == nil {
		os.close(probe)
		_, err = env.load("/dev/zero", limits = {file_bytes_max = 8192, line_bytes_max = 128})
		testing.expect_value(t, err, env.Error.Too_Large)
	}
}

// load stops at the limit: it never reads more than file_bytes_max bytes into memory, so a file
// over the limit allocates nothing at all. The result alone cannot show this, because parse
// would reject the text anyway.
@(test)
test_load_never_buffers_over_the_limit :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	limits := env.Limits {
		file_bytes_max = 64,
		line_bytes_max = 64,
	}
	over, _ := strings.repeat("K=1\n", 17, context.temp_allocator) // 68 bytes, one read chunk
	path, dir := make_temp_file(t, over)
	defer remove_temp(path, dir)

	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	_, err := env.load(path, mem.tracking_allocator(&tracker), limits)
	testing.expect_value(t, err, env.Error.Too_Large)
	testing.expectf(t, tracker.total_allocation_count == 0, "load allocated %d times for a file over the limit", tracker.total_allocation_count)
}

// ============================================================================
// limits
// ============================================================================

@(test)
test_limits_valid :: proc(t: ^testing.T) {
	testing.expect(t, env.limits_valid(LIMITS))
	testing.expect(t, env.limits_valid({file_bytes_max = 1, line_bytes_max = 1}))
	testing.expect(t, env.limits_valid({file_bytes_max = max(u32), line_bytes_max = max(u32)}), "the caller picks the limits")
	testing.expect(t, !env.limits_valid({}), "zero value")
	testing.expect(t, !env.limits_valid({file_bytes_max = 10, line_bytes_max = 0}))
	testing.expect(t, !env.limits_valid({file_bytes_max = 10, line_bytes_max = 11}), "a line cannot be longer than the file")
}

@(test)
test_parse_limits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	// the file limit counts the whole text
	small := env.Limits {
		file_bytes_max = 32,
		line_bytes_max = 32,
	}
	at_limit := strings.concatenate({"K=", strings.repeat("x", 30, context.temp_allocator)}, context.temp_allocator)
	testing.expect_value(t, len(at_limit), 32)
	e, err := env.parse(at_limit, limits = small)
	testing.expect_value(t, err, env.Error.None)
	env.destroy(&e)
	_, err = env.parse(strings.concatenate({at_limit, "x"}, context.temp_allocator), limits = small)
	testing.expect_value(t, err, env.Error.Too_Large)

	// the line limit counts one line, not including its newline
	narrow := env.Limits {
		file_bytes_max = 100,
		line_bytes_max = 10,
	}
	e, err = env.parse("K=12345678\nL=1\n", limits = narrow) // the first line is 10 bytes
	testing.expect_value(t, err, env.Error.None)
	env.destroy(&e)
	_, err = env.parse("L=1\nK=123456789\n", limits = narrow) // the second line is 11 bytes
	testing.expect_value(t, err, env.Error.Line_Too_Long)
	_, err = env.parse("K=123456789\r\n", limits = narrow) // 11 bytes before the line ending
	testing.expect_value(t, err, env.Error.Line_Too_Long)

	// a long comment is a line too
	_, err = env.parse("# 123456789\n", limits = narrow)
	testing.expect_value(t, err, env.Error.Line_Too_Long)
}

// The package limits and a per-call override, the same way the other packages work. This is the
// only test that changes the package limits, and it puts them back.
@(test)
test_package_limits :: proc(t: ^testing.T) {
	saved := env.limits_get()
	defer env.limits_set(saved)

	env.limits_set(env.LIMITS_DEFAULT)
	testing.expect_value(t, env.limits_get(), env.LIMITS_DEFAULT)

	app := env.Limits {
		file_bytes_max = 20,
		line_bytes_max = 10,
	}
	env.limits_set(app)
	testing.expect_value(t, env.limits_get(), app)

	// calls without limits follow the package limits
	e, err := env.parse("K=1\n")
	testing.expect_value(t, err, env.Error.None)
	env.destroy(&e)
	_, err = env.parse("K=123456789012\n")
	testing.expect_value(t, err, env.Error.Line_Too_Long)
	_, err = env.parse("A=1\nB=2\nC=3\nD=4\nE=5\nF=6\nG=7\n")
	testing.expect_value(t, err, env.Error.Too_Large)

	// limits passed to a call win for that call
	wide, wide_err := env.parse("K=123456789012\n", limits = {file_bytes_max = 100, line_bytes_max = 100})
	testing.expect_value(t, wide_err, env.Error.None)
	env.destroy(&wide)

	// the override does not change the package limits
	testing.expect_value(t, env.limits_get(), app)
}

// ============================================================================
// errors
// ============================================================================

@(test)
test_error_to_string :: proc(t: ^testing.T) {
	for err in env.Error {
		testing.expectf(t, len(env.error_to_string(err)) > 0, "no message for %v", err)
	}
	testing.expect_value(t, env.error_to_string(.Not_Found), "env file does not exist")
}

// ============================================================================
// memory
// ============================================================================

@(test)
test_no_leaks :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	// duplicate keys exercise the replace path
	e, err := env.parse("A=1\nA=2\nB=3\nA=4\n\"=x\n", mem.tracking_allocator(&tracker), LIMITS)
	testing.expect_value(t, err, env.Error.None)
	testing.expect(t, len(tracker.allocation_map) > 0)
	env.destroy(&e)
	testing.expectf(t, len(tracker.allocation_map) == 0, "%d allocations left after destroy", len(tracker.allocation_map))
	testing.expectf(t, len(tracker.bad_free_array) == 0, "%d bad frees", len(tracker.bad_free_array))
}

// Allows a number of allocations and refuses every one after that.
Failing_State :: struct {
	allowed: int,
	used:    int,
}

failing_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	state := (^Failing_State)(data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed {
		state.used += 1
		if state.used > state.allowed {
			return nil, .Out_Of_Memory
		}
	}
	return runtime.heap_allocator_proc(data, mode, size, alignment, old_memory, old_size, location)
}

// Whichever allocation fails, parse reports Out_Of_Memory and leaves nothing behind, and a run
// that succeeds frees everything. The text has duplicate keys, so the replace path is covered.
@(test)
test_parse_allocation_failure :: proc(t: ^testing.T) {
	text := "A=1\nB=2\nA=3\nC=\"x\"\nD=four\nB=5\nEXPORT=6\n"
	failed, succeeded := 0, 0
	for allowed in 0 ..< 80 {
		state := Failing_State {
			allowed = allowed,
		}
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, mem.Allocator{failing_proc, &state})

		e, err := env.parse(text, mem.tracking_allocator(&tracker), LIMITS)
		if err == .None {
			succeeded += 1
			testing.expect_value(t, len(e), 5)
			env.destroy(&e)
		} else {
			failed += 1
			testing.expectf(t, err == .Out_Of_Memory, "allowed %d: err = %v, want Out_Of_Memory", allowed, err)
			testing.expectf(t, len(e) == 0, "allowed %d: a failed parse returned %d keys", allowed, len(e))
		}
		testing.expectf(t, len(tracker.allocation_map) == 0, "allowed %d: %d allocations left (err %v)", allowed, len(tracker.allocation_map), err)
		testing.expectf(t, len(tracker.bad_free_array) == 0, "allowed %d: %d bad frees", allowed, len(tracker.bad_free_array))
		mem.tracking_allocator_destroy(&tracker)
	}
	testing.expect(t, failed > 0 && succeeded > 0, "the loop should see both failures and successes")
}

@(test)
test_load_allocation_failure :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	path, dir := make_temp_file(t, "A=1\nB=2\nA=3\nC=\"x\"\n")
	defer remove_temp(path, dir)

	failed, succeeded := 0, 0
	for allowed in 0 ..< 60 {
		state := Failing_State {
			allowed = allowed,
		}
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, mem.Allocator{failing_proc, &state})

		e, err := env.load(path, mem.tracking_allocator(&tracker), LIMITS)
		if err == .None {
			succeeded += 1
			testing.expect_value(t, len(e), 3)
			env.destroy(&e)
		} else {
			failed += 1
			testing.expectf(t, err == .Out_Of_Memory, "allowed %d: err = %v, want Out_Of_Memory", allowed, err)
		}
		testing.expectf(t, len(tracker.allocation_map) == 0, "allowed %d: %d allocations left (err %v)", allowed, len(tracker.allocation_map), err)
		mem.tracking_allocator_destroy(&tracker)
	}
	testing.expect(t, failed > 0 && succeeded > 0, "the loop should see both failures and successes")
}

// Values often hold secrets, so destroy overwrites them before they are freed. An arena does not
// reuse or clear freed memory, so a value that was not overwritten would still be readable.
@(test)
test_destroy_overwrites_values :: proc(t: ^testing.T) {
	storage: [8192]byte
	arena: mem.Arena
	mem.arena_init(&arena, storage[:])

	e, err := env.parse("DB_PASSWORD=hunter2-secret\nAPI_KEY=sk-live-0123456789\n", mem.arena_allocator(&arena), LIMITS)
	testing.expect_value(t, err, env.Error.None)
	testing.expect(t, strings.contains(string(storage[:]), "hunter2-secret"), "the value should be in the arena before destroy")

	env.destroy(&e)
	testing.expect(t, !strings.contains(string(storage[:]), "hunter2-secret"), "a value was left readable after destroy")
	testing.expect(t, !strings.contains(string(storage[:]), "sk-live-0123456789"), "a value was left readable after destroy")
	testing.expect_value(t, len(e), 0)
}

@(test)
test_destroy_twice :: proc(t: ^testing.T) {
	e := parse("A=1\n")
	env.destroy(&e)
	env.destroy(&e) // an empty Env destroys cleanly
	testing.expect_value(t, len(e), 0)
}
