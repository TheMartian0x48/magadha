package password_test

import "base:runtime"
import "core:crypto/argon2id"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"

import password "../../password"

// Small, fast parameters for tests that hash many times.
@(private = "file")
FAST :: argon2id.Parameters {
	memory_size = 64,
	passes      = 2,
	parallelism = 1,
}

// Hashes produced by Node's crypto.argon2Sync (OpenSSL), not by this package,
// with salt bytes 0..15. They check that `verify` agrees with an independent
// Argon2id implementation, and that the PHC encoding is read correctly.
@(private = "file")
REF_M64_T2_P1 :: "$argon2id$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw"
@(private = "file")
REF_M64_T3_P2 :: "$argon2id$v=19$m=64,t=3,p=2$AAECAwQFBgcICQoLDA0ODw$3vDmxbjelaXO85n0Zc4FnjBZDDFU9D7N7tCjV9+SZWU"
@(private = "file")
REF_DEFAULT :: "$argon2id$v=19$m=19456,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$PP3b3DEhLUz5I5fDILA3kKG97RNl7NfAXYL5dpDCOh4"
@(private = "file")
REF_UNICODE :: "$argon2id$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$uVZQMr6AscmTe9sGG0Iqi38CeO5cEWFmbmeV+sNu1iU"

// The default rules, passed explicitly by the validate tests so they never read the package
// rules, which test_package_strength_rules changes.
RULES :: password.STRENGTH_RULES_DEFAULT

// validate

@(test)
test_validate_ok :: proc(t: ^testing.T) {
	valid := []string{"Passw0rd!", "aB3$aaaa", "Zz9_Zz9_Zz9_", "Correct-Horse-9-Battery"}
	for s in valid {
		testing.expect_value(t, password.validate(s, RULES), password.Password_Error.None)
	}
}

@(test)
test_validate_length :: proc(t: ^testing.T) {
	testing.expect_value(t, password.validate("", RULES), password.Password_Error.Too_Short)
	testing.expect_value(
		t,
		password.validate("Aa1!aaa", RULES),
		password.Password_Error.Too_Short,
	) // 7
	testing.expect_value(t, password.validate("Aa1!aaaa", RULES), password.Password_Error.None) // 8

	at_limit := strings.concatenate(
		{"Aa1!", strings.repeat("a", 68, context.temp_allocator)},
		context.temp_allocator,
	)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, len(at_limit), 72)
	testing.expect_value(t, password.validate(at_limit, RULES), password.Password_Error.None)

	over := strings.concatenate({at_limit, "a"}, context.temp_allocator)
	testing.expect_value(t, password.validate(over, RULES), password.Password_Error.Too_Long)
}

@(test)
test_validate_missing_class :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		password.validate("password1!", RULES),
		password.Password_Error.Missing_Uppercase,
	)
	testing.expect_value(
		t,
		password.validate("PASSWORD1!", RULES),
		password.Password_Error.Missing_Lowercase,
	)
	testing.expect_value(
		t,
		password.validate("Password!!", RULES),
		password.Password_Error.Missing_Digit,
	)
	testing.expect_value(
		t,
		password.validate("Password11", RULES),
		password.Password_Error.Missing_Special,
	)
}

@(test)
test_validate_check_order :: proc(t: ^testing.T) {
	// Length is checked before the character classes, then in the order
	// upper, lower, digit, special.
	testing.expect_value(t, password.validate("abc", RULES), password.Password_Error.Too_Short)
	testing.expect_value(
		t,
		password.validate("abcdefgh", RULES),
		password.Password_Error.Missing_Uppercase,
	)
	testing.expect_value(
		t,
		password.validate("ABCDEFGH", RULES),
		password.Password_Error.Missing_Lowercase,
	)
	testing.expect_value(
		t,
		password.validate("Abcdefgh", RULES),
		password.Password_Error.Missing_Digit,
	)
	testing.expect_value(
		t,
		password.validate("Abcdefg1", RULES),
		password.Password_Error.Missing_Special,
	)
}

@(test)
test_validate_unicode :: proc(t: ^testing.T) {
	// Non-ASCII letters count towards their class.
	testing.expect_value(t, password.validate("Éclair9!", RULES), password.Password_Error.None)
	testing.expect_value(t, password.validate("pässWörd1!", RULES), password.Password_Error.None)
	// Symbols count as special: '+' and '€' are symbols, not punctuation.
	testing.expect_value(t, password.validate("Passw0rd+", RULES), password.Password_Error.None)
	testing.expect_value(t, password.validate("Passw0rd€", RULES), password.Password_Error.None)
	// Whitespace is not special.
	testing.expect_value(
		t,
		password.validate("Passw0rd ", RULES),
		password.Password_Error.Missing_Special,
	)
	// The limit counts bytes, not characters: 40 two-byte characters is 80 bytes.
	long := strings.repeat("é", 40, context.temp_allocator)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, password.validate(long, RULES), password.Password_Error.Too_Long)
}

