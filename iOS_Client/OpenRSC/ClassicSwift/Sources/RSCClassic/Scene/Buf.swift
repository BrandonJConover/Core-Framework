// A fixed-size, reference-typed C-style array. The 3D code shares and aliases
// arrays the way rsc-c does with raw pointers (e.g. autocommit models use the
// same storage for vertices and transformed vertices), so value arrays won't do.

public final class Buf<T> {
    public let pointer: UnsafeMutablePointer<T>
    public let count: Int

    public init(_ count: Int, _ value: T) {
        self.count = count
        pointer = .allocate(capacity: Swift.max(count, 1))
        pointer.initialize(repeating: value, count: Swift.max(count, 1))
    }

    public init(_ values: [T]) {
        count = values.count
        pointer = .allocate(capacity: Swift.max(count, 1))
        if count > 0 {
            values.withUnsafeBufferPointer { pointer.initialize(from: $0.baseAddress!, count: count) }
        } else if let first = values.first {
            pointer.initialize(to: first)
        }
    }

    deinit {
        pointer.deinitialize(count: Swift.max(count, 1))
        pointer.deallocate()
    }

    @inline(__always)
    public subscript(i: Int) -> T {
        get {
            assert(i >= 0 && i < Swift.max(count, 1), "Buf index \(i) out of range \(count)")
            return pointer[i]
        }
        set {
            assert(i >= 0 && i < Swift.max(count, 1), "Buf index \(i) out of range \(count)")
            pointer[i] = newValue
        }
    }

    public func copy(from other: Buf<T>, count n: Int) {
        guard n > 0 else { return }
        pointer.update(from: other.pointer, count: n)
    }

    public var array: [T] { Array(UnsafeBufferPointer(start: pointer, count: count)) }
}

extension Buf where T: Numeric {
    public convenience init(_ count: Int) { self.init(count, 0) }
}
