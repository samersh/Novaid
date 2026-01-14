import SwiftUI
import UIKit

// MARK: - App Delegate for Orientation Control
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationManager.shared.orientationLock
    }
}

@main
struct NovaidAssistApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
