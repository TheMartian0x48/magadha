// Package password checks the strength of plaintext passwords and stores them as
// Argon2id hashes in PHC string format.
//
// validate checks a new password against the strength rules. hash_of hashes it with a
// fresh random salt and returns a Password_Hash, which is the string to store.
// hash_from_string wraps a hash read back from storage, and verify checks a plaintext
// password against one. A wrong password is not an error: verify returns false.
//
// Hash strings come from storage, so they are not trusted. They are parsed in full, and
// the cost parameters they ask for must stay within an Argon2id_Policy, so a bad row
// cannot ask for gigabytes of memory or hours of work. The application decides the
// limits: it sets the package policy once at startup with argon2id_policy_set, and any
// call can pass its own policy instead. The policy starts as ARGON2ID_POLICY_DEFAULT,
// which is generous, so set a tighter one that fits your servers. The parameters you pass
// to hash_of are your own and are not checked against the policy.
//
// What counts as a strong password is the application's decision. validate checks a
// password against a Strength_Rules: a shortest and longest length in bytes, and the
// character classes that must appear. The package rules start as STRENGTH_RULES_DEFAULT; the
// application sets its own once at startup with strength_rules_set, and any call can pass
// its own rules instead.
//
// The package policy and the package rules are plain package state: set them before other
// threads use the package, and not while they do.
//
// A Password_Hash is heap allocated and owned by the holder: free it with destroy, using
// the allocator it was created with. Hashing takes its work area (the memory cost of the
// parameters) from the same allocator and releases it before returning, so do not give it
// a small arena. Lengths are counted in bytes.
package password

import "base:runtime"
import "core:crypto"
import "core:crypto/argon2id"
import "core:encoding/base64"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

// ============================================================================
// constants: hashing cost and size limits
// ============================================================================

// The default Argon2id cost, from the OWASP Password Storage Cheat Sheet:
// 19 MiB of memory, 2 passes, 1 lane. Pass your own `argon2id.Parameters` to
// `hash_of` to change it.
DEFAULT_PARAMS :: argon2id.Parameters {
	memory_size = 19 * 1024,
	passes      = 2,
	parallelism = 1,
}

// The package policy until argon2id_policy_set changes it. Each limit is the largest value
// in any of the parameter sets that core:crypto/argon2id recommends (RFC 9106 and OWASP),
// so every recommended set verifies. It is generous: a single verify may take 2 GiB.
// A test keeps these numbers equal to the library's presets.
ARGON2ID_POLICY_DEFAULT :: Argon2id_Policy {
	memory_size = 2 * 1024 * 1024,
	passes      = 5,
	parallelism = 4,
}

// Size in bytes of the random salt and of the derived tag.
SALT_SIZE :: argon2id.RECOMMENDED_SALT_SIZE
TAG_SIZE :: argon2id.RECOMMENDED_TAG_SIZE

// The package rules until strength_rules_set changes them: 8 to 72 bytes, with an uppercase
// letter, a lowercase letter, a digit and a special character. The 72 is kept from the
// bcrypt version of this package, which ignores everything past 72 bytes; Argon2id has no
// such limit, so most applications will want a larger maximum.
STRENGTH_RULES_DEFAULT :: Strength_Rules {
	length_min       = 8,
	length_max       = 72,
	classes_required = {.Uppercase, .Lowercase, .Digit, .Special},
}

// Sanity limit on the length of a hash string accepted by `hash_from_string`.
// A hash made with the default parameters is 97 bytes long.
@(private)
HASH_LENGTH_MAX :: 512

@(private)
PHC_PREFIX :: "$argon2id$v=19$"

// Argon2 requires a salt of at least 8 bytes.
@(private)
SALT_SIZE_MIN :: 8

// Argon2 works in 1 KiB blocks; `memory_size` is a count of them.
@(private)
BLOCK_SIZE_BYTES :: 1024

// ============================================================================
// enums: failure modes
// ============================================================================

// The kinds of character a password can be required to contain.
Character_Class :: enum u8 {
	Uppercase,
	Lowercase,
	Digit,
	Special, // punctuation or a symbol
}

// Password_Error enumerates the failure modes of `validate`.
Password_Error :: enum u8 {
	None,
	Too_Short,
	Too_Long,
	Invalid_Encoding, // not valid UTF-8
	Missing_Uppercase,
	Missing_Lowercase,
	Missing_Digit,
	Missing_Special,
}

