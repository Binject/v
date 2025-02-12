// Copyright (c) 2019-2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module time

#include <time.h>
#include <errno.h>

struct C.tm {
	tm_sec   int
	tm_min   int
	tm_hour  int
	tm_mday  int
	tm_mon   int
	tm_year  int
	tm_wday  int
	tm_yday  int
	tm_isdst int
}

fn C.timegm(&C.tm) C.time_t

// fn C.gmtime_r(&tm, &gbuf)
fn C.localtime_r(t &C.time_t, tm &C.tm)

fn make_unix_time(t C.tm) i64 {
	return i64(C.timegm(&t))
}

// local returns t with the location set to local time.
pub fn (t Time) local() Time {
	loc_tm := C.tm{}
	C.localtime_r(voidptr(&t.unix), &loc_tm)
	return convert_ctime(loc_tm, t.microsecond)
}

// in most systems, these are __quad_t, which is an i64
struct C.timespec {
mut:
	tv_sec  i64
	tv_nsec i64
}

// the first arg is defined in include/bits/types.h as `__S32_TYPE`, which is `int`
fn C.clock_gettime(int, &C.timespec)

fn C.nanosleep(req &C.timespec, rem &C.timespec) int

// sys_mono_now returns a *monotonically increasing time*, NOT a time adjusted for daylight savings, location etc.
pub fn sys_mono_now() u64 {
	$if macos {
		return sys_mono_now_darwin()
	} $else {
		ts := C.timespec{}
		C.clock_gettime(C.CLOCK_MONOTONIC, &ts)
		return u64(ts.tv_sec) * 1000000000 + u64(ts.tv_nsec)
	}
}

// NB: vpc_now is used by `v -profile` .
// It should NOT call *any other v function*, just C functions and casts.
[inline]
fn vpc_now() u64 {
	ts := C.timespec{}
	C.clock_gettime(C.CLOCK_MONOTONIC, &ts)
	return u64(ts.tv_sec) * 1000000000 + u64(ts.tv_nsec)
}

// The linux_* functions are placed here, since they're used on Android as well
// TODO: should `$if linux {}` be parsed on Android as well? (Android runs under the Linux kernel)
// linux_now returns the local time with high precision for most os:es
// this should be implemented properly with support for leap seconds.
// It uses the realtime clock to get and converts it to local time
fn linux_now() Time {
	// get the high precision time as UTC realtime clock
	// and use the nanoseconds part
	mut ts := C.timespec{}
	C.clock_gettime(C.CLOCK_REALTIME, &ts)
	loc_tm := C.tm{}
	C.localtime_r(voidptr(&ts.tv_sec), &loc_tm)
	return convert_ctime(loc_tm, int(ts.tv_nsec / 1000))
}

fn linux_utc() Time {
	// get the high precision time as UTC realtime clock
	// and use the nanoseconds part
	mut ts := C.timespec{}
	C.clock_gettime(C.CLOCK_REALTIME, &ts)
	return unix2(i64(ts.tv_sec), int(ts.tv_nsec / 1000))
}

// dummy to compile with all compilers
pub fn win_now() Time {
	return Time{}
}

// dummy to compile with all compilers
pub fn win_utc() Time {
	return Time{}
}

// dummy to compile with all compilers
pub struct C.timeval {
	tv_sec  u64
	tv_usec u64
}

// return absolute timespec for now()+d
pub fn (d Duration) timespec() C.timespec {
	mut ts := C.timespec{}
	C.clock_gettime(C.CLOCK_REALTIME, &ts)
	d_sec := d / second
	d_nsec := d % second
	ts.tv_sec += d_sec
	ts.tv_nsec += d_nsec
	if ts.tv_nsec > i64(second) {
		ts.tv_nsec -= i64(second)
		ts.tv_sec++
	}
	return ts
}

// return timespec of 1970/1/1
pub fn zero_timespec() C.timespec {
	ts := C.timespec{
		tv_sec: 0
		tv_nsec: 0
	}
	return ts
}

// sleep makes the calling thread sleep for a given duration (in nanoseconds).
pub fn sleep(duration Duration) {
	mut req := C.timespec{duration / second, duration % second}
	rem := C.timespec{}
	for C.nanosleep(&req, &rem) < 0 {
		if C.errno == C.EINTR {
			// Interrupted by a signal handler
			req = rem
		} else {
			break
		}
	}
}

// some *nix system functions (e.g. `C.poll()`, C.epoll_wait()) accept an `int`
// value as *timeout in milliseconds* with the special value `-1` meaning "infinite"
pub fn (d Duration) sys_milliseconds() int {
	if d > C.INT32_MAX * millisecond { // treat 2147483647000001 .. C.INT64_MAX as "infinite"
		return -1
	} else if d <= 0 {
		return 0 // treat negative timeouts as 0 - consistent with Unix behaviour
	} else {
		return int(d / millisecond)
	}
}
