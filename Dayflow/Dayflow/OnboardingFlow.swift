//
//  OnboardingFlow.swift
//  Dayflow
//
//  Created by Jerry Liu on 4/26/25.
//

import SwiftUI
import ScreenCaptureKit
import AppKit
import ServiceManagement

struct OnboardingFlow: View {
    // MARK: – State
    @State private var step: Step = .welcome
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    
    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case .welcome:
                Heading("Welcome to Dayflow",
                        "We'll record your screen (1 fps, 720 p) so you can see how you spend your day.")
            case .screen:
                Heading("Give screen-recording permission",
                        "macOS will open System Settings → Screen Recording. Please enable Dayflow.")
            case .access:
                Heading("Optional: Accessibility",
                        "If you'd like us to tag window titles, allow Accessibility access next.")
            case .login:
                Heading("Start Dayflow at Login",
                        "We can automatically launch Dayflow each time you log in.")
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, newValue in // <-- Use this signature
                            setLogin(newValue) // Pass the newValue to your function
                        }
            case .done:
                Heading("Setup Complete",
                        "You can now close this window; Dayflow will keep running in the menu-bar.")
            }
            
            HStack {
                if step != .welcome { Button("Back")  { step.prev() } }
                Spacer()
                Button(step == .done ? "Finish" : "Next") {
                    advance()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(40)
        .frame(width: 420)
    }
    
    // MARK: – Flow control
    private func advance() {
        switch step {
        case .welcome:      step.next()
        case .screen:
            Task { try? await requestScreenPerm() }
            step.next()
        case .access:
            if !AXIsProcessTrusted() {
                let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(opts)
            }
            step.next()
        case .login:        step.next()
        case .done:         didOnboard = true
        }
    }
    
    private func requestScreenPerm() async throws {
        _ = try await SCShareableContent.current                 // triggers prompt
    }
    
    private func setLogin(_ enable: Bool) {
        try? (enable ? SMAppService.mainApp.register()           // 1-line API in macOS 14
                     : SMAppService.mainApp.unregister())
    }
}

// MARK: – Helpers

/// Wizard step order
private enum Step: Int, CaseIterable { case welcome, screen, access, login, done
    mutating func next() { self = Step(rawValue: rawValue + 1)! }
    mutating func prev() { self = Step(rawValue: rawValue - 1)! }
}

@ViewBuilder private func Heading(_ title: String, _ sub: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.title2.bold())
        Text(sub).font(.subheadline).foregroundColor(.secondary)
    }
}
