import Foundation

struct Track: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let filename: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let artworkFilename: String?
    let addedAt: Date

    var fileURL: URL { LibraryPaths.audio.appendingPathComponent(filename) }
    var artworkURL: URL? { artworkFilename.map { LibraryPaths.artwork.appendingPathComponent($0) } }
}

struct MusicPlaylist: Codable, Identifiable {
    var id = UUID()
    var name: String
    var trackIDs: [String] = []
}

struct MusicFolder: Codable, Identifiable {
    var id = UUID()
    var name: String
    var bookmark: Data
}

struct LibrarySnapshot: Codable {
    var tracks: [Track] = []
    var favorites: Set<String> = []
    var playlists: [MusicPlaylist] = []
    var folders: [MusicFolder] = []
}

enum LibraryPaths {
    static let root = URL.applicationSupportDirectory.appendingPathComponent("Pulse", isDirectory: true)
    static let audio = root.appendingPathComponent("Audio", isDirectory: true)
    static let artwork = root.appendingPathComponent("Artwork", isDirectory: true)
    static let snapshot = root.appendingPathComponent("library.json")

    static func prepare() throws {
        for url in [root, audio, artwork] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var rootURL = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try rootURL.setResourceValues(values)
    }
}

func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let value = Int(seconds)
    return String(format: "%d:%02d", value / 60, value % 60)
}