@(test)
test_error_strings :: proc(t: ^testing.T) {
	for err in password.Password_Error {
		testing.expect(t, len(password.password_error_to_string(err)) > 0)
		testing.expect(t, password.password_error_code(err) != "unknown")
	}
	testing.expect_value(t, password.password_error_code(.Too_Short), "too_short")
	testing.expect_value(t, password.password_error_code(.Missing_Special), "missing_special")
	testing.expect_value(
		t,
		password.password_error_to_string(.Too_Long),
		"password is longer than the maximum length",
	)

	for err in password.Hash_Error {
		testing.expect(t, len(password.hash_error_to_string(err)) > 0)
	}
}

// hashing

@(test)
test_hash_of_format :: proc(t: ^testing.T) {
	h, err := password.hash_of("Passw0rd!x")
	defer password.destroy(h)
	testing.expect_value(t, err, password.Hash_Error.None)

	s := string(h)
	testing.expect(t, strings.has_prefix(s, "$argon2id$v=19$m=19456,t=2,p=1$"), s)
	// prefix 31 + salt 22 + '$' + tag 43
	testing.expect_value(t, len(s), 31 + 22 + 1 + 43)
	testing.expect_value(t, strings.count(s, "$"), 5)
}

@(test)
test_hash_of_verifies :: proc(t: ^testing.T) {
	h, err := password.hash_of("Passw0rd!x")
	defer password.destroy(h)
	testing.expect_value(t, err, password.Hash_Error.None)

	ok, verr := password.verify(h, "Passw0rd!x")
	testing.expect_value(t, verr, password.Hash_Error.None)
	testing.expect(t, ok, "correct password was rejected")

	ok, verr = password.verify(h, "Passw0rd!y")
	testing.expect_value(t, verr, password.Hash_Error.None)
	testing.expect(t, !ok, "wrong password was accepted")
}

@(test)
test_hash_is_salted :: proc(t: ^testing.T) {
	a, ea := password.hash_of("Passw0rd!x", FAST)
	b, eb := password.hash_of("Passw0rd!x", FAST)
	defer password.destroy(a)
	defer password.destroy(b)
	testing.expect_value(t, ea, password.Hash_Error.None)
	testing.expect_value(t, eb, password.Hash_Error.None)

	// Same password, different salt: different strings, both verify.
	testing.expect(t, a != b, "two hashes of one password were identical")
	for h in ([]password.Password_Hash{a, b}) {
		ok, err := password.verify(h, "Passw0rd!x")
		testing.expect_value(t, err, password.Hash_Error.None)
		testing.expect(t, ok)
	}
}

@(test)
test_hash_with_params :: proc(t: ^testing.T) {
	params := argon2id.Parameters {
		memory_size = 128,
		passes      = 3,
		parallelism = 2,
	}
	h, err := password.hash_of("Passw0rd!x", params)
	defer password.destroy(h)
	testing.expect_value(t, err, password.Hash_Error.None)
	testing.expect(t, strings.has_prefix(string(h), "$argon2id$v=19$m=128,t=3,p=2$"), string(h))

	ok, verr := password.verify(h, "Passw0rd!x")
	testing.expect_value(t, verr, password.Hash_Error.None)
	testing.expect(t, ok)
}

@(test)
test_hash_with_invalid_params :: proc(t: ^testing.T) {
	// These would make argon2id.derive panic, so they have to be rejected first.
	bad := []argon2id.Parameters {
		{memory_size = 64, passes = 0, parallelism = 1},
		{memory_size = 64, passes = 2, parallelism = 0},
		{memory_size = 7, passes = 2, parallelism = 1}, // < 8 * p
		{memory_size = 15, passes = 2, parallelism = 2}, // < 8 * p
		{memory_size = 0, passes = 2, parallelism = 1},
	}
	for p in bad {
		h, err := password.hash_of("Passw0rd!x", p)
		testing.expect_value(t, err, password.Hash_Error.Invalid_Parameters)
		testing.expect_value(t, h, password.Password_Hash(""))
	}
}

@(test)
test_hash_unicode_and_empty :: proc(t: ^testing.T) {
	// Hashing does not enforce strength rules, and accepts any bytes.
	for pw in ([]string{"", "pässwörd-Ünï1", "with\x00nul", "日本語パスワード"}) {
		h, err := password.hash_of(pw, FAST)
		testing.expect_value(t, err, password.Hash_Error.None)
		ok, verr := password.verify(h, pw)
		testing.expect_value(t, verr, password.Hash_Error.None)
		testing.expect(t, ok)
		wrong, _ := password.verify(h, "x")
		testing.expect(t, !wrong)
		password.destroy(h)
	}

	// An embedded NUL does not truncate the password.
	h, _ := password.hash_of("with\x00nul", FAST)
	defer password.destroy(h)
	ok, _ := password.verify(h, "with")
	testing.expect(t, !ok, "password was truncated at NUL")
}

