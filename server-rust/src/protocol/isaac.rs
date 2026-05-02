//! ISAAC stream cipher.
//!
//! Byte-for-byte port of `com.openrsc.server.login.ISAACCipher` from the Java
//! server (which itself is a port of Bob Jenkins' canonical Java reference
//! `Rand.java`). Used for opcode shuffling on RSC connections >= mudclient 183.
//!
//! The Java code path during login is:
//!   ```java
//!   ISAACCipher cipher = new ISAACCipher();   // memory[]/results[] zeroed
//!   cipher.setKeys(loginInfo.keys);            // copies seed.length words into results[0..seed.length]
//!                                              // (rest of results[] stays zero), then calls init(true)
//!   ```
//! We replicate this exactly — `IsaacCipher::new(seed)` populates the first
//! 4 words of `results` and then runs `init(true)` (the second-pass mix).
//!
//! All arithmetic is on 32-bit unsigned values with wrapping semantics
//! (matching Java's signed 32-bit `int` overflow behavior, which is the same
//! on the bit pattern level).

#![allow(clippy::needless_range_loop)]

const RATIO: u32 = 0x9e37_79b9;
const SIZE_LOG: u32 = 8;
const SIZE: usize = 1 << SIZE_LOG; // 256
/// Bit-mask used by Java: `(SIZE - 1) << 2` = 0x3FC. The right-shift by 2 in
/// the lookup converts from byte-offset back to word-index, matching Java's
/// pointer-style indexing on its `int[] memory`.
const MASK: u32 = ((SIZE as u32) - 1) << 2;

/// ISAAC cipher state.
///
/// Layout matches Java's `ISAACCipher`:
/// - `results` / `memory` are the 256-word output buffer and internal state
/// - `a`, `b`, `c` are the three accumulators
/// - `count` is the index into `results`, decremented by `next_value()`
#[derive(Debug, Clone)]
pub struct IsaacCipher {
    results: [u32; SIZE],
    memory: [u32; SIZE],
    a: u32,
    b: u32,
    c: u32,
    count: i32,
}

impl IsaacCipher {
    /// Create a new ISAAC cipher initialized from a 4-word seed.
    ///
    /// Matches Java: `new ISAACCipher()` followed by `setKeys(seed)` where
    /// `seed.length == 4`. The first 4 entries of `results` are the seed, the
    /// remaining 252 entries are zero, then `init(true)` runs.
    pub fn new(seed: [u32; 4]) -> Self {
        let mut cipher = Self {
            results: [0; SIZE],
            memory: [0; SIZE],
            a: 0,
            b: 0,
            c: 0,
            count: 0,
        };
        // setKeys: copy seed into the head of results; rest already zero.
        cipher.results[0] = seed[0];
        cipher.results[1] = seed[1];
        cipher.results[2] = seed[2];
        cipher.results[3] = seed[3];
        cipher.init(true);
        cipher
    }

    /// Create a new ISAAC cipher from a seed of arbitrary length (up to 256
    /// words). Words past the end of `seed` are zero. This mirrors Java's
    /// `setKeys(int[] seed)` accepting any seed length.
    pub fn with_seed_slice(seed: &[u32]) -> Self {
        let mut cipher = Self {
            results: [0; SIZE],
            memory: [0; SIZE],
            a: 0,
            b: 0,
            c: 0,
            count: 0,
        };
        let n = seed.len().min(SIZE);
        cipher.results[..n].copy_from_slice(&seed[..n]);
        cipher.init(true);
        cipher
    }

    /// Emit the next stream word. Matches Java's `getNextValue()`.
    ///
    /// Java's logic is:
    /// ```java
    /// if (count-- == 0) { isaac(); count = SIZE - 1; }
    /// return results[count];
    /// ```
    /// `count` is an `int` so it freely goes negative; `count--` post-decrements.
    /// We replicate using `i32` for `count`.
    pub fn next_value(&mut self) -> u32 {
        let prev = self.count;
        self.count -= 1;
        if prev == 0 {
            self.isaac();
            self.count = (SIZE as i32) - 1;
        }
        self.results[self.count as usize]
    }

