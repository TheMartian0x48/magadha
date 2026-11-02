// Package currency looks up ISO 4217 currencies by alpha-3 code or numeric code.
//
// A Currency is an index into a built-in table of 178 entries, sorted by alpha-3.
// The index is only stable within one build, so do not store it: store the
// alpha-3 code and look it up again.
//
// The lookups (from_*) do not allocate. Alpha codes ignore ASCII case. A failed
// lookup returns CURRENCY_NONE together with the error. The accessors (alpha3,
// numeric_code, minor_units, name) require a valid Currency and assert it.
//
// minor_units returns false for funds, metals and units that have no minor unit
// (XAU, XDR, XXX and others), so an amount in them is not formatted as a
// whole-number currency by mistake.
package currency

import "../ascii"

// ============================================================================
// constants: table size and search bounds
// ============================================================================

CURRENCY_COUNT :: 178

// Returned by the from_* procs on failure. Never a valid index, so using it
// trips the assertions in the accessors instead of silently naming a currency.
CURRENCY_NONE :: Currency(max(u16))

// A binary search halves the range each step, so it needs at most
// log2(CURRENCY_COUNT + 1) steps. The #assert keeps the bound honest.
@(private)
SEARCH_STEPS_MAX :: 8
#assert(CURRENCY_COUNT < 1 << SEARCH_STEPS_MAX)

// Stored in the table for funds, metals and units that have no minor unit.
@(private)
MINOR_NOT_APPLICABLE :: max(u8)

// ============================================================================
// enums: lookup errors
// ============================================================================

Error :: enum {
	None,
	Invalid_Format, // wrong length or a character that is not an ASCII letter
	Not_Found,
}

// ============================================================================
// types: currency and its codes
// ============================================================================

// Currency is an ISO 4217 currency, identified by an index into the built-in table.
Currency :: distinct u16

// Alpha3 is a three-letter ISO 4217 code (e.g. "USD").
Alpha3 :: distinct string

// Numeric_Code is a numeric ISO 4217 currency code (e.g. 840).
Numeric_Code :: distinct u16

// Minor_Units is the number of decimal digits in the minor unit (e.g. 2 for USD, 0 for JPY).
Minor_Units :: distinct u8

@(private)
Entry :: struct {
	alpha3:  string,
	numeric: Numeric_Code,
	minor:   u8,
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
		return "currency code is not valid"
	case .Not_Found:
		return "currency code not found in ISO 4217"
	}
	unreachable()
}

// True for every Currency returned by a successful from_* call.
valid :: proc(c: Currency) -> bool {
	return u32(c) < CURRENCY_COUNT
}

// The accessors require a valid Currency (caller responsibility, asserted).
alpha3 :: proc(c: Currency) -> Alpha3 {
	assert(valid(c))
	return Alpha3(ENTRIES[c].alpha3)
}

numeric_code :: proc(c: Currency) -> Numeric_Code {
	assert(valid(c))
	return ENTRIES[c].numeric
}

// false for funds, metals and units that have no minor unit (XAU, XDR, XXX, ...),
// so an amount in them is never formatted as a whole-number currency by mistake.
minor_units :: proc(c: Currency) -> (Minor_Units, bool) {
	assert(valid(c))
	minor := ENTRIES[c].minor
	if minor == MINOR_NOT_APPLICABLE {
		return 0, false
	}
	return Minor_Units(minor), true
}

name :: proc(c: Currency) -> string {
	assert(valid(c))
	return ENTRIES[c].name
}

// ============================================================================
// procs: lookups
// ============================================================================

// None of the lookups allocate. On failure they return CURRENCY_NONE.

// Takes untrusted text and ignores ASCII case.
from_alpha3 :: proc(text: string) -> (Currency, Error) {
	if len(text) != 3 {
		return CURRENCY_NONE, .Invalid_Format
	}
	buffer: [3]u8
	if !ascii.is_letters(text) {
		return CURRENCY_NONE, .Invalid_Format
	}
	position, found := binary_search(ascii.upper_buffer(buffer[:], text), compare_alpha3)
	if !found {
		return CURRENCY_NONE, .Not_Found
	}
	return Currency(position), .None
}

// Takes a typed code, so the round trip from_alpha3_code(alpha3(c)) needs no cast.
// (A proc group with from_alpha3 would make every string literal call ambiguous.)
from_alpha3_code :: proc(code: Alpha3) -> (Currency, Error) {
	return from_alpha3(string(code))
}

from_numeric_code :: proc(code: Numeric_Code) -> (Currency, Error) {
	position, found := binary_search(code, compare_numeric)
	if !found {
		return CURRENCY_NONE, .Not_Found
	}
	return Currency(NUMERIC_ORDER[position]), .None
}

is_valid_alpha3 :: proc(text: string) -> bool {
	_, err := from_alpha3(text)
	return err == .None
}

is_valid_numeric_code :: proc(code: Numeric_Code) -> bool {
	_, err := from_numeric_code(code)
	return err == .None
}

// Self-check of the built-in table: ENTRIES strictly ascending by alpha-3 and
// NUMERIC_ORDER strictly ascending by numeric code. The lookups rely on this
// order; tests call it to pinpoint a bad edit.
tables_sorted :: proc() -> bool {
	for i in 1 ..< CURRENCY_COUNT {
		if ENTRIES[i - 1].alpha3 >= ENTRIES[i].alpha3 {
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

// Searches positions 0 ..< CURRENCY_COUNT, which compare must order ascending by key.
@(private)
binary_search :: proc(
	key: $K,
	compare: proc(position: u32, key: K) -> int,
) -> (
	position: u32,
	found: bool,
) {
	low: u32 = 0
	high: u32 = CURRENCY_COUNT
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
compare_alpha3 :: proc(position: u32, key: string) -> int {
	if ENTRIES[position].alpha3 < key {
		return -1
	}
	return int(ENTRIES[position].alpha3 > key)
}

@(private)
compare_numeric :: proc(position: u32, key: Numeric_Code) -> int {
	return int(ENTRIES[NUMERIC_ORDER[position]].numeric) - int(key)
}
