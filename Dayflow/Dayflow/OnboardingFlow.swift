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
    @State private var timelineOffset: CGFloat = 300 // Start below screen
    @State private var textOpacity: Double = 0
    @State private var animatedText: AttributedString = AttributedString("")
    private let fullText = "Be mindful about where you are spending your time."
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background image
                Image("OnboardingBackgroundv2")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                
                if step == .welcome {
                    // Text positioned in upper portion with typewriter effect
                    VStack {
                        Text(animatedText)
                            .font(.custom("InstrumentSerif-Regular", size: min(36, geometry.size.width / 20)))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.horizontal, 20)
                            .padding(.top, 120)
                            .minimumScaleFactor(0.5)
                            .lineLimit(3)
                            .frame(minHeight: 100) // Min height to prevent jumping
                            .onAppear {
                                // Start with invisible text, then reveal
                                setupInitialText()
                                animateTypewriter()
                            }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Timeline image at bottom that slides up
                    VStack {
                        Spacer()
                        Image("OnboardingTimeline")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: min(geometry.size.width * 0.9, 800))
                            .offset(y: timelineOffset)
                            .opacity(timelineOffset > 0 ? 0 : 1)
                            .onAppear {
                                // Emil Kowalski principles:
                                // - Use spring for natural movement
                                // - Keep it fast (under 1s)
                                // - Ease out for responsiveness
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0).delay(0.3)) {
                                    timelineOffset = 0
                                }
                            }
                    }
                    .ignoresSafeArea(.all)
                } else {
                    // Other onboarding steps
                    VStack(spacing: 24) {
                        switch step {
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
                                .onChange(of: launchAtLogin) { _, newValue in
                                    setLogin(newValue)
                                }
                        case .done:
                            Heading("Setup Complete",
                                    "You can now close this window; Dayflow will keep running in the menu-bar.")
                        default:
                            EmptyView()
                        }
                    }
                    .padding(40)
                    .frame(width: 420)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .shadow(radius: 20)
                    )
                }
                
                // Navigation buttons
                VStack {
                    Spacer()
                    HStack {
                        if step != .welcome { 
                            Button("Back") { 
                                timelineOffset = 300 // Reset for animation
                                step.prev() 
                            } 
                        }
                        Spacer()
                        Button(step == .done ? "Finish" : "Next") {
                            advance()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(40)
                }
            }
        }
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
    
    // MARK: - Typewriter animation
    private func setupInitialText() {
        // Create attributed string with all text invisible
        animatedText = AttributedString(fullText)
        animatedText.foregroundColor = .clear
    }
    
    private func animateTypewriter(at position: Int = 0) {
        guard position <= fullText.count else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            // Create visible and invisible parts
            let visibleText = String(fullText.prefix(position))
            let invisibleText = String(fullText.suffix(fullText.count - position))
            
            // Build attributed string
            let visiblePart = AttributedString(visibleText)
            var invisiblePart = AttributedString(invisibleText)
            invisiblePart.foregroundColor = .clear
            
            // Combine and update
            animatedText = visiblePart + invisiblePart
            
            // Continue animation
            animateTypewriter(at: position + 1)
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
        Text(title)
            .font(.custom("InstrumentSerif-Regular", size: 28))
            .fontWeight(.medium)
        Text(sub)
            .font(.system(size: 14))
            .foregroundColor(.secondary)
    }
}

// MARK: - Preview
struct OnboardingFlow_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingFlow()
            .environmentObject(AppState.shared)
            .frame(width: 1200, height: 800)
    }
}
