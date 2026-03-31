import Observation

#if os(iOS)
import CoreMotion
import UIKit
#endif

@MainActor @Observable
public final class WashiMotionManager {

    public static let shared = WashiMotionManager()

    public private(set) var tiltIntensity: Float = 0.0
    public private(set) var tiltAngle: Float = 0.0

    #if os(iOS)
    private let motion = CMMotionManager()
    #endif
    private var activeCount = 0

    public var isActive: Bool {
        #if os(iOS)
        return activeCount > 0 && motion.isDeviceMotionActive
        #else
        return false
        #endif
    }

    public func start() {
        activeCount += 1
        guard activeCount == 1 else { return }

        #if os(iOS)
        guard motion.isDeviceMotionAvailable,
              !UIAccessibility.isReduceMotionEnabled
        else { return }

        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated {
                guard let self else { return }

                let pitch = Float(data.attitude.pitch)
                let roll = Float(data.attitude.roll)

                // Tilt magnitude: 0 = flat, 1 = ~45 degrees
                let magnitude = sqrt(pitch * pitch + roll * roll)
                let normalizedMag = min(magnitude / (.pi / 4.0), 1.0)

                // Tilt direction
                let angle = atan2(pitch, roll)
                let normalizedAngle = angle < 0 ? angle + 2.0 * .pi : angle

                // Exponential smoothing (magnitude)
                self.tiltIntensity = self.tiltIntensity * 0.7 + normalizedMag * 0.3

                // Vector smoothing (angle — avoids wrap discontinuity at 0/2pi)
                let smoothX = cos(self.tiltAngle) * 0.7 + cos(normalizedAngle) * 0.3
                let smoothY = sin(self.tiltAngle) * 0.7 + sin(normalizedAngle) * 0.3
                self.tiltAngle = atan2(smoothY, smoothX)
                if self.tiltAngle < 0 { self.tiltAngle += 2.0 * .pi }
            }
        }
        #endif
    }

    public func stop() {
        activeCount = max(activeCount - 1, 0)
        guard activeCount == 0 else { return }

        #if os(iOS)
        motion.stopDeviceMotionUpdates()
        #endif

        tiltIntensity = 0
        tiltAngle = 0
    }
}
