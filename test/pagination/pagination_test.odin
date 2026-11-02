package pagination_test

import "core:testing"

import pagination "../../pagination"

// These tests read the package policy only through test_package_policy. All others
// pass a policy explicitly, so they can run beside it without seeing its changes.
POLICY :: pagination.POLICY_DEFAULT

@(test)
test_make_page_request :: proc(t: ^testing.T) {
	Case :: struct {
		offset, limit: u32,
		want_err:      pagination.Error,
	}
	cases := []Case {
		{10, 5, .None},
		{0, 1, .None},
		{0, POLICY.limit_max, .None},
		{max(u32), 1, .None}, // the largest offset
		{0, 0, .Zero_Limit},
		{10, 0, .Zero_Limit},
		{0, POLICY.limit_max + 1, .Over_Limit},
		{0, max(u32), .Over_Limit},
	}
	for c in cases {
		r, err := pagination.make_page_request(c.offset, c.limit, POLICY)
		testing.expectf(t, err == c.want_err, "make_page_request(%d, %d) error = %v, want %v", c.offset, c.limit, err, c.want_err)
		if err == .None {
			testing.expect_value(t, r, pagination.Page_Request{c.offset, c.limit})
			testing.expect(t, pagination.valid(r))
		} else {
			testing.expect_value(t, r, pagination.Page_Request{})
		}
	}
}

@(test)
test_valid :: proc(t: ^testing.T) {
	testing.expect(t, pagination.valid({0, 1}))
	testing.expect(t, pagination.valid({0, POLICY.limit_max}))
	testing.expect(t, !pagination.valid({}), "a zero value request has limit 0")
	testing.expect(t, !pagination.valid({5, 0}))
	// the largest page size belongs to the policy, which valid does not know
	testing.expect(t, pagination.valid({0, POLICY.limit_max + 1}))
}

@(test)
test_first :: proc(t: ^testing.T) {
	testing.expect_value(t, pagination.first(POLICY), pagination.Page_Request{0, POLICY.limit_default})
	testing.expect(t, pagination.valid(pagination.first(POLICY)))
	testing.expect_value(t, pagination.first({limit_default = 7, limit_max = 9}), pagination.Page_Request{0, 7})
}

@(test)
test_next :: proc(t: ^testing.T) {
	testing.expect_value(t, pagination.next({10, 10}), pagination.Page_Request{20, 10})
	testing.expect_value(t, pagination.next({0, 1}), pagination.Page_Request{1, 1})

	// saturates instead of wrapping to a small offset
	testing.expect_value(t, pagination.next({max(u32) - 5, 25}), pagination.Page_Request{max(u32), 25})
	testing.expect_value(t, pagination.next({max(u32), 25}), pagination.Page_Request{max(u32), 25})
	testing.expect_value(t, pagination.next({max(u32) - 25, 25}), pagination.Page_Request{max(u32), 25})
}

@(test)
test_previous :: proc(t: ^testing.T) {
	testing.expect_value(t, pagination.previous({20, 10}), pagination.Page_Request{10, 10})
	testing.expect_value(t, pagination.previous({10, 10}), pagination.Page_Request{0, 10})
	// stops at zero, never wraps around
	testing.expect_value(t, pagination.previous({3, 10}), pagination.Page_Request{0, 10})
	testing.expect_value(t, pagination.previous({0, 10}), pagination.Page_Request{0, 10})
	testing.expect_value(t, pagination.previous({1, 10}), pagination.Page_Request{0, 10})
}

@(test)
test_has_previous :: proc(t: ^testing.T) {
	testing.expect(t, !pagination.has_previous({0, 10}))
	testing.expect(t, pagination.has_previous({1, 10}))
	testing.expect(t, pagination.has_previous({max(u32), 10}))
}

@(test)
test_make_page_meta :: proc(t: ^testing.T) {
	r := pagination.Page_Request{20, 10}
	m := pagination.make_page_meta(r, 7, 27)
	testing.expect_value(t, m, pagination.Page_Meta{total = 27, request = r, count = 7})

	// a full page, and an empty page past the end
	testing.expect_value(t, pagination.make_page_meta(r, 10, 100).count, 10)
	testing.expect_value(t, pagination.make_page_meta({500, 10}, 0, 100).count, 0)
}

@(test)
test_page_count :: proc(t: ^testing.T) {
	count :: proc(limit: u32, total: u64) -> u64 {
		return pagination.page_count(pagination.make_page_meta({0, limit}, 0, total))
	}
	testing.expect_value(t, count(10, 0), 0)
	testing.expect_value(t, count(10, 1), 1)
	testing.expect_value(t, count(10, 10), 1)
	testing.expect_value(t, count(10, 11), 2)
	testing.expect_value(t, count(10, 100), 10)
	testing.expect_value(t, count(1, 7), 7)
	// a total near max(u64) must not overflow the rounding up
	testing.expect_value(t, count(1, max(u64)), max(u64))
	testing.expect_value(t, count(1000, max(u64)), max(u64) / 1000 + 1)
}

