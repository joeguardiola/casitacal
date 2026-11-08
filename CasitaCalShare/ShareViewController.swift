import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Safari → Share → CasitaCal: reads the recipe, lets you pick a day, and saves it to the
/// household (recipe box + meal plan), then waits for the iCloud upload so the kitchen iPad gets it.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.finish = { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        model.cancel = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "CasitaCalShare", code: 0))
        }
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task { await model.load(from: providers) }
    }
}

@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable { case loading, ready, saving, done(String), failed(String) }

    var phase: Phase = .loading
    var recipe: ParsedRecipe?
    var image: Data?
    var day = Calendar.app.startOfDay(for: Date())
    var slot: MealSlot = .dinner

    @ObservationIgnored var finish: () -> Void = {}
    @ObservationIgnored var cancel: () -> Void = {}

    var days: [Date] {
        (0..<10).compactMap { Calendar.app.date(byAdding: .day, value: $0, to: Calendar.app.startOfDay(for: Date())) }
    }

    func load(from providers: [NSItemProvider]) async {
        guard let url = await Self.firstURL(in: providers) else {
            phase = .failed("No web link found to share.")
            return
        }
        do {
            let fetched = try await RecipeImporter.fetch(url)
            recipe = fetched.recipe
            image = fetched.image
            phase = .ready
        } catch {
            // Keep the link even if the page can't be read.
            recipe = ParsedRecipe(title: url.host() ?? "Recipe", sourceURL: url)
            recipe?.siteName = url.host()
            phase = .ready
        }
    }

    func save(plan: Bool) async {
        guard let recipe else { return }
        // The app moves its database into the shared folder on first launch after updating;
        // until then, don't create a second (empty) one here.
        let store = Persistence.storeDirectory().appendingPathComponent("Household.sqlite")
        guard FileManager.default.fileExists(atPath: store.path) else {
            phase = .failed("Open CasitaCal once first, then try sharing again.")
            return
        }
        let persistence = Persistence.shared
        guard persistence.hasHousehold else {
            phase = .failed("This iPhone hasn't joined your household yet. Open CasitaCal first.")
            return
        }
        phase = .saving
        let saved = RecipeImporter.save(recipe, image: image, persistence: persistence)
        if plan {
            RecipeImporter.plan(saved, day: DayKey.from(day), slot: slot.rawValue, persistence: persistence)
        }
        persistence.save()
        await persistence.waitForExport(timeout: .seconds(10))
        phase = .done(plan ? "Added to \(dayLabel(day))’s \(slot.label.lowercased())" : "Saved to your recipes")
        try? await Task.sleep(for: .seconds(1.2))
        finish()
    }

    func dayLabel(_ day: Date) -> String {
        if Calendar.app.isDateInToday(day) { return "today" }
        if Calendar.app.isDateInTomorrow(day) { return "tomorrow" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    private static func firstURL(in providers: [NSItemProvider]) async -> URL? {
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { cont in
                _ = p.loadObject(ofClass: URL.self) { url, _ in cont.resume(returning: url) }
            }
            if let url, url.scheme?.hasPrefix("http") == true { return url }
        }
        for p in providers where p.canLoadObject(ofClass: String.self) {
            let text: String? = await withCheckedContinuation { cont in
                _ = p.loadObject(ofClass: String.self) { s, _ in cont.resume(returning: s) }
            }
            if let text, let url = RecipeImporter.firstLink(in: text) { return url }
        }
        return nil
    }
}

private let accent = Color(red: 0.91, green: 0.48, blue: 0.38)

struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Reading the recipe…").foregroundStyle(.secondary)
                    }
                case .ready, .saving:
                    form
                case let .done(message):
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(accent)
                        Text(message).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    }
                case let .failed(message):
                    ContentUnavailableView("Couldn't add it", systemImage: "exclamationmark.triangle", description: Text(message))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Add to CasitaCal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.cancel() } }
            }
        }
        .tint(accent)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let recipe = model.recipe { preview(recipe) }

                Text("Plan it for").font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.days, id: \.self) { day in
                            let selected = Calendar.app.isDate(day, inSameDayAs: model.day)
                            Button { model.day = day } label: {
                                VStack(spacing: 2) {
                                    Text(Calendar.app.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.abbreviated)))
                                        .font(.caption.weight(.semibold))
                                    Text(day, format: .dateTime.day()).font(.title3.weight(.bold))
                                }
                                .frame(width: 58, height: 58)
                                .foregroundStyle(selected ? .white : .primary)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selected ? accent : Color(.secondarySystemBackground)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                Picker("Meal", selection: $model.slot) {
                    ForEach(MealSlot.allCases) { Text("\($0.emoji) \($0.label)").tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 10) {
                    Button {
                        Task { await model.save(plan: true) }
                    } label: {
                        Group {
                            if model.phase == .saving { ProgressView().tint(.white) } else { Text("Add to plan") }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Just save the recipe") { Task { await model.save(plan: false) } }
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.phase == .saving)
            }
            .padding(20)
        }
    }

    private func preview(_ recipe: ParsedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data = model.image, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text(recipe.title).font(.title2.weight(.bold))
            HStack {
                if let site = recipe.siteName { Text(site) }
                if recipe.hasRecipeDetails {
                    Text("· \(recipe.ingredients.count) ingredients")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