    /// Generate the next batch of 256 results (the Java `isaac()` round
    /// function). The four-step unrolled mix exactly mirrors the Java version,
    /// producing identical word-by-word output.
    fn isaac(&mut self) {
        self.c = self.c.wrapping_add(1);
        self.b = self.b.wrapping_add(self.c);

        // First half: i in [0, SIZE/2), j starts at SIZE/2.
        let mut i: usize = 0;
        let mut j: usize = SIZE / 2;
        while i < SIZE / 2 {
            // step 0: a ^= a << 13
            let x = self.memory[i];
            self.a ^= self.a << 13;
            self.a = self.a.wrapping_add(self.memory[j]);
            j += 1;
            let y = self.memory[((x & MASK) >> 2) as usize]
                .wrapping_add(self.a)
                .wrapping_add(self.b);
            self.memory[i] = y;
            self.b = self.memory[(((y >> SIZE_LOG) & MASK) >> 2) as usize].wrapping_add(x);
            self.results[i] = self.b;
            i += 1;

            // step 1: a ^= a >>> 6
            let x = self.memory[i];
            self.a ^= self.a >> 6;
            self.a = self.a.wrapping_add(self.memory[j]);
            j += 1;
            let y = self.memory[((x & MASK) >> 2) as usize]
                .wrapping_add(self.a)
                .wrapping_add(self.b);
            self.memory[i] = y;
            self.b = self.memory[(((y >> SIZE_LOG) & MASK) >> 2) as usize].wrapping_add(x);
            self.results[i] = self.b;
            i += 1;

            // step 2: a ^= a << 2
            let x = self.memory[i];
            self.a ^= self.a << 2;
            self.a = self.a.wrapping_add(self.memory[j]);
            j += 1;
            let y = self.memory[((x & MASK) >> 2) as usize]
                .wrapping_add(self.a)
                .wrapping_add(self.b);
            self.memory[i] = y;
            self.b = self.memory[(((y >> SIZE_LOG) & MASK) >> 2) as usize].wrapping_add(x);
            self.results[i] = self.b;
            i += 1;

            // step 3: a ^= a >>> 16
            let x = self.memory[i];
            self.a ^= self.a >> 16;
            self.a = self.a.wrapping_add(self.memory[j]);
            j += 1;
            let y = self.memory[((x & MASK) >> 2) as usize]
                .wrapping_add(self.a)
                .wrapping_add(self.b);
            self.memory[i] = y;
            self.b = self.memory[(((y >> SIZE_LOG) & MASK) >> 2) as usize].wrapping_add(x);
            self.results[i] = self.b;
            i += 1;
        }

        // Second half: continue i from SIZE/2 to SIZE, j wraps back to 0.
        let mut j: usize = 0;
        while j < SIZE / 2 {
            let x = self.memory[i];
            self.a ^= self.a << 13;
            self.a = self.a.wrapping_add(self.memory[j]);
            j += 1;
            let y = self.memory[((x & MASK) >> 2) as usize]
                .wrapping_add(self.a)
                .wrapping_add(self.b);
            self.memory[i] = y;
            self.b = self.memory[(((y >> SIZE_LOG) & MASK) >> 2) as usize].wrapping_add(x);
            self.results[i] = self.b;
            i += 1;

            let x = self.memory[i];
            self.a ^= self.a >> 6;
            self.a = self.a.wrapping_add(self.memory[j]);
            j += 1;
            let y = self.memory[((x & MASK) >> 2) as usize]
                .wrapping_add(self.a)
                .wrapping_add(self.b);
            self.memory[i] = y;
            self.b = self.memory[(((y >> SIZE_LOG) & MASK) >> 2) as usize].wrapping_add(x);
            self.results[i] = self.b;
            i += 1;

            let x = self.memory[i];
            self.a ^= self.a << 2;
            self.a = self.a.wrapping_add(self.memory[j]);
            j += 1;
            let y = self.memory[((x & MASK) >> 2) as usize]
                .wrapping_add(self.a)
                .wrapping_add(self.b);
            self.memory[i] = y;
            self.b = self.memory[(((y >> SIZE_LOG) & MASK) >> 2) as usize].wrapping_add(x);
            self.results[i] = self.b;
            i += 1;

            let x = self.memory[i];
            self.a ^= self.a >> 16;
            self.a = self.a.wrapping_add(self.memory[j]);
            j += 1;
            let y = self.memory[((x & MASK) >> 2) as usize]
                .wrapping_add(self.a)
                .wrapping_add(self.b);
            self.memory[i] = y;
            self.b = self.memory[(((y >> SIZE_LOG) & MASK) >> 2) as usize].wrapping_add(x);
            self.results[i] = self.b;
            i += 1;
        }
    }

