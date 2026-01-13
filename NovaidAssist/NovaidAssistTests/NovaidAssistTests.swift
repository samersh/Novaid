import XCTest
@testable import NovaidAssist

final class NovaidAssistTests: XCTestCase {

    // MARK: - User Manager Tests

    func testUserManagerInitialization() {
        let manager = UserManager.shared
        XCTAssertNotNil(manager)
    }

    func testUserIdGeneration() {
        let manager = UserManager.shared
        manager.clearUser()

        manager.initializeUser(role: .user)

        XCTAssertNotNil(manager.currentUser)
        XCTAssertFalse(manager.shortId.isEmpty)
        XCTAssertEqual(manager.shortId.count, 6)
    }

    func testUserRoleAssignment() {
        let manager = UserManager.shared
        manager.clearUser()

        manager.initializeUser(role: .user)
        XCTAssertEqual(manager.currentUser?.role, .user)

        manager.initializeUser(role: .professional)
        XCTAssertEqual(manager.currentUser?.role, .professional)
    }

    // MARK: - Annotation Service Tests

    func testAnnotationServiceCreation() {
        let service = AnnotationService()
        XCTAssertNotNil(service)
        XCTAssertTrue(service.annotations.isEmpty)
    }

    func testDrawingAnnotation() {
        let service = AnnotationService()

        service.startDrawing(at: CGPoint(x: 0, y: 0))
        service.continueDrawing(to: CGPoint(x: 50, y: 50))
        service.continueDrawing(to: CGPoint(x: 100, y: 100))
        service.endDrawing()

        XCTAssertEqual(service.annotations.count, 1)
        XCTAssertEqual(service.annotations.first?.type, .drawing)
        XCTAssertEqual(service.annotations.first?.points.count, 3)
    }

    func testPointerAnnotation() {
        let service = AnnotationService()

        service.createPointer(at: CGPoint(x: 100, y: 100))

        XCTAssertEqual(service.annotations.count, 1)
        XCTAssertEqual(service.annotations.first?.type, .pointer)
        XCTAssertEqual(service.annotations.first?.animationType, .pulse)
    }

    func testArrowAnnotation() {
        let service = AnnotationService()

        service.createArrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))

        XCTAssertEqual(service.annotations.count, 1)
        XCTAssertEqual(service.annotations.first?.type, .arrow)
        XCTAssertEqual(service.annotations.first?.points.count, 2)
    }

    func testCircleAnnotation() {
        let service = AnnotationService()

        service.createCircle(center: CGPoint(x: 100, y: 100), radius: 50)

        XCTAssertEqual(service.annotations.count, 1)
        XCTAssertEqual(service.annotations.first?.type, .circle)
    }

    func testClearAnnotations() {
        let service = AnnotationService()

        service.createPointer(at: CGPoint(x: 0, y: 0))
        service.createPointer(at: CGPoint(x: 100, y: 100))

        XCTAssertEqual(service.annotations.count, 2)

        service.clearAll()

        XCTAssertTrue(service.annotations.isEmpty)
    }

    func testUndoAnnotation() {
        let service = AnnotationService()

        service.createPointer(at: CGPoint(x: 0, y: 0))
        service.createPointer(at: CGPoint(x: 100, y: 100))

        XCTAssertEqual(service.annotations.count, 2)

        service.undo()

        XCTAssertEqual(service.annotations.count, 1)
    }

    // MARK: - Video Stabilizer Tests

    func testVideoStabilizerCreation() {
        let stabilizer = VideoStabilizer()
        XCTAssertNotNil(stabilizer)
        XCTAssertTrue(stabilizer.config.enabled)
    }

    func testStabilizationConfig() {
        let stabilizer = VideoStabilizer()

        var config = VideoStabilizer.Config()
        config.enabled = false
        config.smoothingFactor = 0.8

        stabilizer.updateConfig(config)

        XCTAssertFalse(stabilizer.config.enabled)
        XCTAssertEqual(stabilizer.config.smoothingFactor, 0.8)
    }

    func testStabilizationTransform() {
        let stabilizer = VideoStabilizer()

        let transform = stabilizer.stabilizationTransform()

        // When not moving, transform should be identity
        XCTAssertEqual(transform, .identity)
    }

    // MARK: - Model Tests

    func testUserModel() {
        let user = User(role: .user, name: "Test User")

        XCTAssertFalse(user.id.isEmpty)
        XCTAssertEqual(user.role, .user)
        XCTAssertEqual(user.name, "Test User")
        XCTAssertEqual(user.shortId.count, 6)
    }

    func testAnnotationModel() {
        let annotation = Annotation(
            type: .drawing,
            points: [AnnotationPoint(x: 0, y: 0)],
            color: "#FF0000",
            strokeWidth: 4
        )

        XCTAssertFalse(annotation.id.isEmpty)
        XCTAssertEqual(annotation.type, .drawing)
        XCTAssertEqual(annotation.color, "#FF0000")
        XCTAssertEqual(annotation.strokeWidth, 4)
    }

    func testCallSessionModel() {
        let session = CallSession(userId: "test-user-id", state: .idle)

        XCTAssertFalse(session.id.isEmpty)
        XCTAssertEqual(session.userId, "test-user-id")
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(session.annotations.isEmpty)
        XCTAssertFalse(session.isVideoFrozen)
    }

    // MARK: - Color Extension Tests

    func testColorFromHex() {
        let color = Color(hex: "#FF0000")
        XCTAssertNotNil(color)

        let colorWithoutHash = Color(hex: "00FF00")
        XCTAssertNotNil(colorWithoutHash)
    }

    func testColorToHex() {
        let red = Color.red
        let hex = red.toHex()
        XCTAssertNotNil(hex)
    }

    // MARK: - Kalman Filter Tests

    func testKalmanFilter() {
        let filter = KalmanFilter(processNoise: 0.01, measurementNoise: 0.1)

        // Apply some measurements
        var result: Float = 0
        for i in 0..<10 {
            result = filter.update(measurement: Float(i))
        }

        // Filter should smooth the values
        XCTAssertLessThan(result, 9)
        XCTAssertGreaterThan(result, 0)
    }

    func testKalmanFilterReset() {
        let filter = KalmanFilter(processNoise: 0.01, measurementNoise: 0.1)

        _ = filter.update(measurement: 100)
        filter.reset()
        let result = filter.update(measurement: 0)

        XCTAssertEqual(result, 0)
    }

    // MARK: - Call Manager Tests

    func testCallManagerSingleton() {
        let manager1 = CallManager.shared
        let manager2 = CallManager.shared

        XCTAssertTrue(manager1 === manager2)
    }

    func testInitialCallState() {
        let manager = CallManager.shared

        XCTAssertEqual(manager.callState, .idle)
        XCTAssertNil(manager.currentSession)
        XCTAssertNil(manager.incomingCall)
    }

    func testFormattedDuration() {
        let manager = CallManager.shared

        // Set call duration manually for testing
        // This tests the formatting logic

        XCTAssertEqual(manager.formattedDuration, "00:00")
    }
}

// MARK: - Performance Tests

extension NovaidAssistTests {

    func testAnnotationPerformance() {
        let service = AnnotationService()

        measure {
            for _ in 0..<1000 {
                service.createPointer(at: CGPoint(x: CGFloat.random(in: 0...400), y: CGFloat.random(in: 0...800)))
            }
            service.clearAll()
        }
    }

    func testKalmanFilterPerformance() {
        let filter = KalmanFilter()

        measure {
            for _ in 0..<10000 {
                _ = filter.update(measurement: Float.random(in: -1...1))
            }
        }
    }
}
