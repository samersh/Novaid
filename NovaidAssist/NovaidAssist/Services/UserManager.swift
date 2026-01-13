import Foundation
import SwiftUI

/// Manages user identification and persistence
class UserManager: ObservableObject {
    static let shared = UserManager()

    private let userDefaultsKey = "com.novaid.assist.user"

    @Published var currentUser: User?
    @Published var isInitialized: Bool = false

    private init() {
        loadUser()
    }

    /// Initialize or create a user with the specified role
    func initializeUser(role: UserRole) {
        if let existingUser = currentUser, existingUser.role == role {
            isInitialized = true
            return
        }

        let newUser = User(
            id: generateUniqueId(),
            role: role
        )

        currentUser = newUser
        saveUser(newUser)
        isInitialized = true
    }

    /// Generate a unique user ID
    private func generateUniqueId() -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let random1 = String(format: "%06x", Int.random(in: 0...0xFFFFFF))
        let random2 = String(format: "%06x", Int.random(in: 0...0xFFFFFF))
        return "\(timestamp)-\(random1)-\(random2)"
    }

    /// Get short display ID
    var shortId: String {
        currentUser?.shortId ?? "------"
    }

    /// Get full user ID
    var userId: String? {
        currentUser?.id
    }

    /// Load user from UserDefaults
    private func loadUser() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let user = try? JSONDecoder().decode(User.self, from: data) else {
            return
        }
        currentUser = user
        isInitialized = true
    }

    /// Save user to UserDefaults
    private func saveUser(_ user: User) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    /// Clear user data
    func clearUser() {
        currentUser = nil
        isInitialized = false
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    /// Update user role
    func switchRole(to role: UserRole) {
        guard var user = currentUser else { return }
        user.role = role
        currentUser = user
        saveUser(user)
    }
}
