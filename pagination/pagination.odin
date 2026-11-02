// Package pagination describes offset and limit pagination: a Page_Request asks
// for one page, and a Page_Meta describes the page that came back.
//
// Offsets, limits and counts are unsigned, so they cannot be negative. Page size
// rules live in a Policy: a default page size and a largest page size.
// make_page_request and first take a Policy, which defaults to the package policy.
// The package policy starts as POLICY_DEFAULT; the application can change it once at
// startup with policy_set, and an endpoint with its own rules passes its own Policy
// to override it for that call. The numbers are the application's choice: the package
// only requires 0 < limit_default <= limit_max.
//
// The package policy is plain package state: call policy_set before other threads
// use the package, and not while they do.
//
// A Page_Request{} has limit 0, which is not valid. The procs that take a request
// require a valid one and assert it. valid checks only that the limit is not 0; the
// largest page size is checked when a request is made, against the policy given then.
package pagination

// ============================================================================
// enums: request errors
// ============================================================================

// Reasons make_page_request can reject a request.
Error :: enum {
	None,
	Zero_Limit,
	Over_Limit, // limit > policy.limit_max
}

// ============================================================================
// types: policy, request and metadata
// ============================================================================

// Page size rules for a list. Valid when 0 < limit_default <= limit_max.
Policy :: struct {
	limit_default: u32, // page size of first()
	limit_max:     u32, // largest page size make_page_request accepts
}

// A request for one page: skip `offset` items, then take at most `limit`.
Page_Request :: struct {
	offset: u32,
	limit:  u32,
}

// Describes a fetched page: the total number of items available, the request
// that produced the page, and how many items the page actually holds.
// The 8 byte total comes first so the struct has no padding.
Page_Meta :: struct {
	total:   u64,
	request: Page_Request,
	count:   u32,
}

// ============================================================================
// constants: built-in policy
// ============================================================================

// The package policy until policy_set changes it.
POLICY_DEFAULT :: Policy {
	limit_default = 25,
	limit_max     = 1000,
}

// ============================================================================
// procs: policy
// ============================================================================

@(private)
policy_package := POLICY_DEFAULT

// True if 0 < limit_default <= limit_max.
policy_valid :: proc(policy: Policy) -> bool {
	return 0 < policy.limit_default && policy.limit_default <= policy.limit_max
}

// Replaces the package policy. policy must be valid (asserted).
// Call it before other threads use the package, and not while they do.
policy_set :: proc(policy: Policy) {
	assert(policy_valid(policy))
	policy_package = policy
}

// The package policy now in effect.
policy_get :: proc() -> Policy {
	return policy_package
}

// ============================================================================
// procs: requests
// ============================================================================

error_to_string :: proc(err: Error) -> string {
	switch err {
	case .None:
		return "no error"
	case .Zero_Limit:
		return "page limit is zero"
	case .Over_Limit:
		return "page limit is over the maximum"
	}
	unreachable()
}

// Validates and builds a Page_Request. policy must be valid (asserted).
// Returns .Zero_Limit if limit is 0 and .Over_Limit if limit > policy.limit_max.
make_page_request :: proc(offset, limit: u32, policy := policy_package) -> (Page_Request, Error) {
	assert(policy_valid(policy))
	if limit == 0 {
		return {}, .Zero_Limit
	}
	if limit > policy.limit_max {
		return {}, .Over_Limit
	}
	return {offset, limit}, .None
}

// True if r has a limit other than 0. Every Page_Request returned by
// make_page_request, first, next and previous is valid.
valid :: proc(r: Page_Request) -> bool {
	return r.limit > 0
}

// First page with the policy's default page size. policy must be valid (asserted).
first :: proc(policy := policy_package) -> Page_Request {
	assert(policy_valid(policy))
	return {0, policy.limit_default}
}

// Request for the page after `r`, with the same limit. Does not check against
// any total. The offset saturates at max(u32), so it never wraps around.
next :: proc(r: Page_Request) -> Page_Request {
	assert(valid(r))
	offset := min(u64(r.offset) + u64(r.limit), u64(max(u32)))
	return {u32(offset), r.limit}
}

// Request for the page before `r`, with the same limit. The offset stops at 0.
previous :: proc(r: Page_Request) -> Page_Request {
	assert(valid(r))
	offset := r.offset - r.limit if r.offset > r.limit else 0
	return {offset, r.limit}
}

// True if there are items before this request's offset.
has_previous :: proc(r: Page_Request) -> bool {
	return r.offset > 0
}

// ============================================================================
// procs: metadata
// ============================================================================

// Builds a Page_Meta for request `r`, which returned `count` items out of `total`.
// count cannot exceed the limit (asserted). It is not checked against total,
// because the two usually come from separate queries that can race.
make_page_meta :: proc(r: Page_Request, count: u32, total: u64) -> Page_Meta {
	assert(valid(r))
	assert(count <= r.limit)
	return {total, r, count}
}

// Number of pages needed to hold all items; 0 when there are none.
page_count :: proc(m: Page_Meta) -> u64 {
	assert(valid(m.request))
	limit := u64(m.request.limit)
	// Not (total + limit - 1) / limit: that overflows for a total near max(u64).
	return m.total / limit + u64(m.total % limit != 0)
}

// True if items remain beyond the end of this page.
has_next :: proc(m: Page_Meta) -> bool {
	assert(valid(m.request))
	return u64(m.request.offset) + u64(m.request.limit) < m.total
}
