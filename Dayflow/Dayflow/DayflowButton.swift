//
//  DayflowButton.swift
//  Dayflow
//
//  Custom button component with Dayflow branding
//

import SwiftUI

struct DayflowButton: View {
    let title: String
    let action: () -> Void
    var width: CGFloat = 160
    var fontSize: CGFloat = 16
    var isSubtle: Bool = false
    
    @State private var isPressed = false
    @State private var showPulse = false
    
    var body: some View {
        Button(action: {
            // Trigger pulse animation
            withAnimation(.easeOut(duration: 0.1)) {
                isPressed = true
            }
            
            // Haptic feedback on macOS 11+
            if #available(macOS 11.0, *) {
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .levelChange,
                    performanceTime: .default
                )
            }
            
            // Reset and call action
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                    showPulse = true
                }
                action()
                
                // Reset pulse
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showPulse = false
                }
            }
        }) {
            Text(title)
                .font(.custom("Nunito", size: fontSize))
                .fontWeight(.semibold)
                .foregroundColor(isSubtle ? .black.opacity(0.7) : .white)
                .frame(width: width, height: 56, alignment: .center)
                .background(
                    ZStack {
                        // Main background
                        if isSubtle {
                            Color.white.opacity(0.9)
                        } else {
                            Color(red: 1, green: 0.42, blue: 0.02)
                        }
                        
                        // Pulse effect
                        if showPulse {
                            Group {
                                if isSubtle {
                                    Color.gray.opacity(0.1)
                                } else {
                                    Color(red: 1, green: 0.42, blue: 0.02)
                                        .opacity(0.3)
                                }
                            }
                            .scaleEffect(1.2)
                            .blur(radius: 10)
                            .animation(.easeOut(duration: 0.3), value: showPulse)
                        }
                    }
                )
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.25), radius: 0.25, x: 0, y: 0.5)
                .shadow(color: .black.opacity(0.16), radius: 0.5, x: 0, y: 1)
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .inset(by: 0.75)
                        .stroke(isSubtle ? Color.black.opacity(0.1) : .white.opacity(0.17), lineWidth: 1.5)
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .brightness(isPressed ? -0.1 : 0)
        }
        .buttonStyle(.plain) // Remove default button styling
    }
}

// MARK: - Preview
struct DayflowButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            DayflowButton(title: "Start", action: {})
            DayflowButton(title: "Continue", action: {}, width: 200)
            DayflowButton(title: "Next", action: {}, width: 120, fontSize: 14)
        }
        .padding(40)
        .background(Color.gray.opacity(0.1))
    }
}