#+build darwin, linux
package chrono

foreign import libc "system:c"

@(private = "file")
CLOCK_REALTIME :: 0

// The `struct tm` layout of darwin and linux on 64 bit targets. It is only read for its offset,
// but `localtime_r` writes the whole struct, so every field has to be here.
#assert(size_of(uintptr) == 8)
@(private = "file")
Broken_Down_Time :: struct {
	seconds:         i32,
	minutes:         i32,
	hours:           i32,
	day_of_month:    i32,
	month:           i32,
	year:            i32,
	weekday:         i32,
	day_of_year:     i32,
	daylight_saving: i32,
	gmt_offset:      i64, // Seconds east of UTC, including any daylight saving shift.
	zone_name:       cstring,
}

// The C `struct timespec`: seconds and nanoseconds since the Unix epoch.
@(private = "file")
Timespec :: struct {
	seconds:     i64,
	nanoseconds: i64,
}

@(private = "file")
foreign libc {
	clock_gettime :: proc(clock_id: i32, timespec: ^Timespec) -> i32 ---
	localtime_r :: proc(timer_seconds: ^i64, broken_down_time: ^Broken_Down_Time) -> ^Broken_Down_Time ---
	tzset :: proc() ---
}

// The current moment from the system's real time clock, with nanosecond fields but only as much
// precision as the operating system gives. It is wall clock time, not monotonic: it can jump
// when the system clock is set, so it is wrong for measuring how long something took.
clock_wall_read :: proc() -> Instant {
	timespec: Timespec
	result := clock_gettime(CLOCK_REALTIME, &timespec)
	assert(result == 0)
	assert(timespec.nanoseconds >= 0 && timespec.nanoseconds < 1_000_000_000)

	instant := Instant {
		seconds     = timespec.seconds,
		nanoseconds = u32(timespec.nanoseconds),
	}
	assert(instant_is_valid(instant))

	return instant
}

// Today's date at `offset`. The only date procedure that reads the clock: everything else
// takes the moment as an argument, so prefer `local_date_from_instant` where the moment is
// already known. Returns `false` only if the system clock is absurdly close to the ends of
// the supported range.
local_date_today :: proc(offset: Zone_Offset) -> (Local_Date, bool) {
	return local_date_from_instant(clock_wall_read(), offset)
}

// The offset the machine's time zone has at this moment, with daylight saving applied: in New
// York it is -05:00 in January and -04:00 in July. It follows the `TZ` environment variable, or
// the system zone when that is unset. Reads process wide state, so it is not deterministic.
//
// Returns `false` when the C library cannot convert the moment, or when the zone reports an
// offset beyond `ZONE_OFFSET_SECONDS_MAX`. The environment can cause both, for example a
// `TZ` that asks for 24 hours east of UTC, so they are not asserted.
zone_offset_system_at :: proc(instant: Instant) -> (Zone_Offset, bool) {
	assert(instant_is_valid(instant))

	// `localtime_r` is not required to re-read `TZ`, so refresh it, which is cheap.
	tzset()
	timer_seconds := instant.seconds
	broken_down_time: Broken_Down_Time
	if localtime_r(&timer_seconds, &broken_down_time) == nil {
		return {}, false
	}
	if broken_down_time.gmt_offset < -ZONE_OFFSET_SECONDS_MAX ||
	   broken_down_time.gmt_offset > ZONE_OFFSET_SECONDS_MAX {
		return {}, false
	}

	return zone_offset_make(i32(broken_down_time.gmt_offset))
}

// The wall clock of the machine's time zone right now. The clock is read once, so the date and
// the time always belong to the same moment. Returns `false` in the cases of
// `zone_offset_system_at` and `instant_to_local_date_time`.
local_date_time_now :: proc() -> (Local_Date_Time, bool) {
	instant := clock_wall_read()
	offset, offset_ok := zone_offset_system_at(instant)
	if !offset_ok {
		return {}, false
	}

	return instant_to_local_date_time(instant, offset)
}

// Today's date in the machine's time zone. Do not pair it with `local_time_now`: they read the
// clock separately, so they can straddle midnight and disagree. Use `local_date_time_now` when
// both are needed.
local_date_now :: proc() -> (Local_Date, bool) {
	date_time, ok := local_date_time_now()

	return date_time.date, ok
}

// The time of day in the machine's time zone right now. See `local_date_now` before pairing it
// with a date.
local_time_now :: proc() -> (Local_Time, bool) {
	date_time, ok := local_date_time_now()

	return date_time.time, ok
}
