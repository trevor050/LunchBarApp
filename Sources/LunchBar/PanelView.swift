import LunchKit
import SwiftUI

/// Everything inside the menu window: a fixed header, then the scrolling menu.
///
/// The view reports its natural height (header plus the full, unscrolled
/// content) through `onNaturalHeight`. Content inside a `ScrollView` is laid
/// out without a vertical limit, so the value never depends on the window's
/// current height, and resizing the window cannot feed back into it.
struct PanelView: View {
    @Bindable var model: MenuViewModel
    var openSettings: () -> Void
    var quit: () -> Void
    var onNaturalHeight: (CGFloat) -> Void = { _ in }
    /// Lays the content out without a scroll view, for measuring and snapshots.
    var measuring = false

    /// Height of the area used for loading, empty and error messages.
    static let messageHeight: CGFloat = 190

    var body: some View {
        Group {
            if measuring {
                VStack(spacing: 0) {
                    chrome
                    content
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    chrome
                        .fixedSize(horizontal: false, vertical: true)
                        .background(heightReader(ChromeHeightKey.self))
                    ScrollViewReader { proxy in
                        ScrollView {
                            content
                                .id(ScrollTop.id)
                                .background(heightReader(ContentHeightKey.self))
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .onChange(of: model.day) { proxy.scrollTo(ScrollTop.id, anchor: .top) }
                        .onChange(of: model.source?.key) { proxy.scrollTo(ScrollTop.id, anchor: .top) }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .onPreferenceChange(ChromeHeightKey.self) { chromeHeight = $0; report() }
                .onPreferenceChange(ContentHeightKey.self) { height in
                    contentHeight = height
                    if model.phase != .loading { model.lastContentHeight = height }
                    report()
                }
            }
        }
        .frame(width: PanelGeometry.width)
        .environment(\.textScale, model.settings.textSize.scale)
    }

    @State private var chromeHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private func report() {
        guard chromeHeight > 0, contentHeight > 0 else { return }
        onNaturalHeight(ceil(chromeHeight + contentHeight))
    }

    private func heightReader<Key: PreferenceKey>(_ key: Key.Type) -> some View where Key.Value == CGFloat {
        GeometryReader { proxy in Color.clear.preference(key: key, value: proxy.size.height) }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            header
            Divider()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(DayTitle.title(for: model.day, today: model.today))
                        .scaledFont(.title2, weight: .semibold)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(DayTitle.subtitle(for: model.day, today: model.today))
                        .scaledFont(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    sourceMenu
                    ProgressView()
                        .controlSize(.mini)
                        .opacity(model.isRefreshing ? 1 : 0)
                        .accessibilityHidden(!model.isRefreshing)
                        .accessibilityLabel("Updating menu")
                }
            }
            Spacer(minLength: 0)
            navigation
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var sourceMenu: some View {
        if let source = model.source {
            Menu {
                Section("Saved places") {
                    ForEach(model.settings.savedPlaces, id: \.placeKey) { place in
                        Button { model.select(place: place) } label: {
                            if place.placeKey == source.placeKey {
                                Label(Self.placeName(place), systemImage: "checkmark")
                            } else { Text(Self.placeName(place)) }
                        }
                    }
                    Button("Add Place…", action: openSettings)
                }
                Section("Meal") {
                    ForEach(source.school.menuTypes) { type in
                        Button { model.select(menuType: type) } label: {
                            if type == source.menuType { Label(type.name, systemImage: "checkmark") }
                            else { Text(type.name) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text("\(source.school.name) · \(source.menuType.name)").lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .scaledFont(.subheadline).foregroundStyle(.secondary)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .help("\(source.school.name) · \(source.menuType.name), switch saved place or meal")
            .accessibilityLabel("\(source.school.name), \(source.menuType.name), switch place or meal")
        }
    }

    private static func placeName(_ place: MenuSource) -> String {
        place.school.name + (place.provider == .rutgersFoodPro ? " · FoodPro" : place.district == "rutgers" ? " · Current" : "")
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                IconButton(systemImage: "chevron.left", label: "Previous day", shortcut: .leftArrow) { model.showPrevious() }
                Button("Today") { model.showToday() }
                    .buttonStyle(.borderless)
                    .scaledFont(.subheadline, weight: .medium)
                    .keyboardShortcut("t", modifiers: [])
                    .disabled(model.isShowingDefaultDay)
                    .help("Go to today (T)")
                    .padding(.horizontal, 2)
                IconButton(systemImage: "chevron.right", label: "Next day", shortcut: .rightArrow) { model.showNext() }
            }
            .disabled(model.source == nil)
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r")
            if let url = model.source?.webURL(on: model.day) {
                Button("Open Published Menu") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Settings…", action: openSettings)
                .keyboardShortcut(",")
            Button("Quit LunchBar", action: quit)
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
        .help("Refresh, settings and quit")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let notice = model.staleNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .scaledFont(.caption1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }
            phaseContent
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .needsSetup:
            StateMessage(
                symbol: "fork.knife",
                title: "Save a place",
                message: "Save a Nutrislice school or Rutgers dining hall to see its menu.",
                actionTitle: "Save a Place…",
                action: openSettings
            )
        case .loading:
            // Keep the previous content's height while loading, so switching days
            // resizes the window once (to the new menu), not twice.
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .frame(height: model.lastContentHeight > 0 ? model.lastContentHeight : Self.messageHeight)
                .accessibilityLabel("Loading menu")
        case .menu(let day):
            MenuListView(day: day, settings: model.settings, expanded: $model.expandedItemID,
                         topItems: model.topProteinItems, showsTop: model.showsTopProtein,
                         nutritionLoading: model.nutritionLoading,
                         nutritionNotice: model.nutritionNotice, verifiedRecipes: model.verifiedRecipes, filter: $model.menuFilter)
                .onChange(of: model.expandedItemID) { _, id in model.loadDetails(id) }
                .onChange(of: model.settings.proteinRanking) { model.loadNutrition() }
                .onChange(of: model.settings.avoidedAllergens) { model.loadNutrition() }
        case .empty(let reason):
            emptyState(reason)
        case .failed(let error):
            failure(error)
        }
    }

    @ViewBuilder
    private func emptyState(_ reason: MenuViewModel.EmptyReason) -> some View {
        let next = model.nextMenuDay
        let nextTitle = next.map { "Next menu: \(DayTitle.title(for: $0, today: model.today))" }
        let nextAction: (() -> Void)? = next.map { date in { model.go(to: date) } }
        let dayName = model.day == model.today ? "today" : "on \(DayTitle.title(for: model.day, today: model.today))"
        switch reason {
        case .holiday(let name):
            StateMessage(symbol: "calendar", title: name, message: "No menu \(dayName).",
                         actionTitle: nextTitle, action: nextAction)
        case .weekend:
            StateMessage(symbol: "sun.max", title: "It's the weekend", message: "Nothing on the menu \(dayName).",
                         actionTitle: nextTitle, action: nextAction)
        case .notPosted(let notes):
            StateMessage(symbol: "tray", title: "No menu posted",
                         message: notes.isEmpty ? "The cafeteria hasn't published a menu for this day." : notes.joined(separator: "\n"),
                         actionTitle: nextTitle, action: nextAction)
        }
    }

    @ViewBuilder
    private func failure(_ error: NutrisliceError) -> some View {
        switch error {
        case .offline:
            StateMessage(symbol: "wifi.slash", title: "You're offline",
                         message: "Connect to the internet to load this menu. Menus you've already opened stay available offline.",
                         actionTitle: "Try Again", action: model.refresh)
        case .districtNotFound, .menuNotFound:
            StateMessage(symbol: "questionmark.folder", title: "Menu not found",
                         message: error.message, actionTitle: "Open Settings", action: openSettings)
        case .timedOut, .server, .invalidData:
            StateMessage(symbol: "exclamationmark.icloud", title: "Menu provider isn’t responding",
                         message: model.source?.provider == .rutgersFoodPro
                            ? "Rutgers’ published menu could not be read. Try again after a short wait."
                            : "\(error.message) Try again in a bit.",
                         actionTitle: "Try Again", action: model.refresh)
        }
    }
}

private enum ScrollTop { static let id = "panel-top" }

/// Height of the fixed header.
private struct ChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Height of the unscrolled content (laid out without a vertical limit).
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct IconButton: View {
    let systemImage: String
    let label: String
    let shortcut: KeyEquivalent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(shortcut, modifiers: [])
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Centered icon + title + message, with an optional action. Used for every
/// "nothing to show" state so they read consistently.
struct StateMessage: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .scaledFont(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .scaledFont(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.regular)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, minHeight: PanelView.messageHeight)
        .accessibilityElement(children: .contain)
    }
}

enum DayTitle {
    static func title(for day: LocalDate, today: LocalDate) -> String {
        switch today.days(until: day) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            guard let date = day.date() else { return day.isoString }
            return date.formatted(.dateTime.weekday(.wide))
        }
    }

    static func subtitle(for day: LocalDate, today: LocalDate) -> String {
        guard let date = day.date() else { return "" }
        if day.year != today.year {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
