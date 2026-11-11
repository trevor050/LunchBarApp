import LunchKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var finder: SchoolFinder
    @Bindable var loginItem: LoginItem
    let hotKeyStatus: HotKeyStatus
    let onSourceChange: () -> Void
    let onHotKeyChange: () -> Void
    let onNotificationsChange: () -> Void
    let requestNotifications: () async -> Bool

    @State private var isChangingSchool = false
    @State private var providerChoice = 0
    @State private var rutgersHall = "04"
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            schoolSection
            generalSection
            allergenSection
            favoritesSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 560, idealHeight: 640)
        .onAppear {
            loginItem.refresh()
            if settings.source == nil { isChangingSchool = true }
        }
    }

    // MARK: School

    @ViewBuilder
    private var schoolSection: some View {
        Section {
            if let source = settings.source, !isChangingSchool {
                LabeledContent("Place") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(source.school.name)
                        Text(source.districtName ?? "\(source.district).nutrislice.com")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if source.school.menuTypes.count > 1 {
                    Picker("Menu", selection: menuTypeBinding(for: source)) {
                        ForEach(source.school.menuTypes) { type in
                            Text(type.name).tag(type.slug)
                        }
                    }
                } else {
                    LabeledContent("Menu", value: source.menuType.name)
                }
                if settings.savedPlaces.count > 1 {
                    ForEach(settings.savedPlaces, id: \.placeKey) { place in
                        HStack {
                            Button(place.school.name + (place.provider == .rutgersFoodPro ? " · FoodPro" : "")) {
                                settings.source = place; onSourceChange()
                            }
                            Spacer()
                            Button("Remove") {
                                if settings.source?.placeKey == place.placeKey {
                                    settings.source = settings.savedPlaces.first { $0.placeKey != place.placeKey }
                                }
                                settings.savedPlaces.removeAll { $0.placeKey == place.placeKey }
                                onSourceChange()
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                Button("Add Place…") {
                    finder.reset()
                    finder.input = ""
                    isChangingSchool = true
                }
            } else {
                Picker("Source", selection: $providerChoice) {
                    Text("Nutrislice school").tag(0)
                    Text("Rutgers · current menus").tag(1)
                    Text("Rutgers · FoodPro").tag(2)
                }
                .onChange(of: providerChoice) { _, choice in
                    finder.reset()
                    if choice == 1 { finder.input = "rutgers"; finder.search() }
                }
                if providerChoice == 2 {
                    Picker("Dining hall", selection: $rutgersHall) {
                        ForEach(RutgersLocations.foodPro) { hall in Text(hall.name).tag(hall.slug) }
                    }
                    Text("The Atrium is available under Rutgers’ current menus. FoodPro is the older portal.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Save Dining Hall") {
                        guard let hall = RutgersLocations.foodPro.first(where: { $0.slug == rutgersHall }) else { return }
                        settings.source = RutgersLocations.source(hall: hall)
                        isChangingSchool = false
                        onSourceChange()
                    }
                    if settings.source != nil { Button("Cancel") { isChangingSchool = false } }
                } else {
                    schoolFinder
                }
            }
        } header: {
            Text("Saved places")
        } footer: {
            if settings.source == nil {
                Text("Save Nutrislice schools or Rutgers dining halls, then switch from the popover header.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var schoolFinder: some View {
        if providerChoice == 0 {
        HStack {
            TextField("District", text: $finder.input, prompt: Text("middlesex, or paste a menu link"))
                .onSubmit { finder.search() }
                .accessibilityHint("Type the district name from its Nutrislice web address, or paste a link to a menu.")
            Button("Find") { finder.search() }
                .disabled(finder.input.trimmingCharacters(in: .whitespaces).isEmpty || finder.phase == .searching)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("Use the name from your menu's web address, like **middlesex** in middlesex.nutrislice.com.")
                .foregroundStyle(.secondary)
            Link("Don't know it? Look up your school on Nutrislice", destination: SchoolFinder.lookupURL)
        }
        .font(.callout)

        }

        switch finder.phase {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking up schools…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded:
            schoolPicker
        }

        if settings.source != nil {
            Button("Cancel") {
                finder.reset()
                isChangingSchool = false
            }
        }
    }

    @ViewBuilder
    private var schoolPicker: some View {
        if finder.schools.count > 8 {
            TextField("Filter", text: $finder.filter, prompt: Text("Filter \(finder.schools.count) schools"))
        }
        List(finder.visibleSchools, selection: $finder.selectedSchoolSlug) { school in
            Text(school.name).tag(school.slug)
        }
        .frame(height: min(CGFloat(max(finder.visibleSchools.count, 1)) * 24 + 8, 200))
        .accessibilityLabel(finder.districtName.map { "Schools in \($0)" } ?? "Schools")

        if let school = finder.selectedSchool {
            Picker("Menu", selection: $finder.selectedMenuTypeSlug) {
                ForEach(school.menuTypes) { type in
                    Text(type.name).tag(Optional(type.slug))
                }
            }
        }
        HStack {
            Spacer()
            Button("Save This Place") {
                guard let selection = finder.selection else { return }
                settings.source = selection
                isChangingSchool = false
                finder.reset()
                onSourceChange()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(finder.selection == nil)
        }
    }

    private func menuTypeBinding(for source: MenuSource) -> Binding<String> {
        Binding(
            get: { settings.source?.menuType.slug ?? source.menuType.slug },
            set: { slug in
                guard var current = settings.source,
                      let type = current.school.menuTypes.first(where: { $0.slug == slug }) else { return }
                current.menuType = type
                settings.source = current
                onSourceChange()
            }
        )
    }

    // MARK: General

    private var generalSection: some View {
        Section("General") {
            Toggle("Open at login", isOn: Binding(
                get: { loginItem.isEnabled || loginItem.needsApproval },
                set: { loginItem.setEnabled($0) }
            ))
            .disabled(!isRunningFromAppBundle)
            if loginItem.needsApproval {
                HStack {
                    Text("Allow LunchBar in Login Items to finish turning this on.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Login Items") { loginItem.openSystemSettings() }
                }
                .font(.callout)
            }
            if let error = loginItem.lastError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            if !isRunningFromAppBundle {
                Text("Install LunchBar.app to use this.").font(.callout).foregroundStyle(.secondary)
            }

            LabeledContent("Keyboard shortcut") {
                HStack(spacing: 6) {
                    ShortcutRecorder(combo: $settings.hotKey, onChange: onHotKeyChange)
                    if settings.hotKey != nil {
                        Button {
                            settings.hotKey = nil
                            onHotKeyChange()
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear shortcut")
                    }
                }
            }
            if hotKeyStatus.conflict {
                Text("Another app is already using that shortcut. Pick a different one.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Toggle("Skip weekends", isOn: $settings.skipWeekends)
            Picker("Top protein ranking", selection: $settings.proteinRanking) {
                ForEach(ProteinRanking.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
            }
            Picker("Text size", selection: $settings.textSize) {
                ForEach(TextSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
        }
    }

    // MARK: Allergens

    private var allergenSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(Allergen.allCases) { allergen in
                    Toggle(allergen.displayName, isOn: Binding(
                        get: { settings.avoidedAllergens.contains(allergen) },
                        set: { isOn in
                            if isOn { settings.avoidedAllergens.insert(allergen) } else { settings.avoidedAllergens.remove(allergen) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        } header: {
            Text("Flag items containing")
        } footer: {
            Text("Based on the published menu. Always double-check with dining staff.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Favorites

    private var favoritesSection: some View {
        Section {
            Toggle("Notify me when a favorite is on the menu", isOn: Binding(
                get: { settings.notifyFavorites },
                set: { isOn in
                    settings.notifyFavorites = isOn
                    Task {
                        if isOn {
                            let allowed = await requestNotifications()
                            notificationsDenied = !allowed
                        } else {
                            notificationsDenied = false
                        }
                        onNotificationsChange()
                    }
                }
            ))
            .disabled(!isRunningFromAppBundle)
            if notificationsDenied && settings.notifyFavorites {
                Text("Notifications are turned off for LunchBar in System Settings › Notifications.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if settings.favorites.isEmpty {
                Text("Star an item in the menu to add it here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.favorites.sorted { $0.value < $1.value }, id: \.key) { key, name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button {
                            settings.favorites[key] = nil
                            onNotificationsChange()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(name)")
                    }
                }
            }
        } header: {
            Text("Favorites")
        } footer: {
            Text("Notifications arrive at 7:30 AM on days a favorite is served.")
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
            Text("Unofficial. Not affiliated with Rutgers or Nutrislice. Published nutrition and allergen information can be wrong; check with dining staff.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Link("Source code on GitHub", destination: URL(string: "https://github.com/trevor050/LunchBarApp")!)
        }
    }
}

@MainActor
@Observable
final class HotKeyStatus {
    var conflict = false
}

/// A click-to-record shortcut field.
struct ShortcutRecorder: View {
    @Binding var combo: HotKeyCombo?
    let onChange: () -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? "Type shortcut…" : (combo?.displayString ?? "Record Shortcut"))
                .frame(minWidth: 110)
                .monospacedDigit()
        }
        .accessibilityLabel(isRecording ? "Recording. Press the new shortcut, or Escape to cancel." : "Keyboard shortcut")
        .accessibilityValue(combo?.accessibilityLabel ?? "None")
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        // Let the current shortcut be re-recorded instead of firing.
        NotificationCenter.default.post(name: .lunchBarSuspendHotKey, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                stop()
                return nil
            }
            if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete clears
                combo = nil
                stop()
                return nil
            }
            guard let recorded = HotKeyCombo(event: event) else {
                NSSound.beep()
                return nil
            }
            combo = recorded
            stop()
            return nil
        }
    }

    private func stop() {
        guard isRecording || monitor != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onChange()
    }
}

extension Notification.Name {
    static let lunchBarSuspendHotKey = Notification.Name("LunchBarSuspendHotKey")
}
