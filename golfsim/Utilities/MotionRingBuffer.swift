//
//  MotionRingBuffer.swift
//  golfsim
//

import Foundation

/// Fixed-capacity buffer of recent motion samples (oldest evicted first).
struct MotionRingBuffer: Sendable {
    private var storage: [MotionSample?]
    private var writeIndex = 0
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = Array(repeating: nil, count: self.capacity)
    }

    mutating func append(_ sample: MotionSample) {
        storage[writeIndex] = sample
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        writeIndex = 0
        count = 0
    }

    /// Samples ordered from oldest to newest.
    func chronologicalSnapshot() -> [MotionSample] {
        guard count > 0 else { return [] }
        if count < capacity {
            return storage.prefix(count).compactMap { $0 }
        }
        let tail = storage[writeIndex...].compactMap { $0 }
        let head = storage[..<writeIndex].compactMap { $0 }
        return tail + head
    }
}
