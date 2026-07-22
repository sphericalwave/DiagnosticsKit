//
//  AudioSessionMonitor.swift
//  DiagnosticsKit
//
//  Passive observer that logs every `AVAudioSession` event the system reports:
//  interruptions, route changes, media-services resets, and secondary-audio
//  silence hints.
//
//  Purely diagnostic — it never activates, deactivates, or reconfigures the
//  session. Installing it cannot change audio behavior, which is what makes it
//  safe to drop into every app at once.
//
//  A point-in-time snapshot says *what* the session looks like; this says
//  *when it changed and why*. Across apps sharing a container, the interleaved
//  result shows one app's activation landing as another app's interruption.
//

import Foundation
#if os(iOS)
import AVFoundation
#endif

public final class AudioSessionMonitor {

    public static let shared = AudioSessionMonitor()

    private var log: ErrorLog?
    private var installed = false
    private var tokens: [NSObjectProtocol] = []
    private let lock = NSLock()

    private init() {}

    /// Start observing. Idempotent — calling twice installs one set of
    /// observers. Safe to call from `init()` of the app struct.
    public func install(log: ErrorLog = .shared) {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true
        self.log = log

        log.record(.info, source: "AudioSession",
                   message: "monitor installed \(AudioSessionSnapshot.capture().summary)")

        #if os(iOS)
        let nc = NotificationCenter.default

        tokens.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] note in self?.handleInterruption(note) })

        tokens.append(nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] note in self?.handleRouteChange(note) })

        tokens.append(nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.log?.record(.error, source: "AudioSession",
                              message: "mediaServicesWereReset — audio stack must be rebuilt")
        })

        tokens.append(nc.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: nil, queue: .main
        ) { [weak self] note in self?.handleSecondaryAudioHint(note) })
        #endif
    }

    public func uninstall() {
        lock.lock()
        defer { lock.unlock() }
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        installed = false
    }

    /// Record a session decision the app is about to make or has just made.
    /// Call this around `setCategory` / `setActive` so the timeline shows who
    /// moved first when two apps contend.
    public func note(_ message: String,
                     file: String = #fileID,
                     line: Int = #line,
                     function: String = #function) {
        log?.record(.info, source: "AudioSession", message: message,
                    file: file, line: line, function: function)
    }

    #if os(iOS)
    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let snap = AudioSessionSnapshot.capture()
        switch type {
        case .began:
            var text = "INTERRUPTION began"
            if #available(iOS 14.5, *),
               let reasonRaw = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt,
               let reason = AVAudioSession.InterruptionReason(rawValue: reasonRaw) {
                text += " reason=\(reason)"
            }
            log?.record(.warning, source: "AudioSession",
                        message: "\(text) \(snap.summary)")
        case .ended:
            let optsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
                .contains(.shouldResume)
            log?.record(.info, source: "AudioSession",
                        message: "INTERRUPTION ended shouldResume=\(shouldResume) \(snap.summary)")
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        let snap = AudioSessionSnapshot.capture()
        log?.record(.info, source: "AudioSession",
                    message: "routeChange reason=\(describe(reason)) \(snap.summary)")
    }

    private func handleSecondaryAudioHint(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: raw) else { return }
        let state = type == .begin ? "begin (another app wants silence)" : "end"
        log?.record(.info, source: "AudioSession",
                    message: "silenceSecondaryAudioHint \(state)")
    }

    private func describe(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown:                  return "unknown"
        case .newDeviceAvailable:       return "newDeviceAvailable"
        case .oldDeviceUnavailable:     return "oldDeviceUnavailable"
        case .categoryChange:           return "categoryChange"
        case .override:                 return "override"
        case .wakeFromSleep:            return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        @unknown default:               return "unhandled(\(reason.rawValue))"
        }
    }
    #endif
}