// Hash_Error enumerates the failure modes of hashing, parsing and verifying.
Hash_Error :: enum u8 {
	None,
	// The string is not a well-formed `$argon2id$v=19$...` hash.
	Invalid_Format,
	// The cost parameters are out of the range Argon2id supports.
	Invalid_Parameters,
	Out_Of_Memory,
}

// ============================================================================
// types: password hash and its parsed fields
// ============================================================================

// Password_Hash is an Argon2id-hashed password in PHC string format:
//
//	$argon2id$v=19$m=19456,t=2,p=1$<salt>$<tag>
//
// where salt and tag are unpadded standard base64. The string is heap
// allocated and owned by the holder: free it with `destroy`, using the
// allocator it was created with. Comparable with `==` and usable as a map key.
Password_Hash :: distinct string

// Limits on the cost parameters that a stored hash may ask for. A hash above any of them
// is rejected with Invalid_Parameters before anything is hashed. Each field is the largest
// value allowed, in the units of argon2id.Parameters: memory_size in KiB, passes, parallelism.
// It is a distinct type, so a cost to hash with cannot be passed where a limit is expected.
// Valid when each limit is at least the smallest value Argon2id accepts: 8 KiB, 1 pass,
// 1 lane. A limit above what `argon2id.derive` can run is harmless, because those
// parameters are rejected anyway.
Argon2id_Policy :: distinct argon2id.Parameters

// What `validate` requires of a password. Lengths are in bytes. Valid when 1 <= length_max
// and length_min <= length_max. classes_required may be empty, for no composition rules.
Strength_Rules :: struct {
	length_min:       u32,
	length_max:       u32,
	classes_required: bit_set[Character_Class],
}

// The fields of a parsed hash string. `salt` and `tag` are allocated.
@(private)
Parsed :: struct {
	params: argon2id.Parameters,
	salt:   []byte,
	tag:    []byte,
}

// ============================================================================
// procs: argon2id policy
// ============================================================================

@(private)
argon2id_policy_package := ARGON2ID_POLICY_DEFAULT

// True if every limit is at least the smallest value Argon2id accepts.
argon2id_policy_valid :: proc(policy: Argon2id_Policy) -> bool {
	return(
		policy.memory_size >= 8 &&
		policy.passes >= 1 &&
		policy.parallelism >= argon2id.MIN_PARALLELISM \
	)
}

// Replaces the package policy. policy must be valid (asserted).
// Call it before other threads use the package, and not while they do.
argon2id_policy_set :: proc(policy: Argon2id_Policy) {
	assert(argon2id_policy_valid(policy))
	argon2id_policy_package = policy
}

// The package policy now in effect.
argon2id_policy_get :: proc() -> Argon2id_Policy {
	return argon2id_policy_package
}

// ============================================================================
// procs: strength rules
// ============================================================================

@(private)
strength_rules_package := STRENGTH_RULES_DEFAULT

// True if 1 <= length_max and length_min <= length_max.
strength_rules_valid :: proc(rules: Strength_Rules) -> bool {
	return rules.length_max >= 1 && rules.length_min <= rules.length_max
}

// Replaces the package rules. rules must be valid (asserted).
// Call it before other threads use the package, and not while they do.
strength_rules_set :: proc(rules: Strength_Rules) {
	assert(strength_rules_valid(rules))
	strength_rules_package = rules
}

// The package rules now in effect.
strength_rules_get :: proc() -> Strength_Rules {
	return strength_rules_package
}

// ============================================================================
// procs: error messages
// ============================================================================

password_error_to_string :: proc(err: Password_Error) -> string {
	switch err {
	case .None:
		return "no error"
	case .Too_Short:
		return "password is shorter than the minimum length"
	case .Too_Long:
		return "password is longer than the maximum length"
	case .Invalid_Encoding:
		return "password is not valid UTF-8"
	case .Missing_Uppercase:
		return "password is missing an uppercase letter"
	case .Missing_Lowercase:
		return "password is missing a lowercase letter"
	case .Missing_Digit:
		return "password is missing a digit"
	case .Missing_Special:
		return "password is missing a special character"
	}
	unreachable()
}

