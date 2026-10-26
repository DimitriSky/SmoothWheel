import AppKit
import Combine

struct ExcludedApp: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var distance: Double { didSet { defaults.set(distance, forKey: "distance") } }
    @Published var duration: Double { didSet { defaults.set(duration, forKey: "duration") } }
    @Published var reversed: Bool { didSet { defaults.set(reversed, forKey: "reversed") } }
    @Published var exclusions: [ExcludedApp] {
        didSet {
            defaults.set(try? JSONEncoder().encode(exclusions), forKey: "exclusions")
        }
    }

    init() {
        defaults.register(defaults: ["enabled": true, "distance": 32.0,
                                     "duration": 0.28, "reversed": false])
        enabled = defaults.bool(forKey: "enabled")
        let savedDistance = defaults.double(forKey: "distance")
        let savedDuration = defaults.double(forKey: "duration")
        distance = savedDistance.isFinite ? min(100, max(8, savedDistance)) : 32
        duration = savedDuration.isFinite ? min(0.6, max(0.1, savedDuration)) : 0.28
        reversed = defaults.bool(forKey: "reversed")
        exclusions = defaults.data(forKey: "exclusions")
            .flatMap { try? JSONDecoder().decode([ExcludedApp].self, from: $0) } ?? []
    }

    func addExclusion() {
        let panel = NSOpenPanel()
        panel.title = "Выберите приложение без сглаживания"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard let self, response == .OK else { return }
            for url in panel.urls {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                      !self.exclusions.contains(where: { $0.id == id }) else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                self.exclusions.append(ExcludedApp(id: id, name: name))
            }
        }
    }

    func restoreMotionDefaults() {
        distance = 32
        duration = 0.28
        reversed = false
    }
}
