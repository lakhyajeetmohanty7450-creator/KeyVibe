//
//  RingBuffer.swift
//  Haptyk
//
//  A generic, lock-protected circular buffer optimized for high-frequency
//  sensor data (≈1 kHz accelerometer samples). Uses `os_unfair_lock` for
//  minimal-overhead synchronization between a single writer (sensor thread)
//  and one or more readers (velocity engine, UI).
//
//  Design decisions:
//  - Pre-allocated backing store (`UnsafeMutableBufferPointer`) avoids
//    heap churn and copy-on-write overhead of `Array<T>`.
//  - Circular indexing via bitmask when capacity is a power of two,
//    otherwise modulo — branchless where possible.
//  - `samplesInTimeRange` performs a backwards linear scan, which is
//    optimal for the typical query pattern: "last N milliseconds."
//
//  Created for the Haptyk project.
//  Copyright © 2024 Haptyk. All rights reserved.
//

import Foundation
import os

// MARK: - RingBuffer

/// A thread-safe, pre-allocated circular buffer designed for streaming
/// sensor data at kilohertz rates.
///
/// - Generic over `T` so it can hold `AccelerometerSample` or any other
///   timestamped value type.
/// - **Writer thread**: call `write(_:)` from the IOKit HID callback.
/// - **Reader thread(s)**: call `read(last:)` or `samplesInTimeRange(…)`.
///
/// The buffer overwrites the oldest element when full (classic ring semantics).
public final class RingBuffer<T> {

    // MARK: Properties

    /// Fixed capacity of the ring buffer, set at initialization.
    let capacity: Int

    /// Pre-allocated backing storage. Elements at indices beyond `totalWritten`
    /// are uninitialized memory — callers must never read past `count`.
    private let storage: UnsafeMutablePointer<T>

    /// Total number of elements ever written. Used to compute the logical
    /// head position and the current `count`. Monotonically increasing.
    private var totalWritten: Int = 0

    /// Low-overhead lock for producer/consumer synchronization.
    /// `os_unfair_lock` is the fastest userspace lock on Darwin —
    /// appropriate for the sub-microsecond critical sections here.
    private var lock = os_unfair_lock()

    /// Whether the capacity is a power of two, enabling bitmask indexing.
    private let isPowerOfTwo: Bool

    /// Bitmask for power-of-two capacities (capacity - 1).
    private let mask: Int

    // MARK: Initialization

    /// Creates a ring buffer with the specified capacity.
    ///
    /// - Parameter capacity: Maximum number of elements the buffer can hold.
    ///   Must be ≥ 1. For best performance, use a power of two.
    /// - Precondition: `capacity > 0`
    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        self.capacity = capacity
        self.storage = .allocate(capacity: capacity)
        self.isPowerOfTwo = (capacity & (capacity - 1)) == 0
        self.mask = capacity - 1
    }

    deinit {
        // Deinitialize all currently-valid elements to avoid leaks for
        // reference-counted T (no-op for value types like AccelerometerSample).
        let validCount = min(totalWritten, capacity)
        if validCount > 0 {
            let headIndex = ringIndex(totalWritten - validCount)
            for i in 0..<validCount {
                let idx = ringIndex(headIndex + i)
                storage.advanced(by: idx).deinitialize(count: 1)
            }
        }
        storage.deallocate()
    }

    // MARK: - Write

    /// Appends a new element to the buffer, overwriting the oldest if full.
    ///
    /// - Parameter element: The value to store.
    /// - Complexity: O(1).
    /// - Thread safety: Safe to call from a single writer thread concurrently
    ///   with readers.
    func write(_ element: T) {
        os_unfair_lock_lock(&lock)

        let index = ringIndex(totalWritten)

        if totalWritten >= capacity {
            // Slot already initialized — deinitialize before overwriting.
            storage.advanced(by: index).deinitialize(count: 1)
        }

        storage.advanced(by: index).initialize(to: element)
        totalWritten += 1

        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Read

    /// Returns the most recent `n` elements in chronological order.
    ///
    /// - Parameter n: Number of recent elements to retrieve. Clamped to
    ///   `[0, count]`.
    /// - Returns: An array of at most `n` elements, oldest first.
    /// - Complexity: O(n).
    func read(last n: Int) -> [T] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let available = min(totalWritten, capacity)
        let requested = max(0, min(n, available))

        guard requested > 0 else { return [] }

        var result = [T]()
        result.reserveCapacity(requested)

        let startOffset = totalWritten - requested
        for i in 0..<requested {
            let idx = ringIndex(startOffset + i)
            result.append(storage[idx])
        }

        return result
    }

    /// Returns all elements whose timestamp falls within `[from, to]`.
    ///
    /// The method scans backwards from the newest sample, stopping early once
    /// it reaches a timestamp older than `from`. This is optimal for typical
    /// "last N ms" queries against monotonically-increasing timestamps.
    ///
    /// - Parameters:
    ///   - from: Inclusive lower bound (oldest timestamp desired).
    ///   - to:   Inclusive upper bound (newest timestamp desired).
    ///   - timestampKeyPath: Key path to the `UInt64` timestamp field on `T`.
    /// - Returns: Matching elements in chronological order (oldest first).
    /// - Complexity: O(k) where k is the number of elements scanned (typically
    ///   small relative to capacity for narrow time windows).
    func samplesInTimeRange(
        from: UInt64,
        to: UInt64,
        timestampKeyPath: KeyPath<T, UInt64>
    ) -> [T] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let available = min(totalWritten, capacity)
        guard available > 0, from <= to else { return [] }

        // Scan backwards from newest to find matching range.
        var matches = [T]()
        matches.reserveCapacity(min(available, 128)) // Reasonable pre-allocation

        for i in stride(from: available - 1, through: 0, by: -1) {
            let idx = ringIndex(totalWritten - available + i)
            let sample = storage[idx]
            let ts = sample[keyPath: timestampKeyPath]

            if ts > to {
                // Haven't reached the window yet — keep scanning backwards.
                continue
            }
            if ts < from {
                // Past the window — no older samples will match.
                break
            }
            matches.append(sample)
        }

        // Reverse because we scanned newest → oldest but want chronological order.
        matches.reverse()
        return matches
    }

    // MARK: - Count & Clear

    /// The number of valid elements currently in the buffer.
    var count: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return min(totalWritten, capacity)
    }

    /// Removes all elements from the buffer.
    ///
    /// - Note: Does not deallocate backing storage; the buffer is ready
    ///   for immediate reuse.
    func clear() {
        os_unfair_lock_lock(&lock)

        let validCount = min(totalWritten, capacity)
        if validCount > 0 {
            let headIndex = ringIndex(totalWritten - validCount)
            for i in 0..<validCount {
                let idx = ringIndex(headIndex + i)
                storage.advanced(by: idx).deinitialize(count: 1)
            }
        }
        totalWritten = 0

        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Private Helpers

    /// Converts a logical index to a physical storage index using either
    /// bitmask (power-of-two capacity) or modulo arithmetic.
    @inline(__always)
    private func ringIndex(_ logicalIndex: Int) -> Int {
        if isPowerOfTwo {
            return logicalIndex & mask
        } else {
            // Swift's `%` can return negative values for negative operands,
            // but `logicalIndex` is always ≥ 0 in our usage.
            return logicalIndex % capacity
        }
    }
}

// MARK: - CustomDebugStringConvertible

extension RingBuffer: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "RingBuffer<\(T.self)>(capacity: \(capacity), count: \(count), totalWritten: \(totalWritten))"
    }
}
