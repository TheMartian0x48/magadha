package chrono

import "base:intrinsics"

// ============================================================================
// constants: unit conversions
// ============================================================================

NANOSECONDS_PER_MILLISECOND :: 1_000_000
NANOSECONDS_PER_SECOND :: 1_000_000_000
MILLISECONDS_PER_SECOND :: 1_000
SECONDS_PER_MINUTE :: 60
SECONDS_PER_HOUR :: 3_600
SECONDS_PER_DAY :: 86_400
HOURS_PER_DAY :: 24

// ============================================================================
// constants: supported calendar range
// ============================================================================

// Bounds the supported years so the epoch-day arithmetic can never overflow an `i64`.
YEAR_MIN :: Year(-999_999)
YEAR_MAX :: Year(999_999)

// The epoch days of `YEAR_MIN`-01-01 and `YEAR_MAX`-12-31, so a valid `Epoch_Day` is exactly
// one that converts to a `Local_Date`. The tests check these against the date conversion.
EPOCH_DAY_MIN :: Epoch_Day(-365_961_662)
EPOCH_DAY_MAX :: Epoch_Day(364_522_971)

// The first and last supported dates. Their epoch days are `EPOCH_DAY_MIN` and `EPOCH_DAY_MAX`.
LOCAL_DATE_MIN :: Local_Date{YEAR_MIN, .january, 1}
LOCAL_DATE_MAX :: Local_Date{YEAR_MAX, .december, 31}

// ============================================================================
// constants: time of day
// ============================================================================

// The last second of a day, 23:59:59. There are no leap seconds.
SECOND_OF_DAY_MAX :: Second_Of_Day(SECONDS_PER_DAY - 1)

// The first and last supported times of day. There is no 24:00 and no leap second.
LOCAL_TIME_MIN :: Local_Time{}
LOCAL_TIME_MAX :: Local_Time{23, 59, 59, NANOSECONDS_PER_SECOND - 1}

// Zero is valid for every `Local_Time` field, so a zeroed `Local_Time` is midnight.
LOCAL_TIME_MIDNIGHT :: LOCAL_TIME_MIN
LOCAL_TIME_NOON :: Local_Time{12, 0, 0, 0}

// ============================================================================
// constants: date and time
// ============================================================================

// The first and last supported date times. They are the widest span a `Duration` can hold.
LOCAL_DATE_TIME_MIN :: Local_Date_Time{LOCAL_DATE_MIN, LOCAL_TIME_MIN}
LOCAL_DATE_TIME_MAX :: Local_Date_Time{LOCAL_DATE_MAX, LOCAL_TIME_MAX}

// ============================================================================
// constants: zone offset
// ============================================================================

// Real offsets run from -12:00 to +14:00. The cap leaves room above that and keeps a local
// date within one day of the `Instant` it came from.
ZONE_OFFSET_SECONDS_MAX :: 18 * SECONDS_PER_HOUR

ZONE_OFFSET_UTC :: Zone_Offset{}
ZONE_OFFSET_MIN :: Zone_Offset{-ZONE_OFFSET_SECONDS_MAX}
ZONE_OFFSET_MAX :: Zone_Offset{ZONE_OFFSET_SECONDS_MAX}

// ============================================================================
// constants: supported timeline range
// ============================================================================

// An `Instant` spans from the start of `EPOCH_DAY_MIN` to the last second of `EPOCH_DAY_MAX`,
// so a valid `Instant` always lands on a supported calendar day in UTC. Both limits are about
// 3e13, far inside an `i64`, so adding two of them never overflows.
INSTANT_SECONDS_MIN :: i64(EPOCH_DAY_MIN) * SECONDS_PER_DAY
INSTANT_SECONDS_MAX :: (i64(EPOCH_DAY_MAX) + 1) * SECONDS_PER_DAY - 1

// A `Duration` holds the difference of any two valid `Instant`s. The nanoseconds count
// forward, so the most negative `Duration` reaches one second below the negated maximum.
DURATION_SECONDS_MAX :: INSTANT_SECONDS_MAX - INSTANT_SECONDS_MIN
DURATION_SECONDS_MIN :: -DURATION_SECONDS_MAX - 1

// ============================================================================
// constants: period caps
// ============================================================================

// Each `Period` field is capped at the size of the whole supported calendar, because a larger
// `Period` cannot be applied to any date. The caps are symmetric, so negating never overflows.
PERIOD_YEARS_MAX :: i32(YEAR_MAX - YEAR_MIN)
PERIOD_MONTHS_MAX :: PERIOD_YEARS_MAX * 12
PERIOD_DAYS_MAX :: i32(EPOCH_DAY_MAX - EPOCH_DAY_MIN)

// ============================================================================
// enums
// ============================================================================

// Result of comparing two values of the same type, left against right: `less` means left is
// earlier or smaller. Backed by `i8` so the values are -1, 0, 1 and can feed a sort comparator.
// Unlike `Month` and `Weekday`, zero is valid here: it means `equal`.
Ordering :: enum i8 {
	less    = -1,
	equal   = 0,
	greater = 1,
}

// Starts at 1, not 0, so the value is the month number people write: `january = 1` matches
// "2026-01-15" in ISO 8601. Zero is deliberately not a valid `Month`, so a zeroed `Local_Date`
// is detectable as invalid instead of silently meaning January.
Month :: enum u8 {
	january = 1,
	february,
	march,
	april,
	may,
	june,
	july,
	august,
	september,
	october,
	november,
	december,
}

// Starts at 1 on Monday and ends at 7 on Sunday, the ISO 8601 weekday number, so the value
// matches what ISO week dates print ("2026-W44-7" is a Sunday). Zero is deliberately not a
// valid `Weekday`, so an uninitialized value is detectable as invalid instead of silently
// meaning Monday. Weeks start on Monday; convert explicitly for Sunday-first calendars.
Weekday :: enum u8 {
	monday = 1,
	tuesday,
	wednesday,
	thursday,
	friday,
	saturday,
	sunday,
}

// ============================================================================
// types: distinct numbers
// ============================================================================

// A calendar year in the proleptic Gregorian calendar, astronomical numbering: 1 is 1 AD,
// 0 is 1 BC, -1 is 2 BC. Distinct from `Epoch_Day` and from plain counts such as `Period.years`,
// so a year cannot be passed where a day number is expected.
Year :: distinct i32

// Whole days since 1970-01-01, negative before it. Day 0 is 1970-01-01 (a Thursday).
// Distinct from `Year` and from plain day counts such as `Period.days`, so a day number
// is only produced and consumed by the conversion procs.
Epoch_Day :: distinct i64

// Whole seconds since midnight, 0 for 00:00:00 and `SECOND_OF_DAY_MAX` for 23:59:59. There
// are no leap seconds. Distinct from `Epoch_Day` and from epoch seconds, so the two halves of
// an `Instant` (which day, which second of it) cannot be swapped.
Second_Of_Day :: distinct u32

// ============================================================================
// structs: points and spans on the timeline
// ============================================================================

// A single point on the global timeline, with no time zone and no calendar attached.
// Stored as seconds since 1970-01-01T00:00:00Z (the Unix epoch), ignoring leap seconds
// (POSIX). Negative seconds are before 1970. Convert to a `Local_Date_Time` with a
// `Zone_Offset` to display it.
//
// `Instant` + `Duration` = `Instant`. Exact and zone independent.
//
// Not to be confused with:
//
// - `Duration`: how long, an exact span of seconds, like 90 seconds or 48 hours.
// - `Period`: how many calendar units, like 1 month or 2 days.
Instant :: struct {
	seconds:     i64,
	nanoseconds: u32, // Always < `NANOSECONDS_PER_SECOND`, counted forward from `seconds`.
}