@(test)
test_has_next :: proc(t: ^testing.T) {
	has_next :: proc(offset, limit: u32, total: u64) -> bool {
		return pagination.has_next(pagination.make_page_meta({offset, limit}, 0, total))
	}
	testing.expect(t, has_next(0, 10, 11))
	testing.expect(t, !has_next(0, 10, 10))
	testing.expect(t, !has_next(90, 10, 100))
	testing.expect(t, has_next(80, 10, 100))
	testing.expect(t, !has_next(0, 10, 0), "no items: no next page")
	testing.expect(t, !has_next(500, 10, 100), "a page past the end has no next page")
	testing.expect(t, !has_next(max(u32), 1000, 100), "offset and limit together would overflow u32")
	testing.expect(t, has_next(max(u32), 1000, max(u64)))
}

@(test)
test_walk_all_pages :: proc(t: ^testing.T) {
	// Following next from the first page visits page_count pages and then stops.
	total :: 103
	r := pagination.Page_Request{0, 10}
	pages: u64
	for {
		count := u32(min(u64(r.limit), total - min(u64(r.offset), total)))
		m := pagination.make_page_meta(r, count, total)
		pages += 1
		if !pagination.has_next(m) {
			testing.expect_value(t, pages, pagination.page_count(m))
			break
		}
		r = pagination.next(r)
		testing.expect(t, pages < 100, "next never reached the end")
		if pages >= 100 {
			break
		}
	}
}

@(test)
test_error_to_string :: proc(t: ^testing.T) {
	for err in pagination.Error {
		testing.expectf(t, len(pagination.error_to_string(err)) > 0, "no message for %v", err)
	}
	testing.expect_value(t, pagination.error_to_string(.Zero_Limit), "page limit is zero")
}

@(test)
test_policy_valid :: proc(t: ^testing.T) {
	testing.expect(t, pagination.policy_valid(POLICY))
	testing.expect(t, pagination.policy_valid({limit_default = 1, limit_max = 1}))
	testing.expect(t, pagination.policy_valid({limit_default = 1, limit_max = max(u32)}), "the application picks the cap")
	testing.expect(t, !pagination.policy_valid({}), "zero value")
	testing.expect(t, !pagination.policy_valid({limit_default = 0, limit_max = 10}))
	testing.expect(t, !pagination.policy_valid({limit_default = 11, limit_max = 10}), "default over max")
	testing.expect(t, !pagination.policy_valid({limit_default = 5, limit_max = 0}))
}

// The only test that reads or changes the package policy. It restores it on the way out.
@(test)
test_package_policy :: proc(t: ^testing.T) {
	saved := pagination.policy_get()
	defer pagination.policy_set(saved)

	// built-in policy until the application sets one
	pagination.policy_set(pagination.POLICY_DEFAULT)
	testing.expect_value(t, pagination.policy_get(), pagination.POLICY_DEFAULT)
	testing.expect_value(t, pagination.first(), pagination.Page_Request{0, pagination.POLICY_DEFAULT.limit_default})
	_, err := pagination.make_page_request(0, pagination.POLICY_DEFAULT.limit_max)
	testing.expect_value(t, err, pagination.Error.None)
	_, err = pagination.make_page_request(0, pagination.POLICY_DEFAULT.limit_max + 1)
	testing.expect_value(t, err, pagination.Error.Over_Limit)

	// the application sets its own limits: calls without a policy follow them
	app := pagination.Policy {
		limit_default = 10,
		limit_max     = 50,
	}
	pagination.policy_set(app)
	testing.expect_value(t, pagination.policy_get(), app)
	testing.expect_value(t, pagination.first(), pagination.Page_Request{0, 10})
	r, err2 := pagination.make_page_request(0, 50)
	testing.expect_value(t, err2, pagination.Error.None)
	testing.expect_value(t, r, pagination.Page_Request{0, 50})
	_, err2 = pagination.make_page_request(0, 51)
	testing.expect_value(t, err2, pagination.Error.Over_Limit)

	// an endpoint passes its own policy: it wins for that call, in both directions
	admin := pagination.Policy {
		limit_default = 100,
		limit_max     = 500,
	}
	_, err2 = pagination.make_page_request(0, 500, admin)
	testing.expect_value(t, err2, pagination.Error.None)
	strict := pagination.Policy {
		limit_default = 5,
		limit_max     = 20,
	}
	_, err2 = pagination.make_page_request(0, 21, strict)
	testing.expect_value(t, err2, pagination.Error.Over_Limit)
	testing.expect_value(t, pagination.first(admin), pagination.Page_Request{0, 100})

	// the override does not change the package policy
	testing.expect_value(t, pagination.policy_get(), app)
	_, err2 = pagination.make_page_request(0, 51)
	testing.expect_value(t, err2, pagination.Error.Over_Limit)
}
