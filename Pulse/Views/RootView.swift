import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @State private var showPlayer = false
    @State private var importFolder = false
    @State private var importFiles = false

    var body: some View {
        TabView {
            NavigationStack {
                LibraryView()
                    .toolbar { importToolbar }
                    .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayer { showPlayer = true } }
            }.tabItem { Label("Медиатека", systemImage: "square.stack.fill") }
            NavigationStack {
                PlaylistsView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayer { showPlayer = true } }
            }.tabItem { Label("Плейлисты", systemImage: "music.note.list") }
            NavigationStack {
                SourcesView()
                    .toolbar { importToolbar }
                    .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayer { showPlayer = true } }
            }.tabItem { Label("Папки", systemImage: "folder.fill") }
        }
        .sheet(isPresented: $showPlayer) { PlayerView() }
        .fileImporter(isPresented: $importFolder, allowedContentTypes: [.folder], allowsMultipleSelection: true) { handleImport($0, folder: true) }
        .fileImporter(isPresented: $importFiles, allowedContentTypes: [.audio, .mpeg4Movie], allowsMultipleSelection: true) { handleImport($0, folder: false) }
        .alert("Pulse", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("OK") { library.message = nil }
        } message: { Text(library.message ?? "") }
        .alert("Воспроизведение", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            Button("OK") { player.errorMessage = nil }
        } message: { Text(player.errorMessage ?? "") }
    }

    @ToolbarContentBuilder private var importToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if library.isScanning { ProgressView().accessibilityLabel("Сканирование музыки") }
            else {
                Menu {
                    Button("Выбрать папки", systemImage: "folder.badge.plus") { importFolder = true }
                    Button("Выбрать файлы", systemImage: "doc.badge.plus") { importFiles = true }
                    Button("Сканировать снова", systemImage: "arrow.clockwise") { Task { await library.rescan() } }
                } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Добавить музыку").disabled(!library.canWrite)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>, folder: Bool) {
        switch result {
        case .success(let urls): Task { await library.importURLs(urls, rememberFolders: folder) }
        case .failure(let error): library.message = error.localizedDescription
        }
    }
}

private enum LibrarySection: String, CaseIterable {
    case tracks = "Треки", albums = "Альбомы", artists = "Артисты", favorites = "Избранное"
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @State private var section = LibrarySection.tracks
    @State private var search = ""
    @State private var newestFirst = false

    private var tracks: [Track] {
        let values = library.tracks.filter {
            (section != .favorites || library.snapshot.favorites.contains($0.id)) &&
            (search.isEmpty || "\($0.title) \($0.artist) \($0.album)".localizedCaseInsensitiveContains(search))
        }
        return newestFirst ? values.sorted { $0.addedAt > $1.addedAt } : values
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Раздел медиатеки", selection: $section) { ForEach(LibrarySection.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 10)
            if library.tracks.isEmpty {
                ContentUnavailableView("Ваша музыка — здесь", systemImage: "waveform", description: Text("Нажмите +, выберите папку или файлы. Pulse найдёт треки и прочитает обложки и теги."))
            } else if tracks.isEmpty {
                ContentUnavailableView("Пока пусто", systemImage: "music.note", description: Text("Измените поиск или добавьте треки в избранное через меню трека."))
            } else {
                List {
                    if section == .albums || section == .artists { groups }
                    else {
                        HStack {
                            Text("\(tracks.count) треков").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { if let first = tracks.randomElement() { if !player.shuffle { player.toggleShuffle() }; player.play(first, in: tracks) } } label: { Label("Перемешать", systemImage: "shuffle").font(.caption) }
                        }.listRowBackground(Color.clear)
                        ForEach(tracks) { TrackRow(track: $0, tracks: tracks) }
                    }
                }.listStyle(.plain)
            }
        }
        .navigationTitle("Pulse")
        .searchable(text: $search, prompt: "Трек, исполнитель или альбом")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu { Toggle("Сначала новые", isOn: $newestFirst) } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Сортировка")
            }
        }
    }

    @ViewBuilder private var groups: some View {
        let grouped = Dictionary(grouping: tracks) { track in section == .artists ? track.artist : "\(track.album)\u{001F}\(track.artist)" }
        ForEach(grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { key in
            let items = grouped[key] ?? []
            NavigationLink {
                TrackListView(title: section == .artists ? key : items.first?.album ?? key, tracks: items)
            } label: {
                HStack(spacing: 14) {
                    ArtworkView(track: items.first)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section == .artists ? key : items.first?.album ?? key).lineLimit(1)
                        Text(section == .artists ? "\(items.count) треков" : "\(items.first?.artist ?? "") · \(items.count) треков").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.padding(.vertical, 4)
            }
        }
    }
}

