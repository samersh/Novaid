import SwiftUI

@main
struct NovaidAssistApp: App {
    @StateObject private var callManager = CallManager.shared
    @StateObject private var userManager = UserManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(callManager)
                .environmentObject(userManager)
                .preferredColorScheme(.dark)
        }
    }
}
