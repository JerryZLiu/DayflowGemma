//
//  StatusBarController.swift
//  Dayflow
//
//  Created by Jerry Liu on 4/26/25.
//

import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var sub: Any?
    
    init() {
        sub = AppState.shared.$isRecording.sink { [weak self] rec in
            self?.item.button?.title = rec ? "● Dayflow" : "◌ Dayflow"
        }
        item.menu = menu
        item.button?.title = "● Dayflow"
    }
    
    private lazy var menu: NSMenu = {
        let m = NSMenu()

        // Pause / Resume
        m.addItem(withTitle: "Pause / Resume",
                  action: #selector(toggle),
                  keyEquivalent: "" ).target = self

        // Open Recordings…
        let open = NSMenuItem(title: "Open Recordings…",
                              action: #selector(openFolder),
                              keyEquivalent: "o")
        open.target = self               // ← add this line
        m.addItem(open)

        let debug = NSMenuItem(title: "Debug…", action: #selector(openBatchViewer), keyEquivalent: "b")
        debug.target = self
        m.addItem(debug)
        
        m.addItem(NSMenuItem.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit",
                              action: #selector(quit),
                              keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        return m
    }()
    

@objc private func openBatchViewer() {
    let window = NSWindow(
        contentRect: .init(x: 0, y: 0, width: 800, height: 450),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Dayflow – Debug"
    window.contentView = NSHostingView(rootView: DebugView())
    window.center()
    window.makeKeyAndOrderFront(nil)
}

    
    @objc private func openFolder() {
        let dir = StorageManager.shared.recordingsRoot
        NSWorkspace.shared.open(dir)
    }
    @objc private func toggle() { AppState.shared.isRecording.toggle() }
    @objc private func quit()   { NSApp.terminate(nil) }
}
