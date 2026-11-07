import CloudKit
import SwiftUI
import UIKit

/// Settings → Family sharing: invite another Apple ID (e.g. a spouse) to the household.
struct HouseholdSharingSection: View {
    @Environment(Persistence.self) private var persistence
    @State private var isPreparing = false
    @State private var error: String?
    @State private var coordinator = ShareCoordinator()

    var body: some View {
        Section {
            if !persistence.usesCloudKit {
                Label("Turns on with the paid Apple Developer account", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
            } else if persistence.isParticipant {
                Label("Joined a household shared with you", systemImage: "person.2.fill")
                Text("Chores, lists, meals and family members sync with the kitchen iPad.")
                    .foregroundStyle(.secondary)
            } else {
                let share = persistence.existingShare()
                let others = share?.participants.filter { $0.role != .owner } ?? []
                if others.isEmpty {
                    Label("Only on your Apple ID so far", systemImage: "person.fill")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(others, id: \.self) { p in
                        let name = p.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
                        LabeledContent(name ?? p.userIdentity.lookupInfo?.emailAddress ?? "Invited person",
                                       value: p.acceptanceStatus == .accepted ? "Joined" : "Invited")
                    }
                }
                Button {
                    invite()
                } label: {
                    if isPreparing { ProgressView() } else {
                        Label(others.isEmpty ? "Invite family…" : "Manage sharing…", systemImage: "person.badge.plus")
                    }
                }
                .disabled(isPreparing)
            }
            if let error = error ?? persistence.lastShareError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Family sharing")
        } footer: {
            Text("Send an invite by Messages or Mail. Once accepted on their iPhone (in CasitaCal), chores, lists, meals and family members stay in sync. Phones on the same Apple ID as this iPad sync automatically — no invite needed.")
        }
    }

    private func invite() {
        isPreparing = true
        error = nil
        Task {
            defer { isPreparing = false }
            do {
                let share = try await persistence.shareForHousehold()
                coordinator.present(share: share, persistence: persistence)
            } catch {
                self.error = "Couldn't start sharing: \(error.localizedDescription)"
            }
        }
    }
}

/// Presents Apple's standard "Share with…" sheet for the household.
@MainActor
final class ShareCoordinator: NSObject, @preconcurrency UICloudSharingControllerDelegate {
    private var persistence: Persistence?

    func present(share: CKShare, persistence: Persistence) {
        self.persistence = persistence
        let controller = UICloudSharingController(share: share, container: persistence.cloudKitContainer)
        controller.delegate = self
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        guard let top = Self.topViewController() else { return }
        controller.popoverPresentationController?.sourceView = top.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(controller, animated: true)
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { "CasitaCal household" }

    func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
        UIImage(named: "Logo")?.pngData()
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("Share save failed: \(error)")
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        if let share = csc.share { persistence?.persistUpdatedShare(share) }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

/// Shown on phones (with iCloud on) until the household arrives from iCloud.
struct WaitingForHouseholdView: View {
    @Environment(Persistence.self) private var persistence

    var body: some View {
        VStack(spacing: 22) {
            Image("Logo")
                .resizable()
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text("Connecting to your household")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                Label("Same Apple ID as the kitchen iPad? Just wait a minute — it syncs automatically.", systemImage: "icloud.and.arrow.down")
                Label("Different Apple ID? On the iPad, open Settings → Family sharing → Invite family…, then tap the link on this phone.", systemImage: "envelope.open")
            }
            .foregroundStyle(Palette.inkSecondary)
            ProgressView()
            if let error = persistence.lastShareError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(32)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }
}