// verify against independent reference hashes

@(test)
test_verify_reference_hashes :: proc(t: ^testing.T) {
	refs := []string{REF_M64_T2_P1, REF_M64_T3_P2, REF_DEFAULT}
	for ref in refs {
		h, err := password.hash_from_string(ref)
		testing.expect_value(t, err, password.Hash_Error.None)

		ok, verr := password.verify(h, "Passw0rd!x")
		testing.expect_value(t, verr, password.Hash_Error.None)
		testing.expectf(t, ok, "reference hash not verified: %s", ref)

		ok, verr = password.verify(h, "Passw0rd!X")
		testing.expect_value(t, verr, password.Hash_Error.None)
		testing.expectf(t, !ok, "wrong password accepted for: %s", ref)
		password.destroy(h)
	}

	h, err := password.hash_from_string(REF_UNICODE)
	defer password.destroy(h)
	testing.expect_value(t, err, password.Hash_Error.None)
	ok, _ := password.verify(h, "pässwörd-Ünï1")
	testing.expect(t, ok, "unicode reference hash not verified")
	ok, _ = password.verify(h, "passwörd-Ünï1")
	testing.expect(t, !ok)
}

// hash_from_string

@(test)
test_hash_from_string_round_trip :: proc(t: ^testing.T) {
	h, _ := password.hash_of("Passw0rd!x", FAST)
	defer password.destroy(h)

	h2, err := password.hash_from_string(string(h))
	defer password.destroy(h2)
	testing.expect_value(t, err, password.Hash_Error.None)
	testing.expect_value(t, h2, h)

	// It is a copy, so it outlives the string it was made from.
	testing.expect(t, raw_data(string(h2)) != raw_data(string(h)))
}

@(test)
test_hash_from_string_malformed :: proc(t: ^testing.T) {
	malformed := []string {
		"",
		"plain text",
		"$2b$10$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ab", // bcrypt
		"$argon2i$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // wrong variant
		"$argon2d$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
		"$argon2id$v=16$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // old version
		"$argon2id$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // no version
		"$argon2id$v=19$m=64,t=2$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // missing p
		"$argon2id$v=19$t=2,m=64,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // order
		"$argon2id$v=19$m=64,t=2,p=1,x=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // extra field
		"$argon2id$v=19$m=abc,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
		"$argon2id$v=19$m=064,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // leading zero
		"$argon2id$v=19$m=-64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
		"$argon2id$v=19$m=99999999999,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // > u32
		"$argon2id$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw", // no tag
		"$argon2id$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$", // empty tag
		"$argon2id$v=19$m=64,t=2,p=1$$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // empty salt
		"$argon2id$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw$extra",
		"$argon2id$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw=$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // padded
		"$argon2id$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0O!w$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // bad char
		"$argon2id$v=19$m=64,t=2,p=1$AAECAwQ$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw", // salt < 8 bytes
	}
	for s in malformed {
		h, err := password.hash_from_string(s)
		testing.expectf(t, err == .Invalid_Format, "%q: got %v, want Invalid_Format", s, err)
		testing.expect_value(t, h, password.Password_Hash(""))
	}
}

@(test)
test_hash_from_string_bad_parameters :: proc(t: ^testing.T) {
	// Well-formed, but parameters argon2id.derive would panic on.
	bad := []string {
		"$argon2id$v=19$m=64,t=0,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
		"$argon2id$v=19$m=64,t=2,p=0$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
		"$argon2id$v=19$m=4,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
		"$argon2id$v=19$m=8,t=2,p=2$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
	}
	for s in bad {
		_, err := password.hash_from_string(s)
		testing.expectf(
			t,
			err == .Invalid_Parameters,
			"%q: got %v, want Invalid_Parameters",
			s,
			err,
		)
	}
}

@(test)
test_hash_from_string_too_long :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)

	long := strings.concatenate({REF_M64_T2_P1, strings.repeat("A", 600)})
	_, err := password.hash_from_string(long)
	testing.expect_value(t, err, password.Hash_Error.Invalid_Format)
}

// verify

