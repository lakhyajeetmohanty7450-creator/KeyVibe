//
//  AccelerometerManager.swift
//  Haptyk
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 Haptyk. All rights reserved.
//
//  Interfaces directly with Apple's Sensor Processing Unit (SPU) via
//  IOKit HID to capture 3-axis accelerometer data at ~1,000 Hz.
//

import Foundation
import IOKit
import IOKit.hid
import os.log

// MARK: - AccelerometerSample

/// A single 3-axis accelerometer reading with a high-precision timestamp.
public struct AccelerometerSample: Sendable {
    /// Acceleration along X axis (lateral/side-to-side) in Gs.
    public let x: Double
    /// Acceleration along Y axis (longitudinal/front-to-back) in Gs.
    public let y: Double
    /// Acceleration along Z axis (vertical/normal to keyboard plate) in Gs.
    public let z: Double
    /// High-precision hardware timestamp (mach_absolute_time).
    public let timestamp: UInt64

    /// Total vector magnitude M = sqrt(x^2 + y^2 + z^2).
    public var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }

    public init(x: Double, y: Double, z: Double, timestamp: UInt64) {
        self.x = x
        self.y = y
        self.z = z
        self.timestamp = timestamp
    }
}

// MARK: - AccelerometerManager

/// Manages the high-frequency accelerometer stream from the MacBook SPU.
///
/// Discovers the internal HID motion sensor, subscribes to value callbacks
/// at ~1,000 Hz, parses 3-axis acceleration vectors, and buffers them in a
/// lock-free ring buffer for temporal cross-correlation with keystrokes.
public final class AccelerometerManager {

    // MARK: - Shared Instance

    public static let shared = AccelerometerManager()

    // MARK: - Properties

    /// Whether the hardware accelerometer is available and stream is active.
    public private(set) var isAvailable: Bool = false

    /// Lock-protected ring buffer holding the most recent 2 seconds of telemetry.
    public let ringBuffer: RingBuffer<AccelerometerSample>

    /// Dedicated background thread runloop for receiving HID callbacks.
    private var sensorThread: Thread?
    private var sensorRunLoop: CFRunLoop?

    /// IOKit HID manager reference.
    private var hidManager: IOHIDManager?

    /// Dedicated logger.
    private let log = HaptykLogger(category: .accelerometer)

    /// Baseline calibration vector (gravity offset).
    private var baselineX: Double = 0.0
    private var baselineY: Double = 0.0
    private var baselineZ: Double = 1.0 // 1G downward gravity by default
    private var isCalibrated: Bool = false

    /// Calibration sample accumulator.
    private var calibrationSamples: [AccelerometerSample] = []
    private let calibrationCountTarget = 100

    // MARK: - Initialization

    public init(bufferCapacity: Int = Constants.Accelerometer.bufferSize) {
        self.ringBuffer = RingBuffer<AccelerometerSample>(capacity: bufferCapacity)
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Starts the accelerometer streaming pipeline.
    public func start() {
        guard !isAvailable else {
            log.info("AccelerometerManager is already running.")
            return
        }

        log.info("Starting AccelerometerManager...")

        // Spawn dedicated high-priority sensor thread to run the HID run loop
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            self.sensorRunLoop = CFRunLoopGetCurrent()
            self.setupHIDManager()
            CFRunLoopRun()
        }
        thread.name = "com.haptyk.accelerometer-stream"
        thread.qualityOfService = .userInteractive
        self.sensorThread = thread
        thread.start()
    }

