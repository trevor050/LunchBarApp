import LunchKit
import SwiftUI

/// Everything inside the menu bar popover.
struct PopoverView: View {
    @Bindable var model: MenuViewModel
    var openSettings: () -> Void
    var quit: () -> Void

    static let size = CGSize(width: 360, height: 460)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.textScale, model.settings.textSize.scale)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(DayTitle.title(for: model.day, today: model.today))
                        .scaledFont(.title2, weight: .semibold)
                    Text(DayTitle.subtitle(for: model.day, today: model.today))
                        .scaledFont(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                sourceMenu
            }
            Spacer(minLength: 0)
            navigation
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var sourceMenu: some View {
        if let source = model.source {
            let types = source.school.menuTypes
            if types.count > 1 {
                Menu {
                    ForEach(types) { type in
                        Button {
                            model.select(menuType: type)
                        } label: {
                            if type == source.menuType {
                                Label(type.name, systemImage: "checkmark")
                            } else {
                                Text(type.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(source.school.name) · \(source.menuType.name)")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .scaledFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("\(source.school.name), \(source.menuType.name) menu")
                .accessibilityHint("Switch between this school's menus")
            } else {
                Text("\(source.school.name) · \(source.menuType.name)")
                    .scaledFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var navigation: some View {
        HStack(spacing: 2) {
            NavButton(systemImage: "chevron.left", label: "Previous day", shortcut: .leftArrow) {
                model.showPrevious()
            }
            Button("Today") { model.showToday() }
                .buttonStyle(.borderless)
                .scaledFont(.subheadline, weight: .medium)
                .keyboardShortcut("t", modifiers: [])
                .disabled(model.isShowingDefaultDay)
                .help("Go to today (T)")
            NavButton(systemImage: "chevron.right", label: "Next day", shortcut: .rightArrow) {
                model.showNext()
            }
        }
        .disabled(model.source == nil)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .needsSetup:
            StateMessage(
                symbol: "fork.knife",
                title: "Pick your school",
                message: "LunchBar works with any school or campus that publishes its menu on Nutrislice.",
                actionTitle: "Choose School…",
                action: openSettings
            )
        case .loading:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading menu")
        case .menu(let day):
            MenuListView(day: day, settings: model.settings, expanded: $model.expandedItemID)
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
            StateMessage(symbol: "exclamationmark.icloud", title: "Nutrislice isn't responding",
                         message: "\(error.message) Try again in a bit.",
                         actionTitle: "Try Again", action: model.refresh)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let notice = model.staleNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .scaledFont(.caption1)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if model.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("Updating…").scaledFont(.caption1).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Refresh") { model.refresh() }
                    .keyboardShortcut("r")
                if let url = model.source?.webURL(on: model.day) {
                    Button("Open on Nutrislice") { NSWorkspace.shared.open(url) }
                }
                Divider()
                Button("Settings…", action: openSettings)
                    .keyboardShortcut(",")
                Button("Quit LunchBar", action: quit)
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
            .help("Refresh, settings and quit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 34)
    }
}

private struct NavButton: View {
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
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
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
