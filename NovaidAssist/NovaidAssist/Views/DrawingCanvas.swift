import SwiftUI

/// Canvas view for drawing annotations
struct DrawingCanvasView: View {
    @ObservedObject var annotationService: AnnotationService
    var onAnnotationCreated: ((Annotation) -> Void)?

    @State private var currentPoints: [CGPoint] = []
    @State private var startPoint: CGPoint?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent overlay to capture touches
                Color.clear

                // Current drawing preview
                if !currentPoints.isEmpty && annotationService.selectedTool == .pen {
                    CurrentDrawingPath(points: currentPoints)
                        .stroke(
                            annotationService.selectedColor,
                            style: StrokeStyle(
                                lineWidth: annotationService.strokeWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }

                // Arrow preview
                if let start = startPoint,
                   annotationService.selectedTool == .arrow,
                   let end = currentPoints.last {
                    ArrowPreview(start: start, end: end)
                        .stroke(
                            annotationService.selectedColor,
                            lineWidth: annotationService.strokeWidth
                        )
                }

                // Circle preview
                if let start = startPoint,
                   annotationService.selectedTool == .circle,
                   let end = currentPoints.last {
                    let radius = hypot(end.x - start.x, end.y - start.y)
                    Circle()
                        .stroke(annotationService.selectedColor, lineWidth: annotationService.strokeWidth)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(start)
                }
            }
            .contentShape(Rectangle()) // Make entire area tappable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        canvasSize = geometry.size
                        handleDrag(value, in: geometry.size)
                    }
                    .onEnded { value in
                        canvasSize = geometry.size
                        handleDragEnd(value, in: geometry.size)
                    }
            )
            .onAppear {
                canvasSize = geometry.size
            }
        }
    }

    private func handleDrag(_ value: DragGesture.Value, in size: CGSize) {
        let location = value.location

        switch annotationService.selectedTool {
        case .pen:
            currentPoints.append(location)

        case .arrow, .circle:
            if startPoint == nil {
                startPoint = location
            }
            currentPoints = [location]

        case .pointer:
            // Pointer creates on tap end
            break
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value, in size: CGSize) {
        let location = value.location

        switch annotationService.selectedTool {
        case .pen:
            if currentPoints.count >= 2 {
                // Create annotation with normalized coordinates
                let normalizedPoints = currentPoints.map { point in
                    AnnotationPoint.normalized(from: point, in: size)
                }

                let annotation = Annotation(
                    type: .drawing,
                    points: normalizedPoints,
                    color: annotationService.selectedColor.toHex() ?? "#FF0000",
                    strokeWidth: annotationService.strokeWidth,
                    isComplete: true
                )

                annotationService.annotations.append(annotation)
                onAnnotationCreated?(annotation)
                print("[Drawing] Created pen annotation with \(normalizedPoints.count) points")
            }
            currentPoints.removeAll()

        case .arrow:
            if let start = startPoint {
                let normalizedStart = AnnotationPoint.normalized(from: start, in: size)
                let normalizedEnd = AnnotationPoint.normalized(from: location, in: size)

                let annotation = Annotation(
                    type: .arrow,
                    points: [normalizedStart, normalizedEnd],
                    color: annotationService.selectedColor.toHex() ?? "#FF0000",
                    strokeWidth: annotationService.strokeWidth,
                    isComplete: true
                )

                annotationService.annotations.append(annotation)
                onAnnotationCreated?(annotation)
                print("[Drawing] Created arrow annotation")
            }
            startPoint = nil
            currentPoints.removeAll()

        case .circle:
            if let start = startPoint {
                let radius = hypot(location.x - start.x, location.y - start.y)
                let normalizedCenter = AnnotationPoint.normalized(from: start, in: size)
                // Store radius as normalized (relative to width)
                let normalizedRadius = AnnotationPoint(x: radius / size.width, y: radius / size.width, normalized: true)

                let annotation = Annotation(
                    type: .circle,
                    points: [normalizedCenter, normalizedRadius],
                    color: annotationService.selectedColor.toHex() ?? "#FF0000",
                    strokeWidth: annotationService.strokeWidth,
                    isComplete: true
                )

                annotationService.annotations.append(annotation)
                onAnnotationCreated?(annotation)
                print("[Drawing] Created circle annotation")
            }
            startPoint = nil
            currentPoints.removeAll()

        case .pointer:
            let normalizedPoint = AnnotationPoint.normalized(from: location, in: size)

            let annotation = Annotation(
                type: .pointer,
                points: [normalizedPoint],
                color: annotationService.selectedColor.toHex() ?? "#FF0000",
                strokeWidth: annotationService.strokeWidth,
                animationType: .pulse,
                isComplete: true
            )

            annotationService.annotations.append(annotation)
            onAnnotationCreated?(annotation)
            print("[Drawing] Created pointer annotation")
        }
    }
}

/// Path for current drawing
struct CurrentDrawingPath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard let first = points.first else { return path }

        path.move(to: first)

        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }
}

/// Arrow preview while drawing
struct ArrowPreview: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: start)
        path.addLine(to: end)

        // Arrow head
        let headLength: CGFloat = 20
        let headAngle: CGFloat = .pi / 6
        let angle = atan2(end.y - start.y, end.x - start.x)

        let arrowPoint1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )

        let arrowPoint2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        path.move(to: end)
        path.addLine(to: arrowPoint1)
        path.move(to: end)
        path.addLine(to: arrowPoint2)

        return path
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        DrawingCanvasView(annotationService: AnnotationService())
    }
}
