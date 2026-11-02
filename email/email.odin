// Package email validates email addresses of the form local@domain.
//
// An Email is a string that borrows the caller's text: it is not copied, so it
// is only valid while that text is. parse is the way to build one from text; it
// checks the address and returns the first error found. Procs that take an
// Email require a valid one and assert it.
//
// The rules follow RFC 5321 for plain addresses, with these limits and choices:
//   - Length is checked first, so a long address is Too_Long before anything else.
//   - Local part: letters, digits and . _ % + -, no leading, trailing or
//     consecutive dots. No quoted strings.
//   - Domain: dot separated labels of letters, digits and hyphens, with at least
//     two labels. No label starts or ends with a hyphen, and the last label is
//     not all digits, so an IP address is not a domain.
//   - ASCII only. Internationalised addresses (RFC 6531) are rejected.
//   - Case is kept as given. The domain is case-insensitive, so User@Example.COM
//     and User@example.com compare unequal as strings.
package email

import "../ascii"
import "core:strings"

// ============================================================================
// constants: length limits
// ============================================================================

// RFC 5321 limits, in bytes.
LOCAL_BYTES_MAX :: 64
LABEL_BYTES_MAX :: 63
EMAIL_BYTES_MAX :: 254

// ============================================================================
// enums: parse errors
// ============================================================================

Error :: enum {
	None,
	Missing_At,
	Empty_Local,
	Empty_Domain,
	Invalid_Local, // a disallowed character, or a leading, trailing or consecutive dot
	Invalid_Domain, // a malformed label, a disallowed character, or fewer than two labels
	Too_Long, // the address, the local part or a domain label is over its limit
}

// ============================================================================
// types: email
// ============================================================================

// Email is a valid address that borrows its text from the caller.
Email :: distinct string

// ============================================================================
// procs: parse and accessors
// ============================================================================

// Checks s and returns it as an Email. The local part is checked before the domain.
parse :: proc(s: string) -> (Email, Error) {
	if len(s) > EMAIL_BYTES_MAX {
		return {}, .Too_Long
	}
	at := strings.index_byte(s, '@')
	if at < 0 {
		return {}, .Missing_At
	}
	if err := check_local(s[:at]); err != .None {
		return {}, err
	}
	if err := check_domain(s[at + 1:]); err != .None {
		return {}, err
	}
	return Email(s), .None
}

// True if s would parse. Takes an Email, so it also checks a value cast from a string.
is_valid :: proc(email: Email) -> bool {
	_, err := parse(string(email))
	return err == .None
}

// The part before '@'. email must be valid (caller responsibility, asserted).
local :: proc(email: Email) -> string {
	assert(is_valid(email))
	e := string(email)
	return e[:strings.index_byte(e, '@')]
}

// The part after '@'. email must be valid (caller responsibility, asserted).
domain :: proc(email: Email) -> string {
	assert(is_valid(email))
	e := string(email)
	return e[strings.index_byte(e, '@') + 1:]
}

error_to_string :: proc(err: Error) -> string {
	switch err {
	case .None:
		return "no error"
	case .Missing_At:
		return "email is missing an @ sign"
	case .Empty_Local:
		return "email local part is empty"
	case .Empty_Domain:
		return "email domain is empty"
	case .Invalid_Local:
		return "email local part has a disallowed character or a misplaced dot"
	case .Invalid_Domain:
		return "email domain is malformed"
	case .Too_Long:
		return "email, local part or domain label is too long"
	}
	unreachable()
}

// ============================================================================
// procs: local part and domain checks
// ============================================================================

// Loops are bounded: parse has already limited the address to EMAIL_BYTES_MAX bytes.

@(private)
check_local :: proc(local: string) -> Error {
	if len(local) == 0 {
		return .Empty_Local
	}
	if len(local) > LOCAL_BYTES_MAX {
		return .Too_Long
	}
	if local[0] == '.' || local[len(local) - 1] == '.' {
		return .Invalid_Local
	}
	for i in 0 ..< len(local) {
		c := local[i]
		if !is_allowed_local(c) {
			return .Invalid_Local
		}
		if c == '.' && local[i + 1] == '.' { 	// i + 1 is in range: the last byte is not a dot
			return .Invalid_Local
		}
	}
	return .None
}

@(private)
check_domain :: proc(domain: string) -> Error {
	if len(domain) == 0 {
		return .Empty_Domain
	}

	label_start := 0
	label_count := 0
	for i in 0 ..= len(domain) {
		if i < len(domain) && domain[i] != '.' {
			if !is_allowed_domain(domain[i]) {
				return .Invalid_Domain
			}
			continue
		}
		label := domain[label_start:i]
		if err := check_label(label); err != .None {
			return err
		}
		label_start = i + 1
		label_count += 1
		if i == len(domain) && ascii.is_digits(label) {
			return .Invalid_Domain // the last label is all digits: an IP address, not a name
		}
	}
	if label_count < 2 {
		return .Invalid_Domain
	}
	return .None
}

@(private)
check_label :: proc(label: string) -> Error {
	if len(label) == 0 {
		return .Invalid_Domain // a leading, trailing or consecutive dot
	}
	if len(label) > LABEL_BYTES_MAX {
		return .Too_Long
	}
	if label[0] == '-' || label[len(label) - 1] == '-' {
		return .Invalid_Domain
	}
	return .None
}

@(private)
is_allowed_local :: proc(c: byte) -> bool {
	switch c {
	case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '.', '_', '%', '+', '-':
		return true
	}
	return false
}

// Dots separate labels and are handled by check_domain.
@(private)
is_allowed_domain :: proc(c: byte) -> bool {
	switch c {
	case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-':
		return true
	}
	return false
}
