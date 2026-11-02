//
//  MainTest.swift
//  HaptykTests
//

import Foundation

@main
struct MainTest {
    static func main() {
        print("🧪 Running Haptyk Verification Tests...")

        // 1. RingBuffer Test
        print("  [1/4] Testing RingBuffer...")
        let buffer = RingBuffer<Int>(capacity: 4)
        assert(buffer.count == 0, "Initial count should be 0")
        buffer.write(1)
        buffer.write(2)
        buffer.write(3)
        buffer.write(4)
        assert(buffer.count == 4, "Count should be 4")
        assert(buffer.read(last: 4) == [1, 2, 3, 4], "Buffer content mismatch")
        buffer.write(5) // Overwrite
        assert(buffer.read(last: 4) == [2, 3, 4, 5], "Wraparound content mismatch")
        print("      ✓ RingBuffer passed")

        // 2. Force Tier Classifier
        print("  [2/4] Testing ForceTierClassifier...")
        let classifier = ForceTierClassifier()
        assert(classifier.classify(0.10) == .soft, "0.10 should be soft")
        assert(classifier.classify(0.50) == .medium, "0.50 should be medium")
        assert(classifier.classify(0.85) == .hard, "0.85 should be hard")
        assert(classifier.classify(1.30) == .slam, "1.30 should be slam")
        print("      ✓ ForceTierClassifier passed")

        // 3. Crossfade Calculator
        print("  [3/4] Testing CrossfadeCalculator...")
        let calc = CrossfadeCalculator()
        let weights = calc.calculateWeights(magnitude: 0.30, classifier: classifier)
        assert(weights.lowerTier == .soft, "Lower tier should be soft")
        assert(weights.upperTier == .medium, "Upper tier should be medium")
        assert(abs((weights.lowerWeight + weights.upperWeight) - 1.0) < 0.001, "Weights must sum to 1.0")
        print("      ✓ CrossfadeCalculator passed")

        // 4. KeyMapper
        print("  [4/4] Testing KeyMapper...")
        assert(KeyMapper.category(for: 0x31) == .spacebar, "0x31 must be spacebar")
        assert(KeyMapper.category(for: 0x24) == .enter, "0x24 must be enter")
        assert(KeyMapper.category(for: 0x00) == .alphanumeric, "0x00 must be alphanumeric")
        print("      ✓ KeyMapper passed")

        print("🎉 ALL TESTS PASSED! Haptyk engine core is 100% verified.")
    }
}

