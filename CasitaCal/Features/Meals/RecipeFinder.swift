import SwiftUI
import WebKit

/// "Find a Recipe" for a feast-day dish: a recipe search inside the app. Open a recipe you like
/// and the bar at the bottom saves it to Recipes or puts it on that day's plan.
struct RecipeFinderSheet: View {
    let dish: String
    let searchURL: URL
    let day: Date
    /// False for ideas that aren't a dinner (desserts, drinks): those can be saved or added as a side.
    let allowDinner: Bool

    @Environment(Persistence.self) private var persistence
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var browser = RecipeBrowser()
    @State private var done: Set<Action> = []
    @State private var dinnerTitle: String?
    @State private var confirmingReplace = false

    private enum Action: Hashable { case saved, dinner, side }

    private var dayKey: String { DayKey.from(day) }
    private var dayName: String {
        Calendar.app.isDateInToday(day) ? "Tonight" : day.formatted(.dateTime.weekday(.wide))
    }
    private var hasDinner: Bool { !(dinnerTitle ?? "").isEmpty }

    var body: some View {
        NavigationStack {
            WebView(webView: browser.webView)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom) { bar }
                .navigationTitle(dish)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back", systemImage: "chevron.backward") { browser.webView.goBack() }
                            .disabled(!browser.canGoBack)
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .task {
            dinnerTitle = MealPlan.dinnerTitle(day: dayKey, context: persistence.context)
            browser.load(searchURL)
        }
        .onChange(of: browser.found?.recipe) { done = [] }
        .alert("Replace dinner?", isPresented: $confirmingReplace) {
            Button("Replace") { planDinner() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(dinnerTitle ?? "Something else") is planned that night. Replace it? Any sides stay.")
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bar: some View {
        Group {
            if let found = browser.found {
                let layout = sizeClass == .compact
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
                layout {
                    ParsedRecipeCard(recipe: found.recipe, image: found.image)
                        .frame(maxWidth: sizeClass == .compact ? .infinity : 420, alignment: .leading)
                    if sizeClass != .compact { Spacer(minLength: 0) }
                    actions
                }
            } else {
                HStack(spacing: 10) {
                    if browser.isScanning {
                        ProgressView()
                    } else {
                        Image(systemName: "fork.knife").foregroundStyle(Palette.inkSecondary)
                    }
                    Text(browser.isScanning ? "Looking for a recipe on this page…" : "Open a recipe to save it or plan it.")
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .animation(.snappy, value: browser.found?.recipe)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actionButton(.saved, title: "Save to Recipes", doneTitle: "Saved", symbol: "book.closed", action: save)
            if allowDinner {
                actionButton(.dinner, title: "\(dayName)'s Dinner", doneTitle: "Planned", symbol: "fork.knife") {
                    if hasDinner { confirmingReplace = true } else { planDinner() }
                }
            }
            if hasDinner && !done.contains(.dinner) {
                actionButton(.side, title: "Add as a Side", doneTitle: "Added as a side", symbol: "plus", action: addSide)
            }
        }
        .controlSize(.large)
        .fixedSize()
    }

    @ViewBuilder
    private func actionButton(_ kind: Action, title: String, doneTitle: String, symbol: String,
                              action: @escaping () -> Void) -> some View {
        if done.contains(kind) {
            Label(doneTitle, systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Button(title, systemImage: symbol, action: action)
                .buttonStyle(.bordered)
        }
    }

    // MARK: Actions

    /// Saves the open recipe (once per link) and returns it.
    @discardableResult
    private func saveRecipe() -> CDRecipe? {
        guard let found = browser.found else { return nil }
        let recipe = RecipeImporter.save(found.recipe, image: found.image, persistence: persistence)
        persistence.save()
        done.insert(.saved)
        return recipe
    }

    private func save() { saveRecipe() }

    private func planDinner() {
        guard let recipe = saveRecipe() else { return }
        let title = recipe.title ?? dish
        MealPlan.planDinner(title: title, recipe: recipe, day: dayKey, persistence: persistence)
        dinnerTitle = title
        done.insert(.dinner)
    }

    private func addSide() {
        guard let recipe = saveRecipe() else { return }
        if MealPlan.addSide(title: recipe.title ?? dish, recipe: recipe, day: dayKey, persistence: persistence) {
            done.insert(.side)
        }
    }
}

/// The web view plus what it found: after each page loads, the page's own HTML goes through
/// `RecipeParser`, so sites that block a separate download still work.
@MainActor
@Observable
final class RecipeBrowser: NSObject, WKNavigationDelegate {
    @ObservationIgnored let webView: WKWebView
    private(set) var canGoBack = false
    private(set) var isScanning = false
    private(set) var found: (recipe: ParsedRecipe, image: Data?)?
    @ObservationIgnored private var scan: Task<Void, Never>?

    override init() {
        let config = WKWebViewConfiguration()
        // Nothing from these searches is kept between visits.
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func load(_ url: URL) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        scan?.cancel()
        found = nil
        isScanning = false
        canGoBack = webView.canGoBack
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        canGoBack = webView.canGoBack
        startScan()
    }

    /// Some sites add their recipe data after the page loads, so look again a couple of times.
    private func startScan() {
        scan?.cancel()
        guard let url = webView.url, !Self.isSearchPage(url) else { return }
        isScanning = true
        scan = Task { [weak self] in
            for delay in [0.0, 1.5, 3.5] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                if let recipe = await self.recipeOnPage(url) {
                    self.found = (recipe, nil)
                    self.isScanning = false
                    if let imageURL = recipe.imageURL, let image = try? await RecipeImporter.downloadImage(imageURL),
                       !Task.isCancelled, self.found?.recipe == recipe {
                        self.found?.image = image
                    }
                    return
                }
            }
            self?.isScanning = false
        }
    }

    private func recipeOnPage(_ url: URL) async -> ParsedRecipe? {
        guard let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String,
              let parsed = RecipeParser.parse(html: html, url: webView.url ?? url),
              parsed.hasRecipeDetails else { return nil }
        return parsed
    }

    private static func isSearchPage(_ url: URL) -> Bool {
        (url.host() ?? "").contains("google.") && url.path().hasPrefix("/search")
    }
}

private struct WebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