@(test)
test_verify_tampered_hash :: proc(t: ^testing.T) {
	// A flipped character in the tag must fail verification, not the parse.
	tampered := strings.clone(REF_M64_T2_P1)
	defer delete(tampered)
	bytes := transmute([]byte)tampered
	bytes[len(bytes) - 5] = 'Q' if bytes[len(bytes) - 5] != 'Q' else 'R'

	h, err := password.hash_from_string(tampered)
	defer password.destroy(h)
	testing.expect_value(t, err, password.Hash_Error.None)
	ok, verr := password.verify(h, "Passw0rd!x")
	testing.expect_value(t, verr, password.Hash_Error.None)
	testing.expect(t, !ok, "tampered hash verified")
}

@(test)
test_verify_malformed_hash :: proc(t: ^testing.T) {
	// A password.Password_Hash not made by this package is reported, not trusted.
	ok, err := password.verify(password.Password_Hash("not a hash"), "anything")
	testing.expect_value(t, err, password.Hash_Error.Invalid_Format)
	testing.expect(t, !ok)

	ok, err = password.verify(password.Password_Hash(""), "anything")
	testing.expect_value(t, err, password.Hash_Error.Invalid_Format)
	testing.expect(t, !ok)

	ok, err = password.verify(
		password.Password_Hash(
			"$argon2id$v=19$m=1,t=1,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
		),
		"anything",
	)
	testing.expect_value(t, err, password.Hash_Error.Invalid_Parameters)
	testing.expect(t, !ok)
}

@(test)
test_verify_is_case_sensitive :: proc(t: ^testing.T) {
	h, _ := password.hash_of("Passw0rd!x", FAST)
	defer password.destroy(h)
	ok, _ := password.verify(h, "passw0rd!x")
	testing.expect(t, !ok)
	ok, _ = password.verify(h, "Passw0rd!x ")
	testing.expect(t, !ok, "trailing space ignored")
	ok, _ = password.verify(h, "")
	testing.expect(t, !ok)
}

// map key and equality

@(test)
test_hash_as_map_key :: proc(t: ^testing.T) {
	a, _ := password.hash_of("Passw0rd!x", FAST)
	b, _ := password.hash_of("Passw0rd!y", FAST)
	defer password.destroy(a)
	defer password.destroy(b)

	// password.Password_Hash is a string type, so == compares by content.
	copy_a, _ := password.hash_from_string(string(a))
	defer password.destroy(copy_a)
	testing.expect(t, a == copy_a)
	testing.expect(t, a != b)

	m := make(map[password.Password_Hash]int)
	defer delete(m)
	m[a] = 1
	m[b] = 2
	testing.expect_value(t, m[copy_a], 1)
	testing.expect_value(t, len(m), 2)
}

// cost parameter limits

// A well-formed hash string with the given cost parameters. Parsing it does no hashing.
phc_with_costs :: proc(memory, passes, parallelism: u32) -> string {
	return fmt.tprintf(
		"$argon2id$v=19$m=%d,t=%d,p=%d$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
		memory,
		passes,
		parallelism,
	)
}

// The policy used by the tests below: small, so each limit is easy to cross.
@(private = "file")
POLICY :: password.Argon2id_Policy {
	memory_size = 1024,
	passes      = 4,
	parallelism = 2,
}

// Each cost parameter is accepted at its limit and rejected one past it, and
// the bounds that belong to the library are enforced whatever the policy says.
@(test)
test_cost_limits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	Case :: struct {
		memory, passes, parallelism: u32,
		want:                        password.Hash_Error,
	}
	cases := []Case {
		{POLICY.memory_size, 1, 1, .None},
		{POLICY.memory_size + 1, 1, 1, .Invalid_Parameters},
		{64, POLICY.passes, 1, .None},
		{64, POLICY.passes + 1, 1, .Invalid_Parameters},
		{8 * POLICY.parallelism, 1, POLICY.parallelism, .None},
		{1024, 1, POLICY.parallelism + 1, .Invalid_Parameters},
		// the library's own bounds
		{8, 1, 1, .None}, // smallest accepted memory
		{7, 1, 1, .Invalid_Parameters},
		{15, 1, 2, .Invalid_Parameters}, // memory < 8 * parallelism
		{64, 0, 1, .Invalid_Parameters},
		{64, 1, 0, .Invalid_Parameters},
		{max(u32), max(u32), max(u32), .Invalid_Parameters},
	}
	for c in cases {
		s := phc_with_costs(c.memory, c.passes, c.parallelism)
		h, err := password.hash_from_string(s, policy = POLICY)
		testing.expectf(
			t,
			err == c.want,
			"hash_from_string(m=%d,t=%d,p=%d) = %v, want %v",
			c.memory,
			c.passes,
			c.parallelism,
			err,
			c.want,
		)
		password.destroy(h)

		// verify applies the same limits before it derives anything.
		if c.want == .Invalid_Parameters {
			ok, verr := password.verify(password.Password_Hash(s), "anything", policy = POLICY)
			testing.expectf(
				t,
				verr == .Invalid_Parameters && !ok,
				"verify(%q) = %v, %v",
				s,
				ok,
				verr,
			)
		}
	}
}

