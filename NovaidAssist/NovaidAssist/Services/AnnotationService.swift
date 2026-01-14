import Foundation
import SwiftUI

/// Service for managing AR annotations
class AnnotationService: ObservableObject {
    // MARK: - Published Properties
    @Published var annotations: [Annotation] = []
    @Published var currentAnnotation: Annotation?
    @Published var selectedTool: AnnotationTool = .pen
    @Published var selectedColor: Color = .red
    @Published var strokeWidth: CGFloat = 4

    // MARK: - Callbacks
    var onAnnotationCreated: ((Annotation) -> Void)?
    var onAnnotationUpdated: ((Annotation) -> Void)?
    var onAnnotationCompleted: ((Annotation) -> Void)?

    // MARK: - Tool Types
    enum AnnotationTool: String, CaseIterable {
        case pen = "pencil"
        case arrow = "arrow.right"
        case circle = "circle"
        case pointer = "hand.point.up.fill"

        var icon: String { rawValue }
    }

    // MARK: - Available Colors
    static let availableColors: [Color] = [
        .red, .green, .blue, .yellow, .orange, .purple, .white
    ]

    // MARK: - Drawing Methods

    /// Start a new drawing annotation
    func startDrawing(at point: CGPoint) {
        let colorHex = selectedColor.toHex() ?? "#FF0000"

        let annotation = Annotation(
            type: .drawing,
            points: [AnnotationPoint(point)],
            color: colorHex,
            strokeWidth: strokeWidth
        )

        currentAnnotation = annotation
        annotations.append(annotation)
    }

    /// Continue drawing
    func continueDrawing(to point: CGPoint) {
        guard var annotation = currentAnnotation,
              annotation.type == .drawing else { return }

        annotation.points.append(AnnotationPoint(point))
        currentAnnotation = annotation

        // Update in annotations array
        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[index] = annotation
        }

        onAnnotationUpdated?(annotation)
    }

    /// End drawing
    func endDrawing() {
        guard var annotation = currentAnnotation else { return }

        annotation.isComplete = true
        currentAnnotation = nil

        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[index] = annotation
        }

        onAnnotationCompleted?(annotation)
        onAnnotationCreated?(annotation)
    }

    // MARK: - Quick Annotations

    /// Create a pointer annotation
    func createPointer(at point: CGPoint) {
        let colorHex = selectedColor.toHex() ?? "#FF0000"

        let annotation = Annotation(
            type: .pointer,
            points: [AnnotationPoint(point)],
            color: colorHex,
            strokeWidth: strokeWidth,
            animationType: .pulse,
            isComplete: true
        )

        annotations.append(annotation)
        onAnnotationCreated?(annotation)
    }

    /// Create an arrow annotation
    func createArrow(from start: CGPoint, to end: CGPoint) {
        let colorHex = selectedColor.toHex() ?? "#FF0000"

        let annotation = Annotation(
            type: .arrow,
            points: [AnnotationPoint(start), AnnotationPoint(end)],
            color: colorHex,
            strokeWidth: strokeWidth,
            isComplete: true
        )

        annotations.append(annotation)
        onAnnotationCreated?(annotation)
    }

    /// Create a circle annotation
    func createCircle(center: CGPoint, radius: CGFloat) {
        let colorHex = selectedColor.toHex() ?? "#FF0000"

        let annotation = Annotation(
            type: .circle,
            points: [AnnotationPoint(center), AnnotationPoint(x: radius, y: radius)],
            color: colorHex,
            strokeWidth: strokeWidth,
            isComplete: true
        )

        annotations.append(annotation)
        onAnnotationCreated?(annotation)
    }

    /// Create a text annotation
    func createText(at point: CGPoint, text: String) {
        let colorHex = selectedColor.toHex() ?? "#FF0000"

        let annotation = Annotation(
            type: .text,
            points: [AnnotationPoint(point)],
            color: colorHex,
            strokeWidth: strokeWidth,
            text: text,
            isComplete: true
        )

        annotations.append(annotation)
        onAnnotationCreated?(annotation)
    }

    /// Create an animated annotation
    func createAnimation(at point: CGPoint, type: AnimationType) {
        let colorHex = selectedColor.toHex() ?? "#FF0000"

        let annotation = Annotation(
            type: .animation,
            points: [AnnotationPoint(point)],
            color: colorHex,
            strokeWidth: strokeWidth,
            animationType: type,
            isComplete: true
        )

        annotations.append(annotation)
        onAnnotationCreated?(annotation)
    }

    // MARK: - Management

    /// Add remote annotation
    func addRemoteAnnotation(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    /// Remove annotation
    func removeAnnotation(_ id: String) {
        annotations.removeAll { $0.id == id }
    }

    /// Clear all annotations
    func clearAll() {
        annotations.removeAll()
        currentAnnotation = nil
    }

    /// Undo last annotation
    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
    }

    /// Get annotations since timestamp
    func getAnnotationsSince(_ timestamp: Date) -> [Annotation] {
        annotations.filter { $0.timestamp >= timestamp }
    }
}

// MARK: - Touch Handler for Canvas
class AnnotationTouchHandler {
    private let service: AnnotationService
    private var startPoint: CGPoint?
    private var isDrawing = false

    init(service: AnnotationService) {
        self.service = service
    }

    func handleTouchBegan(at point: CGPoint) {
        startPoint = point

        switch service.selectedTool {
        case .pen:
            service.startDrawing(at: point)
            isDrawing = true

        case .pointer:
            service.createPointer(at: point)

        case .arrow, .circle:
            // Wait for touch end to create
            break
        }
    }

    func handleTouchMoved(to point: CGPoint) {
        if isDrawing && service.selectedTool == .pen {
            service.continueDrawing(to: point)
        }
    }

    func handleTouchEnded(at point: CGPoint) {
        guard let start = startPoint else { return }

        switch service.selectedTool {
        case .pen:
            service.endDrawing()
            isDrawing = false

        case .arrow:
            service.createArrow(from: start, to: point)

        case .circle:
            let radius = hypot(point.x - start.x, point.y - start.y)
            service.createCircle(center: start, radius: radius)

        case .pointer:
            // Already created on touch begin
            break
        }

        startPoint = nil
    }

    func handleTouchCancelled() {
        if isDrawing {
            service.endDrawing()
            isDrawing = false
        }
        startPoint = nil
    }
}
