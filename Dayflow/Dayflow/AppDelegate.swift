//
//  AppDelegate.swift
//  Dayflow
//
//  Created by Jerry Liu on 4/26/25.
//

import AppKit
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var recorder : ScreenRecorder!
    private var splashWindow: SplashWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        // Show splash window first
        splashWindow = SplashWindow(onClose: {
            // Show main window after splash closes
            DispatchQueue.main.async {
                // Find and show the main window
                for window in NSApp.windows {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    break
                }
            }
        })
        
        // Hide main windows after splash is created
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for window in NSApp.windows {
                if window !== self.splashWindow {
                    window.orderOut(nil)
                }
            }
        }
        
        statusBar = StatusBarController()   // safe: AppKit is ready, main thread
        recorder  = ScreenRecorder()        // hooks into AppState
        try? SMAppService.mainApp.register()// autostart at login
        
        // Start the Gemini analysis background job
        setupGeminiAnalysis()
    }
    
    // Start Gemini analysis as a background task
    private func setupGeminiAnalysis() {
        // Perform after a short delay to ensure other initialization completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            GeminiAnalysisManager.shared.startAnalysisJob()
            print("AppDelegate: Gemini analysis job started")
        }
    }
}