// hash_of checks only what derive needs. The policy limits stored hashes, not the
// caller's own choice of parameters.
@(test)
test_hash_of_ignores_policy :: proc(t: ^testing.T) {
	over_policy := argon2id.Parameters {
		memory_size = POLICY.memory_size * 2,
		passes      = POLICY.passes + 1,
		parallelism = POLICY.parallelism + 1,
	}
	h, err := password.hash_of("Passw0rd!x", over_policy)
	defer password.destroy(h)
	testing.expect_value(t, err, password.Hash_Error.None)

	// ...but that hash is above the policy, so verify refuses it under POLICY...
	ok, verr := password.verify(h, "Passw0rd!x", policy = POLICY)
	testing.expect_value(t, verr, password.Hash_Error.Invalid_Parameters)
	testing.expect(t, !ok)

	// ...and accepts it under a policy that allows it.
	wide := password.Argon2id_Policy {
		memory_size = over_policy.memory_size,
		passes      = over_policy.passes,
		parallelism = over_policy.parallelism,
	}
	ok, verr = password.verify(h, "Passw0rd!x", policy = wide)
	testing.expect_value(t, verr, password.Hash_Error.None)
	testing.expect(t, ok)

	// parameters the library cannot run are still rejected
	_, err = password.hash_of("x", {memory_size = 7, passes = 1, parallelism = 1})
	testing.expect_value(t, err, password.Hash_Error.Invalid_Parameters)
	_, err = password.hash_of("x", {memory_size = 64, passes = 0, parallelism = 1})
	testing.expect_value(t, err, password.Hash_Error.Invalid_Parameters)
}

@(test)
test_argon2id_policy_valid :: proc(t: ^testing.T) {
	testing.expect(t, password.argon2id_policy_valid(POLICY))
	testing.expect(t, password.argon2id_policy_valid(password.ARGON2ID_POLICY_DEFAULT))
	testing.expect(
		t,
		password.argon2id_policy_valid({memory_size = 8, passes = 1, parallelism = 1}),
		"the smallest policy",
	)
	testing.expect(
		t,
		password.argon2id_policy_valid(
			{memory_size = max(u32), passes = max(u32), parallelism = max(u32)},
		),
		"the caller picks the limits",
	)
	testing.expect(t, !password.argon2id_policy_valid({}), "zero value")
	testing.expect(
		t,
		!password.argon2id_policy_valid({memory_size = 7, passes = 1, parallelism = 1}),
	)
	testing.expect(
		t,
		!password.argon2id_policy_valid({memory_size = 8, passes = 0, parallelism = 1}),
	)
	testing.expect(
		t,
		!password.argon2id_policy_valid({memory_size = 8, passes = 1, parallelism = 0}),
	)
}

// The default must let every parameter set that core:crypto/argon2id recommends verify, and
// must not be larger than the largest of them: it is derived from them, not chosen.
@(test)
test_default_policy_matches_library_presets :: proc(t: ^testing.T) {
	presets := [?]argon2id.Parameters {
		argon2id.PARAMS_RFC9106,
		argon2id.PARAMS_RFC9106_SMALL,
		argon2id.PARAMS_OWASP,
		argon2id.PARAMS_OWASP_SMALL,
	}
	want: password.Argon2id_Policy
	for p in presets {
		want.memory_size = max(want.memory_size, p.memory_size)
		want.passes = max(want.passes, p.passes)
		want.parallelism = max(want.parallelism, p.parallelism)
		testing.expectf(
			t,
			p.memory_size <= password.ARGON2ID_POLICY_DEFAULT.memory_size,
			"preset %v is over the default memory limit",
			p,
		)
		testing.expectf(
			t,
			p.passes <= password.ARGON2ID_POLICY_DEFAULT.passes,
			"preset %v is over the default passes limit",
			p,
		)
		testing.expectf(
			t,
			p.parallelism <= password.ARGON2ID_POLICY_DEFAULT.parallelism,
			"preset %v is over the default parallelism limit",
			p,
		)
	}
	testing.expect_value(t, password.ARGON2ID_POLICY_DEFAULT, want)
}

