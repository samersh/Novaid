import SwiftUI

/// Overlay view for displaying AR annotations
struct AnnotationOverlayView: View {
    let annotations: [Annotation]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Render each annotation with geometry for coordinate conversion
                ForEach(annotations) { annotation in
                    AnnotationShape(annotation: annotation, containerSize: geometry.size)
                }
            }
        }
        .allowsHitTesting(false) // Pass through touches
    }
}

/// Shape view for individual annotation with 3D effects
struct AnnotationShape: View {
    let annotation: Annotation
    let containerSize: CGSize

    var body: some View {
        switch annotation.type {
        case .drawing:
            DrawingPath(points: annotation.points, containerSize: containerSize)
                .stroke(
                    annotation.swiftUIColor,
                    style: StrokeStyle(
                        lineWidth: annotation.strokeWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: annotation.swiftUIColor.opacity(0.5), radius: 8, x: 0, y: 4)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

        case .arrow:
            if annotation.points.count >= 2 {
                let start = annotation.points[0].toAbsolute(in: containerSize)
                let end = annotation.points[1].toAbsolute(in: containerSize)
                ArrowShape(start: start, end: end)
                    .stroke(annotation.swiftUIColor, lineWidth: annotation.strokeWidth)
                    .shadow(color: annotation.swiftUIColor.opacity(0.6), radius: 10, x: 0, y: 5)
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
            }

        case .circle:
            if annotation.points.count >= 2 {
                let center = annotation.points[0].toAbsolute(in: containerSize)
                // Radius is stored as normalized relative to width
                let radiusNormalized = annotation.points[1].x
                let radius = radiusNormalized * containerSize.width

                ZStack {
                    // Outer glow
                    Circle()
                        .stroke(annotation.swiftUIColor.opacity(0.3), lineWidth: annotation.strokeWidth + 4)
                        .frame(width: radius * 2, height: radius * 2)
                        .blur(radius: 4)

                    // Main circle with 3D effect
                    Circle()
                        .stroke(annotation.swiftUIColor, lineWidth: annotation.strokeWidth)
                        .frame(width: radius * 2, height: radius * 2)
                }
                .position(center)
                .shadow(color: annotation.swiftUIColor.opacity(0.6), radius: 12, x: 0, y: 6)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 3)
            }

        case .pointer, .animation:
            if let point = annotation.points.first {
                let absolutePoint = point.toAbsolute(in: containerSize)
                AnimatedPointer(
                    position: absolutePoint,
                    color: annotation.swiftUIColor,
                    animationType: annotation.animationType ?? .pulse
                )
            }

        case .text:
            if let point = annotation.points.first,
               let text = annotation.text {
                let absolutePoint = point.toAbsolute(in: containerSize)
                Text(text)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(annotation.swiftUIColor)
                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
                    .shadow(color: annotation.swiftUIColor.opacity(0.5), radius: 8, x: 0, y: 4)
                    .position(absolutePoint)
            }
        }
    }
}

/// Path for freehand drawing
struct DrawingPath: Shape {
    let points: [AnnotationPoint]
    let containerSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard let first = points.first else { return path }

        // Convert normalized coordinates to absolute
        let firstAbsolute = first.toAbsolute(in: containerSize)
        path.move(to: firstAbsolute)

        for point in points.dropFirst() {
            let absolutePoint = point.toAbsolute(in: containerSize)
            path.addLine(to: absolutePoint)
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
            // Outer glow ring
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 60, height: 60)
                .blur(radius: 8)

            // Outer pulse
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 50, height: 50)
                .scaleEffect(isAnimating ? 1.5 : 1.0)
                .opacity(isAnimating ? 0 : 0.5)

            // Middle ring with 3D effect
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [color, color.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 40, height: 40)
                .shadow(color: color.opacity(0.6), radius: 8, x: 0, y: 4)

            // Inner circle with gradient for 3D depth
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.9), color],
                        center: .topLeading,
                        startRadius: 5,
                        endRadius: 20
                    )
                )
                .frame(width: 30, height: 30)
                .scaleEffect(animationType == .bounce && isAnimating ? 1.2 : 1.0)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
        }
        .position(position)
        .shadow(color: color.opacity(0.7), radius: 15, x: 0, y: 7)
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
                    AnnotationPoint(x: 0.1, y: 0.2, normalized: true),
                    AnnotationPoint(x: 0.2, y: 0.3, normalized: true),
                    AnnotationPoint(x: 0.3, y: 0.2, normalized: true)
                ],
                color: "#FF0000"
            ),
            Annotation(
                type: .arrow,
                points: [
                    AnnotationPoint(x: 0.4, y: 0.4, normalized: true),
                    AnnotationPoint(x: 0.6, y: 0.6, normalized: true)
                ],
                color: "#00FF00"
            ),
            Annotation(
                type: .circle,
                points: [
                    AnnotationPoint(x: 0.5, y: 0.7, normalized: true),
                    AnnotationPoint(x: 0.1, y: 0.1, normalized: true)  // radius
                ],
                color: "#0000FF"
            ),
            Annotation(
                type: .pointer,
                points: [AnnotationPoint(x: 0.7, y: 0.8, normalized: true)],
                color: "#FFFF00",
                animationType: .pulse
            )
        ])
    }
}
