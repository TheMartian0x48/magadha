// Package phone parses and formats E.164 phone numbers.
//
// A Phone is the number's digits as a u64, without the '+'. make_phone is the
// only way to build one from text: it checks the format (a '+' followed by
// 7 to 15 digits) and that the number starts with a known country code. It does
// not check whether the number is in use.
//
// Procs that take a Phone require a valid one (see valid) and assert it. Every
// Phone returned by make_phone is valid.
//
// Lookups do not allocate. to_string and national allocate with the given
// allocator; bprint_e164 and bprint_national write into a caller buffer.
package phone

import "core:fmt"
import "core:math/bits"

// ============================================================================
// constants: digit limits and buffer sizes
// ============================================================================

PHONE_MIN_DIGITS :: 7
PHONE_MAX_DIGITS :: 15

// '+' followed by the longest number.
E164_BUFFER_BYTES :: 1 + PHONE_MAX_DIGITS

// ============================================================================
// enums: parse errors
// ============================================================================

Error :: enum {
	None,
	Invalid_Format, // missing '+', or a character that is not a digit
	Too_Short,
	Too_Long,
	Unknown_Country_Code,
}

// ============================================================================
// types: phone number and country code
// ============================================================================

Phone :: distinct u64
Country_Code :: distinct u16

// ============================================================================
// procs: make_phone and accessors
// ============================================================================

// Parses an E.164 number: '+' followed by 7 to 15 digits, starting with a known country code.
// Checks the format and the country code only, not whether the number is in use.
make_phone :: proc(s: string) -> (Phone, Error) {
	if len(s) == 0 || s[0] != '+' {
		return 0, .Invalid_Format
	}
	digits := s[1:]
	if len(digits) < PHONE_MIN_DIGITS {
		return 0, .Too_Short
	}
	if len(digits) > PHONE_MAX_DIGITS {
		return 0, .Too_Long
	}

	n: u64
	for c in transmute([]u8)digits {
		if c < '0' || c > '9' {
			return 0, .Invalid_Format
		}
		n = n * 10 + u64(c - '0')
	}

	// A leading zero would shrink the digit count, and no country code starts with 0.
	if digits[0] == '0' {
		return 0, .Unknown_Country_Code
	}
	if _, ok := find_country_code(n); !ok {
		return 0, .Unknown_Country_Code
	}
	return Phone(n), .None
}

error_to_string :: proc(err: Error) -> string {
	switch err {
	case .None:
		return "no error"
	case .Invalid_Format:
		return "phone number must be '+' followed by digits"
	case .Too_Short:
		return "phone number has fewer than 7 digits"
	case .Too_Long:
		return "phone number has more than 15 digits"
	case .Unknown_Country_Code:
		return "phone number does not start with a known country code"
	}
	unreachable()
}

// True if p has 7 to 15 digits and starts with a known country code.
// Every Phone returned by make_phone is valid.
valid :: proc(p: Phone) -> bool {
	n := u64(p)
	if n < POW10[PHONE_MIN_DIGITS - 1] || n >= POW10[PHONE_MAX_DIGITS] {
		return false
	}
	_, ok := find_country_code(n)
	return ok
}

// p must be valid (caller responsibility, asserted).
country_code :: proc(p: Phone) -> Country_Code {
	assert(valid(p))
	cc, ok := find_country_code(u64(p))
	assert(ok)
	return cc
}

// ============================================================================
// procs: formatted output
// ============================================================================

// Allocates "+<digits>" with the given allocator. p must be valid.
to_string :: proc(p: Phone, allocator := context.allocator) -> string {
	assert(valid(p))
	return fmt.aprintf("+%d", u64(p), allocator = allocator)
}

// Writes "+<digits>" into buf, which must hold E164_BUFFER_BYTES. p must be valid.
bprint_e164 :: proc(buf: []u8, p: Phone) -> string {
	assert(valid(p))
	assert(len(buf) >= E164_BUFFER_BYTES)
	return fmt.bprintf(buf, "+%d", u64(p))
}

// Allocates the digits after the country code, keeping leading zeros. p must be valid.
national :: proc(p: Phone, allocator := context.allocator) -> string {
	digits, n := national_parts(p)
	return fmt.aprintf("%0*d", digits, n, allocator = allocator)
}

// Writes the digits after the country code into buf, which must hold
// PHONE_MAX_DIGITS bytes. p must be valid.
bprint_national :: proc(buf: []u8, p: Phone) -> string {
	assert(len(buf) >= PHONE_MAX_DIGITS)
	digits, n := national_parts(p)
	return fmt.bprintf(buf, "%0*d", digits, n)
}

// ============================================================================
// procs: private helpers
// ============================================================================

@(private)
national_parts :: proc(p: Phone) -> (digits: u32, n: u64) {
	cc_digits := digit_count(u64(country_code(p)))
	p_digits := digit_count(u64(p))
	assert(cc_digits < p_digits)
	digits = p_digits - cc_digits
	n = u64(p) % POW10[digits]
	return
}

// Matches the longest known country code at the start of n (>= PHONE_MIN_DIGITS digits).
// Returns code 1 and false if none matches.
@(private)
find_country_code :: proc(n: u64) -> (Country_Code, bool) {
	assert(n >= POW10[PHONE_MIN_DIGITS - 1])
	d1, d12, d123 := leading_123(n)

	// Longest match first.
	if COUNTRY_CODE_KNOWN[d123] {
		return Country_Code(d123), true
	}
	if COUNTRY_CODE_KNOWN[d12] {
		return Country_Code(d12), true
	}
	if COUNTRY_CODE_KNOWN[d1] {
		return Country_Code(d1), true
	}
	return Country_Code(1), false
}

