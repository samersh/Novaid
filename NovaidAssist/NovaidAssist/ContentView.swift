import SwiftUI

struct ContentView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var callManager: CallManager
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else if userManager.currentUser == nil {
                RoleSelectionView()
                    .transition(.opacity)
            } else {
                MainNavigationView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: showSplash)
        .animation(.easeInOut(duration: 0.3), value: userManager.currentUser?.role)
        .onAppear {
            // Show splash for 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Role Selection View
struct RoleSelectionView: View {
    @EnvironmentObject var userManager: UserManager

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "#0f0f23")!, Color(hex: "#1a1a2e")!],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                // Logo
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#4361ee")!)
                            .frame(width: 100, height: 100)
                            .shadow(color: Color(hex: "#4361ee")!.opacity(0.5), radius: 20)

                        Text("N")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("Novaid")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)

                    Text("Remote Assistance Platform")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Text("Select your role")
                    .font(.title3)
                    .foregroundColor(.gray)

                // Role buttons
                VStack(spacing: 16) {
                    RoleButton(
                        icon: "person.fill",
                        title: "User",
                        description: "Get remote assistance from a professional",
                        color: Color(hex: "#4361ee")!
                    ) {
                        userManager.initializeUser(role: .user)
                    }

                    RoleButton(
                        icon: "person.badge.shield.checkmark.fill",
                        title: "Professional",
                        description: "Provide remote assistance to users",
                        color: Color(hex: "#e94560")!
                    ) {
                        userManager.initializeUser(role: .professional)
                    }
                }
                .padding(.horizontal)

                Spacer()

                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(.top, 60)
        }
    }
}

// MARK: - Role Button
struct RoleButton: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)
                    .frame(width: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(color, lineWidth: 2)
                    )
            )
        }
    }
}

// MARK: - Main Navigation View
struct MainNavigationView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var callManager: CallManager

    var body: some View {
        NavigationStack {
            Group {
                if userManager.currentUser?.role == .user {
                    UserHomeView()
                } else {
                    ProfessionalHomeView()
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(UserManager.shared)
        .environmentObject(CallManager.shared)
}
