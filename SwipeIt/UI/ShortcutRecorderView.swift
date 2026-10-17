//
//  ShortcutRecorderView.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import SwiftUI
import AppKit

/// Renders a single tactile miniature keycap.
public struct SingleKeycapView: View {
    public let label: String
    public var isHighlighted: Bool = false

    public init(label: String, isHighlighted: Bool = false) {
        self.label = label
        self.isHighlighted = isHighlighted
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(isHighlighted ? Color.red : Color.primary.opacity(0.9))
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? Color.red.opacity(0.6) : Color.white.opacity(0.18),
                        lineWidth: 1
                    )
            )
    }
}

/// Renders a group of tactile keycaps representing a shortcut or key chord.
public struct KeycapBadgeView: View {
    public let tokens: [String]
    public var isRecording: Bool = false
    public var placeholder: String = "Press keys…"

    public init(tokens: [String], isRecording: Bool = false, placeholder: String = "Press keys…") {
        self.tokens = tokens
        self.isRecording = isRecording
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 5) {
            if isRecording && tokens.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                    Text(placeholder)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            } else if tokens.isEmpty {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    SingleKeycapView(label: token, isHighlighted: isRecording)
                }
            }
        }
    }
}

/// Interactive shortcut recorder row with tactile keycaps, duplicate detection, and focus-loss safety.
public struct ShortcutRecorderRow: View {
    public let title: String
    public let subtitle: String
    @Binding public var combo: KeyCombo
    public var duplicateCheck: ((KeyCombo) -> String?)?
    public var onCommit: () -> Void
    public var onRecordingStateChange: (Bool) -> Void

    @State private var isRecording: Bool = false
    @State private var heldKeys: Set<Int64> = []
    @State private var peakKeys: Set<Int64> = []
    @State private var peakModifiers: UInt64 = 0
    @State private var errorMessage: String?
    @State private var eventMonitor: Any?

    public init(
        title: String,
        subtitle: String,
        combo: Binding<KeyCombo>,
        duplicateCheck: ((KeyCombo) -> String?)? = nil,
        onCommit: @escaping () -> Void = {},
        onRecordingStateChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.title = title
        self.subtitle = subtitle
        self._combo = combo
        self.duplicateCheck = duplicateCheck
        self.onCommit = onCommit
        self.onRecordingStateChange = onRecordingStateChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isRecording {
                            KeycapBadgeView(tokens: currentTokens, isRecording: true)
                        } else {
                            KeycapBadgeView(tokens: combo.keyTokens, isRecording: false)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isRecording ? Color.red.opacity(0.12) : Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isRecording ? Color.red.opacity(0.5) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }
        }
        .onDisappear {
            if isRecording {
                stopRecording()
            }
        }
        // Safety: If user switches away from the window or app mid-recording, cleanly cancel recording and re-enable global hotkeys
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if isRecording {
                stopRecording()
            }
        }
    }

    private var currentTokens: [String] {
        if peakKeys.isEmpty && peakModifiers == 0 {
            return []
        }
        return KeyCombo(keyCodes: peakKeys, modifiers: peakModifiers).keyTokens
    }

    private func startRecording() {
        errorMessage = nil
        heldKeys.removeAll()
        peakKeys.removeAll()
        peakModifiers = 0
        isRecording = true
        onRecordingStateChange(true)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            handleRecordingEvent(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
        heldKeys.removeAll()
        peakKeys.removeAll()
        peakModifiers = 0
        onRecordingStateChange(false)
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        let keyCode = Int64(event.keyCode)
        let cgFlags = event.cgEvent?.flags.rawValue ?? 0
        let normalizedMods = cgFlags & KeyCombo.relevantModifierMask

        if event.type == .keyDown {
            heldKeys.insert(keyCode)
            peakKeys.insert(keyCode)
            if normalizedMods != 0 {
                peakModifiers = normalizedMods
            }

            // Snappy commit if modifiers + single key pressed
            if peakModifiers != 0 && peakKeys.count == 1 {
                let candidate = KeyCombo(keyCodes: peakKeys, modifiers: peakModifiers)
                commitCandidateIfValid(candidate)
            }
        } else if event.type == .keyUp {
            heldKeys.remove(keyCode)

            if heldKeys.isEmpty {
                // If user pressed only Esc to cancel recording
                if peakKeys == [53] && peakModifiers == 0 {
                    stopRecording()
                    return
                }

                let candidate = KeyCombo(keyCodes: peakKeys, modifiers: peakModifiers)
                commitCandidateIfValid(candidate)
            }
        }
    }

    private func commitCandidateIfValid(_ candidate: KeyCombo) {
        if !candidate.isValidUserShortcut {
            errorMessage = "Shortcut too simple. Use ⌘, ⌃, or ⌥+⇧ with a key (or 3+ keys for chords)."
            stopRecording()
            return
        }

        if let duplicateMsg = duplicateCheck?(candidate) {
            errorMessage = duplicateMsg
            stopRecording()
            return
        }

        combo = candidate
        onCommit()
        stopRecording()
    }
}
