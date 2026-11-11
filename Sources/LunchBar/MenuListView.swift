import AppKit
import LunchKit
import SwiftUI

/// The day's menu: optional "Top protein" group, then stations of items.
/// Lays out at its natural height; the panel puts it in a scroll view.
struct MenuListView: View {
    let day: MenuDay
    let settings: AppSettings
    @Binding var expanded: String?
    var topItems: [MenuItem] = []
    var showsTop = false
    var nutritionLoading = false
    var nutritionNotice: String?
    var verifiedRecipes: Set<String> = []
    @Binding var filter: String
    /// Frozen copy of the Top protein rows while the pointer is over the list;
    /// nil means "show `topItems` as they are".
    @State private var visibleTop: [MenuItem]?
    @State private var hoveringMenu = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var large: Bool { day.items.count > 25 }
    private var foodPro: Bool { settings.source?.provider == .rutgersFoodPro }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if large {
                TextField("Filter menu", text: $filter, prompt: Text("Filter \(day.items.count) items"))
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
                    .accessibilityLabel("Filter items by name")
            }
            if filter.isEmpty && showsTop {
                picksGroup
            }
            if let nutritionNotice {
                Text(nutritionNotice).scaledFont(.caption1).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 6)
            }
            ForEach(day.sections) { section in
                let matches = section.items.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
                if !matches.isEmpty {
                    // Keyed on the provider's own title: display casing may change.
                    let key = (settings.source?.key ?? "") + "/" + (section.providerTitle ?? section.id)
                    let open = !filter.isEmpty || (settings.stationExpansion[key] ?? !large)
                    let photos = section.items.contains { $0.imageURL != nil }
                    if let title = section.title {
                        SectionHeader(title: title, count: matches.count, open: open) {
                            settings.stationExpansion[key] = !open
                        }
                    }
                    if open || section.title == nil {
                        ForEach(matches) { item in row(item, photos: photos) }
                    }
                }
            }
            if !filter.isEmpty && !day.items.contains(where: { $0.name.localizedCaseInsensitiveContains(filter) }) {
                Text("No items match “\(filter)”").scaledFont(.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
        .padding(.bottom, 8)
        .onHover { inside in
            hoveringMenu = inside
            if !inside && expanded == nil { visibleTop = nil }
        }
        .onChange(of: topItems) { old, _ in
            // Keep names under the pointer (and an expanded row) stable during enrichment.
            if !hoveringMenu && expanded == nil { visibleTop = nil }
            else {
                visibleTop = (visibleTop ?? old).compactMap { old in
                    guard var current = day.items.first(where: { $0.id == old.id }) else { return nil }
                    guard current.warnings(avoiding: settings.avoidedAllergens).isEmpty else { return nil }
                    current.category = old.category
                    return current
                }
            }
        }
        .onChange(of: expanded) { _, id in
            if id == nil && !hoveringMenu { visibleTop = nil }
        }
        .onChange(of: day.date) { filter = ""; visibleTop = nil }
        .onChange(of: settings.source?.key) { filter = ""; visibleTop = nil }
    }

    private var picksGroup: some View {
        let goal = settings.pickGoal
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Menu {
                    Picker("Top picks", selection: Bindable(settings).pickGoal) {
                        ForEach(PickGoal.allCases, id: \.self) { goal in Text(goal.title).tag(goal) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 4) {
                        Text("Top picks · \(goal.title)")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .scaledFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Choose what Top picks ranks by")
                .accessibilityLabel("Top picks, \(goal.title). Choose a goal")
                if nutritionLoading { ProgressView().controlSize(.mini).accessibilityLabel("Loading published nutrition") }
                Spacer()
                Text(goal.unitDescription)
                    .scaledFont(.caption1)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
            let shown = visibleTop ?? topItems
            if shown.isEmpty {
                Text("Checking published nutrition…")
                    .scaledFont(.caption1).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).frame(height: 40)
            } else {
                let photos = shown.contains { $0.imageURL != nil }
                ForEach(shown) { item in row(item, photos: photos, goal: goal) }
            }
        }
        .padding(.bottom, 4)
    }

    private func row(_ item: MenuItem, photos: Bool, goal: PickGoal? = nil) -> some View {
        MenuItemRow(item: item, avoided: settings.avoidedAllergens,
                    isFavorite: settings.isFavorite(item), isExpanded: expanded == item.id,
                    showsPhoto: photos,
                    toggleExpanded: { toggle(item) }, toggleFavorite: { settings.toggleFavorite(item) },
                    goal: goal, unknownAllergens: foodPro && !verifiedRecipes.contains(item.foodID))
    }

    private func toggle(_ item: MenuItem) {
        let change = { expanded = expanded == item.id ? nil : item.id }
        if reduceMotion { change() } else { withAnimation(.snappy(duration: 0.22), change) }
    }
}

/// A quiet, clickable station title with its item count.
private struct SectionHeader: View {
    let title: String
    let count: Int
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(title).lineLimit(2)
                Spacer(minLength: 8)
                Text("\(count)").monospacedDigit().foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .foregroundStyle(.tertiary)
            }
            .scaledFont(.subheadline, weight: .semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) items")
        .accessibilityValue(open ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Formats the figures shown on rows and in details.
enum Figures {
    static func grams(_ value: Double) -> String {
        if value >= 10 || value == value.rounded() { return "\(Int(value.rounded())) g" }
        return String(format: "%.1f g", value)
    }

    /// The Top picks figure for a goal's value.
    static func goal(_ value: Double, _ goal: PickGoal) -> String {
        switch goal {
        case .leanProtein: String(format: "%.1f g", value)
        case .lowCalorie: "\(Int(value.rounded()))"
        case .lowSodium: "\(Int(value.rounded())) mg"
        default: grams(value)
        }
    }

    static func nutrient(_ item: MenuItem, _ names: String...) -> Double? {
        item.nutrition.first { nutrient in names.contains(nutrient.name.lowercased()) && nutrient.unit == "g" }?.amount
    }
}

struct MenuItemRow: View {
    let item: MenuItem
    let avoided: Set<Allergen>
    let isFavorite: Bool
    let isExpanded: Bool
    let showsPhoto: Bool
    let toggleExpanded: () -> Void
    let toggleFavorite: () -> Void
    /// Set for rows in the Top picks group: the figure follows the goal.
    var goal: PickGoal? = nil
    var unknownAllergens = false

    @State private var isHovering = false
    @Namespace private var photoSpace
    @Environment(\.textScale) private var scale

    private var warnings: [AllergenWarning] { item.warnings(avoiding: avoided) }
    private var thumbnail: CGFloat { (48 * min(scale, 1.15)).rounded() }
    /// Expanded items lead with their photo when it is a real photo; small images
    /// (often clip art) keep the thumbnail rather than being blown up.
    private var largePhoto: Bool { isExpanded && item.imageURL.map(ImageStore.shared.isPhoto) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleExpanded) {
                Group {
                    if largePhoto { expandedHeader } else { compactHeader }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows nutrition and allergen details")
            .accessibilityAction(named: isFavorite ? "Remove from favorites" : "Add to favorites", toggleFavorite)

            if isExpanded {
                ItemDetailView(item: item, avoided: avoided, unknownAllergens: unknownAllergens,
                               isFavorite: isFavorite, toggleFavorite: toggleFavorite)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .background(isExpanded ? Color.primary.opacity(0.045) : isHovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", action: toggleFavorite)
            Button(isExpanded ? "Hide Details" : "Show Details", action: toggleExpanded)
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsPhoto {
                FoodPhoto(url: item.imageURL)
                    .matchedGeometryEffect(id: "photo", in: photoSpace)
                    .frame(width: thumbnail, height: thumbnail)
            }
            nameBlock
            Spacer(minLength: 8)
            figure.opacity(isExpanded ? 0 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, showsPhoto ? 6 : 8)
    }

    private var expandedHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            FoodPhoto(url: item.imageURL)
                .matchedGeometryEffect(id: "photo", in: photoSpace)
                .frame(maxWidth: .infinity)
                .frame(height: 176)
            nameBlock
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.name)
                    .scaledFont(largePhoto ? .headline : .body, weight: largePhoto ? .semibold : .medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }
            }
            secondaryLine
        }
    }

    /// One quiet line: an avoided-allergen warning first (it matters most), then
    /// dietary highlights, or the station for the Top picks group.
    @ViewBuilder
    private var secondaryLine: some View {
        let context: [String] = goal != nil
            ? [item.category, goal == .leanProtein ? item.protein.map { Figures.grams($0) + " protein" } : nil].compactMap { $0 }
            : Array(item.dietaryTags.prefix(2))
        // Expanded details flag avoided allergens themselves.
        let warnings = isExpanded ? [] : warnings
        if !warnings.isEmpty || !context.isEmpty {
            HStack(spacing: 6) {
                if !warnings.isEmpty {
                    Label(warningText, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                        .fontWeight(.medium)
                }
                if !context.isEmpty {
                    Text(context.joined(separator: " · ")).foregroundStyle(.secondary)
                }
            }
            .scaledFont(.caption1)
            .lineLimit(1)
        }
    }

    /// The right-hand column: calories, or in the Top picks group the goal's
    /// figure over the calories.
    @ViewBuilder
    private var figure: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let goal, goal != .lowCalorie, let value = goal.value(item) {
                Text(Figures.goal(value, goal)).scaledFont(.body, weight: .semibold)
                if let calories = item.calories {
                    Text("\(calories) cal").scaledFont(.caption1).foregroundStyle(.secondary)
                }
            } else if let calories = item.calories {
                Text("\(calories)").scaledFont(.body, weight: .semibold)
                Text("cal").scaledFont(.caption1).foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .frame(minWidth: 44 * scale, alignment: .trailing)
        .accessibilityHidden(true)
    }

    private var warningText: String {
        let names = warnings.map(\.allergen.displayName).joined(separator: ", ").lowercased()
        return warnings.allSatisfy(\.isPrecautionary) ? "May contain \(names)" : "Contains \(names)"
    }

    private var accessibilityLabel: String {
        var parts = [item.name]
        if let goal, goal != .lowCalorie, let value = goal.value(item) {
            parts.append(Figures.goal(value, goal).replacingOccurrences(of: " g", with: "").replacingOccurrences(of: " mg", with: "") + " " + goal.unitDescription.replacingOccurrences(of: "g ", with: "grams ").replacingOccurrences(of: "mg ", with: "milligrams "))
        }
        if let calories = item.calories { parts.append("\(calories) calories") }
        parts += item.dietaryTags
        if !warnings.isEmpty {
            parts.append("Contains allergens you avoid: " + warnings.map(\.allergen.displayName).joined(separator: ", "))
        }
        if isFavorite { parts.append("Favorite") }
        return parts.joined(separator: ", ")
    }
}

/// A food photo cropped to a rounded square or banner. Items without a photo get
/// a quiet glyph so rows in a section with photos still line up.
struct FoodPhoto: View {
    let url: URL?

    var body: some View {
        // The rectangle takes the proposed size; the photo fills it and is cropped.
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .overlay {
                if let url {
                    RemoteImage(url: url)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// Shows a cached image immediately (no placeholder flash when a row expands)
/// and loads it once otherwise.
struct RemoteImage: View {
    let url: URL
    @State private var image: NSImage?

    init(url: URL) {
        self.url = url
        _image = State(initialValue: ImageStore.shared.cached(url))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            if image == nil { image = await ImageStore.shared.load(url) }
        }
    }
}

/// Shared image cache. Observable so a row that depends on whether its photo
/// has loaded (`isPhoto`) updates when it arrives.
@MainActor
@Observable
final class ImageStore {
    static let shared = ImageStore()
    @ObservationIgnored private let cache = NSCache<NSURL, NSImage>()
    /// Downloads in progress. Tasks carry Data (Sendable); images are made on the main actor.
    @ObservationIgnored private var inFlight: [URL: Task<Data?, Never>] = [:]
    /// URLs whose loaded image is large enough for a banner.
    private var photos: Set<URL> = []

    init() { cache.countLimit = 300 }

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    /// True for a loaded image large enough to show as a banner (about 300 points
    /// wide on a Retina display without visible upscaling).
    func isPhoto(_ url: URL) -> Bool { photos.contains(url) && cached(url) != nil }

    func load(_ url: URL) async -> NSImage? {
        if let hit = cached(url) { return hit }
        let task: Task<Data?, Never>
        if let running = inFlight[url] {
            task = running
        } else {
            task = Task { try? await URLSession.shared.data(from: url).0 }
            inFlight[url] = task
        }
        let data = await task.value
        inFlight[url] = nil
        if let hit = cached(url) { return hit }
        guard let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        let width = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
        if width >= 320 { photos.insert(url) }
        return image
    }
}

/// Details under an expanded row: macros at a glance, allergens and diet, then
/// the description and full label for anyone who wants them.
struct ItemDetailView: View {
    let item: MenuItem
    let avoided: Set<Allergen>
    var unknownAllergens = false
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    @State private var showsLabel = false
    @State private var showsIngredients = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !macros.isEmpty { macroRow }
            facts
            if let description = item.description {
                Text(description)
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item.nutrition.count > 1 || item.ingredients != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if item.nutrition.count > 1 {
                        Disclosure(title: "Nutrition facts", isOpen: $showsLabel) { nutritionLabel }
                    }
                    if let ingredients = item.ingredients {
                        Disclosure(title: "Ingredients", isOpen: $showsIngredients) {
                            Text(ingredients)
                                .scaledFont(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if item.allergens.isEmpty && item.nutrition.isEmpty && item.calories == nil && item.ingredients == nil && item.description == nil {
                Text("The cafeteria hasn't published details for this item.")
                    .scaledFont(.callout).foregroundStyle(.secondary)
            }
            Button(action: toggleFavorite) {
                Label(isFavorite ? "Favorite" : "Add to Favorites", systemImage: isFavorite ? "star.fill" : "star")
                    .scaledFont(.subheadline, weight: .medium)
            }
            .buttonStyle(.borderless)
            .tint(isFavorite ? .yellow : nil)
            .help(isFavorite ? "Remove from favorites" : "Get notified when it's on the menu")
            .accessibilityLabel(isFavorite ? "Remove \(item.name) from favorites" : "Add \(item.name) to favorites")
        }
        .accessibilityElement(children: .contain)
    }

    private var macros: [(value: String, label: String)] {
        var result: [(String, String)] = []
        if let calories = item.calories { result.append(("\(calories)", "Calories")) }
        if let protein = item.protein { result.append((Figures.grams(protein), "Protein")) }
        if let carbs = Figures.nutrient(item, "total carbohydrate", "carbohydrates", "total carbohydrates") { result.append((Figures.grams(carbs), "Carbs")) }
        if let fat = Figures.nutrient(item, "total fat", "fat") { result.append((Figures.grams(fat), "Fat")) }
        return result
    }

    private var macroRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(macros, id: \.label) { macro in
                VStack(alignment: .leading, spacing: 0) {
                    Text(macro.value).scaledFont(.title3, weight: .semibold).monospacedDigit()
                    Text(macro.label).scaledFont(.caption1).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var facts: some View {
        let tags = item.dietaryTags
        if !item.allergens.isEmpty || !tags.isEmpty || item.servingSize != nil || unknownAllergens {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
                if !item.allergens.isEmpty {
                    GridRow {
                        factLabel("Allergens")
                        allergenText.fixedSize(horizontal: false, vertical: true)
                    }
                } else if unknownAllergens {
                    GridRow {
                        factLabel("Allergens")
                        Text("Not checked yet. Check the published label before eating.")
                            .scaledFont(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !tags.isEmpty {
                    GridRow {
                        factLabel("Diet")
                        Text(tags.joined(separator: ", ")).scaledFont(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let serving = item.servingSize {
                    GridRow {
                        factLabel("Serving")
                        Text(serving).scaledFont(.callout)
                    }
                }
            }
        }
    }

    private func factLabel(_ title: String) -> some View {
        Text(title).scaledFont(.callout).foregroundStyle(.secondary).gridColumnAlignment(.leading)
    }

    /// Allergens the person avoids come first, in orange with a warning sign.
    private var allergenText: some View {
        let flagged = item.allergens.filter { label in avoided.contains { $0.matches(label) } }
        let others = item.allergens.filter { !flagged.contains($0) }
        let warning = flagged.isEmpty ? Text("") : Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(flagged.joined(separator: ", "))")
            .foregroundStyle(.orange).fontWeight(.semibold)
        let rest = Text((flagged.isEmpty || others.isEmpty ? "" : ", ") + others.joined(separator: ", "))
        return Text("\(warning)\(rest)").scaledFont(.callout)
            .accessibilityLabel(flagged.isEmpty
                ? "Allergens: " + item.allergens.joined(separator: ", ")
                : "Contains allergens you avoid: \(flagged.joined(separator: ", ")). Other allergens: \(others.isEmpty ? "none" : others.joined(separator: ", "))")
    }

    private var nutritionLabel: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            ForEach(item.nutrition) { nutrient in
                GridRow {
                    Text(nutrient.name)
                        .padding(.leading, nutrient.isSubRow ? 12 : 0)
                        .foregroundStyle(nutrient.isSubRow ? .secondary : .primary)
                    Text(nutrient.formattedAmount)
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .scaledFont(.callout)
        .padding(.top, 4)
    }
}

/// A plain disclosure row whose content height is part of the panel's natural height.
private struct Disclosure<Content: View>: View {
    let title: String
    @Binding var isOpen: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if reduceMotion { isOpen.toggle() } else { withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() } }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text(title)
                }
                .scaledFont(.subheadline, weight: .medium)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            if isOpen { content().transition(.opacity) }
        }
    }
}
