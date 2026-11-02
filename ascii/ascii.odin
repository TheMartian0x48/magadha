// Package ascii has case conversion and character classification for ASCII text.
//
// Only the ASCII letters 'a' to 'z' and 'A' to 'Z' change case. Every other byte,
// including the bytes of multi-byte UTF-8 characters, is copied unchanged, so
// this is not a Unicode case mapping and is not locale aware.
//
// upper and lower are groups: upper_buffer and lower_buffer write into a caller
// buffer without allocating, upper_allocated and lower_allocated allocate.
package ascii

import "base:runtime"

// ============================================================================
// procs: classification
// ============================================================================

// True if every byte of text is an ASCII letter. Empty text is trivially true.
is_letters :: proc(text: string) -> bool {
	for i in 0 ..< len(text) {
		c := text[i]
		if !('a' <= c && c <= 'z') && !('A' <= c && c <= 'Z') {
			return false
		}
	}
	return true
}

// True if every byte of text is an ASCII digit. Empty text is trivially true.
is_digits :: proc(text: string) -> bool {
	for i in 0 ..< len(text) {
		c := text[i]
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// ============================================================================
// procs: upper case
// ============================================================================

// Upper-cases the ASCII letters of text, copying every other byte unchanged.
// upper_buffer writes into a supplied buffer and upper_allocated allocates.
// The group upper picks one by its arguments.

// Returns a string backed by buffer, which must hold len(text) bytes (asserted).
upper_buffer :: proc(buffer: []u8, text: string) -> string {
	assert(len(buffer) >= len(text))
	for i in 0 ..< len(text) {
		c := text[i]
		if 'a' <= c && c <= 'z' {
			c -= 'a' - 'A'
		}
		buffer[i] = c
	}
	return string(buffer[:len(text)])
}

// Returns a string allocated with allocator. The caller deletes it.
upper_allocated :: proc(
	text: string,
	allocator := context.allocator,
) -> (
	string,
	runtime.Allocator_Error,
) {
	buffer, err := make([]u8, len(text), allocator)
	if err != nil {
		return "", err
	}
	return upper_buffer(buffer, text), nil
}

// ============================================================================
// procs: lower case
// ============================================================================

// Lower-cases the ASCII letters of text, copying every other byte unchanged.
// Same two variants and group as the upper case procs.

// Returns a string backed by buffer, which must hold len(text) bytes (asserted).
lower_buffer :: proc(buffer: []u8, text: string) -> string {
	assert(len(buffer) >= len(text))
	for i in 0 ..< len(text) {
		c := text[i]
		if 'A' <= c && c <= 'Z' {
			c += 'a' - 'A'
		}
		buffer[i] = c
	}
	return string(buffer[:len(text)])
}

// Returns a string allocated with allocator. The caller deletes it.
lower_allocated :: proc(
	text: string,
	allocator := context.allocator,
) -> (
	string,
	runtime.Allocator_Error,
) {
	buffer, err := make([]u8, len(text), allocator)
	if err != nil {
		return "", err
	}
	return lower_buffer(buffer, text), nil
}

// ============================================================================
// procs: groups
// ============================================================================

// The argument types pick the variant: (buffer, text) or (text[, allocator]).
upper :: proc {
	upper_buffer,
	upper_allocated,
}

lower :: proc {
	lower_buffer,
	lower_allocated,
}
