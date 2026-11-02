// Package country looks up ISO 3166-1 countries by alpha-2 code, alpha-3 code,
// numeric code or name.
//
// A Country is an index into a built-in table of 249 entries, sorted by alpha-2.
// The index is only stable within one build, so do not store it: store the
// alpha-2 code and look it up again.
//
// The lookups (from_*) do not allocate. Alpha codes ignore ASCII case, and names
// are ASCII-folded and must match the table in full. A failed lookup returns
// COUNTRY_NONE together with the error. The accessors (alpha2, alpha3,
// numeric_code, name) require a valid Country and assert it.
package country

import "core:strings"

import "../ascii"

// ============================================================================
// constants: table size and search bounds
// ============================================================================

COUNTRY_COUNT :: 249

// Returned by the from_* procs on failure. Never a valid index, so using it
// trips the assertions in the accessors instead of silently naming a country.
COUNTRY_NONE :: Country(max(u16))

// A binary search halves the range each step, so it needs at most
// log2(COUNTRY_COUNT + 1) steps. The #assert keeps the bound honest.
@(private)
SEARCH_STEPS_MAX :: 8
#assert(COUNTRY_COUNT < 1 << SEARCH_STEPS_MAX)

// ============================================================================
// enums: lookup errors
// ============================================================================

Error :: enum {
	None,
	Invalid_Format, // wrong length or a character that is not an ASCII letter
	Not_Found,
}

// ============================================================================
// types: country and its codes
// ============================================================================

// Country is an ISO 3166-1 country, identified by an index into the built-in table.
Country :: distinct u16

// Numeric_Code is a numeric ISO 3166-1 country code (e.g. 840).
Numeric_Code :: distinct u16

// Alpha2 is a two-letter ISO 3166-1 Alpha-2 code (e.g. "US").
Alpha2 :: distinct string

// Alpha3 is a three-letter ISO 3166-1 Alpha-3 code (e.g. "USA").
Alpha3 :: distinct string

@(private)
Entry :: struct {
	alpha2:  string,
	alpha3:  string,
	numeric: Numeric_Code,
	name:    string,
}

// ============================================================================
// procs: accessors
// ============================================================================

error_to_string :: proc(err: Error) -> string {
	switch err {
	case .None:
		return "no error"
	case .Invalid_Format:
		return "country code is not valid"
	case .Not_Found:
		return "country code not found in ISO 3166-1"
	}
	unreachable()
}

// True for every Country returned by a successful from_* call.
valid :: proc(c: Country) -> bool {
	return u32(c) < COUNTRY_COUNT
}

// The accessors require a valid Country (caller responsibility, asserted).
alpha2 :: proc(c: Country) -> Alpha2 {
	assert(valid(c))
	return Alpha2(ENTRIES[c].alpha2)
}

alpha3 :: proc(c: Country) -> Alpha3 {
	assert(valid(c))
	return Alpha3(ENTRIES[c].alpha3)
}

numeric_code :: proc(c: Country) -> Numeric_Code {
	assert(valid(c))
	return ENTRIES[c].numeric
}

name :: proc(c: Country) -> string {
	assert(valid(c))
	return ENTRIES[c].name
}

// ============================================================================
// procs: lookups
// ============================================================================

// None of the lookups allocate. On failure they return COUNTRY_NONE.
// Alpha codes and names ignore ASCII case.

from_numeric_code :: proc(code: Numeric_Code) -> (Country, Error) {
	position, found := binary_search(code, compare_numeric)
	if !found {
		return COUNTRY_NONE, .Not_Found
	}
	return Country(NUMERIC_ORDER[position]), .None
}

// from_alpha2 and from_alpha3 take untrusted text. from_alpha2_code and
// from_alpha3_code take a typed code, so the round trip
// from_alpha2_code(alpha2(c)) needs no cast. (A proc group would make every
// string literal call ambiguous.)
from_alpha2 :: proc(text: string) -> (Country, Error) {
	if len(text) != 2 {
		return COUNTRY_NONE, .Invalid_Format
	}
	buffer: [2]u8
	if !ascii.is_letters(text) {
		return COUNTRY_NONE, .Invalid_Format
	}
	position, found := binary_search(ascii.upper_buffer(buffer[:], text), compare_alpha2)
	if !found {
		return COUNTRY_NONE, .Not_Found
	}
	return Country(position), .None
}

