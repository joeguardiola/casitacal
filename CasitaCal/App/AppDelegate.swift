import CloudKit
@preconcurrency import GoogleSignIn
import UIKit

/// Hooks SwiftUI can't provide on its own: accepting iCloud share invites.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// App was launched by tapping an invite link.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let metadata = options.cloudKitShareMetadata {
            Task { @MainActor in await Persistence.shared.acceptShare(metadata) }
        }
    }

    /// Invite link tapped while the app was already running.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in await Persistence.shared.acceptShare(metadata) }
    }

    /// Google sign-in redirect fallback (SwiftUI's onOpenURL may not fire with a custom scene delegate).
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            _ = GIDSignIn.sharedInstance.handle(context.url)
        }
    }
}