// The package policy and a per-call policy, the same way pagination does it. This is the only
// test that changes the package policy, and it puts it back.
@(test)
test_package_argon2id_policy :: proc(t: ^testing.T) {
	saved := password.argon2id_policy_get()
	defer password.argon2id_policy_set(saved)

	small := phc_with_costs(64, 2, 1)
	large := phc_with_costs(4096, 2, 1)
	defer free_all(context.temp_allocator)

	password.argon2id_policy_set(password.ARGON2ID_POLICY_DEFAULT)
	testing.expect_value(t, password.argon2id_policy_get(), password.ARGON2ID_POLICY_DEFAULT)
	_, err := password.hash_from_string(large)
	testing.expect_value(t, err, password.Hash_Error.None)

	// the application tightens the package policy: calls without a policy follow it
	app := password.Argon2id_Policy {
		memory_size = 1024,
		passes      = 4,
		parallelism = 2,
	}
	password.argon2id_policy_set(app)
	testing.expect_value(t, password.argon2id_policy_get(), app)
	h, small_err := password.hash_from_string(small)
	password.destroy(h)
	testing.expect_value(t, small_err, password.Hash_Error.None)
	_, err = password.hash_from_string(large)
	testing.expect_value(t, err, password.Hash_Error.Invalid_Parameters)

	// a call that passes its own policy wins, in both directions
	wide := password.Argon2id_Policy {
		memory_size = 8192,
		passes      = 4,
		parallelism = 2,
	}
	h2, wide_err := password.hash_from_string(large, policy = wide)
	password.destroy(h2)
	testing.expect_value(t, wide_err, password.Hash_Error.None)
	_, err = password.hash_from_string(
		small,
		policy = {memory_size = 32, passes = 4, parallelism = 2},
	)
	testing.expect_value(t, err, password.Hash_Error.Invalid_Parameters)

	// the override does not change the package policy
	testing.expect_value(t, password.argon2id_policy_get(), app)
}

// leaks on error paths

// A hash that fails to parse must not leave anything allocated, whichever field is bad.
@(test)
test_parse_errors_do_not_leak :: proc(t: ^testing.T) {
	bad := []string {
		// valid salt, tag with a bad character: the salt is already decoded
		"$argon2id$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFr!",
		// valid salt, tag shorter than the minimum
		"$argon2id$v=19$m=64,t=2,p=1$AAECAwQFBgcICQoLDA0ODw$AAAA",
		// salt shorter than the minimum
		"$argon2id$v=19$m=64,t=2,p=1$AAECAwQ$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
		// bad parameters, before anything is decoded
		"$argon2id$v=19$m=64,t=0,p=1$AAECAwQFBgcICQoLDA0ODw$Z1NI6uhycWC+2oQ/vfBCW8CyiH5ImxWvV4itq9ebFrw",
	}
	for s in bad {
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		allocator := mem.tracking_allocator(&tracker)

		_, from_err := password.hash_from_string(s, allocator)
		_, verify_err := password.verify(password.Password_Hash(s), "anything", allocator)
		testing.expectf(t, from_err != .None && verify_err != .None, "%q was accepted", s)
		testing.expectf(
			t,
			len(tracker.allocation_map) == 0,
			"%q leaked %d allocations",
			s,
			len(tracker.allocation_map),
		)

		mem.tracking_allocator_destroy(&tracker)
	}
}

// hash_of takes params second and allocator third, so the allocator is passed by name
// when params is left at its default.
@(test)
test_hash_of_argument_forms :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	allocator := mem.tracking_allocator(&tracker)

	// default params, named allocator
	a, err_a := password.hash_of("Passw0rd!x", allocator = allocator)
	testing.expect_value(t, err_a, password.Hash_Error.None)
	testing.expect(t, strings.has_prefix(string(a), "$argon2id$v=19$m=19456,t=2,p=1$"), string(a))

	// custom params, then allocator, both positional
	b, err_b := password.hash_of("Passw0rd!x", FAST, allocator)
	testing.expect_value(t, err_b, password.Hash_Error.None)
	testing.expect(t, strings.has_prefix(string(b), "$argon2id$v=19$m=64,t=2,p=1$"), string(b))

	// the work area is released; only the two result strings remain
	testing.expect_value(t, len(tracker.allocation_map), 2)
	password.destroy(a, allocator)
	password.destroy(b, allocator)
	testing.expect_value(t, len(tracker.allocation_map), 0)
}

// invalid UTF-8

// A byte that is not valid UTF-8 decodes to U+FFFD, a symbol. It must not pass for the
// special character that a real password needs.
@(test)
test_validate_invalid_utf8 :: proc(t: ^testing.T) {
	for s in ([]string {
			"Aa1\xff\xff\xff\xff\xff", // stray bytes
			"Aa1bbbb\xc3", // a two-byte sequence cut short
			"Aa1bbb\xc3b", // a lead byte followed by a non-continuation byte
			"Aa1bbb\xed\xa0\x80", // an encoded surrogate
			"Aa1bbb\xc0\xaf", // an overlong encoding
		}) {
		testing.expectf(
			t,
			password.validate(s) == .Invalid_Encoding,
			"validate(%q) = %v, want Invalid_Encoding",
			s,
			password.validate(s),
		)
	}

	// length is still checked first, and valid text is unaffected
	testing.expect_value(t, password.validate("\xff"), password.Password_Error.Too_Short)
	testing.expect_value(t, password.validate("Passw0rd!"), password.Password_Error.None)
	testing.expect_value(t, password.validate("Éclair9!"), password.Password_Error.None)
	// a real U+FFFD, correctly encoded, is a symbol like any other
	testing.expect_value(t, password.validate("Aa1bbbb�"), password.Password_Error.None)
}