struct TrackListView: View {
    let title: String
    let tracks: [Track]
    var body: some View {
        List(tracks) { TrackRow(track: $0, tracks: tracks) }.listStyle(.plain).navigationTitle(title)
    }
}

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var creating = false
    @State private var name = ""
    var body: some View {
        List {
            if library.snapshot.playlists.isEmpty {
                Text("Создайте плейлист кнопкой +. Для добавления треков удерживайте трек в медиатеке.").foregroundStyle(.secondary)
            }
            ForEach(library.snapshot.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistID: playlist.id)
                } label: {
                    Label { VStack(alignment: .leading) { Text(playlist.name); Text("\(playlist.trackIDs.count) треков").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "music.note.list").foregroundStyle(.orange) }
                }.swipeActions { Button("Удалить", role: .destructive) { library.removePlaylist(playlist) } }
            }
        }.navigationTitle("Плейлисты")
        .toolbar { Button("Создать плейлист", systemImage: "plus") { creating = true } }
        .alert("Новый плейлист", isPresented: $creating) {
            TextField("Название", text: $name)
            Button("Создать") { library.createPlaylist(name: name); name = "" }
            Button("Отмена", role: .cancel) { name = "" }
        }
    }
}

private struct PlaylistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    let playlistID: UUID
    var body: some View {
        let playlist = library.snapshot.playlists.first { $0.id == playlistID }
        let tracks = playlist.map { library.tracks(in: $0) } ?? []
        List(tracks) { track in
            TrackRow(track: track, tracks: tracks)
                .swipeActions { Button("Убрать", role: .destructive) { library.remove(track, from: playlistID) } }
        }.listStyle(.plain).navigationTitle(playlist?.name ?? "Плейлист")
    }
}

struct SourcesView: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        List {
            Section("Папки для сканирования") {
                ForEach(library.snapshot.folders) { folder in Label(folder.name, systemImage: "folder") }
                if library.snapshot.folders.isEmpty { Text("Нажмите + и выберите папку в приложении «Файлы».").foregroundStyle(.secondary) }
                Button { Task { await library.rescan() } } label: { Label("Сканировать снова", systemImage: "arrow.clockwise") }
                    .disabled(library.isScanning || !library.canWrite)
            }
            Section("Хранение") {
                LabeledContent("Треков", value: "\(library.tracks.count)")
                Text("Pulse копирует выбранные файлы в своё хранилище. Копии доступны без интернета. Повторное сканирование добавляет новые треки; исходные файлы не изменяются.").font(.footnote).foregroundStyle(.secondary)
                Text("Для iCloud сначала загрузите файлы на iPhone. iOS разрешает читать только выбранные вами папки. После удаления Pulse его копии музыки также удаляются.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Siri и Команды") {
                Text("Попробуйте: «Siri, включи музыку в Pulse», «Пауза в Pulse», «Следующий трек в Pulse», «Обнови библиотеку в Pulse».")
                Text("В приложении «Команды» можно добавить действие «Включить музыку» от Pulse и указать трек или исполнителя. Эти команды открывают Pulse. Произношение названия и доступность фраз зависят от языка Siri.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Папки и Siri")
    }
}
