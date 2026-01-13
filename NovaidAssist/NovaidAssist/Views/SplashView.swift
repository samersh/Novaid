import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    @State private var showTagline = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "#0f0f23")!, Color(hex: "#1a1a2e")!],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Animated Logo
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#4361ee")!, Color(hex: "#e94560")!],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .opacity(isAnimating ? 0.5 : 1.0)

                    // Inner circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#4361ee")!, Color(hex: "#3a0ca3")!],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: Color(hex: "#4361ee")!.opacity(0.6), radius: 20)

                    // Logo text
                    Text("N")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .scaleEffect(isAnimating ? 1.0 : 0.8)

                // App name
                VStack(spacing: 8) {
                    Text("Novaid")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if showTagline {
                        Text("Remote Assistance")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }

                // Loading indicator
                if isAnimating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                        .padding(.top, 20)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                isAnimating = true
            }

            withAnimation(.easeInOut(duration: 0.5).delay(0.3)) {
                showTagline = true
            }
        }
    }
}

#Preview {
    SplashView()
}
