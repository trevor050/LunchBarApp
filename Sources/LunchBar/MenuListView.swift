import LunchKit
import SwiftUI

/// Reports the natural height of the menu rows so the popover can size itself to fit.
struct MenuListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuListView: View {
    let day: MenuDay
    let settings: AppSettings
    @Binding var expanded: String?
    var topItems: [MenuItem] = []
    var nutritionLoading = false
    var nutritionNotice: String?
    var verifiedRecipes: Set<String> = []
    @Binding var filter: String
    @State private var visibleTop: [MenuItem] = []
    @State private var hoveringTop = false
    @State private var hoveringMenu = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var large: Bool { day.items.count > 25 }
    private var foodPro: Bool { settings.source?.provider == .rutgersFoodPro }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if large {
                    TextField("Filter menu", text: $filter, prompt: Text("Filter \(day.items.count) items"))
                        .textFieldStyle(.roundedBorder).padding(.horizontal, 12).padding(.top, 10)
                        .accessibilityLabel("Filter items by name")
                }
                if filter.isEmpty && (!visibleTop.isEmpty || nutritionLoading || !topItems.isEmpty) {
                    proteinGroup
                }
                if let nutritionNotice {
                    Text(nutritionNotice).scaledFont(.caption1).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                ForEach(day.sections) { section in
                    let matches = section.items.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
                    if !matches.isEmpty {
                        let key = (settings.source?.key ?? "") + "/" + (section.title ?? section.id)
                        let open = !filter.isEmpty || (settings.stationExpansion[key] ?? !large)
                        if let title = section.title {
                            Button {
                                settings.stationExpansion[key] = !open
                            } label: {
                                HStack {
                                    Text(title).lineLimit(2)
                                    Spacer()
                                    Text("\(matches.count)").monospacedDigit()
                                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9))
                                }
                                .scaledFont(.subheadline, weight: .semibold).foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 5)
                            .accessibilityLabel("\(title), \(matches.count) items")
                            .accessibilityValue(open ? "Expanded" : "Collapsed")
                        }
                        if open || section.title == nil {
                            ForEach(matches) { item in row(item) }
                        }
                    }
                }
                if !filter.isEmpty && !day.items.contains(where: { $0.name.localizedCaseInsensitiveContains(filter) }) {
                    Text("No matching items").scaledFont(.body).foregroundStyle(.secondary).padding(16)
                }
            }
            .padding(.bottom, 8)
            .background(GeometryReader { proxy in Color.clear.preference(key: MenuListHeightKey.self, value: proxy.size.height) })
        }
        .scrollIndicators(.automatic)
        .onAppear { visibleTop = topItems }
        .onHover { inside in
            hoveringMenu = inside
            if !inside && expanded == nil { visibleTop = topItems }
        }
        .onChange(of: topItems) { _, items in
            // Keep names under the pointer (and an expanded row) stable during enrichment.
            if !hoveringMenu && expanded == nil { visibleTop = items }
            else {
                visibleTop = visibleTop.compactMap { old in
                    guard var current = day.items.first(where: { $0.id == old.id }) else { return nil }
                    guard current.warnings(avoiding: settings.avoidedAllergens).isEmpty else { return nil }
                    current.category = old.category
                    return current
                }
            }
        }
        .onChange(of: expanded) { _, id in
            if id == nil && !hoveringMenu { visibleTop = topItems }
        }
        .onChange(of: day.date) { filter = ""; visibleTop = topItems }
        .onChange(of: settings.source?.key) { filter = ""; visibleTop = topItems }
    }

    private var proteinGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Top protein · \(settings.proteinRanking.heading)").scaledFont(.subheadline, weight: .semibold)
                if nutritionLoading { ProgressView().controlSize(.mini).accessibilityLabel("Loading published nutrition") }
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            if visibleTop.isEmpty {
                Text(nutritionLoading ? "Checking published nutrition…" : "Top choices ready").scaledFont(.caption1).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).frame(height: 44)
            } else {
                ForEach(visibleTop) { item in row(item, protein: settings.proteinRanking) }
            }
            Divider().padding(.top, 6)
        }
        .onHover { inside in
            hoveringTop = inside
            if !inside && !hoveringMenu && expanded == nil { visibleTop = topItems }
        }
    }

    private func row(_ item: MenuItem, protein: ProteinRanking? = nil) -> some View {
        MenuItemRow(item: item, warnings: item.warnings(avoiding: settings.avoidedAllergens),
                    isFavorite: settings.isFavorite(item), isExpanded: expanded == item.id,
                    toggleExpanded: { toggle(item) }, toggleFavorite: { settings.toggleFavorite(item) },
                    proteinMode: protein, unknownAllergens: foodPro && !verifiedRecipes.contains(item.foodID))
    }
    private func toggle(_ item: MenuItem) {
        let change = { expanded = expanded == item.id ? nil : item.id }
        if reduceMotion { change() } else { withAnimation(.snappy(duration: 0.2), change) }
    }
}

