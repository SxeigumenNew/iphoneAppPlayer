import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var seeking = false
    @State private var seekPosition = 0.0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.accessibilityLabel("Свернуть плеер")
                        Spacer()
                        VStack(spacing: 4) { Text("СЕЙЧАС ИГРАЕТ").font(.caption2.weight(.semibold)).tracking(3); Text(player.current?.album ?? "Pulse").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        Button { showQueue = true } label: { Image(systemName: "text.line.first.and.arrowtriangle.forward").frame(width: 44, height: 44) }.accessibilityLabel("Очередь воспроизведения")
                    }.foregroundStyle(.white)
                    ArtworkView(track: player.current, size: max(160, min(geometry.size.width - 56, 380)))
                        .shadow(color: .orange.opacity(0.10), radius: 30, y: 10)
                        .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                            if value.translation.width < -40 { player.next() }
                            else if value.translation.width > 40 { player.previous() }
                        })
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(player.current?.title ?? "Выберите трек").font(.title2.bold()).lineLimit(2)
                            Text(player.current?.artist ?? "Ваша музыка в Pulse").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let track = player.current {
                            Button { library.toggleFavorite(track) } label: { Image(systemName: library.snapshot.favorites.contains(track.id) ? "heart.fill" : "heart").font(.title2).frame(width: 44, height: 44) }
                                .accessibilityLabel(library.snapshot.favorites.contains(track.id) ? "Убрать из избранного" : "Добавить в избранное")
                        }
                    }
                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { seeking ? seekPosition : min(player.position, max(player.duration, 1)) }, set: { seekPosition = $0 }), in: 0...max(player.duration, 1)) { editing in
                            if editing { seekPosition = player.position; seeking = true }
                            else { seeking = false; player.seek(to: seekPosition) }
                        }.accessibilityLabel("Позиция воспроизведения")
                        HStack { Text(timeLabel(seeking ? seekPosition : player.position)); Spacer(); Text("−" + timeLabel(max(0, player.duration - (seeking ? seekPosition : player.position)))) }
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 0) {
                        Button { player.toggleShuffle() } label: { Image(systemName: "shuffle").foregroundStyle(player.shuffle ? Color.orange : Color.secondary).frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel(player.shuffle ? "Выключить перемешивание" : "Перемешать")
                        Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.title).frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel("Предыдущий трек")
                        Button { player.toggle() } label: {
                            ZStack { Circle().fill(.orange).frame(width: 80, height: 80); Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 29, weight: .semibold)).foregroundStyle(.black) }
                        }.accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
                        Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title).frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel("Следующий трек")
                        Button { player.repeatMode = player.repeatMode.next } label: { Image(systemName: player.repeatMode.symbol).foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.orange).frame(maxWidth: .infinity, minHeight: 48) }.accessibilityLabel(player.repeatMode.label)
                    }.foregroundStyle(.white)
                    HStack(spacing: 14) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                        VolumeControl().frame(height: 28).accessibilityLabel("Громкость")
                        AudioRouteControl().frame(width: 40, height: 40).accessibilityLabel("AirPlay и аудиовыход")
                    }.padding(.top, 8)
                    if player.isLoading { ProgressView("Загрузка…").font(.caption) }
                }.padding(.horizontal, 26).padding(.bottom, 24)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
            }.background(LinearGradient(colors: [Color(red: 0.13, green: 0.10, blue: 0.09), Color(white: 0.035)], startPoint: .top, endPoint: .bottom))
        }
        .sheet(isPresented: $showQueue) {
            NavigationStack {
                List(player.queue) { track in
                    Button { player.playQueued(track) } label: {
                        HStack(spacing: 12) { ArtworkView(track: track, size: 44); VStack(alignment: .leading) { Text(track.title).foregroundStyle(player.current?.id == track.id ? .orange : .white); Text(track.artist).font(.caption).foregroundStyle(.secondary) } }
                    }
                }.navigationTitle("Очередь").toolbar { Button("Готово") { showQueue = false } }
            }
        }
    }
}
