import SwiftUI

/// Overlay view for displaying AR annotations
struct AnnotationOverlayView: View {
    let annotations: [Annotation]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Render each annotation
                ForEach(annotations) { annotation in
                    AnnotationShape(annotation: annotation)
                }
            }
        }
        .allowsHitTesting(false) // Pass through touches
    }
}

/// Shape view for individual annotation
struct AnnotationShape: View {
    let annotation: Annotation

    var body: some View {
        switch annotation.type {
        case .drawing:
            DrawingPath(points: annotation.points)
                .stroke(
                    annotation.swiftUIColor,
                    style: StrokeStyle(
                        lineWidth: annotation.strokeWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

        case .arrow:
            if annotation.points.count >= 2 {
                ArrowShape(
                    start: annotation.points[0].cgPoint,
                    end: annotation.points[1].cgPoint
                )
                .stroke(annotation.swiftUIColor, lineWidth: annotation.strokeWidth)
            }

        case .circle:
            if annotation.points.count >= 2 {
                let center = annotation.points[0].cgPoint
                let radius = annotation.points[1].x

                Circle()
                    .stroke(annotation.swiftUIColor, lineWidth: annotation.strokeWidth)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
            }

        case .pointer, .animation:
            if let point = annotation.points.first {
                AnimatedPointer(
                    position: point.cgPoint,
                    color: annotation.swiftUIColor,
                    animationType: annotation.animationType ?? .pulse
                )
            }

        case .text:
            if let point = annotation.points.first,
               let text = annotation.text {
                Text(text)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(annotation.swiftUIColor)
                    .position(point.cgPoint)
            }
        }
    }
}

/// Path for freehand drawing
struct DrawingPath: Shape {
    let points: [AnnotationPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard let first = points.first else { return path }

        path.move(to: first.cgPoint)

        for point in points.dropFirst() {
            path.addLine(to: point.cgPoint)
        }

        return path
    }
}

/// Arrow shape
struct ArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let headLength: CGFloat = 20
    let headAngle: CGFloat = .pi / 6

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Main line
        path.move(to: start)
        path.addLine(to: end)

        // Arrow head
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

/// Animated pointer marker
struct AnimatedPointer: View {
    let position: CGPoint
    let color: Color
    let animationType: AnimationType

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Outer pulse
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 50, height: 50)
                .scaleEffect(isAnimating ? 1.5 : 1.0)
                .opacity(isAnimating ? 0 : 0.5)

            // Inner circle
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .scaleEffect(animationType == .bounce && isAnimating ? 1.2 : 1.0)
        }
        .position(position)
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        switch animationType {
        case .pulse:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }

        case .bounce:
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                isAnimating = true
            }

        case .highlight:
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        AnnotationOverlayView(annotations: [
            Annotation(
                type: .drawing,
                points: [
                    AnnotationPoint(x: 50, y: 100),
                    AnnotationPoint(x: 100, y: 150),
                    AnnotationPoint(x: 150, y: 100)
                ],
                color: "#FF0000"
            ),
            Annotation(
                type: .arrow,
                points: [
                    AnnotationPoint(x: 200, y: 200),
                    AnnotationPoint(x: 300, y: 300)
                ],
                color: "#00FF00"
            ),
            Annotation(
                type: .circle,
                points: [
                    AnnotationPoint(x: 200, y: 400),
                    AnnotationPoint(x: 50, y: 50)
                ],
                color: "#0000FF"
            ),
            Annotation(
                type: .pointer,
                points: [AnnotationPoint(x: 300, y: 500)],
                color: "#FFFF00",
                animationType: .pulse
            )
        ])
    }
}
