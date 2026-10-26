import AVKit
import MediaPlayer
import SwiftUI

private final class ArtworkCache {
    static let shared = NSCache<NSURL, UIImage>()
}

struct ArtworkView: View {
    let track: Track?
    var size: CGFloat = 52
    private var artwork: UIImage? {
        guard let url = track?.artworkURL else { return nil }
        if let cached = ArtworkCache.shared.object(forKey: url as NSURL) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        ArtworkCache.shared.countLimit = 80
        ArtworkCache.shared.setObject(image, forKey: url as NSURL)
        return image
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.28, green: 0.20, blue: 0.18), Color(white: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let artwork { Image(uiImage: artwork).resizable().scaledToFill() }
            else { Image(systemName: "waveform").font(.system(size: size * 0.32, weight: .light)).foregroundStyle(.orange) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.07))
        .accessibilityHidden(true)
    }
}

struct TrackRow: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    let track: Track
    let tracks: [Track]
    var body: some View {
        Button { player.play(track, in: tracks) } label: {
            HStack(spacing: 13) {
                ArtworkView(track: track)
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title).font(.body.weight(.medium)).foregroundStyle(player.current?.id == track.id ? .orange : .white).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if library.snapshot.favorites.contains(track.id) { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.orange) }
                Text(timeLabel(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }
        .contextMenu {
            Button(library.snapshot.favorites.contains(track.id) ? "Убрать из избранного" : "В избранное", systemImage: "heart") { library.toggleFavorite(track) }
            if !library.snapshot.playlists.isEmpty {
                Menu("Добавить в плейлист", systemImage: "text.badge.plus") {
                    ForEach(library.snapshot.playlists) { list in Button(list.name) { library.add(track, to: list) } }
                }
            }
        }
    }
}

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerStore
    var open: () -> Void
    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                ProgressView(value: min(player.position, max(player.duration, 1)), total: max(player.duration, 1)).tint(.orange)
                HStack(spacing: 12) {
                    Button(action: open) {
                        HStack(spacing: 12) {
                            ArtworkView(track: track, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title).font(.subheadline.weight(.medium)).lineLimit(1).foregroundStyle(.white)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.accessibilityLabel("Открыть плеер: \(track.title)")
                    Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 44, height: 44) }
                        .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
                    Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 40, height: 44) }.accessibilityLabel("Следующий трек")
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }.background(.ultraThinMaterial)
        }
    }
}

struct VolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.showsRouteButton = false
        view.tintColor = .systemOrange
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct AudioRouteControl: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .lightGray
        view.activeTintColor = .systemOrange
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
