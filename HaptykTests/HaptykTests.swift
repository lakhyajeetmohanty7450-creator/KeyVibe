//
//  HaptykTests.swift
//  HaptykTests
//
//  Unit tests for Haptyk's core algorithms:
//  - RingBuffer temporal range queries and circular index wraparound
//  - ForceTierClassifier sensitivity thresholding
//  - CrossfadeCalculator linear gain interpolation
//  - KeyMapper virtual key codes
//  - TrialTracker checksum & tamper protection
//

import XCTest
@testable import Haptyk

final class HaptykTests: XCTestCase {

    // MARK: - RingBuffer Tests

    func testRingBufferCapacityAndWraparound() {
        let buffer = RingBuffer<Int>(capacity: 4)
        XCTAssertEqual(buffer.count, 0)

        buffer.write(10)
        buffer.write(20)
        buffer.write(30)
        buffer.write(40)
        XCTAssertEqual(buffer.count, 4)
        XCTAssertEqual(buffer.read(last: 4), [10, 20, 30, 40])

        // Overwrite oldest (10 and 20)
        buffer.write(50)
        buffer.write(60)
        XCTAssertEqual(buffer.count, 4)
        XCTAssertEqual(buffer.read(last: 4), [30, 40, 50, 60])
    }

    func testRingBufferTimeRangeQuery() {
        struct MockSample {
            let val: Int
            let timestamp: UInt64
        }

        let buffer = RingBuffer<MockSample>(capacity: 8)
        for i in 1...6 {
            buffer.write(MockSample(val: i, timestamp: UInt64(i * 1000)))
        }

        // Query window between 2500 and 4500
        let matches = buffer.samplesInTimeRange(from: 2500, to: 4500, timestampKeyPath: \.timestamp)
        XCTAssertEqual(matches.map(\.val), [3, 4])
    }

    // MARK: - Force Tier & Crossfade Tests

    func testForceTierClassification() {
        let classifier = ForceTierClassifier(
            softThreshold: 0.15,
            mediumThreshold: 0.45,
            hardThreshold: 0.75,
            slamThreshold: 1.20
        )

        XCTAssertEqual(classifier.classify(0.10), .soft)
        XCTAssertEqual(classifier.classify(0.30), .soft)
        XCTAssertEqual(classifier.classify(0.50), .medium)
        XCTAssertEqual(classifier.classify(0.80), .hard)
        XCTAssertEqual(classifier.classify(1.50), .slam)
    }

    func testCrossfadeInterpolation() {
        let classifier = ForceTierClassifier(
            softThreshold: 0.15,
            mediumThreshold: 0.45,
            hardThreshold: 0.75,
            slamThreshold: 1.20
        )
        let calc = CrossfadeCalculator()

        // Below soft -> 100% soft
        let softWeights = calc.calculateWeights(magnitude: 0.10, classifier: classifier)
        XCTAssertEqual(softWeights.lowerTier, .soft)
        XCTAssertEqual(softWeights.upperTier, .soft)
        XCTAssertEqual(softWeights.lowerWeight, 1.0)
        XCTAssertEqual(softWeights.upperWeight, 0.0)

        // Exactly halfway between soft (0.15) and medium (0.45) = 0.30
        let midWeights = calc.calculateWeights(magnitude: 0.30, classifier: classifier)
        XCTAssertEqual(midWeights.lowerTier, .soft)
        XCTAssertEqual(midWeights.upperTier, .medium)
        XCTAssertEqual(midWeights.lowerWeight, 0.5, accuracy: 0.01)
        XCTAssertEqual(midWeights.upperWeight, 0.5, accuracy: 0.01)

        // Beyond slam -> 100% slam
        let slamWeights = calc.calculateWeights(magnitude: 2.0, classifier: classifier)
        XCTAssertEqual(slamWeights.lowerTier, .slam)
        XCTAssertEqual(slamWeights.upperTier, .slam)
    }

    // MARK: - KeyMapper Tests

    func testKeyCategoryMapping() {
        // Spacebar is 0x31
        XCTAssertEqual(KeyMapper.category(for: 0x31), .spacebar)
        // Return is 0x24
        XCTAssertEqual(KeyMapper.category(for: 0x24), .enter)
        // Delete is 0x33
        XCTAssertEqual(KeyMapper.category(for: 0x33), .backspace)
        // 'A' is 0x00
        XCTAssertEqual(KeyMapper.category(for: 0x00), .alphanumeric)
    }

    // MARK: - Trial Verification Tests

    func testTrialCountdownLogic() {
        TrialTracker.recordInstallDateIfNeeded()
        let days = TrialTracker.daysRemaining()
        XCTAssertGreaterThanOrEqual(days, 1)
        XCTAssertLessThanOrEqual(days, 3)
        XCTAssertFalse(TrialTracker.isExpired())
    }
}

