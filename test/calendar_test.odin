package chrono_test

import "core:testing"

import chrono "../"

@(test)
test_days_in_month :: proc(t: ^testing.T) {
	testing.expect_value(t, chrono.days_in_month(2026, .january), 31)
	testing.expect_value(t, chrono.days_in_month(2026, .february), 28)
	testing.expect_value(t, chrono.days_in_month(2024, .february), 29)
	testing.expect_value(t, chrono.days_in_month(1900, .february), 28)
	testing.expect_value(t, chrono.days_in_month(2026, .april), 30)
	testing.expect_value(t, chrono.days_in_month(2026, .december), 31)
}
