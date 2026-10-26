import AVFoundation
import Combine
import MediaPlayer
import UIKit

enum RepeatMode: String, CaseIterable {
    case off, all, one
    var symbol: String { self == .one ? "repeat.1" : "repeat" }
    var label: String { switch self { case .off: return "Повтор выключен"; case .all: return "Повтор очереди"; case .one: return "Повтор трека" } }
    var next: Self { switch self { case .off: return .all; case .all: return .one; case .one: return .off } }
}

private struct SavedPlayback: Codable {
    var queueIDs: [String]
    var originalIDs: [String]
    var currentID: String
    var position: Double
    var shuffle: Bool
    var repeatValue: String
}

@MainActor
final class PlayerStore: ObservableObject {
    static let shared = PlayerStore()
    @Published private(set) var queue: [Track] = []
    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var shuffle = false
    @Published var repeatMode: RepeatMode = .off { didSet { savePlayback() } }
    @Published var errorMessage: String?
    private let player = AVPlayer()
    private var originalQueue: [Track] = []
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private var resumeAfterInterruption = false
    private var lastSavedSecond = -1
    private var nowPlayingArtwork: MPMediaItemArtwork?

    private init() {
        configureCommands()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.position = time.seconds.isFinite ? max(0, time.seconds) : 0
                if let seconds = self.player.currentItem?.duration.seconds, seconds.isFinite { self.duration = seconds }
                self.updateNowPlaying()
                let second = Int(self.position)
                if second % 5 == 0, second != self.lastSavedSecond {
                    self.lastSavedSecond = second
                    self.savePlayback()
                }
            }
        }
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, let ended = notification.object as? AVPlayerItem, ended === self.player.currentItem else { return }
                if self.repeatMode == .one { self.seek(to: 0); self.resume() }
                else { self.next(automatic: true) }
            }
        })
        notifications.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, let failed = notification.object as? AVPlayerItem, failed === self.player.currentItem else { return }
                self.pause()
                self.errorMessage = "Не удалось воспроизвести файл. Попробуйте импортировать его заново."
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.resumeAfterInterruption = self.isPlaying
                    self.pause()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    if self.resumeAfterInterruption, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { self.resume() }
                    self.resumeAfterInterruption = false
                }
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        })
        restorePlayback()
    }

    func play(_ track: Track, in tracks: [Track]) {
        originalQueue = tracks.contains(where: { $0.id == track.id }) ? tracks : [track]
        queue = shuffle ? [track] + originalQueue.filter { $0.id != track.id }.shuffled() : originalQueue
        load(track, autoplay: true)
    }

    func resume() {
        if current == nil {
            if let first = LibraryStore.shared.tracks.first { play(first, in: LibraryStore.shared.tracks) }
            else { errorMessage = "Сначала добавьте треки через кнопку +." }
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            player.play()
            isPlaying = true
            updateNowPlaying()
            savePlayback()
        } catch { errorMessage = error.localizedDescription }
    }

    func pause() { player.pause(); isPlaying = false; updateNowPlaying(); savePlayback() }
    func toggle() { isPlaying ? pause() : resume() }

    func next(automatic: Bool = false) {
        guard let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        if index + 1 < queue.count { load(queue[index + 1], autoplay: true) }
        else if repeatMode == .all, let first = queue.first { load(first, autoplay: true) }
        else if automatic { pause(); seek(to: 0) }
    }

    func previous() {
        if position > 3 { seek(to: 0); return }
        guard let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        if index > 0 { load(queue[index - 1], autoplay: true) }
        else { seek(to: 0) }
    }

    func seek(to seconds: Double) {
        let target = max(0, min(seconds, duration))
        position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
        savePlayback()
    }

    func toggleShuffle() {
        shuffle.toggle()
        if shuffle, let current { queue = [current] + originalQueue.filter { $0.id != current.id }.shuffled() }
        else { queue = originalQueue }
        savePlayback()
    }

    func playQueued(_ track: Track) { load(track, autoplay: true) }

    private func load(_ track: Track, autoplay: Bool) {
        current = track
        position = 0
        duration = track.duration
        isLoading = true
        lastSavedSecond = -1
        let image = track.artworkURL.flatMap { UIImage(contentsOfFile: $0.path) }
        nowPlayingArtwork = image.map { artwork in MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork } }
        let item = AVPlayerItem(url: track.fileURL)
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            let status = observed.status
            let error = observed.error?.localizedDescription
            Task { @MainActor in
                guard let self, self.player.currentItem === observed else { return }
                self.isLoading = status == .unknown
                if status == .failed { self.pause(); self.errorMessage = error ?? "Файл недоступен" }
            }
        }
        player.replaceCurrentItem(with: item)
        if autoplay { resume() } else { isPlaying = false; updateNowPlaying() }
        savePlayback()
    }

    private func configureCommands() {
        let remote = MPRemoteCommandCenter.shared()
        remote.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        remote.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        remote.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        remote.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        remote.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        remote.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: current.title, MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyAlbumTitle: current.album, MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func savePlayback() {
        guard let current else { return }
        let saved = SavedPlayback(queueIDs: queue.map(\.id), originalIDs: originalQueue.map(\.id), currentID: current.id,
                                  position: position, shuffle: shuffle, repeatValue: repeatMode.rawValue)
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "playback") }
    }

    private func restorePlayback() {
        guard let data = UserDefaults.standard.data(forKey: "playback"),
              let saved = try? JSONDecoder().decode(SavedPlayback.self, from: data) else { return }
        let lookup = Dictionary(uniqueKeysWithValues: LibraryStore.shared.tracks.map { ($0.id, $0) })
        guard let track = lookup[saved.currentID] else { return }
        queue = saved.queueIDs.compactMap { lookup[$0] }
        originalQueue = saved.originalIDs.compactMap { lookup[$0] }
        shuffle = saved.shuffle
        repeatMode = RepeatMode(rawValue: saved.repeatValue) ?? .off
        load(track, autoplay: false)
        seek(to: saved.position)
    }
}
