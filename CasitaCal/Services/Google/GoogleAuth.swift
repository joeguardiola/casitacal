@preconcurrency import GoogleSignIn
import Observation
import UIKit

/// Wraps Google Sign-In. Tokens are stored by the SDK in the Keychain — never in files or source.
@MainActor
@Observable
final class GoogleAuth {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(email: String, name: String)
    }

    static let scopes = [
        "https://www.googleapis.com/auth/calendar.events",
        "https://www.googleapis.com/auth/calendar.readonly",
    ]

    private(set) var state: State = .unknown
    private(set) var lastError: String?

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    /// Whether Info.plist got a client ID from Config/Local.xcconfig.
    var isConfigured: Bool {
        let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        return id.hasSuffix(".apps.googleusercontent.com")
    }

    func restore() async {
        guard isConfigured else { state = .signedOut; return }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            apply(user)
        } catch {
            state = .signedOut
        }
    }

    func signIn() async {
        lastError = nil
        guard isConfigured else {
            lastError = "Missing GOOGLE_CLIENT_ID in Config/Local.xcconfig."
            return
        }
        guard let presenter = Self.topViewController() else { return }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: Self.scopes
            )
            let granted = Set(result.user.grantedScopes ?? [])
            if !Set(Self.scopes).isSubset(of: granted) {
                lastError = "Calendar access wasn't granted. Sign in again and allow calendar access."
            }
            apply(result.user)
        } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
            // User closed the sheet — not an error.
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        state = .signedOut
    }

    /// A fresh access token, refreshing if it's about to expire.
    func accessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            state = .signedOut
            throw GoogleCalendarError.notSignedIn
        }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }

    func handle(url: URL) {
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    private func apply(_ user: GIDGoogleUser) {
        state = .signedIn(
            email: user.profile?.email ?? "Google account",
            name: user.profile?.name ?? ""
        )
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