// An exact amount of elapsed time, measured in seconds and nanoseconds. It knows nothing about
// months, years or DST: it is always the same length wherever and whenever it is applied.
// The difference of two `Instant`s is a `Duration`. Use it for elapsed time and timeouts.
//
// A day is not always 24 hours. Adding `Duration{seconds = 86_400}` to an `Instant` moves
// exactly 24 hours, which across a DST change lands on a different wall clock time. To keep
// the wall clock time and move the calendar date, use a `Period`.
//
// Not to be confused with:
//
// - `Instant`: when it happened, a point on the timeline like 2026-11-01T00:38:00Z.
// - `Period`: how many calendar units, like 1 month or 2 days.
Duration :: struct {
	seconds:     i64,
	nanoseconds: u32, // Always < `NANOSECONDS_PER_SECOND`, counted forward from `seconds`.
}

// An amount of calendar time in years, months and days. It has no fixed length in seconds:
// the real length depends on the date it is applied to (leap years, 28 to 31 day months).
// Use it for scheduling by the calendar (next month, tomorrow, birthday).
//
// `Local_Date` + `Period` = `Local_Date`. Calendar based, so the result depends on the date it
// starts from. Only valid with `Local_Date` and `Local_Date_Time`, never with an `Instant`.
// Adding `Period{days = 1}` to a `Local_Date_Time` keeps the wall clock time and moves the
// calendar date, where a `Duration` of 24 hours would not across a DST change.
//
// Fields are independent and may be negative, so `Period{months = 14}` is not normalized
// to 1 year 2 months. Each field is capped, see `PERIOD_YEARS_MAX` and friends.
//
// Applying a `Period` to a date is not reversible: Jan 31 plus 1 month is Feb 28, and minus
// 1 month from there is Jan 28, not Jan 31. The day is clamped to the end of the month.
//
// There is deliberately no "period between two dates". Several `Period`s reach the same date
// (Jan 31 to Feb 28 is 1 month or 28 days), and the usual rule does not round trip backwards
// or negate when the two dates swap.
//
// Not to be confused with:
//
// - `Instant`: when it happened, a point on the timeline like 2026-11-01T00:38:00Z.
// - `Duration`: how long, an exact span of seconds, like 90 seconds or 48 hours.
Period :: struct {
	years:  i32,
	months: i32,
	days:   i32,
}

// ============================================================================
// structs: zone offset and local date and time
// ============================================================================

// A fixed difference from UTC, in seconds east of it: `+05:30` is `19_800` and `-08:00` is
// `-28_800`. It is only an offset, with no rules and no DST, so a local value and an `Instant`
// convert to each other one to one. Zero is valid and is UTC. Capped at 18 hours either way,
// see `ZONE_OFFSET_SECONDS_MAX`.
Zone_Offset :: struct {
	seconds: i32,
}

// A calendar date in the proleptic Gregorian calendar, like 2026-11-01, with no time of day
// and no zone. The year runs from `YEAR_MIN` to `YEAR_MAX`. A zeroed `Local_Date` is invalid,
// because month 0 does not exist. Build one with `local_date_make` to have it checked, or write
// the struct directly and trust `local_date_is_valid` to tell you if it is real.
Local_Date :: struct {
	year:  Year,
	month: Month,
	day:   u8,
}

// A date in the ISO 8601 week calendar, like 2026-W44-7: the Sunday of week 44 of 2026. Weeks
// start on Monday, week 1 is the week that holds January 4th (so also the year's first
// Thursday), and a year has 52 or 53 weeks.
//
// `week_year` is not always the calendar year. A few days at each end of a year belong to the
// neighbouring year's weeks: 2021-01-01 is in week 53 of 2020, and 2024-12-31 is in week 1 of
// 2025. Pairing the calendar year with the week number gives dates that do not exist.
//
// These are ISO weeks only. The US convention, where weeks start on Sunday and week 1 holds
// January 1st, numbers some dates differently.
Iso_Week_Date :: struct {
	week_year: Year,
	week:      u8, // 1 to `year_iso_week_count(week_year)`.
	weekday:   Weekday,
}

// A time of day on a 24 hour clock, from 00:00:00 to 23:59:59.999999999. There is no 24:00 and
// no leap second 23:59:60. Unlike `Month` and `Weekday`, zero is valid in every field: a
// zeroed `Local_Time` is midnight.
Local_Time :: struct {
	hour:        u8,
	minute:      u8,
	second:      u8,
	nanoseconds: u32, // Always < `NANOSECONDS_PER_SECOND`.
}

// A date and a time of day together, like 2026-11-01 14:30:00, with no zone and no offset. It
// is a wall clock reading, not a moment: the same value is a different `Instant` in every
// zone. A zeroed `Local_Date_Time` is invalid, because a zeroed `Local_Date` is.
//
// Arithmetic with a `Duration` is elapsed wall clock time and knows nothing about DST. 23:00
// plus 2 hours is 01:00 the next day. Arithmetic with a `Period` moves the date and keeps the
// time of day.
Local_Date_Time :: struct {
	date: Local_Date,
	time: Local_Time,
}

// A wall clock reading together with the offset that fixes it to one real moment, like
// 2026-11-01 00:44:11 at +05:30. Unlike `Local_Date_Time`, it names a single `Instant`; unlike
// `Instant`, it remembers which offset it was written at. Use it for logs, API timestamps and
// showing one moment in the reader's offset.
//
// The same moment has many representations: 12:00 at +01:00, 11:00 at +00:00 and 06:00 at
// -05:00 are one `Instant`, so `offset_date_time_compare` calls them equal. `==` compares the
// fields instead and says they differ. Use `offset_date_time_compare` to order or match moments.
//
// The moment is not stored, only computed, so the fields cannot disagree with it. A zeroed
// `Offset_Date_Time` is invalid, because a zeroed `Local_Date` is.
//
// With a fixed offset there is no DST, so one day as a `Period` and 24 hours as a `Duration`
// land on the same value. They only differ with named zones, which this library does not have.
Offset_Date_Time :: struct {
	date_time: Local_Date_Time,
	offset:    Zone_Offset,
}

// ============================================================================
// procs: ordering
// ============================================================================

// True for `.less`, `.equal` and `.greater`. Any other value can only come from a cast.
ordering_is_valid :: #force_inline proc(ordering: Ordering) -> bool {
	return ordering >= .less && ordering <= .greater
}

// Three-way comparison of two values of the same type.
//
// Meant for integers, enums and distinct integers such as `Year`, `Month` and `u8`. They are
// fixed size, so the two tests compile to one compare and conditional selects with no branch.
// `intrinsics.type_is_ordered` also admits other types, which do not behave the same way:
//
// - strings: not fixed size, and `<` and `>` are two separate comparisons of the contents.
// - floats: NaN is neither less nor greater, so it compares as `.equal` to everything.
ordering_compare :: #force_inline proc(
	left, right: $T,
) -> Ordering where intrinsics.type_is_ordered(T) {
	if left < right {
		return .less
	}
	if left > right {
		return .greater
	}

	return .equal
}

// Chains comparisons for lexicographic order: the first ordering decides unless it is equal,
// then the second decides. For example, year then month then day is
// `ordering_then(year_order, ordering_then(month_order, day_order))`.
//
// It does not short-circuit. Odin evaluates both arguments, so every field is compared even
// when the first already differs.
//
// For integer and enum fields that is still the fast choice. With `-o:speed` the chain becomes
// loads and conditional selects with no branches, so the time does not depend on the data.
// An early return only wins when the first difference comes early and the branch is
// predictable. On unpredictable data it measured about 4 times slower (arm64, asserts off).
//
// Do not chain expensive comparisons such as strings, because each one runs in full whether
// or not it is needed.
ordering_then :: #force_inline proc(first, second: Ordering) -> Ordering {
	assert(ordering_is_valid(first))
	assert(ordering_is_valid(second))

	return second if first == .equal else first
}