    /// Stops the accelerometer stream and tears down the HID manager.
    public func stop() {
        guard isAvailable || sensorThread != nil else { return }
        log.info("Stopping AccelerometerManager...")

        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if let runLoop = sensorRunLoop {
                IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.commonModes.rawValue)
            }
            self.hidManager = nil
        }

        if let runLoop = sensorRunLoop {
            CFRunLoopStop(runLoop)
            self.sensorRunLoop = nil
        }

        self.sensorThread?.cancel()
        self.sensorThread = nil
        self.isAvailable = false
        log.info("AccelerometerManager stopped.")
    }

    // MARK: - Peak Detection

    /// Returns the peak acceleration delta magnitude within a time window
    /// centered around a given `mach_absolute_time` timestamp.
    ///
    /// - Parameters:
    ///   - timestamp: The keystroke event timestamp.
    ///   - windowMs: Window size in milliseconds (e.g. 10.0 ms).
    /// - Returns: Peak delta magnitude in Gs above resting baseline.
    public func peakMagnitudeInWindow(around timestamp: UInt64, windowMs: Double = Constants.Accelerometer.correlationWindowMs) -> Double {
        // Convert windowMs to mach time units
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanosPerMach = Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
        let halfWindowNanos = (windowMs / 2.0) * 1_000_000.0
        let halfWindowMach = UInt64(halfWindowNanos / nanosPerMach)

        let startTimestamp = timestamp > halfWindowMach ? timestamp - halfWindowMach : 0
        let endTimestamp = timestamp + halfWindowMach

        let samples = ringBuffer.samplesInTimeRange(
            from: startTimestamp,
            to: endTimestamp,
            timestampKeyPath: \.timestamp
        )

        guard !samples.isEmpty else {
            // If no samples exist in window (e.g. synthetic or external kb), return nominal baseline
            return 0.0
        }

        var peakDelta: Double = 0.0
        for sample in samples {
            // Delta from resting baseline vector
            let dx = sample.x - baselineX
            let dy = sample.y - baselineY
            let dz = sample.z - baselineZ
            let deltaMagnitude = sqrt(dx * dx + dy * dy + dz * dz)
            if deltaMagnitude > peakDelta {
                peakDelta = deltaMagnitude
            }
        }

        return peakDelta
    }

    // MARK: - Private HID Setup

    private func setupHIDManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        // Match internal Apple motion sensors (SPU accelerometer)
        // Usage Page: Generic Desktop (0x01) or Motion (0x20)
        let matchingDicts: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: 0x01, // Generic Desktop
                kIOHIDDeviceUsageKey as String: 0x04       // Joystick / Motion Multi-axis
            ],
            [
                kIOHIDDeviceUsagePageKey as String: 0x20  // Sensors Page
            ],
            [
                kIOHIDDeviceUsagePageKey as String: 0xFF00 // Apple Vendor Specific
            ]
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()

        // Register value callback
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let context = context else { return }
            let manager = Unmanaged<AccelerometerManager>.fromOpaque(context).takeUnretainedValue()
            manager.handleHIDValue(value)
        }, context)

        guard let runLoop = sensorRunLoop else { return }
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.commonModes.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            self.isAvailable = true
            log.info("IOHIDManager opened successfully. Streaming accelerometer data.")
        } else {
            log.warning("IOHIDManagerOpen returned code \(openResult). Fallback mode active.")
            self.isAvailable = false
        }
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        // Accelerometer axis usages (X: 0x30, Y: 0x31, Z: 0x32, or sensor specific)
        let intVal = IOHIDValueGetIntegerValue(value)
        let timestamp = mach_absolute_time()

        // Scale raw integer to Gs (typical sensor range: -4G to +4G mapped over 16-bit integer)
        let scaledVal = Double(intVal) / 8192.0

        // In a multi-axis delivery, we update axes and push samples
        recordRawAxis(usagePage: usagePage, usage: usage, value: scaledVal, timestamp: timestamp)
    }

    private var currentX: Double = 0.0
    private var currentY: Double = 0.0
    private var currentZ: Double = 1.0

    private func recordRawAxis(usagePage: UInt32, usage: UInt32, value: Double, timestamp: UInt64) {
        switch usage {
        case 0x30: currentX = value
        case 0x31: currentY = value
        case 0x32:
            currentZ = value
            let sample = AccelerometerSample(x: currentX, y: currentY, z: currentZ, timestamp: timestamp)
            ringBuffer.write(sample)

            // Dynamic baseline calibration
            if !isCalibrated {
                calibrationSamples.append(sample)
                if calibrationSamples.count >= calibrationCountTarget {
                    let avgX = calibrationSamples.map(\.x).reduce(0, +) / Double(calibrationSamples.count)
                    let avgY = calibrationSamples.map(\.y).reduce(0, +) / Double(calibrationSamples.count)
                    let avgZ = calibrationSamples.map(\.z).reduce(0, +) / Double(calibrationSamples.count)
                    baselineX = avgX
                    baselineY = avgY
                    baselineZ = avgZ
                    isCalibrated = true
                    log.info("Accelerometer baseline calibrated: X=\(avgX), Y=\(avgY), Z=\(avgZ)")
                }
            }
        default:
            break
        }
    }
}

