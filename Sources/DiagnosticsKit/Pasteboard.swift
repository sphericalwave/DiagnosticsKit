//
//  Pasteboard.swift
//  DiagnosticsKit
//
//  Copying a log entry is the whole point of reading one on a phone — the
//  text has to get somewhere it can be pasted into a bug report.
//

#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum Pasteboard {
    static func copy(_ text: String) {
        #if os(iOS) || os(visionOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