// n must have at most PHONE_MAX_DIGITS digits, so the estimate indexes POW10 in bounds.
@(private)
digit_count :: #force_inline proc(n: u64) -> u32 {
	assert(n < POW10[PHONE_MAX_DIGITS])
	bl := u32(bits.len_u64(n | 1))
	t := (bl * 1233) >> 12 // estimate of digits-1 (or digits)
	return t + u32(n >= POW10[t]) // branchless fix-up
}

// Leading 1, 2 and 3 digits. (always expecting >= 4 digit number)
@(private)
leading_123 :: #force_inline proc(n: u64) -> (d1, d2, d3: u64) {
	d := digit_count(n)
	assert(d >= 3)
	d1 = n / POW10[d - 1]
	d2 = n / POW10[d - 2]
	d3 = n / POW10[d - 3]
	return
}

// ============================================================================
// constants: lookup tables
// ============================================================================

@(private)
@(rodata)
POW10 := [PHONE_MAX_DIGITS + 1]u64 {
	1,
	10,
	100,
	1_000,
	10_000,
	100_000,
	1_000_000,
	10_000_000,
	100_000_000,
	1_000_000_000,
	10_000_000_000,
	100_000_000_000,
	1_000_000_000_000,
	10_000_000_000_000,
	100_000_000_000_000,
	1_000_000_000_000_000,
}

// Indexed by country code (1 to 3 digits). Includes the ITU shared and
// global service codes (800, 808, 878, 888, 979).
@(private)
@(rodata)
COUNTRY_CODE_KNOWN := [1000]bool {
	1   = true,
	7   = true,
	20  = true,
	27  = true,
	30  = true,
	31  = true,
	32  = true,
	33  = true,
	34  = true,
	36  = true,
	39  = true,
	40  = true,
	41  = true,
	43  = true,
	44  = true,
	45  = true,
	46  = true,
	47  = true,
	48  = true,
	49  = true,
	51  = true,
	52  = true,
	53  = true,
	54  = true,
	55  = true,
	56  = true,
	57  = true,
	58  = true,
	60  = true,
	61  = true,
	62  = true,
	63  = true,
	64  = true,
	65  = true,
	66  = true,
	81  = true,
	82  = true,
	84  = true,
	86  = true,
	90  = true,
	91  = true,
	92  = true,
	93  = true,
	94  = true,
	95  = true,
	98  = true,
	211 = true,
	212 = true,
	213 = true,
	216 = true,
	218 = true,
	220 = true,
	221 = true,
	222 = true,
	223 = true,
	224 = true,
	225 = true,
	226 = true,
	227 = true,
	228 = true,
	229 = true,
	230 = true,
	231 = true,
	232 = true,
	233 = true,
	234 = true,
	235 = true,
	236 = true,
	237 = true,
	238 = true,
	239 = true,
	240 = true,
	241 = true,
	242 = true,
	243 = true,
	244 = true,
	245 = true,
	246 = true,
	247 = true,
	248 = true,
	249 = true,
	250 = true,
	251 = true,
	252 = true,
	253 = true,
	254 = true,
	255 = true,
	256 = true,
	257 = true,
	258 = true,
	260 = true,
	261 = true,
	262 = true,
	263 = true,
	264 = true,
	265 = true,
	266 = true,
	267 = true,
	268 = true,
	269 = true,
	290 = true,
	291 = true,
	297 = true,
	298 = true,
	299 = true,
	350 = true,
	351 = true,
	352 = true,
	353 = true,
	354 = true,
	355 = true,
	356 = true,
	357 = true,
	358 = true,
	359 = true,
	370 = true,
	371 = true,
	372 = true,
	373 = true,
	374 = true,
	375 = true,
	376 = true,
	377 = true,
	378 = true,
	379 = true,
	380 = true,
	381 = true,
	382 = true,
	383 = true,
	385 = true,
	386 = true,
	387 = true,
	389 = true,
	420 = true,
	421 = true,
	423 = true,
	500 = true,
	501 = true,
	502 = true,
	503 = true,
	504 = true,
	505 = true,
	506 = true,
	507 = true,
	508 = true,
	509 = true,
	590 = true,
	591 = true,
	592 = true,
	593 = true,
	594 = true,
	595 = true,
	596 = true,
	597 = true,
	598 = true,
	599 = true,
	670 = true,
	671 = true,
	672 = true,
	673 = true,
	674 = true,
	675 = true,
	676 = true,
	677 = true,
	678 = true,
	679 = true,
	680 = true,
	681 = true,
	682 = true,
	683 = true,
	685 = true,
	686 = true,
	687 = true,
	688 = true,
	689 = true,
	690 = true,
	691 = true,
	692 = true,
	800 = true,
	808 = true,
	850 = true,
	852 = true,
	853 = true,
	855 = true,
	856 = true,
	857 = true,
	858 = true,
	859 = true,
	870 = true,
	878 = true,
	880 = true,
	881 = true,
	882 = true,
	883 = true,
	886 = true,
	888 = true,
	960 = true,
	961 = true,
	962 = true,
	963 = true,
	964 = true,
	965 = true,
	966 = true,
	967 = true,
	968 = true,
	970 = true,
	971 = true,
	972 = true,
	973 = true,
	974 = true,
	975 = true,
	976 = true,
	977 = true,
	979 = true,
	992 = true,
	993 = true,
	994 = true,
	995 = true,
	996 = true,
	998 = true,
}
