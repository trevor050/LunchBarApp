import Foundation
import LunchKit
import Observation

/// State for the "find your school" flow in Settings.
///
/// Nutrislice has no open district search (its lookup site sits behind a
/// CAPTCHA), so the user supplies the district (or pastes any menu link) and
/// everything after that is discovered from the district's public schools list.
@MainActor
@Observable
final class SchoolFinder {
    enum Phase: Equatable {
        case idle
        case searching
        case loaded
        case failed(String)
    }

    var input = ""
    var filter = ""
    private(set) var phase: Phase = .idle
    private(set) var district: String?
    private(set) var districtName: String?
    private(set) var schools: [School] = []
    var selectedSchoolSlug: String? {
        didSet { syncMenuType() }
    }
    var selectedMenuTypeSlug: String?

    @ObservationIgnored private let client: NutrisliceClient
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(client: NutrisliceClient) {
        self.client = client
    }

    static let lookupURL = URL(string: "https://lookup.nutrislice.com/")!

    var visibleSchools: [School] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return schools }
        return schools.filter { $0.name.localizedStandardContains(query) || $0.slug.contains(query.lowercased()) }
    }

    var selectedSchool: School? { schools.first { $0.slug == selectedSchoolSlug } }

    var selection: MenuSource? {
        guard let district, let school = selectedSchool,
              let type = school.menuTypes.first(where: { $0.slug == selectedMenuTypeSlug }) else { return nil }
        return MenuSource(district: district, districtName: districtName, school: school, menuType: type)
    }

    func search() {
        searchTask?.cancel()
        guard let link = MenuLink.parse(input) else {
            phase = .failed("Enter a district name like “middlesex”, or paste a link from a Nutrislice menu page.")
            return
        }
        phase = .searching
        searchTask = Task {
            do throws(NutrisliceError) {
                async let name = client.districtName(district: link.district)
                let found = try await client.schools(district: link.district)
                let resolvedName = await name
                guard !Task.isCancelled else { return }
                apply(link: link, schools: found, districtName: resolvedName)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.message(for: error))
            }
        }
    }

    func reset() {
        searchTask?.cancel()
        phase = .idle
        schools = []
        district = nil
        districtName = nil
        selectedSchoolSlug = nil
        selectedMenuTypeSlug = nil
        filter = ""
    }

    private func apply(link: MenuLink, schools found: [School], districtName name: String?) {
        let usable = found.filter { !$0.menuTypes.isEmpty }
        guard !usable.isEmpty else {
            phase = .failed("“\(link.district)” doesn't have any menus published right now.")
            return
        }
        district = link.district
        districtName = name
        schools = usable
        filter = ""
        selectedSchoolSlug = link.schoolSlug.flatMap { slug in usable.first { $0.slug == slug }?.slug }
            ?? (usable.count == 1 ? usable[0].slug : nil)
        if let type = link.menuTypeSlug, selectedSchool?.menuTypes.contains(where: { $0.slug == type }) == true {
            selectedMenuTypeSlug = type
        }
        phase = .loaded
    }

    /// Default to Lunch when the school has it (it's in the app's name, after all).
    private func syncMenuType() {
        guard let school = selectedSchool else {
            selectedMenuTypeSlug = nil
            return
        }
        if let current = selectedMenuTypeSlug, school.menuTypes.contains(where: { $0.slug == current }) { return }
        selectedMenuTypeSlug = school.menuTypes.first { $0.slug.contains("lunch") }?.slug ?? school.menuTypes.first?.slug
    }

    static func message(for error: NutrisliceError) -> String {
        switch error {
        case .districtNotFound(let district):
            "Couldn't find “\(district)” on Nutrislice. Check the name in your district's menu address (the part before .nutrislice.com)."
        case .offline:
            "You're offline. Connect to the internet and try again."
        default:
            error.message + " Try again in a bit."
        }
    }
}