    /// Initialise the ISAAC state. `flag = true` performs the second pass that
    /// mixes in the seeded `results` array (matching Java's `init(true)` call
    /// after `setKeys`). The sequence of 24 mixing operations on
    /// (a, b, c, d, e, f, g, h) is identical to the Java reference.
    fn init(&mut self, flag: bool) {
        let mut a = RATIO;
        let mut b = RATIO;
        let mut c = RATIO;
        let mut d = RATIO;
        let mut e = RATIO;
        let mut f = RATIO;
        let mut g = RATIO;
        let mut h = RATIO;

        // 4 rounds of mixing.
        for _ in 0..4 {
            mix(&mut a, &mut b, &mut c, &mut d, &mut e, &mut f, &mut g, &mut h);
        }

        // First pass: seed memory[] from the (results-mixed) (a..h).
        let mut i = 0;
        while i < SIZE {
            if flag {
                a = a.wrapping_add(self.results[i]);
                b = b.wrapping_add(self.results[i + 1]);
                c = c.wrapping_add(self.results[i + 2]);
                d = d.wrapping_add(self.results[i + 3]);
                e = e.wrapping_add(self.results[i + 4]);
                f = f.wrapping_add(self.results[i + 5]);
                g = g.wrapping_add(self.results[i + 6]);
                h = h.wrapping_add(self.results[i + 7]);
            }
            mix(&mut a, &mut b, &mut c, &mut d, &mut e, &mut f, &mut g, &mut h);
            self.memory[i] = a;
            self.memory[i + 1] = b;
            self.memory[i + 2] = c;
            self.memory[i + 3] = d;
            self.memory[i + 4] = e;
            self.memory[i + 5] = f;
            self.memory[i + 6] = g;
            self.memory[i + 7] = h;
            i += 8;
        }

        // Second pass: re-mix from memory[] itself (only when flag is set).
        if flag {
            let mut i = 0;
            while i < SIZE {
                a = a.wrapping_add(self.memory[i]);
                b = b.wrapping_add(self.memory[i + 1]);
                c = c.wrapping_add(self.memory[i + 2]);
                d = d.wrapping_add(self.memory[i + 3]);
                e = e.wrapping_add(self.memory[i + 4]);
                f = f.wrapping_add(self.memory[i + 5]);
                g = g.wrapping_add(self.memory[i + 6]);
                h = h.wrapping_add(self.memory[i + 7]);
                mix(&mut a, &mut b, &mut c, &mut d, &mut e, &mut f, &mut g, &mut h);
                self.memory[i] = a;
                self.memory[i + 1] = b;
                self.memory[i + 2] = c;
                self.memory[i + 3] = d;
                self.memory[i + 4] = e;
                self.memory[i + 5] = f;
                self.memory[i + 6] = g;
                self.memory[i + 7] = h;
                i += 8;
            }
        }

        self.isaac();
        // count = SIZE means next_value() will check (count-- == 0) -> false,
        // count becomes 255, and we read results[255] first. This matches Java.
        self.count = SIZE as i32;
    }
}