from_alpha2_code :: proc(code: Alpha2) -> (Country, Error) {
	return from_alpha2(string(code))
}

from_alpha3 :: proc(text: string) -> (Country, Error) {
	if len(text) != 3 {
		return COUNTRY_NONE, .Invalid_Format
	}
	buffer: [3]u8
	if !ascii.is_letters(text) {
		return COUNTRY_NONE, .Invalid_Format
	}
	position, found := binary_search(ascii.upper_buffer(buffer[:], text), compare_alpha3)
	if !found {
		return COUNTRY_NONE, .Not_Found
	}
	return Country(ALPHA3_ORDER[position]), .None
}

from_alpha3_code :: proc(code: Alpha3) -> (Country, Error) {
	return from_alpha3(string(code))
}

// Matches the full name in the table, so "United States" does not match
// "United States of America".
from_name :: proc(text: string) -> (Country, Error) {
	if len(text) == 0 {
		return COUNTRY_NONE, .Invalid_Format
	}
	for entry, i in ENTRIES {
		if strings.equal_fold(entry.name, text) {
			return Country(i), .None
		}
	}
	return COUNTRY_NONE, .Not_Found
}

is_valid_numeric_code :: proc(code: Numeric_Code) -> bool {
	_, err := from_numeric_code(code)
	return err == .None
}

is_valid_alpha2 :: proc(text: string) -> bool {
	_, err := from_alpha2(text)
	return err == .None
}

is_valid_alpha3 :: proc(text: string) -> bool {
	_, err := from_alpha3(text)
	return err == .None
}

is_valid_name :: proc(text: string) -> bool {
	_, err := from_name(text)
	return err == .None
}

// Self-check of the built-in table: ENTRIES ascending by alpha-2, ALPHA3_ORDER
// ascending by alpha-3, NUMERIC_ORDER ascending by numeric code, all strictly.
// The lookups rely on this order; tests call it to pinpoint a bad edit.
tables_sorted :: proc() -> bool {
	for i in 1 ..< COUNTRY_COUNT {
		if ENTRIES[i - 1].alpha2 >= ENTRIES[i].alpha2 {
			return false
		}
		if ENTRIES[ALPHA3_ORDER[i - 1]].alpha3 >= ENTRIES[ALPHA3_ORDER[i]].alpha3 {
			return false
		}
		if ENTRIES[NUMERIC_ORDER[i - 1]].numeric >= ENTRIES[NUMERIC_ORDER[i]].numeric {
			return false
		}
	}
	return true
}

// ============================================================================
// procs: search helpers
// ============================================================================

// Searches positions 0 ..< COUNTRY_COUNT, which compare must order ascending by key.
@(private)
binary_search :: proc(
	key: $K,
	compare: proc(position: u32, key: K) -> int,
) -> (
	position: u32,
	found: bool,
) {
	low: u32 = 0
	high: u32 = COUNTRY_COUNT
	for _ in 0 ..< SEARCH_STEPS_MAX {
		if low >= high {
			break
		}
		middle := low + (high - low) / 2
		order := compare(middle, key)
		switch {
		case order == 0:
			return middle, true
		case order < 0:
			low = middle + 1
		case:
			high = middle
		}
	}
	return 0, false
}

@(private)
compare_alpha2 :: proc(position: u32, key: string) -> int {
	return strings.compare(ENTRIES[position].alpha2, key)
}

@(private)
compare_alpha3 :: proc(position: u32, key: string) -> int {
	return strings.compare(ENTRIES[ALPHA3_ORDER[position]].alpha3, key)
}

@(private)
compare_numeric :: proc(position: u32, key: Numeric_Code) -> int {
	return int(ENTRIES[NUMERIC_ORDER[position]].numeric) - int(key)
}