// Flips `.less` and `.greater`, leaves `.equal`. Use it to turn an ascending comparison into a
// descending one, for example when sorting newest first.
ordering_reverse :: proc(ordering: Ordering) -> Ordering {
	assert(ordering_is_valid(ordering))

	// Safe because the values are exactly -1, 0 and 1.
	return Ordering(-i8(ordering))
}

// ============================================================================
// procs: month
// ============================================================================

// True for `.january` to `.december`. Zero and 13 or more can only come from a cast.
month_is_valid :: proc(month: Month) -> bool {
	return month >= .january && month <= .december
}

// Wraps around the year in both directions: `month_plus(.december, 1)` is `.january` and
// `month_plus(.january, -1)` is `.december`. Does not carry into a year, see
// `local_date_plus_months`.
month_plus :: proc(month: Month, months: i64) -> Month {
	assert(month_is_valid(month))

	// Reduce the offset first so adding it to the month cannot overflow an i64.
	month_index := (months %% 12 + i64(month) - 1) %% 12

	return Month(month_index + 1)
}

// ============================================================================
// procs: weekday
// ============================================================================

// True for `.monday` to `.sunday`. Zero and 8 or more can only come from a cast.
weekday_is_valid :: proc(weekday: Weekday) -> bool {
	return weekday >= .monday && weekday <= .sunday
}

// Wraps around the week in both directions: `weekday_plus(.sunday, 1)` is `.monday` and
// `weekday_plus(.monday, -1)` is `.sunday`.
weekday_plus :: proc(weekday: Weekday, days: i64) -> Weekday {
	assert(weekday_is_valid(weekday))

	// Reduce the offset first so adding it to the weekday cannot overflow an i64.
	weekday_index := (days %% 7 + i64(weekday) - 1) %% 7

	return Weekday(weekday_index + 1)
}

// ============================================================================
// procs: year
// ============================================================================

// True for `YEAR_MIN` to `YEAR_MAX`.
year_is_valid :: proc(year: Year) -> bool {
	return year >= YEAR_MIN && year <= YEAR_MAX
}

// The Gregorian rule: every 4th year, except every 100th, except every 400th. 1900 is not a
// leap year and 2000 is. It holds for year 0 and negative years too. The year is not range
// checked here, see `year_is_valid`.
year_is_leap :: proc(year: Year) -> bool {
	// Floor modulo (%%) keeps the rule correct for proleptic years at or before zero.
	return year %% 4 == 0 && (year %% 100 != 0 || year %% 400 == 0)
}

// 365 or 366.
year_day_count :: proc(year: Year) -> u16 {
	return 366 if year_is_leap(year) else 365
}

// The number of ISO weeks in the year, 52 or 53. It is 53 when January 1st is a Thursday, or a
// Wednesday in a leap year. 2020 and 2026 have 53 weeks, 2025 has 52.
year_iso_week_count :: proc(year: Year) -> u8 {
	assert(year_is_valid(year))

	weekday := local_date_weekday(Local_Date{year = year, month = .january, day = 1})
	if weekday == .thursday || (weekday == .wednesday && year_is_leap(year)) {
		return 53
	}

	return 52
}

// Returns `false` when the result leaves `YEAR_MIN..YEAR_MAX`. Negative years go backwards.
year_plus :: proc(year: Year, years: i64) -> (Year, bool) {
	assert(year_is_valid(year))

	// Compare against the remaining room, not the sum, so no i64 can overflow.
	if years < i64(YEAR_MIN) - i64(year) || years > i64(YEAR_MAX) - i64(year) {
		return 0, false
	}

	return year + Year(years), true
}

// ============================================================================
// procs: epoch day
// ============================================================================

// True for `EPOCH_DAY_MIN` to `EPOCH_DAY_MAX`, the days from `LOCAL_DATE_MIN` to `LOCAL_DATE_MAX`.
epoch_day_is_valid :: proc(epoch_day: Epoch_Day) -> bool {
	return epoch_day >= EPOCH_DAY_MIN && epoch_day <= EPOCH_DAY_MAX
}

// Returns `false` when the result leaves `EPOCH_DAY_MIN..EPOCH_DAY_MAX`. Negative days go
// backwards.
epoch_day_plus :: proc(epoch_day: Epoch_Day, days: i64) -> (Epoch_Day, bool) {
	assert(epoch_day_is_valid(epoch_day))

	// Compare against the remaining room, not the sum, so no i64 can overflow.
	if days < i64(EPOCH_DAY_MIN) - i64(epoch_day) || days > i64(EPOCH_DAY_MAX) - i64(epoch_day) {
		return 0, false
	}

	return epoch_day + Epoch_Day(days), true
}

// Number of days from `from` to `to`: positive when `to` is later, negative when earlier.
epoch_day_between :: proc(from, to: Epoch_Day) -> i64 {
	assert(epoch_day_is_valid(from))
	assert(epoch_day_is_valid(to))

	return i64(to) - i64(from)
}

// The weekday of a day number, without building a date. Day 0, 1970-01-01, was a Thursday.
epoch_day_weekday :: proc(epoch_day: Epoch_Day) -> Weekday {
	assert(epoch_day_is_valid(epoch_day))

	// 1970-01-01 (epoch day 0) was a Thursday, which is 4 in ISO numbering.
	weekday := Weekday((i64(epoch_day) + 3) %% 7 + 1)
	assert(weekday_is_valid(weekday))

	return weekday
}

// ============================================================================
// procs: calendar helpers
// ============================================================================

// The length of the month, 28 to 31. February has 29 days in a leap year. Asserts that the year
// and month are valid.
days_in_month :: proc(year: Year, month: Month) -> u8 {
	assert(year_is_valid(year))
	assert(month_is_valid(month))

	switch month {
	case .february:
		return 29 if year_is_leap(year) else 28
	case .april, .june, .september, .november:
		return 30
	case .january, .march, .may, .july, .august, .october, .december:
		return 31
	}
	unreachable()
}

// ============================================================================
// procs: local date
// ============================================================================

// True when the year is in range, the month exists, and the day is between 1 and the length of
// that month. 2026-02-29 is invalid, and so is a zeroed `Local_Date`.
local_date_is_valid :: proc(date: Local_Date) -> bool {
	if !year_is_valid(date.year) {
		return false
	}
	if !month_is_valid(date.month) {
		return false
	}

	return date.day >= 1 && date.day <= days_in_month(date.year, date.month)
}

// The checked way to build a `Local_Date`. Returns `false` when the fields are not a real date.
local_date_make :: proc(year: Year, month: Month, day: u8) -> (Local_Date, bool) {
	date := Local_Date {
		year  = year,
		month = month,
		day   = day,
	}
	if !local_date_is_valid(date) {
		return {}, false
	}

	return date, true
}

// Days since 1970-01-01, negative before it. Howard Hinnant's `days_from_civil`.
local_date_to_epoch_day :: proc(date: Local_Date) -> Epoch_Day {
	assert(local_date_is_valid(date))

	month := i64(date.month)
	// The algorithm counts years from March so the leap day is the last day of the year.
	year := i64(date.year) - (1 if month <= 2 else 0)
	era := (year if year >= 0 else year - 399) / 400
	year_of_era := year - era * 400
	month_from_march := month + (-3 if month > 2 else 9)
	day_of_year := (153 * month_from_march + 2) / 5 + i64(date.day) - 1
	day_of_era := year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year

	return Epoch_Day(era * 146_097 + day_of_era - 719_468)
}