// allocation failure

// Serves large requests (the hashing work area) from the heap and refuses small ones, as an
// exhausted arena would. The hash string and the decoded salt and tag are small.
@(private = "file")
small_refused_proc :: proc(
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
	if size < 128 &&
	   (mode == .Alloc ||
			   mode == .Alloc_Non_Zeroed ||
			   mode == .Resize ||
			   mode == .Resize_Non_Zeroed) {
		return nil, .Out_Of_Memory
	}
	return runtime.heap_allocator_proc(data, mode, size, alignment, old_memory, old_size, location)
}

// A hash that was not produced must never look like one that was.
@(test)
test_hash_of_allocation_failure :: proc(t: ^testing.T) {
	refused := mem.Allocator{small_refused_proc, nil}

	h, err := password.hash_of("Passw0rd!x", FAST, refused)
	testing.expect_value(t, err, password.Hash_Error.Out_Of_Memory)
	testing.expectf(t, len(string(h)) == 0, "a failed hash_of returned %q", string(h))

	// the same call with a working allocator succeeds
	ok_hash, ok_err := password.hash_of("Passw0rd!x", FAST)
	defer password.destroy(ok_hash)
	testing.expect_value(t, ok_err, password.Hash_Error.None)
	testing.expect(t, len(string(ok_hash)) > 0)
}

// parse, hash_from_string and verify each allocate small buffers; a refusal is an error,
// never a wrong answer.
@(test)
test_parse_allocation_failure :: proc(t: ^testing.T) {
	refused := mem.Allocator{small_refused_proc, nil}

	h, from_err := password.hash_from_string(REF_M64_T2_P1, refused)
	testing.expect_value(t, from_err, password.Hash_Error.Out_Of_Memory)
	testing.expect_value(t, len(string(h)), 0)

	ok, verify_err := password.verify(password.Password_Hash(REF_M64_T2_P1), "Passw0rd!x", refused)
	testing.expect_value(t, verify_err, password.Hash_Error.Out_Of_Memory)
	testing.expect(t, !ok, "verify reported a match after an allocation failure")
}

// configurable strength rules

@(test)
test_strength_rules_valid :: proc(t: ^testing.T) {
	testing.expect(t, password.strength_rules_valid(RULES))
	testing.expect(
		t,
		password.strength_rules_valid({length_min = 0, length_max = 1}),
		"no minimum",
	)
	testing.expect(
		t,
		password.strength_rules_valid({length_min = 5, length_max = 5}),
		"an exact length",
	)
	testing.expect(
		t,
		password.strength_rules_valid(
			{length_min = 0, length_max = max(u32), classes_required = {}},
		),
		"no composition rules",
	)
	testing.expect(t, !password.strength_rules_valid({}), "zero value: nothing is allowed")
	testing.expect(
		t,
		!password.strength_rules_valid({length_min = 9, length_max = 8}),
		"min over max",
	)
	testing.expect(t, !password.strength_rules_valid({length_min = 0, length_max = 0}))
}

@(test)
test_validate_length_rules :: proc(t: ^testing.T) {
	rules := password.Strength_Rules {
		length_min       = 12,
		length_max       = 20,
		classes_required = {},
	}
	// 11, 12, 20 and 21 bytes, with no class required
	testing.expect_value(
		t,
		password.validate("aaaaaaaaaaa", rules),
		password.Password_Error.Too_Short,
	)
	testing.expect_value(t, password.validate("aaaaaaaaaaaa", rules), password.Password_Error.None)
	testing.expect_value(
		t,
		password.validate("aaaaaaaaaaaaaaaaaaaa", rules),
		password.Password_Error.None,
	)
	testing.expect_value(
		t,
		password.validate("aaaaaaaaaaaaaaaaaaaaa", rules),
		password.Password_Error.Too_Long,
	)

	// a long passphrase is fine once the maximum is raised: this is why 72 is only a default
	defer free_all(context.temp_allocator)
	long := strings.repeat("a", 500, context.temp_allocator)
	testing.expect_value(t, password.validate(long, RULES), password.Password_Error.Too_Long)
	testing.expect_value(
		t,
		password.validate(long, {length_min = 8, length_max = 500, classes_required = {}}),
		password.Password_Error.None,
	)
	testing.expect_value(
		t,
		password.validate(long, {length_min = 8, length_max = 499, classes_required = {}}),
		password.Password_Error.Too_Long,
	)
}

