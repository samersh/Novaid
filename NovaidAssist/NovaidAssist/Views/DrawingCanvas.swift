import SwiftUI

/// Canvas view for drawing annotations
struct DrawingCanvasView: View {
    @ObservedObject var annotationService: AnnotationService
    @State private var currentPoints: [CGPoint] = []
    @State private var startPoint: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
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
                        handleDrag(value, in: geometry.size)
                    }
                    .onEnded { value in
                        handleDragEnd(value, in: geometry.size)
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        // Handle tap for pointer tool
                        // Location will come from drag gesture
                    }
            )
        }
    }

    private func handleDrag(_ value: DragGesture.Value, in size: CGSize) {
        let location = value.location

        switch annotationService.selectedTool {
        case .pen:
            if currentPoints.isEmpty {
                annotationService.startDrawing(at: location)
            }
            currentPoints.append(location)
            annotationService.continueDrawing(to: location)

        case .arrow, .circle:
            if startPoint == nil {
                startPoint = location
            }
            currentPoints = [location]

        case .pointer:
            // Pointer creates on tap, handled in onEnded
            break
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value, in size: CGSize) {
        let location = value.location

        switch annotationService.selectedTool {
        case .pen:
            annotationService.endDrawing()
            currentPoints.removeAll()

        case .arrow:
            if let start = startPoint {
                annotationService.createArrow(from: start, to: location)
            }
            startPoint = nil
            currentPoints.removeAll()

        case .circle:
            if let start = startPoint {
                let radius = hypot(location.x - start.x, location.y - start.y)
                annotationService.createCircle(center: start, radius: radius)
            }
            startPoint = nil
            currentPoints.removeAll()

        case .pointer:
            annotationService.createPointer(at: location)
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
