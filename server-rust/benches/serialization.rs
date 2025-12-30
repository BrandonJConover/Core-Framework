//! Benchmarks for serialization performance.

use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn serialize_packet_benchmark(c: &mut Criterion) {
    c.bench_function("serialize_packet", |b| {
        b.iter(|| {
            // Placeholder benchmark
            let data = vec![1u8, 2, 3, 4, 5, 6, 7, 8];
            black_box(data)
        })
    });
}

fn deserialize_packet_benchmark(c: &mut Criterion) {
    c.bench_function("deserialize_packet", |b| {
        let data = vec![1u8, 2, 3, 4, 5, 6, 7, 8];
        b.iter(|| {
            black_box(&data)
        })
    });
}

criterion_group!(benches, serialize_packet_benchmark, deserialize_packet_benchmark);
criterion_main!(benches);