// Returns a short stable identifier for the error, e.g. "too_short", suitable
// for API responses and logs.
password_error_code :: proc(err: Password_Error) -> string {
	switch err {
	case .None:
		return "none"
	case .Too_Short:
		return "too_short"
	case .Too_Long:
		return "too_long"
	case .Invalid_Encoding:
		return "invalid_encoding"
	case .Missing_Uppercase:
		return "missing_uppercase"
	case .Missing_Lowercase:
		return "missing_lowercase"
	case .Missing_Digit:
		return "missing_digit"
	case .Missing_Special:
		return "missing_special"
	}
	unreachable()
}

hash_error_to_string :: proc(err: Hash_Error) -> string {
	switch err {
	case .None:
		return "no error"
	case .Invalid_Format:
		return "password hash is not a valid argon2id string"
	case .Invalid_Parameters:
		return "password hash parameters are out of range"
	case .Out_Of_Memory:
		return "out of memory while hashing the password"
	}
	unreachable()
}

// ============================================================================
// procs: strength rules
// ============================================================================

// Checks a plaintext password against `rules`, which default to the package rules: its length
// in bytes, and that it contains each character class the rules require. The text must be
// valid UTF-8. Returns the first rule that fails, in this order: length, encoding, then
// uppercase, lowercase, digit, special. rules must be valid (asserted).
validate :: proc(s: string, rules := strength_rules_package) -> Password_Error {
	assert(strength_rules_valid(rules))
	if u64(len(s)) < u64(rules.length_min) {
		return .Too_Short
	}
	if u64(len(s)) > u64(rules.length_max) {
		return .Too_Long
	}
	// A byte that is not valid UTF-8 decodes to U+FFFD, a symbol, and would count as the
	// special character. Reject it instead of letting it satisfy a rule.
	if !utf8.valid_string(s) {
		return .Invalid_Encoding
	}
	found: bit_set[Character_Class]
	for c in s {
		switch {
		case unicode.is_upper(c):
			found += {.Uppercase}
		case unicode.is_lower(c):
			found += {.Lowercase}
		case unicode.is_decimal(c):
			found += {.Digit}
		case unicode.is_punct(c) || unicode.is_symbol(c):
			found += {.Special}
		}
	}
	missing := rules.classes_required - found
	switch {
	case .Uppercase in missing:
		return .Missing_Uppercase
	case .Lowercase in missing:
		return .Missing_Lowercase
	case .Digit in missing:
		return .Missing_Digit
	case .Special in missing:
		return .Missing_Special
	}
	return .None
}

// ============================================================================
// procs: hashing and verifying
// ============================================================================

// Hashes a plaintext password with Argon2id and a fresh random salt. The cost
// parameters default to `DEFAULT_PARAMS`; pass your own to change them. Does not
// check password strength; see `validate`.
//
// The parameters are your own, so they are not checked against the Argon2id_Policy, only
// against what `argon2id.derive` accepts. A hash made above the policy is rejected later
// by `verify`, so keep the two in step.
//
// The result is allocated with `allocator`; free it with `destroy`. The hashing
// work area (`params.memory_size` KiB) is also taken from `allocator` and
// released before returning, so avoid small arenas and the temp allocator.
hash_of :: proc(
	plain: string,
	params := DEFAULT_PARAMS,
	allocator := context.allocator,
) -> (
	Password_Hash,
	Hash_Error,
) {
	params := params
	if !params_derivable(params) {
		return "", .Invalid_Parameters
	}

	salt: [SALT_SIZE]byte
	crypto.rand_bytes(salt[:])

	tag: [TAG_SIZE]byte
	if err := argon2id.derive(
		&params,
		transmute([]byte)plain,
		salt[:],
		tag[:],
		allocator = allocator,
	); err != nil {
		return "", .Out_Of_Memory
	}

	// 22 and 43 characters of unpadded base64; the buffers have room to spare.
	// Encoding into a big enough buffer cannot fail, so a failure is a bug here.
	salt_buf, tag_buf: [64]byte
	salt_b64, salt_err := base64.encode_into_buf(salt_buf[:], salt[:], options = {.No_Padding})
	tag_b64, tag_err := base64.encode_into_buf(tag_buf[:], tag[:], options = {.No_Padding})
	assert(salt_err == nil && tag_err == nil)
	assert(len(salt_b64) == 22 && len(tag_b64) == 43)

	// Format into a stack buffer, then make the one allocation that can fail and check it.
	// A builder on the context allocator would ignore an allocation failure and hand back a
	// truncated hash. This one writes into fixed storage and never allocates.
	text_buf: [HASH_LENGTH_MAX]byte
	sb := strings.builder_from_bytes(text_buf[:])
	strings.write_string(&sb, PHC_PREFIX)
	strings.write_string(&sb, "m=")
	strings.write_u64(&sb, u64(params.memory_size))
	strings.write_string(&sb, ",t=")
	strings.write_u64(&sb, u64(params.passes))
	strings.write_string(&sb, ",p=")
	strings.write_u64(&sb, u64(params.parallelism))
	strings.write_byte(&sb, '$')
	strings.write_bytes(&sb, salt_b64)
	strings.write_byte(&sb, '$')
	strings.write_bytes(&sb, tag_b64)
	text := strings.to_string(sb)
	// The longest text is 15 + 2 + 10 + 3 + 10 + 3 + 10 + 1 + 22 + 1 + 43 = 120 bytes, so it
	// always fits; a full buffer would silently drop the end of the hash.
	assert(len(text) < HASH_LENGTH_MAX)

	hash, clone_err := strings.clone(text, allocator)
	if clone_err != nil {
		return "", .Out_Of_Memory
	}
	return Password_Hash(hash), .None
}

