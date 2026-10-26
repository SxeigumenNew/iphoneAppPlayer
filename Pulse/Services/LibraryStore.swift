import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()
    @Published private(set) var snapshot = LibrarySnapshot()
    @Published private(set) var isScanning = false
    @Published var message: String?
    @Published private(set) var canWrite = true

    var tracks: [Track] { snapshot.tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }

    private init() {
        do {
            try LibraryPaths.prepare()
            if FileManager.default.fileExists(atPath: LibraryPaths.snapshot.path) {
                snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: LibraryPaths.snapshot))
            }
        } catch {
            canWrite = false
            message = "Не удалось открыть библиотеку: \(error.localizedDescription). Исходные данные сохранены; импорт отключён."
        }
    }

    func importURLs(_ urls: [URL], rememberFolders: Bool) async {
        guard !isScanning, canWrite else { return }
        isScanning = true
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            scoped.forEach { $0.stopAccessingSecurityScopedResource() }
            isScanning = false
        }
        var bookmarkFailures: [String] = []
        if rememberFolders {
            for url in urls {
                do {
                    let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    // Resolve existing bookmarks to avoid adding the same folder twice.
                    let isKnown = snapshot.folders.contains { folder in
                        var stale = false
                        return (try? URL(resolvingBookmarkData: folder.bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)) == url
                    }
                    if !isKnown { snapshot.folders.append(MusicFolder(name: url.lastPathComponent, bookmark: bookmark)) }
                } catch { bookmarkFailures.append(url.lastPathComponent) }
            }
        }
        let result = await AudioImporter.scan(urls: urls, existingIDs: Set(snapshot.tracks.map(\.id)))
        snapshot.tracks.append(contentsOf: result.tracks)
        guard persist() else { return }
        var report = "Добавлено: \(result.tracks.count). Уже в библиотеке: \(result.duplicates)."
        if !result.failures.isEmpty { report += "\nНе прочитано: \(result.failures.count).\n" + result.failures.prefix(5).joined(separator: "\n") }
        if !bookmarkFailures.isEmpty { report += "\nДля повторного сканирования выберите папки заново: " + bookmarkFailures.joined(separator: ", ") }
        message = report
    }

    func rescan() async {
        guard !isScanning else { return }
        var urls: [URL] = []
        var inaccessible: [String] = []
        for index in snapshot.folders.indices {
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: snapshot.folders[index].bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
                if stale {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    snapshot.folders[index].bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                }
                urls.append(url)
            } catch { inaccessible.append(snapshot.folders[index].name) }
        }
        guard !urls.isEmpty else {
            message = "Выберите папку через кнопку +. Если доступ к прежней папке потерян, выберите её ещё раз."
            return
        }
        await importURLs(urls, rememberFolders: false)
        if !inaccessible.isEmpty { message = (message ?? "") + "\nВыберите заново: " + inaccessible.joined(separator: ", ") }
    }

    func toggleFavorite(_ track: Track) {
        guard canWrite else { return }
        if snapshot.favorites.contains(track.id) { snapshot.favorites.remove(track.id) }
        else { snapshot.favorites.insert(track.id) }
        persist()
    }

    func createPlaylist(name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canWrite, !value.isEmpty else { return }
        snapshot.playlists.append(MusicPlaylist(name: value))
        persist()
    }

    func add(_ track: Track, to playlist: MusicPlaylist) {
        guard canWrite, let index = snapshot.playlists.firstIndex(where: { $0.id == playlist.id }), !snapshot.playlists[index].trackIDs.contains(track.id) else { return }
        snapshot.playlists[index].trackIDs.append(track.id)
        persist()
    }

    func removePlaylist(_ playlist: MusicPlaylist) {
        guard canWrite else { return }
        snapshot.playlists.removeAll { $0.id == playlist.id }
        persist()
    }

    func remove(_ track: Track, from playlistID: UUID) {
        guard canWrite, let index = snapshot.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        snapshot.playlists[index].trackIDs.removeAll { $0 == track.id }
        persist()
    }

    func tracks(in playlist: MusicPlaylist) -> [Track] {
        let lookup = Dictionary(uniqueKeysWithValues: snapshot.tracks.map { ($0.id, $0) })
        return playlist.trackIDs.compactMap { lookup[$0] }
    }

    @discardableResult
    private func persist() -> Bool {
        guard canWrite else { return false }
        do {
            try JSONEncoder().encode(snapshot).write(to: LibraryPaths.snapshot, options: .atomic)
            return true
        } catch {
            message = "Не удалось сохранить библиотеку: \(error.localizedDescription)"
            return false
        }
    }
}
