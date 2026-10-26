import AppIntents
import Foundation

struct PlayMusicIntent: AppIntent {
    static var title: LocalizedStringResource = "Включить музыку"
    static var description = IntentDescription("Воспроизводит локальную библиотеку Pulse. Можно указать название трека или исполнителя.")
    static var openAppWhenRun = true

    @Parameter(title: "Трек или исполнитель") var query: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let library = LibraryStore.shared.tracks
        let value = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty, PlayerStore.shared.current != nil {
            PlayerStore.shared.resume()
            return .result(dialog: "Продолжаю воспроизведение в Pulse.")
        }
        let matches = value.isEmpty ? library : library.filter {
            $0.title.localizedCaseInsensitiveContains(value) || $0.artist.localizedCaseInsensitiveContains(value)
        }
        guard let first = matches.first else { return .result(dialog: "Трек не найден. Сначала добавьте музыку в Pulse.") }
        PlayerStore.shared.play(first, in: matches)
        return .result(dialog: "Включаю музыку в Pulse.")
    }
}

struct PauseMusicIntent: AppIntent {
    static var title: LocalizedStringResource = "Пауза"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        PlayerStore.shared.pause()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Следующий трек"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        PlayerStore.shared.next()
        return .result()
    }
}

struct ScanLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Обновить библиотеку"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        if LibraryStore.shared.isScanning { return .result(dialog: "Сканирование уже идёт.") }
        await LibraryStore.shared.rescan()
        return .result(dialog: "Проверка папок завершена. Результат показан в Pulse.")
    }
}

struct PulseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayMusicIntent(), phrases: ["Включи музыку в \(.applicationName)", "Play music in \(.applicationName)"], shortTitle: "Включить музыку", systemImageName: "play.fill")
        AppShortcut(intent: PauseMusicIntent(), phrases: ["Пауза в \(.applicationName)", "Pause \(.applicationName)"], shortTitle: "Пауза", systemImageName: "pause.fill")
        AppShortcut(intent: NextTrackIntent(), phrases: ["Следующий трек в \(.applicationName)", "Next track in \(.applicationName)"], shortTitle: "Следующий трек", systemImageName: "forward.end.fill")
        AppShortcut(intent: ScanLibraryIntent(), phrases: ["Обнови библиотеку в \(.applicationName)", "Scan library in \(.applicationName)"], shortTitle: "Обновить библиотеку", systemImageName: "arrow.clockwise")
    }
}