// Wraps an existing Argon2id PHC string (e.g. "$argon2id$v=19$m=19456,t=2,p=1$...")
// as a Password_Hash. Intended for re-hydrating a hash read from a SQL column;
// for hashing a new plaintext password use `hash_of`.
//
// The whole string is parsed, so a malformed or unsupported hash is rejected
// here rather than at `verify`. Its cost parameters must be within `policy`, which
// defaults to the package policy; policy must be valid (asserted). The result is a copy
// allocated with `allocator`, so it must be freed with `destroy` like any other Password_Hash.
hash_from_string :: proc(
	s: string,
	allocator := context.allocator,
	policy := argon2id_policy_package,
) -> (
	Password_Hash,
	Hash_Error,
) {
	assert(argon2id_policy_valid(policy))
	parsed, err := parse(s, policy, allocator)
	if err != nil {
		return "", err
	}
	parsed_destroy(parsed, allocator)

	cloned, clone_err := strings.clone(s, allocator)
	if clone_err != nil {
		return "", .Out_Of_Memory
	}
	return Password_Hash(cloned), .None
}

// Reports whether `plain` matches the hash. A wrong password is not an error:
// it returns `false, .None`. An error is returned only if the hash itself is
// malformed (possible only for a Password_Hash not made by this package), or
// on allocation failure. The comparison runs in constant time.
//
// The hash's cost parameters must be within `policy`, which defaults to the package
// policy; policy must be valid (asserted). Hashing takes up to `policy.memory_size`
// KiB from `allocator`.
verify :: proc(
	hash: Password_Hash,
	plain: string,
	allocator := context.allocator,
	policy := argon2id_policy_package,
) -> (
	ok: bool,
	err: Hash_Error,
) {
	assert(argon2id_policy_valid(policy))
	parsed := parse(string(hash), policy, allocator) or_return
	defer parsed_destroy(parsed, allocator)

	derived, alloc_err := make([]byte, len(parsed.tag), allocator)
	if alloc_err != nil {
		return false, .Out_Of_Memory
	}
	defer {
		crypto.zero_explicit(raw_data(derived), len(derived))
		delete(derived, allocator)
	}

	assert(len(derived) == len(parsed.tag))
	params := parsed.params
	if derive_err := argon2id.derive(
		&params,
		transmute([]byte)plain,
		parsed.salt,
		derived,
		allocator = allocator,
	); derive_err != nil {
		return false, .Out_Of_Memory
	}
	return crypto.compare_constant_time(derived, parsed.tag) == 1, .None
}

// Frees a Password_Hash. `allocator` must be the one it was created with.
destroy :: proc(hash: Password_Hash, allocator := context.allocator) {
	delete(string(hash), allocator)
}

// ============================================================================
// procs: parsing a stored hash
// ============================================================================

// Reports whether `argon2id.derive` accepts the parameters. It panics on anything else, so
// this has to be checked before hashing untrusted values. These bounds belong to the
// library, not to the application, so they are not configurable.
@(private)
params_derivable :: proc(p: argon2id.Parameters) -> bool {
	if p.parallelism < argon2id.MIN_PARALLELISM || p.parallelism > argon2id.MAX_PARALLELISM {
		return false
	}
	if p.passes < 1 {
		return false
	}
	// At least 8 blocks per lane, and the memory in bytes must fit an int.
	return(
		u64(p.memory_size) >= 8 * u64(p.parallelism) &&
		u64(p.memory_size) * BLOCK_SIZE_BYTES <= u64(max(int)) \
	)
}

