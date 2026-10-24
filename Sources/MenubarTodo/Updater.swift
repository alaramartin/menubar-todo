import Foundation

/// Checks GitHub for a newer release once a day and remembers what it found.
@MainActor
final class Updater: ObservableObject {
    struct Release {
        let version: String
        let url: URL
    }

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/alaramartin/menubar-todo/releases/latest")!

    /// Set when a release newer than this build exists.
    @Published private(set) var available: Release?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private var timer: Timer?

    func start() {
        Task { try? await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { try? await self?.check() }
        }
    }

    /// Returns the newer release if there is one, or nil if up to date. Throws on network errors.
    @discardableResult
    func check() async throws -> Release? {
        var request = URLRequest(url: Self.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)

        struct Payload: Decodable {
            let tag_name: String
            let html_url: URL
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let latest = payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        available = Self.isNewer(latest, than: currentVersion) ? Release(version: latest, url: payload.html_url) : nil
        return available
    }

    /// Compares dotted version numbers, e.g. "1.10.0" > "1.9.2".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