/// The 24-step Bob-Jenkins mixing function on eight `u32` registers. Matches
/// Java's inline expansion at the top of `init()`.
#[inline(always)]
#[allow(clippy::too_many_arguments)]
fn mix(
    a: &mut u32,
    b: &mut u32,
    c: &mut u32,
    d: &mut u32,
    e: &mut u32,
    f: &mut u32,
    g: &mut u32,
    h: &mut u32,
) {
    *a ^= *b << 11;
    *d = d.wrapping_add(*a);
    *b = b.wrapping_add(*c);

    *b ^= *c >> 2;
    *e = e.wrapping_add(*b);
    *c = c.wrapping_add(*d);

    *c ^= *d << 8;
    *f = f.wrapping_add(*c);
    *d = d.wrapping_add(*e);

    *d ^= *e >> 16;
    *g = g.wrapping_add(*d);
    *e = e.wrapping_add(*f);

    *e ^= *f << 10;
    *h = h.wrapping_add(*e);
    *f = f.wrapping_add(*g);

    *f ^= *g >> 4;
    *a = a.wrapping_add(*f);
    *g = g.wrapping_add(*h);

    *g ^= *h << 8;
    *b = b.wrapping_add(*g);
    *h = h.wrapping_add(*a);

    *h ^= *a >> 9;
    *c = c.wrapping_add(*h);
    *a = a.wrapping_add(*b);
}

#[cfg(test)]
mod tests {
    use super::*;

    /// All-zero seed: regression vector against Bob Jenkins' canonical Java
    /// `Rand.java` (which is what Graham Edgecombe's port — and therefore the
    /// OpenRSC Java code — descends from).
    ///
    /// These first-batch values are produced by both:
    ///   - Bob Jenkins' Rand.java run with the all-zero seed
    ///   - OpenRSC's `ISAACCipher.setKeys(new int[]{0,0,0,0})`
    ///
    /// `next_value()` returns from the *end* of `results` first because of
    /// Java's `count--` post-decrement, so we capture the values in the
    /// canonical [0..256] forward order by collecting then reversing.
    #[test]
    fn zero_seed_first_batch_matches_jenkins() {
        let mut c = IsaacCipher::new([0, 0, 0, 0]);
        // Pull all 256 of the first batch — they come out in reverse order
        // (results[255], results[254], ..., results[0]).
        let mut emitted = [0u32; SIZE];
        for slot in emitted.iter_mut() {
            *slot = c.next_value();
        }
        // The first emitted word is results[255]; the value at "logical
        // position 0" is the LAST one emitted in the batch.
        // Known canonical output: results[0] for zero-seed is 0xf650e4c8.
        // (See e.g. https://burtleburtle.net/bob/rand/isaacafa.html — the
        //  Java reference `randvect.txt` first line.)
        assert_eq!(emitted[SIZE - 1], 0xf650_e4c8);
        // Spot-check more positions against the canonical sequence:
        // results[1] = 0xe448e96d, results[2] = 0x98db2fb4
        assert_eq!(emitted[SIZE - 2], 0xe448_e96d);
        assert_eq!(emitted[SIZE - 3], 0x98db_2fb4);
    }

    /// State-machine sanity: `next_value` should never return the same word
    /// twice in immediate succession from a real seed, and after 256 calls
    /// the cipher should refill (call `isaac()` internally).
    #[test]
    fn next_value_progresses_and_refills() {
        let mut c = IsaacCipher::new([1, 2, 3, 4]);
        let first = c.next_value();
        let second = c.next_value();
        assert_ne!(first, second, "consecutive ISAAC outputs collided");

        // Drain the rest of the first batch (254 more), then one extra to
        // force a refill. None should panic; values should still differ.
        for _ in 0..254 {
            let _ = c.next_value();
        }
        let after_refill = c.next_value();
        // After a refill we're sampling a new batch — extremely unlikely to
        // equal `first` by coincidence, but we don't hard-assert that.
        let _ = after_refill;
    }

    /// Determinism: same seed → same stream.
    #[test]
    fn same_seed_same_stream() {
        let seed = [0xdead_beef, 0xcafe_babe, 0x1234_5678, 0x9abc_def0];
        let mut a = IsaacCipher::new(seed);
        let mut b = IsaacCipher::new(seed);
        for _ in 0..1024 {
            assert_eq!(a.next_value(), b.next_value());
        }
    }

    /// `with_seed_slice` with 4 words must equal `new` with the same 4 words.
    #[test]
    fn slice_constructor_matches_array_constructor() {
        let seed = [0x1111_1111u32, 0x2222_2222, 0x3333_3333, 0x4444_4444];
        let mut a = IsaacCipher::new(seed);
        let mut b = IsaacCipher::with_seed_slice(&seed);
        for _ in 0..512 {
            assert_eq!(a.next_value(), b.next_value());
        }
    }
}
