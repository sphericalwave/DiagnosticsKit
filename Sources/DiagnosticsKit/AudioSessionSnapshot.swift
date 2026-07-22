//
//  AudioSessionSnapshot.swift
//  DiagnosticsKit
//
//  Point-in-time reading of `AVAudioSession`. Generalized from MindHeist's
//  `AudioSessionConfigurator.snapshot(_:)`.
//
//  This is the thing that answers "why did my audio go silent without being
//  paused": if the session says another app is playing and our category isn't
//  mixing, that's the culprit — no guesswork.
//
//  Read-only. Capturing never mutates the session.
//

import Foundation
#if os(iOS)
import AVFoundation
#endif

public struct AudioSessionSnapshot: Sendable, Equatable {

    public var category: String
    public var mode: String
    public var optionsRaw: UInt
    /// Human-readable option names — the raw bitmask is useless in a log, and
    /// a missing `.mixWithOthers` is the single most common cause of one app
    /// stopping another's audio.
    public var optionNames: [String]
    public var isOtherAudioPlaying: Bool
    public var secondaryAudioShouldBeSilencedHint: Bool
    public var outputVolume: Float
    public var isInputAvailable: Bool
    public var outputs: [String]
    public var inputs: [String]
    public var sampleRate: Double
    public var ioBufferDuration: Double

    public var summary: String {
        let opts = optionNames.isEmpty ? "none" : optionNames.joined(separator: "+")
        return "cat=\(category) mode=\(mode) opts=[\(opts)] "
            + "otherAudioPlaying=\(isOtherAudioPlaying) "
            + "secondarySilenceHint=\(secondaryAudioShouldBeSilencedHint) "
            + "outVol=\(String(format: "%.2f", outputVolume)) "
            + "inputAvailable=\(isInputAvailable) "
            + "out=[\(outputs.joined(separator: ","))] "
            + "in=[\(inputs.joined(separator: ","))] "
            + "sr=\(Int(sampleRate)) ioBuf=\(String(format: "%.4f", ioBufferDuration))"
    }

    #if os(iOS)
    public static func capture() -> AudioSessionSnapshot {
        let s = AVAudioSession.sharedInstance()
        return AudioSessionSnapshot(
            category: s.category.rawValue
                .replacingOccurrences(of: "AVAudioSessionCategory", with: ""),
            mode: s.mode.rawValue
                .replacingOccurrences(of: "AVAudioSessionMode", with: ""),
            optionsRaw: s.categoryOptions.rawValue,
            optionNames: optionNames(s.categoryOptions),
            isOtherAudioPlaying: s.isOtherAudioPlaying,
            secondaryAudioShouldBeSilencedHint: s.secondaryAudioShouldBeSilencedHint,
            outputVolume: s.outputVolume,
            isInputAvailable: s.isInputAvailable,
            outputs: s.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" },
            inputs: s.currentRoute.inputs.map { "\($0.portType.rawValue):\($0.portName)" },
            sampleRate: s.sampleRate,
            ioBufferDuration: s.ioBufferDuration
        )
    }

    /// Decodes the category-option bitmask into names.
    public static func optionNames(_ options: AVAudioSession.CategoryOptions) -> [String] {
        var names: [String] = []
        if options.contains(.mixWithOthers)               { names.append("mixWithOthers") }
        if options.contains(.duckOthers)                  { names.append("duckOthers") }
        if options.contains(.allowBluetoothA2DP)          { names.append("allowBluetoothA2DP") }
        if options.contains(.allowAirPlay)                { names.append("allowAirPlay") }
        if options.contains(.defaultToSpeaker)            { names.append("defaultToSpeaker") }
        if options.contains(.interruptSpokenAudioAndMixWithOthers) {
            names.append("interruptSpokenAudioAndMixWithOthers")
        }
        if options.contains(.overrideMutedMicrophoneInterruption) {
            names.append("overrideMutedMicrophoneInterruption")
        }
        return names
    }
    #else
    /// Non-iOS platforms have no `AVAudioSession`; capture yields an empty
    /// snapshot so cross-platform call sites compile unchanged.
    public static func capture() -> AudioSessionSnapshot {
        AudioSessionSnapshot(
            category: "n/a", mode: "n/a", optionsRaw: 0, optionNames: [],
            isOtherAudioPlaying: false, secondaryAudioShouldBeSilencedHint: false,
            outputVolume: 0, isInputAvailable: false, outputs: [], inputs: [],
            sampleRate: 0, ioBufferDuration: 0
        )
    }
    #endif
}

public extension ErrorLog {
    /// Capture the current session state into the log. `context` tags the
    /// caller ("play-start", "foreground", "manual") so the timeline reads as
    /// a sequence of decisions rather than isolated dumps.
    func recordAudioSnapshot(_ context: String,
                             file: String = #fileID,
                             line: Int = #line,
                             function: String = #function) {
        let snap = AudioSessionSnapshot.capture()
        record(.info, source: "AudioSession",
               message: "snapshot[\(context)] \(snap.summary)",
               file: file, line: line, function: function)
    }
}
