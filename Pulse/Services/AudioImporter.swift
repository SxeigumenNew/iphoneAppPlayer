import AVFoundation
import CryptoKit
import Foundation

struct ImportResult: Sendable {
    var tracks: [Track] = []
    var duplicates = 0
    var failures: [String] = []
}

enum AudioImporter {
    static let extensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4"]

    // The caller keeps security-scoped access open until this operation completes.
    static func scan(urls: [URL], existingIDs: Set<String>) async -> ImportResult {
        await Task.detached(priority: .userInitiated) {
            var result = ImportResult()
            var known = existingIDs
            let manager = FileManager.default
            var candidates: [URL] = []
            for url in urls {
                do {
                    if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                        if let walker = manager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { failedURL, error in
                            result.failures.append("\(failedURL.lastPathComponent): \(error.localizedDescription)")
                            return true
                        }) {
                            for case let file as URL in walker where extensions.contains(file.pathExtension.lowercased()) {
                                if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { candidates.append(file) }
                            }
                        }
                    } else if extensions.contains(url.pathExtension.lowercased()) {
                        candidates.append(url)
                    }
                } catch { result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            for url in candidates {
                do {
                    let id = try digest(url)
                    guard known.insert(id).inserted else { result.duplicates += 1; continue }
                    let filename = "\(id).\(url.pathExtension.lowercased())"
                    let destination = LibraryPaths.audio.appendingPathComponent(filename)
                    let alreadyStored = manager.fileExists(atPath: destination.path)
                    if !alreadyStored { try manager.copyItem(at: url, to: destination) }
                    do {
                        let track = try await metadata(url: destination, id: id, fallback: url.deletingPathExtension().lastPathComponent)
                        result.tracks.append(track)
                    } catch {
                        if !alreadyStored { try? manager.removeItem(at: destination) }
                        throw error
                    }
                } catch { result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            return result
        }.value
    }

    private static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func metadata(url: URL, id: String, fallback: String) async throws -> Track {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
            throw NSError(domain: "Pulse", code: 1, userInfo: [NSLocalizedDescriptionKey: "Формат не поддерживается iOS или файл повреждён"])
        }
        let items = (try? await asset.load(.commonMetadata)) ?? []
        var title = fallback
        var artist = "Неизвестный исполнитель"
        var album = "Без альбома"
        var artworkFilename: String?
        for item in items {
            switch item.commonKey {
            case .commonKeyTitle:
                if let value = try? await item.load(.stringValue), !value.isEmpty { title = value }
            case .commonKeyArtist:
                if let value = try? await item.load(.stringValue), !value.isEmpty { artist = value }
            case .commonKeyAlbumName:
                if let value = try? await item.load(.stringValue), !value.isEmpty { album = value }
            case .commonKeyArtwork:
                if let data = try? await item.load(.dataValue) {
                    let name = "\(id).artwork"
                    if (try? data.write(to: LibraryPaths.artwork.appendingPathComponent(name), options: .atomic)) != nil { artworkFilename = name }
                }
            default: break
            }
        }
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        return Track(id: id, filename: url.lastPathComponent, title: title, artist: artist, album: album,
                     duration: duration.isFinite ? max(0, duration) : 0, artworkFilename: artworkFilename, addedAt: Date())
    }
}
