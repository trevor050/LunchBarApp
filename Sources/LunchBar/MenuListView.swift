import LunchKit
import SwiftUI

struct MenuListView: View {
    let day: MenuDay
    let settings: AppSettings
    @State private var expanded: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(day.sections) { section in
                    if let title = section.title {
                        Text(title)
                            .scaledFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 2)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(section.items) { item in
                        MenuItemRow(
                            item: item,
                            warnings: item.warnings(avoiding: settings.avoidedAllergens),
                            isFavorite: settings.isFavorite(item),
                            isExpanded: expanded == item.id,
                            toggleExpanded: { toggle(item) },
                            toggleFavorite: { settings.toggleFavorite(item) }
                        )
                    }
                }
                if !day.notes.isEmpty {
                    Text(day.notes.joined(separator: "\n"))
                        .scaledFont(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.automatic)
        .onChange(of: day.date) { expanded = nil }
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
                            summary
                        }
                        Spacer(minLength: 0)
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
