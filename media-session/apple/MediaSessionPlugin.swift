import Foundation
import MediaPlayer
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Native part of the Media Session plugin on Apple platforms: the now-playing info center and the remote commands of MediaPlayer. The lock screen, the control center and the Dynamic Island of iPhones and iPads, the now-playing screen of the Apple TV, the now-playing item of the control center and of the menu bar of a Mac and the controls of Apple Vision Pro show what the app plays. The commands of those controls, the media keys of a Mac and the buttons of headsets, accessories and remotes reach the app as `media-session.command` on the main thread.
@objc(MediaSessionPlugin)
final class MediaSessionPlugin: NSObject, HaylenPlugin {
    // The commands of the controls by the names that the app reads, each with the remote command of MediaPlayer that serves it.
    enum Command: String, CaseIterable {
        case play, pause, togglePlayPause, stop, next, previous, seek

        func remote(in center: MPRemoteCommandCenter) -> MPRemoteCommand {
            switch self {
            case .play: center.playCommand
            case .pause: center.pauseCommand
            case .togglePlayPause: center.togglePlayPauseCommand
            case .stop: center.stopCommand
            case .next: center.nextTrackCommand
            case .previous: center.previousTrackCommand
            case .seek: center.changePlaybackPositionCommand
            }
        }
    }

    // What plays, as the Lua API sends it, with the bytes of the artwork as `Data` and the commands as an object of their names.
    struct Track {
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let position: Double
        let playing: Bool
        let artwork: Data?
        let commands: Set<Command>

        init?(_ params: Any) {
            guard let fields = params as? [String: Any], let commands = fields["commands"] as? [String: Any] else {
                return nil
            }
            title = fields["title"] as? String ?? ""
            artist = fields["artist"] as? String ?? ""
            album = fields["album"] as? String ?? ""
            duration = (fields["duration"] as? NSNumber)?.doubleValue ?? 0
            position = (fields["position"] as? NSNumber)?.doubleValue ?? 0
            playing = fields["playing"] as? Bool ?? false
            artwork = fields["artwork"] as? Data
            self.commands = Set(Command.allCases.filter { commands[$0.rawValue] != nil })
        }
    }

    private var context: HaylenPluginContext!

    // Whether every remote command has its handler, which it keeps for the life of the process, while the commands that the app offers turn on and off.
    private var handlesCommands = false

    // Whether the controls show what an app of the process plays, so a process that never showed anything leaves MediaPlayer alone.
    private var showing = false

    func load(with context: HaylenPluginContext) {
        self.context = context

        context.registerHandler("setNowPlaying") { [unowned self] params, reply in
            guard let track = Track(params) else {
                reply(false, ["message": "The parameters of what plays are invalid.", "code": "invalidParams"])
                return
            }
            self.show(track)
            reply(true, nil)
        }

        context.registerHandler("clear") { [unowned self] _, reply in
            self.clear()
            reply(true, nil)
        }

        context.registerHandler("nowPlaying") { _, reply in
            reply(true, Self.shown())
        }
    }

    // A Mac and Mac Catalyst follow the playback state too, which the media keys of the keyboard and the menu bar read, and tvOS has none.
    private func show(_ track: Track) {
        let center = MPNowPlayingInfoCenter.default()
        enable(track.commands)
        center.nowPlayingInfo = Self.info(of: track)
        #if !os(tvOS)
        center.playbackState = track.playing ? .playing : .paused
        #endif
        showing = true
    }

    private func clear() {
        guard showing else {
            return
        }
        showing = false
        let center = MPNowPlayingInfoCenter.default()
        enable([])
        center.nowPlayingInfo = nil
        #if !os(tvOS)
        center.playbackState = .stopped
        #endif
    }

    // The commands answer with the status `success`, and a seek carries the position that the person picked.
    private func enable(_ commands: Set<Command>) {
        let center = MPRemoteCommandCenter.shared()
        for command in Command.allCases {
            let remote = command.remote(in: center)
            if !handlesCommands {
                remote.addTarget { [context] event in
                    var payload: [String: Any] = ["command": command.rawValue]
                    if command == .seek, let seek = event as? MPChangePlaybackPositionCommandEvent {
                        payload["position"] = seek.positionTime
                    }
                    context?.emit("command", payload: payload)
                    return .success
                }
            }
            remote.isEnabled = commands.contains(command)
        }
        handlesCommands = true
    }

    private static func info(of track: Track) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: track.position,
            MPNowPlayingInfoPropertyPlaybackRate: track.playing ? 1.0 : 0.0,
        ]
        if track.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = track.duration
        }
        if let artwork = track.artwork.flatMap(artwork(of:)) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        return info
    }

    // Bytes that are no PNG or JPEG image show no artwork. MediaPlayer asks the artwork for its image on a queue of its own, so the artwork belongs to no actor.
    private nonisolated static func artwork(of bytes: Data) -> MPMediaItemArtwork? {
        #if os(macOS)
        let picture = NSImage(data: bytes)
        #else
        let picture = UIImage(data: bytes)
        #endif
        guard let image = picture else {
            return nil
        }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // What the info center holds, read back from it, or `nil` while it holds nothing.
    private static func shown() -> [String: Any]? {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return nil
        }
        return [
            "title": info[MPMediaItemPropertyTitle] as? String ?? "",
            "artist": info[MPMediaItemPropertyArtist] as? String ?? "",
            "album": info[MPMediaItemPropertyAlbumTitle] as? String ?? "",
            "duration": (info[MPMediaItemPropertyPlaybackDuration] as? NSNumber)?.doubleValue ?? 0,
            "playing": ((info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0) > 0,
            "artwork": info[MPMediaItemPropertyArtwork] != nil,
        ]
    }
}