struct MenuItemRow: View {
    let item: MenuItem
    let warnings: [AllergenWarning]
    let isFavorite: Bool
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let toggleFavorite: () -> Void
    var proteinMode: ProteinRanking? = nil
    var unknownAllergens = false

    @State private var isHovering = false
    @Environment(\.textScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: toggleExpanded) {
                    HStack(alignment: .top, spacing: 10) {
                        thumbnail
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .scaledFont(.body, weight: .medium)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if proteinMode != nil {
                                Text([item.calories.map { "\($0) cal" }, item.category].compactMap { $0 }.joined(separator: " · "))
                                    .scaledFont(.caption1).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                if proteinMode == .per100Calories, let score = proteinMode?.score(item) {
                                    Text(String(format: "%.1f g / 100 cal", score)).scaledFont(.caption1).foregroundStyle(.secondary)
                                }
                            } else { summary }
                        }
                        Spacer(minLength: 0)
                        if proteinMode != nil, let protein = item.protein {
                            Text(String(format: "%.1f g", protein))
                                .scaledFont(.title3, weight: .semibold).monospacedDigit().foregroundStyle(.primary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows nutrition and allergen details")
                .accessibilityAction(named: isFavorite ? "Remove from favorites" : "Add to favorites", toggleFavorite)

                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                        .font(.system(size: 13 * scale))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .opacity(isFavorite || isHovering || isExpanded ? 1 : 0)
                .accessibilityLabel(isFavorite ? "Remove \(item.name) from favorites" : "Add \(item.name) to favorites")
                .help(isFavorite ? "Remove from favorites" : "Favorite: get notified when it's on the menu")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if isExpanded {
                if unknownAllergens {
                    Text("Allergens not checked yet. Check the published label before eating.")
                        .scaledFont(.caption1).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 6)
                }
                ItemDetailView(item: item)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .background(isHovering || isExpanded ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = item.imageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.primary.opacity(0.06)
                }
            }
            .frame(width: 36 * scale, height: 36 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
        }
    }

    /// One quiet line under the name: allergen warning first (it matters most),
    /// then calories and dietary highlights.
    @ViewBuilder
    private var summary: some View {
        let details = (item.calories.map { ["\($0) cal"] } ?? []) + item.dietaryTags.prefix(2)
        if !warnings.isEmpty || !details.isEmpty {
            HStack(spacing: 6) {
                if !warnings.isEmpty {
                    Label(warningText, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
            }
            .scaledFont(.caption1)
            .lineLimit(1)
        }
    }

    private var warningText: String {
        let names = warnings.map(\.allergen.displayName).joined(separator: ", ").lowercased()
        return warnings.allSatisfy(\.isPrecautionary) ? "May contain \(names)" : "Contains \(names)"
    }

    private var accessibilityLabel: String {
        var parts = [item.name]
        if let protein = item.protein, proteinMode != nil { parts.append("\(protein) grams protein") }
        if let calories = item.calories { parts.append("\(calories) calories") }
        parts += item.dietaryTags
        if !warnings.isEmpty {
            parts.append("Contains allergens you avoid: " + warnings.map(\.allergen.displayName).joined(separator: ", "))
        }
        if isFavorite { parts.append("Favorite") }
        return parts.joined(separator: ", ")
    }
}

struct ItemDetailView: View {
    let item: MenuItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let description = item.description {
                Text(description)
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.allergens.isEmpty {
                detail("Allergens", item.allergens.joined(separator: ", "))
            }
            if !item.dietaryTags.isEmpty || !item.foodGroups.isEmpty {
                detail("Highlights", (item.dietaryTags + item.foodGroups).joined(separator: ", "))
            }
            if let serving = item.servingSize {
                detail("Serving", serving)
            }
            if !item.nutrition.isEmpty || item.calories != nil {
                nutrition
            }
            if let ingredients = item.ingredients {
                detail("Ingredients", ingredients)
            }
            if item.allergens.isEmpty && item.nutrition.isEmpty && item.ingredients == nil && item.description == nil {
                Text("The cafeteria hasn't published details for this item.")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .scaledFont(.caption1, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .scaledFont(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var nutrition: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nutrition")
                .scaledFont(.caption1, weight: .semibold)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                if let calories = item.calories {
                    row("Calories", "\(calories)", bold: true)
                }
                ForEach(item.nutrition) { nutrient in
                    row(nutrient.name, nutrient.formattedAmount, indent: nutrient.isSubRow)
                }
            }
        }
    }

    private func row(_ name: String, _ value: String, bold: Bool = false, indent: Bool = false) -> some View {
        GridRow {
            Text(name)
                .scaledFont(.callout, weight: bold ? .semibold : nil)
                .padding(.leading, indent ? 12 : 0)
                .foregroundStyle(indent ? .secondary : .primary)
            Text(value)
                .scaledFont(.callout, weight: bold ? .semibold : nil)
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