// Reports whether the parameters are derivable and within the application's policy.
@(private)
params_within :: proc(p: argon2id.Parameters, policy: Argon2id_Policy) -> bool {
	return(
		params_derivable(p) &&
		p.memory_size <= policy.memory_size &&
		p.passes <= policy.passes &&
		p.parallelism <= policy.parallelism \
	)
}

// Parses `$argon2id$v=19$m=<m>,t=<t>,p=<p>$<salt>$<tag>`. Only that exact form
// is accepted: fixed field order, unpadded canonical base64, no extra fields.
// On success the caller owns `salt` and `tag` (see `parsed_destroy`).
@(private)
parse :: proc(
	s: string,
	policy: Argon2id_Policy,
	allocator := context.allocator,
) -> (
	parsed: Parsed,
	err: Hash_Error,
) {
	if len(s) > HASH_LENGTH_MAX || !strings.has_prefix(s, PHC_PREFIX) {
		return {}, .Invalid_Format
	}

	params_str, sep, rest := strings.partition(s[len(PHC_PREFIX):], "$")
	if sep == "" {
		return {}, .Invalid_Format
	}
	salt_str, sep2, tag_str := strings.partition(rest, "$")
	if sep2 == "" || strings.contains_rune(tag_str, '$') {
		return {}, .Invalid_Format
	}

	m_str, comma1, after_m := strings.partition(params_str, ",")
	t_str, comma2, p_str := strings.partition(after_m, ",")
	if comma1 == "" || comma2 == "" {
		return {}, .Invalid_Format
	}
	if !strings.has_prefix(m_str, "m=") ||
	   !strings.has_prefix(t_str, "t=") ||
	   !strings.has_prefix(p_str, "p=") {
		return {}, .Invalid_Format
	}
	m, m_ok := parse_u32(m_str[2:])
	t, t_ok := parse_u32(t_str[2:])
	p, p_ok := parse_u32(p_str[2:])
	if !m_ok || !t_ok || !p_ok {
		return {}, .Invalid_Format
	}
	parsed.params = {
		memory_size = m,
		passes      = t,
		parallelism = p,
	}
	if !params_within(parsed.params, policy) {
		return {}, .Invalid_Parameters
	}

	parsed.salt = decode_b64(salt_str, allocator) or_return
	parsed.tag, err = decode_b64(tag_str, allocator)
	if err != .None {
		delete(parsed.salt, allocator) // already decoded: do not leak it
		return {}, err
	}
	if len(parsed.salt) < SALT_SIZE_MIN || len(parsed.tag) < argon2id.MIN_TAG_SIZE {
		parsed_destroy(parsed, allocator)
		return {}, .Invalid_Format
	}
	assert(params_within(parsed.params, policy))
	assert(len(parsed.salt) >= SALT_SIZE_MIN && len(parsed.tag) >= argon2id.MIN_TAG_SIZE)
	return parsed, .None
}

@(private)
parsed_destroy :: proc(parsed: Parsed, allocator := context.allocator) {
	delete(parsed.salt, allocator)
	delete(parsed.tag, allocator)
}

// Decodes strict, unpadded base64. Strict mode rejects non-canonical input, so
// each hash has exactly one valid spelling.
@(private)
decode_b64 :: proc(s: string, allocator := context.allocator) -> (b: []byte, err: Hash_Error) {
	decoded, decode_err := base64.decode(
		s,
		options = {.No_Padding, .Strict},
		allocator = allocator,
	)
	if decode_err != nil {
		if _, is_alloc := decode_err.(runtime.Allocator_Error); is_alloc {
			return nil, .Out_Of_Memory
		}
		return nil, .Invalid_Format
	}
	return decoded, .None
}

// Parses a plain decimal number that fits a u32: digits only, no sign and no
// leading zeros (as PHC requires).
@(private)
parse_u32 :: proc(s: string) -> (n: u32, ok: bool) {
	if len(s) == 0 || len(s) > 10 || (len(s) > 1 && s[0] == '0') {
		return 0, false
	}
	v: u64
	for c in transmute([]byte)s {
		if c < '0' || c > '9' {
			return 0, false
		}
		v = v * 10 + u64(c - '0')
	}
	if v > u64(max(u32)) {
		return 0, false
	}
	return u32(v), true
}
