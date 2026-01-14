import SwiftUI
import UIKit

/// Manager for controlling device orientation lock
class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    @Published var orientationLock: UIInterfaceOrientationMask = .all

    private init() {}

    /// Lock to landscape orientation
    func lockLandscape() {
        orientationLock = .landscape

        // Force rotation to landscape
        if #available(iOS 16.0, *) {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        }

        UINavigationController.attemptRotationToDeviceOrientation()
    }

    /// Lock to portrait orientation
    func lockPortrait() {
        orientationLock = .portrait

        if #available(iOS 16.0, *) {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }

        UINavigationController.attemptRotationToDeviceOrientation()
    }

    /// Unlock all orientations
    func unlock() {
        orientationLock = .all
    }
}

/// AppDelegate for handling orientation
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationManager.shared.orientationLock
    }
}

/// View modifier to lock orientation
struct LandscapeLockModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                if isActive {
                    OrientationManager.shared.lockLandscape()
                }
            }
            .onDisappear {
                OrientationManager.shared.unlock()
            }
    }
}

extension View {
    func landscapeLock(_ active: Bool = true) -> some View {
        modifier(LandscapeLockModifier(isActive: active))
    }
}
