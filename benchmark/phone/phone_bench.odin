package phone_bench

import "core:log"
import "core:testing"
import "core:time"

import phone "../../phone"

BENCH_ITERATIONS :: 5_000_000

// Numbers with 1, 2 and 3 digit country codes, so every lookup path runs.
@(private = "file")
BENCH_PHONES := [?]phone.Phone {
	12_025_550_123, // 1   (falls through all three searches)
	74_951_234_567, // 7
	442_071_838_750, // 44
	4_915_112_345_678, // 49
	919_876_543_210, // 91
	353_851_234_567, // 353
	971_501_234_567, // 971
	2_348_012_345_678, // 234
}

// Run with -o:speed for numbers that mean anything:
//   make bench_phone
@(test)
bench_phone_country_code :: proc(t: ^testing.T) {
	sink: phone.Country_Code

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	for i in 0 ..< BENCH_ITERATIONS {
		sink += phone.country_code(BENCH_PHONES[i % len(BENCH_PHONES)])
	}
	time.stopwatch_stop(&sw)

	elapsed := time.stopwatch_duration(sw)
	ns_per_op := f64(time.duration_nanoseconds(elapsed)) / f64(BENCH_ITERATIONS)
	log.infof("phone_country_code: %.1f ns/op over %d ops (sink %d)", ns_per_op, BENCH_ITERATIONS, sink)

	// Guard against a regression to something pathologically slow.
	testing.expectf(t, ns_per_op < 1000, "country_code took %.1f ns/op", ns_per_op)
}

@(private = "file")
BENCH_STRINGS := [?]string {
	"+12025550123",
	"+74951234567",
	"+442071838750",
	"+4915112345678",
	"+919876543210",
	"+353851234567",
	"+971501234567",
	"+2348012345678",
}

// Run with -o:speed for numbers that mean anything:
//   odin test benchmark/phone -o:speed -define:ODIN_TEST_NAMES=phone_bench.bench_phone_make_phone
@(test)
bench_phone_make_phone :: proc(t: ^testing.T) {
	sink: phone.Phone

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	for i in 0 ..< BENCH_ITERATIONS {
		p, _ := phone.make_phone(BENCH_STRINGS[i % len(BENCH_STRINGS)])
		sink += p
	}
	time.stopwatch_stop(&sw)

	elapsed := time.stopwatch_duration(sw)
	ns_per_op := f64(time.duration_nanoseconds(elapsed)) / f64(BENCH_ITERATIONS)
	log.infof("phone_make_phone: %.1f ns/op over %d ops (sink %d)", ns_per_op, BENCH_ITERATIONS, sink)

	testing.expectf(t, ns_per_op < 1000, "make_phone took %.1f ns/op", ns_per_op)
}