// Each class is required only when the rules say so, and the first missing one is reported
// in the order uppercase, lowercase, digit, special.
@(test)
test_validate_class_rules :: proc(t: ^testing.T) {
	only :: proc(classes: bit_set[password.Character_Class]) -> password.Strength_Rules {
		return {length_min = 8, length_max = 72, classes_required = classes}
	}
	// "abcdefgh" has only lowercase letters
	testing.expect_value(t, password.validate("abcdefgh", only({})), password.Password_Error.None)
	testing.expect_value(
		t,
		password.validate("abcdefgh", only({.Lowercase})),
		password.Password_Error.None,
	)
	testing.expect_value(
		t,
		password.validate("abcdefgh", only({.Uppercase})),
		password.Password_Error.Missing_Uppercase,
	)
	testing.expect_value(
		t,
		password.validate("abcdefgh", only({.Digit})),
		password.Password_Error.Missing_Digit,
	)
	testing.expect_value(
		t,
		password.validate("abcdefgh", only({.Special})),
		password.Password_Error.Missing_Special,
	)

	// when several are missing, the order is fixed
	testing.expect_value(
		t,
		password.validate("abcdefgh", only({.Special, .Digit, .Uppercase})),
		password.Password_Error.Missing_Uppercase,
	)
	testing.expect_value(
		t,
		password.validate("abcdefgh", only({.Special, .Digit})),
		password.Password_Error.Missing_Digit,
	)
	testing.expect_value(
		t,
		password.validate("ABCDEFGH", only({.Lowercase, .Special})),
		password.Password_Error.Missing_Lowercase,
	)

	// all four, as in the default rules
	testing.expect_value(
		t,
		password.validate("Passw0rd!", only({.Uppercase, .Lowercase, .Digit, .Special})),
		password.Password_Error.None,
	)
}

// Length is checked before the encoding, and the encoding before the classes, whatever the rules.
@(test)
test_validate_check_order_with_rules :: proc(t: ^testing.T) {
	rules := password.Strength_Rules {
		length_min       = 4,
		length_max       = 10,
		classes_required = {.Special},
	}
	testing.expect_value(t, password.validate("ab\xff", rules), password.Password_Error.Too_Short)
	testing.expect_value(
		t,
		password.validate("abc\xffdef", rules),
		password.Password_Error.Invalid_Encoding,
	)
	testing.expect_value(
		t,
		password.validate("abcdefg", rules),
		password.Password_Error.Missing_Special,
	)
}

// The package rules and a per-call override, the same way the Argon2id policy works. This is the
// only test that changes the package rules, and it puts them back.
@(test)
test_package_strength_rules :: proc(t: ^testing.T) {
	saved := password.strength_rules_get()
	defer password.strength_rules_set(saved)

	password.strength_rules_set(password.STRENGTH_RULES_DEFAULT)
	testing.expect_value(t, password.strength_rules_get(), password.STRENGTH_RULES_DEFAULT)
	testing.expect_value(
		t,
		password.validate("abcdefgh"),
		password.Password_Error.Missing_Uppercase,
	)

	// the application sets its own rules: calls without rules follow them
	app := password.Strength_Rules {
		length_min       = 10,
		length_max       = 128,
		classes_required = {},
	}
	password.strength_rules_set(app)
	testing.expect_value(t, password.strength_rules_get(), app)
	testing.expect_value(t, password.validate("abcdefghi"), password.Password_Error.Too_Short)
	testing.expect_value(t, password.validate("abcdefghij"), password.Password_Error.None)

	// rules passed to a call win for that call, in both directions
	testing.expect_value(
		t,
		password.validate("abcdefghij", RULES),
		password.Password_Error.Missing_Uppercase,
	)
	testing.expect_value(
		t,
		password.validate("abcdefgh", {length_min = 8, length_max = 8, classes_required = {}}),
		password.Password_Error.None,
	)

	// the override does not change the package rules
	testing.expect_value(t, password.strength_rules_get(), app)
}

@(test)
test_length_messages_name_no_numbers :: proc(t: ^testing.T) {
	// the limits are configurable now, so the messages about them must not state a number
	for err in ([]password.Password_Error{.Too_Short, .Too_Long}) {
		message := password.password_error_to_string(err)
		for c in transmute([]u8)message {
			testing.expectf(
				t,
				c < '0' || c > '9',
				"message for %v contains a digit: %q",
				err,
				message,
			)
		}
	}
}
