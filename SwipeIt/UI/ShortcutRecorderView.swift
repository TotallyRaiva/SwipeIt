//
//  ShortcutRecorderView.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import SwiftUI
import AppKit

/// Interactive shortcut recorder row allowing users to bind custom modifier shortcuts or multi-key chords.
public struct ShortcutRecorderRow: View {
    public let title: String
    public let subtitle: String
    @Binding public var combo: KeyCombo
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
        onCommit: @escaping () -> Void = {},
        onRecordingStateChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.title = title
        self.subtitle = subtitle
        self._combo = combo
        self.onCommit = onCommit
        self.onRecordingStateChange = onRecordingStateChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text(livePreviewText)
                                .font(.system(.callout, design: .monospaced, weight: .semibold))
                                .foregroundStyle(.red)
                        } else {
                            Text(combo.displayString)
                                .font(.system(.callout, design: .monospaced, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minWidth: 130)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isRecording ? Color.red.opacity(0.12) : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isRecording ? Color.red.opacity(0.6) : Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear {
            if isRecording {
                stopRecording()
            }
        }
    }

    private var livePreviewText: String {
        if peakKeys.isEmpty && peakModifiers == 0 {
            return "Press keys..."
        }
        let preview = KeyCombo(keyCodes: peakKeys, modifiers: peakModifiers)
        return preview.displayString
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

        // Allow single Escape press (without modifiers or other keys) to cancel recording
        if event.type == .keyDown && keyCode == 53 && normalizedMods == 0 && heldKeys.isEmpty && peakKeys.isEmpty {
            // Track in case user is building a chord starting with Esc (like Esc + arrows),
            // so we commit on keyUp!
        }

        if event.type == .keyDown {
            heldKeys.insert(keyCode)
            peakKeys.insert(keyCode)
            if normalizedMods != 0 {
                peakModifiers = normalizedMods
            }

            // If user pressed Modifiers + Single Key, commit immediately for snappy UX
            if peakModifiers != 0 && peakKeys.count == 1 {
                let candidate = KeyCombo(keyCodes: peakKeys, modifiers: peakModifiers)
                if candidate.isValidUserShortcut {
                    combo = candidate
                    onCommit()
                    stopRecording()
                }
            }
        } else if event.type == .keyUp {
            heldKeys.remove(keyCode)

            // When all held keys are released, evaluate the peak chord
            if heldKeys.isEmpty {
                // Single Esc without modifiers cancels recording
                if peakKeys == [53] && peakModifiers == 0 {
                    stopRecording()
                    return
                }

                let candidate = KeyCombo(keyCodes: peakKeys, modifiers: peakModifiers)
                if candidate.isValidUserShortcut {
                    combo = candidate
                    onCommit()
                    stopRecording()
                } else {
                    errorMessage = "Include at least one modifier (⌘, ⌥, ⌃, ⇧) or hold 2+ keys together."
                    stopRecording()
                }
            }
        }
    }
}
