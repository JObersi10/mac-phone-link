import Foundation
import MediaPlayer
import Companion

/// Bridges the phone's media playback into macOS's own Now Playing surface
/// (Control Center, the lock screen, and the media keys) using the public
/// MediaPlayer framework.
///
/// Direction:
///   phone MPRIS state  → `update(...)` → `MPNowPlayingInfoCenter`
///   Control Center / media keys → `MPRemoteCommandCenter` → `onCommand` →
///       forwarded to the phone as a KDE Connect mpris.request.
///
/// We publish *as a source* via the public API rather than reading other apps'
/// now-playing via the private MediaRemote framework — that is the correct
/// direction here and keeps us off private API.
final class NowPlayingBridge {
    /// Emits scrcpy/MPRIS-style action strings: "Play", "Pause", "PlayPause",
    /// "Next", "Previous".
    var onCommand: ((String) -> Void)?

    init() { registerCommands() }

    func update(from media: MprisBody) {
        var info: [String: Any] = [:]
        if let title = media.title { info[MPMediaItemPropertyTitle] = title }
        if let artist = media.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = media.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let length = media.length {
            info[MPMediaItemPropertyPlaybackDuration] = Double(length) / 1000.0
        }
        if let pos = media.pos {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(pos) / 1000.0
        }
        let playing = media.isPlaying ?? false
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.onCommand?("Play"); return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onCommand?("Pause"); return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onCommand?("PlayPause"); return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.onCommand?("Next"); return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onCommand?("Previous"); return .success
        }
    }
}