// Inverse of `local_date_to_epoch_day`. Howard Hinnant's `civil_from_days`.
// Returns `false` when `epoch_day` is outside `EPOCH_DAY_MIN..EPOCH_DAY_MAX`, which is exactly
// when the date would fall outside `YEAR_MIN..YEAR_MAX`.
local_date_from_epoch_day :: proc(epoch_day: Epoch_Day) -> (Local_Date, bool) {
	if !epoch_day_is_valid(epoch_day) {
		return {}, false
	}

	shifted := i64(epoch_day) + 719_468
	era := (shifted if shifted >= 0 else shifted - 146_096) / 146_097
	day_of_era := shifted - era * 146_097
	year_of_era :=
		(day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365
	day_of_year := day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
	month_from_march := (5 * day_of_year + 2) / 153
	day := day_of_year - (153 * month_from_march + 2) / 5 + 1
	month := month_from_march + (3 if month_from_march < 10 else -9)
	year := year_of_era + era * 400 + (1 if month <= 2 else 0)

	date := Local_Date {
		year  = Year(year),
		month = Month(month),
		day   = u8(day),
	}
	assert(local_date_is_valid(date))

	return date, true
}

// The day of the week. 2026-11-01 is a Sunday.
local_date_weekday :: proc(date: Local_Date) -> Weekday {
	return epoch_day_weekday(local_date_to_epoch_day(date))
}

// 1 for January 1st, 365 or 366 for December 31st.
local_date_day_of_year :: proc(date: Local_Date) -> u16 {
	january_first := Local_Date {
		year  = date.year,
		month = .january,
		day   = 1,
	}
	day_of_year :=
		epoch_day_between(local_date_to_epoch_day(january_first), local_date_to_epoch_day(date)) +
		1
	assert(day_of_year >= 1 && day_of_year <= i64(year_day_count(date.year)))

	return u16(day_of_year)
}

// Orders by year, then month, then day. Asserts that both dates are valid.
local_date_compare :: proc(left, right: Local_Date) -> Ordering {
	assert(local_date_is_valid(left))
	assert(local_date_is_valid(right))

	return ordering_then(
		ordering_compare(left.year, right.year),
		ordering_then(
			ordering_compare(left.month, right.month),
			ordering_compare(left.day, right.day),
		),
	)
}

// Moves forward by `days`, or backward when negative. Returns `false` when the result leaves
// `YEAR_MIN..YEAR_MAX`.
local_date_plus_days :: proc(date: Local_Date, days: i64) -> (Local_Date, bool) {
	assert(local_date_is_valid(date))

	epoch_day, ok := epoch_day_plus(local_date_to_epoch_day(date), days)
	if !ok {
		return {}, false
	}

	return local_date_from_epoch_day(epoch_day)
}

// Keeps the day of month, clamped to the last day of the target month:
// Jan 31 plus 1 month is Feb 28, or Feb 29 in a leap year.
// Returns `false` when the result leaves `YEAR_MIN..YEAR_MAX`.
local_date_plus_months :: proc(date: Local_Date, months: i64) -> (Local_Date, bool) {
	assert(local_date_is_valid(date))

	// An offset beyond the whole supported calendar always fails. Rejecting it first keeps
	// the sum below inside an i64.
	months_limit := i64(PERIOD_MONTHS_MAX) + 11
	if months < -months_limit || months > months_limit {
		return {}, false
	}

	month_index := i64(date.year) * 12 + i64(date.month) - 1 + months
	year := (month_index - month_index %% 12) / 12
	if year < i64(YEAR_MIN) || year > i64(YEAR_MAX) {
		return {}, false
	}

	month := Month(month_index %% 12 + 1)
	assert(month_is_valid(month))

	return Local_Date {
			year = Year(year),
			month = month,
			day = min(date.day, days_in_month(Year(year), month)),
		},
		true
}

// Keeps month and day, clamping Feb 29 to Feb 28 when the target year is not a leap year.
// Returns `false` when the result leaves `YEAR_MIN..YEAR_MAX`.
local_date_plus_years :: proc(date: Local_Date, years: i64) -> (Local_Date, bool) {
	assert(local_date_is_valid(date))

	year, ok := year_plus(date.year, years)
	if !ok {
		return {}, false
	}

	return Local_Date {
			year = year,
			month = date.month,
			day = min(date.day, days_in_month(year, date.month)),
		},
		true
}

// Years and months are applied first, as one number of months, and days after. The order
// matters: Jan 30 plus `{months = 1, days = 2}` is Feb 28 plus 2 days, which is Mar 2.
// Returns `false` when the date after the months step, or the final date, is out of range.
local_date_plus_period :: proc(date: Local_Date, period: Period) -> (Local_Date, bool) {
	assert(local_date_is_valid(date))
	assert(period_is_valid(period))

	months := i64(period.years) * 12 + i64(period.months)
	shifted, ok := local_date_plus_months(date, months)
	if !ok {
		return {}, false
	}

	return local_date_plus_days(shifted, i64(period.days))
}

// Number of days from `from` to `to`: positive when `to` is later, negative when earlier.
local_date_days_between :: proc(from, to: Local_Date) -> i64 {
	assert(local_date_is_valid(from))
	assert(local_date_is_valid(to))

	return epoch_day_between(local_date_to_epoch_day(from), local_date_to_epoch_day(to))
}

// True when `left` is earlier than `right`. Equal dates give `false`.
local_date_is_before :: proc(left, right: Local_Date) -> bool {
	return local_date_compare(left, right) == .less
}

// True when `left` is later than `right`. Equal dates give `false`.
local_date_is_after :: proc(left, right: Local_Date) -> bool {
	return local_date_compare(left, right) == .greater
}

// The earlier of the two dates. Equal dates return `left`.
local_date_earlier :: proc(left, right: Local_Date) -> Local_Date {
	return right if local_date_is_before(right, left) else left
}

// The later of the two dates. Equal dates return `left`.
local_date_later :: proc(left, right: Local_Date) -> Local_Date {
	return right if local_date_is_after(right, left) else left
}

// The 1st of the same month. It cannot fail, because it stays in the same month and year.
local_date_first_day_of_month :: proc(date: Local_Date) -> Local_Date {
	assert(local_date_is_valid(date))

	return Local_Date{year = date.year, month = date.month, day = 1}
}

// The last day of the same month, 28 to 31. It cannot fail, as above.
local_date_last_day_of_month :: proc(date: Local_Date) -> Local_Date {
	assert(local_date_is_valid(date))

	return Local_Date {
		year = date.year,
		month = date.month,
		day = days_in_month(date.year, date.month),
	}
}

// January 1st of the same year. It cannot fail, because it stays in the same year.
local_date_first_day_of_year :: proc(date: Local_Date) -> Local_Date {
	assert(local_date_is_valid(date))

	return Local_Date{year = date.year, month = .january, day = 1}
}

// December 31st of the same year. It cannot fail, as above.
local_date_last_day_of_year :: proc(date: Local_Date) -> Local_Date {
	assert(local_date_is_valid(date))

	return Local_Date{year = date.year, month = .december, day = 31}
}

// Inverse of `local_date_day_of_year`: day 1 is January 1st, day 365 or 366 is December 31st.
// Returns `false` when the year is out of range or the day is 0 or past `year_day_count`.
local_date_from_year_day :: proc(year: Year, day_of_year: u16) -> (Local_Date, bool) {
	if !year_is_valid(year) || day_of_year < 1 || day_of_year > year_day_count(year) {
		return {}, false
	}

	january_first := Local_Date {
		year  = year,
		month = .january,
		day   = 1,
	}

	return local_date_plus_days(january_first, i64(day_of_year) - 1)
}

// ============================================================================
// procs: iso week date
// ============================================================================

// True when the week year is in range, the week exists in that year (week 53 only in a
// 53 week year), and the day it names is a supported date. The last two days of `YEAR_MAX`'s
// final week, Saturday and Sunday, fall in the next calendar year and are not valid.
iso_week_date_is_valid :: proc(iso: Iso_Week_Date) -> bool {
	_, ok := local_date_from_iso_week_date(iso)

	return ok
}

// The ISO week, week year and weekday of the date. It cannot fail: the week belongs to the
// year of its Thursday, and the supported range ends on a Friday and starts on a Monday, so
// the Thursday of every supported date is a supported date too.
local_date_to_iso_week_date :: proc(date: Local_Date) -> Iso_Week_Date {
	assert(local_date_is_valid(date))

	weekday := local_date_weekday(date)
	thursday, ok := local_date_plus_days(date, i64(Weekday.thursday) - i64(weekday))
	assert(ok)

	iso := Iso_Week_Date {
		week_year = thursday.year,
		week      = u8((local_date_day_of_year(thursday) - 1) / 7 + 1),
		weekday   = weekday,
	}
	assert(iso_week_date_is_valid(iso))

	return iso
}

// Inverse of `local_date_to_iso_week_date`. Returns `false` when `iso` is not valid, see
// `iso_week_date_is_valid`: week 0, week 53 of a 52 week year, a week year out of range.
local_date_from_iso_week_date :: proc(iso: Iso_Week_Date) -> (Local_Date, bool) {
	if !year_is_valid(iso.week_year) || !weekday_is_valid(iso.weekday) {
		return {}, false
	}
	if iso.week < 1 || iso.week > year_iso_week_count(iso.week_year) {
		return {}, false
	}

	// January 4th is always in week 1. From its weekday, step to the requested week and day.
	january_fourth := Local_Date {
		year  = iso.week_year,
		month = .january,
		day   = 4,
	}
	days := i64(iso.week - 1) * 7 + i64(iso.weekday) - i64(local_date_weekday(january_fourth))

	return local_date_plus_days(january_fourth, days)
}

// ============================================================================
// procs: local time
// ============================================================================

// True for 00:00:00 to 23:59:59.999999999. Hour 24 and second 60 are invalid. A zeroed
// `Local_Time` is valid and is midnight.
local_time_is_valid :: proc(time: Local_Time) -> bool {
	if time.hour >= HOURS_PER_DAY || time.minute >= 60 || time.second >= 60 {
		return false
	}

	return time.nanoseconds < NANOSECONDS_PER_SECOND
}

// The checked way to build a `Local_Time`. Returns `false` when a field is out of range.
local_time_make :: proc(hour, minute, second: u8, nanoseconds: u32) -> (Local_Time, bool) {
	time := Local_Time {
		hour        = hour,
		minute      = minute,
		second      = second,
		nanoseconds = nanoseconds,
	}
	if !local_time_is_valid(time) {
		return {}, false
	}

	return time, true
}

// Orders by hour, then minute, then second, then nanoseconds. Asserts that both are valid.
local_time_compare :: proc(left, right: Local_Time) -> Ordering {
	assert(local_time_is_valid(left))
	assert(local_time_is_valid(right))

	return ordering_then(
		ordering_compare(left.hour, right.hour),
		ordering_then(
			ordering_compare(left.minute, right.minute),
			ordering_then(
				ordering_compare(left.second, right.second),
				ordering_compare(left.nanoseconds, right.nanoseconds),
			),
		),
	)
}

// True when `left` is earlier in the day than `right`. Equal times give `false`.
local_time_is_before :: proc(left, right: Local_Time) -> bool {
	return local_time_compare(left, right) == .less
}

// True when `left` is later in the day than `right`. Equal times give `false`.
local_time_is_after :: proc(left, right: Local_Time) -> bool {
	return local_time_compare(left, right) == .greater
}

// The earlier of the two times. Equal times return `left`.
local_time_earlier :: proc(left, right: Local_Time) -> Local_Time {
	return right if local_time_is_before(right, left) else left
}

// The later of the two times. Equal times return `left`.
local_time_later :: proc(left, right: Local_Time) -> Local_Time {
	return right if local_time_is_after(right, left) else left
}

// Whole seconds since midnight. The nanoseconds are dropped, so pair this with
// `time.nanoseconds` to keep the full value.
local_time_to_second_of_day :: proc(time: Local_Time) -> Second_Of_Day {
	assert(local_time_is_valid(time))

	return Second_Of_Day(
		u32(time.hour) * SECONDS_PER_HOUR +
		u32(time.minute) * SECONDS_PER_MINUTE +
		u32(time.second),
	)
}

// Inverse of `local_time_to_second_of_day`. Returns `false` when the second is past
// `SECOND_OF_DAY_MAX` or the nanoseconds are not below `NANOSECONDS_PER_SECOND`.
local_time_from_second_of_day :: proc(
	second_of_day: Second_Of_Day,
	nanoseconds: u32,
) -> (
	Local_Time,
	bool,
) {
	if second_of_day > SECOND_OF_DAY_MAX || nanoseconds >= NANOSECONDS_PER_SECOND {
		return {}, false
	}

	seconds := u32(second_of_day)
	time := Local_Time {
		hour        = u8(seconds / SECONDS_PER_HOUR),
		minute      = u8(seconds % SECONDS_PER_HOUR / SECONDS_PER_MINUTE),
		second      = u8(seconds % SECONDS_PER_MINUTE),
		nanoseconds = nanoseconds,
	}
	assert(local_time_is_valid(time))

	return time, true
}

// Moves the time by the duration and wraps around midnight. The second result is the whole
// days passed, rounded down: 23:00 plus 2 hours is 01:00 with 1, and 01:00 minus 2 hours is
// 23:00 with -1. `Local_Date_Time` adds it to its date. It never fails, because a `Duration`
// holds at most about 6.5e13 seconds, which is far inside an `i64` of days.
local_time_plus_duration :: proc(time: Local_Time, duration: Duration) -> (Local_Time, i64) {
	assert(local_time_is_valid(time))
	assert(duration_is_valid(duration))

	// Seconds of the day (below 86_400) plus a Duration cannot overflow an i64, and both
	// nanoseconds are below 1e9, so their sum fits a u32.
	total_seconds := i64(local_time_to_second_of_day(time)) + duration.seconds
	total_nanoseconds := time.nanoseconds + duration.nanoseconds
	if total_nanoseconds >= NANOSECONDS_PER_SECOND {
		total_nanoseconds -= NANOSECONDS_PER_SECOND
		total_seconds += 1
	}

	second_of_day := total_seconds %% SECONDS_PER_DAY
	day_carry := (total_seconds - second_of_day) / SECONDS_PER_DAY
	result, ok := local_time_from_second_of_day(Second_Of_Day(second_of_day), total_nanoseconds)
	assert(ok)

	return result, day_carry
}

// The `Duration` from `from` to `to` within one day: positive when `to` is later, negative when
// earlier. Always representable, it is never longer than a day.
local_time_between :: proc(from, to: Local_Time) -> Duration {
	assert(local_time_is_valid(from))
	assert(local_time_is_valid(to))

	duration := Duration {
		seconds = i64(local_time_to_second_of_day(to)) - i64(local_time_to_second_of_day(from)),
	}
	if to.nanoseconds >= from.nanoseconds {
		duration.nanoseconds = to.nanoseconds - from.nanoseconds
	} else {
		// Borrow one second so the nanoseconds keep counting forward.
		duration.seconds -= 1
		duration.nanoseconds = to.nanoseconds + NANOSECONDS_PER_SECOND - from.nanoseconds
	}
	assert(duration_is_valid(duration))

	return duration
}

// ============================================================================
// procs: duration
// ============================================================================

// True when `nanoseconds` is below one second and `seconds` is within
// `DURATION_SECONDS_MIN..DURATION_SECONDS_MAX`. A negative duration keeps `nanoseconds`
// positive and borrows from `seconds`: minus half a second is `{-1, 500_000_000}`.
duration_is_valid :: proc(duration: Duration) -> bool {
	if duration.nanoseconds >= NANOSECONDS_PER_SECOND {
		return false
	}

	return duration.seconds >= DURATION_SECONDS_MIN && duration.seconds <= DURATION_SECONDS_MAX
}

// The checked way to build a `Duration`. Returns `false` when it is not valid.
duration_make :: proc(seconds: i64, nanoseconds: u32) -> (Duration, bool) {
	duration := Duration {
		seconds     = seconds,
		nanoseconds = nanoseconds,
	}
	if !duration_is_valid(duration) {
		return {}, false
	}

	return duration, true
}

// The unit constructors return `false` when the amount is outside the `Duration` range, which is
// about 2 million years. They are exact: an hour is always 3600 seconds, with no calendar.
duration_from_hours :: proc(hours: i64) -> (Duration, bool) {
	if hours < DURATION_SECONDS_MIN / SECONDS_PER_HOUR ||
	   hours > DURATION_SECONDS_MAX / SECONDS_PER_HOUR {
		return {}, false
	}

	return duration_make(hours * SECONDS_PER_HOUR, 0)
}

// Exactly 60 seconds per minute. Returns `false` outside the `Duration` range.
duration_from_minutes :: proc(minutes: i64) -> (Duration, bool) {
	if minutes < DURATION_SECONDS_MIN / SECONDS_PER_MINUTE ||
	   minutes > DURATION_SECONDS_MAX / SECONDS_PER_MINUTE {
		return {}, false
	}

	return duration_make(minutes * SECONDS_PER_MINUTE, 0)
}

// A whole number of seconds with no fraction. Returns `false` outside the `Duration` range.
duration_from_seconds :: proc(seconds: i64) -> (Duration, bool) {
	return duration_make(seconds, 0)
}

// Negative milliseconds borrow a second so the nanoseconds keep counting forward:
// -1 millisecond is `{-1, 999_000_000}`.
duration_from_milliseconds :: proc(milliseconds: i64) -> (Duration, bool) {
	seconds := milliseconds / MILLISECONDS_PER_SECOND
	remainder := milliseconds % MILLISECONDS_PER_SECOND
	if remainder < 0 {
		seconds -= 1
		remainder += MILLISECONDS_PER_SECOND
	}

	return duration_make(seconds, u32(remainder) * NANOSECONDS_PER_MILLISECOND)
}

// Returns `false` when the result is out of range: the most negative seconds have no positive
// counterpart. Half a second backwards is `{-1, 500_000_000}`, and its negation is
// `{0, 500_000_000}`.
duration_negate :: proc(duration: Duration) -> (Duration, bool) {
	assert(duration_is_valid(duration))

	negated := Duration {
		seconds = -duration.seconds,
	}
	if duration.nanoseconds != 0 {
		// Borrow one second so the nanoseconds keep counting forward.
		negated.seconds -= 1
		negated.nanoseconds = NANOSECONDS_PER_SECOND - duration.nanoseconds
	}
	if !duration_is_valid(negated) {
		return {}, false
	}

	return negated, true
}

// Orders by `seconds`, then `nanoseconds`, so a negative duration is smaller. Just under zero,
// `{-1, 999_999_999}`, is less than zero.
duration_compare :: proc(left, right: Duration) -> Ordering {
	assert(duration_is_valid(left))
	assert(duration_is_valid(right))

	return ordering_then(
		ordering_compare(left.seconds, right.seconds),
		ordering_compare(left.nanoseconds, right.nanoseconds),
	)
}

// Returns `false` when the sum is out of range.
duration_plus :: proc(left, right: Duration) -> (Duration, bool) {
	assert(duration_is_valid(left))
	assert(duration_is_valid(right))

	// Both seconds are bounded by about 6.5e13, so the sum cannot overflow an i64, and both
	// nanoseconds are below 1e9, so their sum fits a u32.
	sum := Duration {
		seconds     = left.seconds + right.seconds,
		nanoseconds = left.nanoseconds + right.nanoseconds,
	}
	if sum.nanoseconds >= NANOSECONDS_PER_SECOND {
		sum.nanoseconds -= NANOSECONDS_PER_SECOND
		sum.seconds += 1
	}
	if !duration_is_valid(sum) {
		return {}, false
	}

	return sum, true
}

// ============================================================================
// procs: instant
// ============================================================================

// True when `nanoseconds` is below one second and `seconds` is within
// `INSTANT_SECONDS_MIN..INSTANT_SECONDS_MAX`.
instant_is_valid :: proc(instant: Instant) -> bool {
	if instant.nanoseconds >= NANOSECONDS_PER_SECOND {
		return false
	}

	return instant.seconds >= INSTANT_SECONDS_MIN && instant.seconds <= INSTANT_SECONDS_MAX
}

// The checked way to build an `Instant`. Returns `false` when it is not valid.
instant_make :: proc(seconds: i64, nanoseconds: u32) -> (Instant, bool) {
	instant := Instant {
		seconds     = seconds,
		nanoseconds = nanoseconds,
	}
	if !instant_is_valid(instant) {
		return {}, false
	}

	return instant, true
}

// Orders by `seconds`, then `nanoseconds`, so an earlier moment is less. Just before the epoch,
// `{-1, 999_999_999}`, is earlier than the epoch.
instant_compare :: proc(left, right: Instant) -> Ordering {
	assert(instant_is_valid(left))
	assert(instant_is_valid(right))

	return ordering_then(
		ordering_compare(left.seconds, right.seconds),
		ordering_compare(left.nanoseconds, right.nanoseconds),
	)
}

// True when `left` is an earlier moment than `right`. The same moment gives `false`.
instant_is_before :: proc(left, right: Instant) -> bool {
	return instant_compare(left, right) == .less
}

// True when `left` is a later moment than `right`. The same moment gives `false`.
instant_is_after :: proc(left, right: Instant) -> bool {
	return instant_compare(left, right) == .greater
}

// Moves the instant forward by the duration, or backward when the duration is negative.
// Returns `false` when the result leaves `INSTANT_SECONDS_MIN..INSTANT_SECONDS_MAX`.
// Subtracting is adding the `duration_negate` of it.
instant_plus :: proc(instant: Instant, duration: Duration) -> (Instant, bool) {
	assert(instant_is_valid(instant))
	assert(duration_is_valid(duration))

	// Both seconds are bounded by about 6e13, so the sum cannot overflow an i64, and both
	// nanoseconds are below 1e9, so their sum fits a u32.
	result := Instant {
		seconds     = instant.seconds + duration.seconds,
		nanoseconds = instant.nanoseconds + duration.nanoseconds,
	}
	if result.nanoseconds >= NANOSECONDS_PER_SECOND {
		result.nanoseconds -= NANOSECONDS_PER_SECOND
		result.seconds += 1
	}
	if !instant_is_valid(result) {
		return {}, false
	}

	return result, true
}

// The `Duration` that moves `from` to `to`: positive when `to` is later, negative when earlier.
// Always representable, because `DURATION_SECONDS_MIN..DURATION_SECONDS_MAX` is sized for it.
instant_between :: proc(from, to: Instant) -> Duration {
	assert(instant_is_valid(from))
	assert(instant_is_valid(to))

	duration := Duration {
		seconds = to.seconds - from.seconds,
	}
	if to.nanoseconds >= from.nanoseconds {
		duration.nanoseconds = to.nanoseconds - from.nanoseconds
	} else {
		// Borrow one second so the nanoseconds keep counting forward.
		duration.seconds -= 1
		duration.nanoseconds = to.nanoseconds + NANOSECONDS_PER_SECOND - from.nanoseconds
	}
	assert(duration_is_valid(duration))

	return duration
}

// ============================================================================
// procs: period
// ============================================================================

// True when each field is within its cap in either direction: `PERIOD_YEARS_MAX`,
// `PERIOD_MONTHS_MAX` and `PERIOD_DAYS_MAX`.
period_is_valid :: proc(period: Period) -> bool {
	// Explicit ranges, not abs(): abs(min(i32)) overflows and would pass a <= check.
	if period.years < -PERIOD_YEARS_MAX || period.years > PERIOD_YEARS_MAX {
		return false
	}
	if period.months < -PERIOD_MONTHS_MAX || period.months > PERIOD_MONTHS_MAX {
		return false
	}

	return period.days >= -PERIOD_DAYS_MAX && period.days <= PERIOD_DAYS_MAX
}

// The checked way to build a `Period`. Returns `false` when a field passes its cap.
period_make :: proc(years, months, days: i32) -> (Period, bool) {
	period := Period {
		years  = years,
		months = months,
		days   = days,
	}
	if !period_is_valid(period) {
		return {}, false
	}

	return period, true
}

// True when all three fields are zero. Fields do not cancel each other, so
// `{years = 1, months = -12}` is not zero.
period_is_zero :: proc(period: Period) -> bool {
	assert(period_is_valid(period))

	return period == {}
}

// Always representable, because every cap is symmetric.
period_negate :: proc(period: Period) -> Period {
	assert(period_is_valid(period))

	return Period{years = -period.years, months = -period.months, days = -period.days}
}

// Adds field by field. Returns `false` when a field passes its cap.
period_plus :: proc(left, right: Period) -> (Period, bool) {
	assert(period_is_valid(left))
	assert(period_is_valid(right))

	// Each field is capped well below 2^30, so the sums cannot overflow an i32.
	return period_make(
		left.years + right.years,
		left.months + right.months,
		left.days + right.days,
	)
}

// Folds whole years out of the months: 14 months becomes 1 year 2 months. Years and months
// then share a sign. Days are left alone, because a month has no fixed number of days.
// Returns `false` when the folded years pass `PERIOD_YEARS_MAX`.
period_normalized :: proc(period: Period) -> (Period, bool) {
	assert(period_is_valid(period))

	total_months := i64(period.years) * 12 + i64(period.months)

	return period_make(i32(total_months / 12), i32(total_months % 12), period.days)
}

// ============================================================================
// procs: local date time
// ============================================================================

// True when both the date and the time are valid. A zeroed value is invalid.
local_date_time_is_valid :: proc(date_time: Local_Date_Time) -> bool {
	return local_date_is_valid(date_time.date) && local_time_is_valid(date_time.time)
}

// The checked way to build a `Local_Date_Time`. Returns `false` when either part is invalid.
local_date_time_make :: proc(date: Local_Date, time: Local_Time) -> (Local_Date_Time, bool) {
	date_time := Local_Date_Time {
		date = date,
		time = time,
	}
	if !local_date_time_is_valid(date_time) {
		return {}, false
	}

	return date_time, true
}

// The start of the day: 00:00:00 on `date`.
local_date_time_midnight_of :: proc(date: Local_Date) -> Local_Date_Time {
	assert(local_date_is_valid(date))

	return Local_Date_Time{date = date, time = LOCAL_TIME_MIDNIGHT}
}

// The date decides first, then the time of day: 2026-01-02 00:00 is later than 2026-01-01 23:59.
local_date_time_compare :: proc(left, right: Local_Date_Time) -> Ordering {
	assert(local_date_time_is_valid(left))
	assert(local_date_time_is_valid(right))

	return ordering_then(
		local_date_compare(left.date, right.date),
		local_time_compare(left.time, right.time),
	)
}

// True when `left` is earlier than `right`, the date first and then the time of day.
local_date_time_is_before :: proc(left, right: Local_Date_Time) -> bool {
	return local_date_time_compare(left, right) == .less
}

// True when `left` is later than `right`, the date first and then the time of day.
local_date_time_is_after :: proc(left, right: Local_Date_Time) -> bool {
	return local_date_time_compare(left, right) == .greater
}

// The earlier of the two. Equal values return `left`.
local_date_time_earlier :: proc(left, right: Local_Date_Time) -> Local_Date_Time {
	return right if local_date_time_is_before(right, left) else left
}

// The later of the two. Equal values return `left`.
local_date_time_later :: proc(left, right: Local_Date_Time) -> Local_Date_Time {
	return right if local_date_time_is_after(right, left) else left
}

// Moves forward by the duration, or backward when it is negative, as plain elapsed wall clock
// time: the time of day wraps around midnight and carries into the date. Subtracting is adding
// the `duration_negate` of it. Returns `false` when the date leaves `YEAR_MIN..YEAR_MAX`.
local_date_time_plus_duration :: proc(
	date_time: Local_Date_Time,
	duration: Duration,
) -> (
	Local_Date_Time,
	bool,
) {
	assert(local_date_time_is_valid(date_time))
	assert(duration_is_valid(duration))

	time, day_carry := local_time_plus_duration(date_time.time, duration)
	date, ok := local_date_plus_days(date_time.date, day_carry)
	if !ok {
		return {}, false
	}

	return Local_Date_Time{date = date, time = time}, true
}

// The `Duration` that moves `from` to `to`: positive when `to` is later, negative when
// earlier. Always representable, because the widest span is exactly the `Duration` range.
local_date_time_between :: proc(from, to: Local_Date_Time) -> Duration {
	assert(local_date_time_is_valid(from))
	assert(local_date_time_is_valid(to))

	// Whole days go through the seconds directly, because the time of day can pull the total
	// below the day count: 01-01 23:00 to 01-02 01:00 is 1 day minus 22 hours.
	days := local_date_days_between(from.date, to.date)
	time_difference := local_time_between(from.time, to.time)

	duration := Duration {
		seconds     = days * SECONDS_PER_DAY + time_difference.seconds,
		nanoseconds = time_difference.nanoseconds,
	}
	assert(duration_is_valid(duration))

	return duration
}

// Applies the period to the date and keeps the time of day, so `Period{days = 1}` moves to the
// same clock time on the next date. Years and months clamp the day as `local_date_plus_period`
// does. Returns `false` when the date leaves `YEAR_MIN..YEAR_MAX`.
local_date_time_plus_period :: proc(
	date_time: Local_Date_Time,
	period: Period,
) -> (
	Local_Date_Time,
	bool,
) {
	assert(local_date_time_is_valid(date_time))
	assert(period_is_valid(period))

	date, ok := local_date_plus_period(date_time.date, period)
	if !ok {
		return {}, false
	}

	return Local_Date_Time{date = date, time = date_time.time}, true
}

// ============================================================================
// procs: zone offset
// ============================================================================

// True from -18:00 to +18:00, both included. Zero is UTC.
zone_offset_is_valid :: proc(offset: Zone_Offset) -> bool {
	return offset.seconds >= -ZONE_OFFSET_SECONDS_MAX && offset.seconds <= ZONE_OFFSET_SECONDS_MAX
}

// The checked way to build a `Zone_Offset` from seconds. For the `+05:30` style, see
// `zone_offset_make_hours_minutes`.
zone_offset_make :: proc(seconds: i32) -> (Zone_Offset, bool) {
	offset := Zone_Offset {
		seconds = seconds,
	}
	if !zone_offset_is_valid(offset) {
		return {}, false
	}

	return offset, true
}

// Builds an offset from the parts of `+05:30`, which is `(5, 30)`. West of UTC both parts are
// negative: `-05:30` is `(-5, -30)`. Mixed signs are rejected, because `(-5, 30)` would
// silently mean `-04:30`. Minutes must be below 60.
zone_offset_make_hours_minutes :: proc(hours, minutes: i32) -> (Zone_Offset, bool) {
	if (hours > 0 && minutes < 0) || (hours < 0 && minutes > 0) {
		return {}, false
	}
	if minutes <= -60 || minutes >= 60 {
		return {}, false
	}

	// Computed in an i64 so a huge `hours` cannot overflow before the range check.
	seconds := i64(hours) * SECONDS_PER_HOUR + i64(minutes) * SECONDS_PER_MINUTE
	if seconds < -ZONE_OFFSET_SECONDS_MAX || seconds > ZONE_OFFSET_SECONDS_MAX {
		return {}, false
	}

	return zone_offset_make(i32(seconds))
}

// Offsets further east of UTC are greater.
zone_offset_compare :: proc(left, right: Zone_Offset) -> Ordering {
	assert(zone_offset_is_valid(left))
	assert(zone_offset_is_valid(right))

	return ordering_compare(left.seconds, right.seconds)
}

// Always representable, because the cap is symmetric.
zone_offset_negate :: proc(offset: Zone_Offset) -> Zone_Offset {
	assert(zone_offset_is_valid(offset))

	return Zone_Offset{seconds = -offset.seconds}
}

// ============================================================================
// procs: instant with an offset
// ============================================================================

// The wall clock reading at `offset` for this moment. The nanoseconds carry over unchanged.
// Returns `false` for the first or last few hours of the `Instant` range, where the local
// date would pass `YEAR_MIN` or `YEAR_MAX`.
instant_to_local_date_time :: proc(
	instant: Instant,
	offset: Zone_Offset,
) -> (
	Local_Date_Time,
	bool,
) {
	assert(instant_is_valid(instant))
	assert(zone_offset_is_valid(offset))

	// Floor division, so instants before 1970 land on the right day and second.
	local_seconds := instant.seconds + i64(offset.seconds)
	second_of_day := local_seconds %% SECONDS_PER_DAY
	epoch_day := (local_seconds - second_of_day) / SECONDS_PER_DAY

	date, date_ok := local_date_from_epoch_day(Epoch_Day(epoch_day))
	if !date_ok {
		return {}, false
	}
	time, time_ok := local_time_from_second_of_day(
		Second_Of_Day(second_of_day),
		instant.nanoseconds,
	)
	assert(time_ok)

	return Local_Date_Time{date = date, time = time}, true
}

// The moment at which a wall clock at `offset` reads `date_time`. Inverse of
// `instant_to_local_date_time`. Returns `false` when that moment is outside the `Instant`
// range, which can only happen within a few hours of its ends.
local_date_time_to_instant :: proc(
	date_time: Local_Date_Time,
	offset: Zone_Offset,
) -> (
	Instant,
	bool,
) {
	assert(local_date_time_is_valid(date_time))
	assert(zone_offset_is_valid(offset))

	local_seconds :=
		i64(local_date_to_epoch_day(date_time.date)) * SECONDS_PER_DAY +
		i64(local_time_to_second_of_day(date_time.time))

	instant := Instant {
		seconds     = local_seconds - i64(offset.seconds),
		nanoseconds = date_time.time.nanoseconds,
	}
	if !instant_is_valid(instant) {
		return {}, false
	}

	return instant, true
}

// The calendar date at `offset` for this moment. The same moment is on different dates in
// different zones. Returns `false` in the same cases as `instant_to_local_date_time`.
local_date_from_instant :: proc(instant: Instant, offset: Zone_Offset) -> (Local_Date, bool) {
	date_time, ok := instant_to_local_date_time(instant, offset)

	return date_time.date, ok
}

// ============================================================================
// procs: offset date time
// ============================================================================

// Both parts must be valid and the moment they name must lie inside the `Instant` range. The
// range check is what makes `offset_date_time_to_instant` total.
offset_date_time_is_valid :: proc(value: Offset_Date_Time) -> bool {
	if !local_date_time_is_valid(value.date_time) || !zone_offset_is_valid(value.offset) {
		return false
	}
	_, in_range := local_date_time_to_instant(value.date_time, value.offset)

	return in_range
}

// The checked way to build an `Offset_Date_Time`. Returns `false` when either part is invalid or
// the moment is outside the `Instant` range, see `offset_date_time_is_valid`.
offset_date_time_make :: proc(
	date_time: Local_Date_Time,
	offset: Zone_Offset,
) -> (
	Offset_Date_Time,
	bool,
) {
	value := Offset_Date_Time {
		date_time = date_time,
		offset    = offset,
	}
	if !offset_date_time_is_valid(value) {
		return {}, false
	}

	return value, true
}

// The reading at `offset` for this moment. Returns `false` in the same cases as
// `instant_to_local_date_time`, within a few hours of the ends of the range.
offset_date_time_from_instant :: proc(
	instant: Instant,
	offset: Zone_Offset,
) -> (
	Offset_Date_Time,
	bool,
) {
	date_time, ok := instant_to_local_date_time(instant, offset)
	if !ok {
		return {}, false
	}
	value := Offset_Date_Time {
		date_time = date_time,
		offset    = offset,
	}
	assert(offset_date_time_is_valid(value))

	return value, true
}

// The one moment this value names. It cannot fail, because `offset_date_time_is_valid` already
// checked the range.
offset_date_time_to_instant :: proc(value: Offset_Date_Time) -> Instant {
	assert(offset_date_time_is_valid(value))

	instant, ok := local_date_time_to_instant(value.date_time, value.offset)
	assert(ok)

	return instant
}

// The same moment written at a different offset: 00:44 at +05:30 is 19:14 the day before at
// UTC. Returns `false` when the reading at the new offset would pass `YEAR_MIN` or `YEAR_MAX`.
offset_date_time_with_offset :: proc(
	value: Offset_Date_Time,
	offset: Zone_Offset,
) -> (
	Offset_Date_Time,
	bool,
) {
	return offset_date_time_from_instant(offset_date_time_to_instant(value), offset)
}

// Orders by the moment, not by the fields, so the same moment at two offsets compares `equal`
// even though `==` says they differ.
offset_date_time_compare :: proc(left, right: Offset_Date_Time) -> Ordering {
	return instant_compare(offset_date_time_to_instant(left), offset_date_time_to_instant(right))
}

// True when `left` is an earlier moment than `right`, whatever offsets they are written at.
// The same moment written two ways gives `false`.
offset_date_time_is_before :: proc(left, right: Offset_Date_Time) -> bool {
	return offset_date_time_compare(left, right) == .less
}

// True when `left` is a later moment than `right`, whatever offsets they are written at.
// The same moment written two ways gives `false`.
offset_date_time_is_after :: proc(left, right: Offset_Date_Time) -> bool {
	return offset_date_time_compare(left, right) == .greater
}

// Moves the moment forward by the duration, or backward when it is negative, and keeps the
// offset. Subtracting is adding the `duration_negate` of it. Returns `false` when the result
// leaves the `Instant` range or its reading leaves `YEAR_MIN..YEAR_MAX`.
offset_date_time_plus_duration :: proc(
	value: Offset_Date_Time,
	duration: Duration,
) -> (
	Offset_Date_Time,
	bool,
) {
	instant, ok := instant_plus(offset_date_time_to_instant(value), duration)
	if !ok {
		return {}, false
	}

	return offset_date_time_from_instant(instant, value.offset)
}

// The `Duration` that moves `from` to `to`, whatever offsets they are written at: positive
// when `to` is later. Always representable, like `instant_between`.
offset_date_time_between :: proc(from, to: Offset_Date_Time) -> Duration {
	return instant_between(offset_date_time_to_instant(from), offset_date_time_to_instant(to))
}

// Moves the date and keeps the clock time and the offset, as `local_date_time_plus_period`
// does. Returns `false` when the date leaves `YEAR_MIN..YEAR_MAX`, or when the new reading
// names a moment outside the `Instant` range.
offset_date_time_plus_period :: proc(
	value: Offset_Date_Time,
	period: Period,
) -> (
	Offset_Date_Time,
	bool,
) {
	assert(offset_date_time_is_valid(value))
	assert(period_is_valid(period))

	date_time, ok := local_date_time_plus_period(value.date_time, period)
	if !ok {
		return {}, false
	}

	return offset_date_time_make(date_time, value.offset)
}
