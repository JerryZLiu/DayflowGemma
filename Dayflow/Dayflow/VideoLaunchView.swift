//
//  VideoLaunchView.swift
//  Dayflow
//
//  Video launch screen that plays before onboarding or main app
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoLaunchView: View {
    @State private var player: AVPlayer?
    @State private var hasCompleted = false
    private var onComplete: (() -> Void)?
    
    func onVideoComplete(_ completion: @escaping () -> Void) -> VideoLaunchView {
        var view = self
        view.onComplete = completion
        return view
    }
    
    var body: some View {
        ZStack {
            if let player = player {
                // Custom AVPlayer view without controls
                AVPlayerControllerRepresented(player: player)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            setupVideo()
            // Focus the window
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func setupVideo() {
        guard let videoData = NSDataAsset(name: "DayflowAnimation")?.data else {
            // No fallback - just complete immediately
            completeVideo()
            return
        }
        
        // Create temporary file URL for AVPlayer
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("dayflow_launch.mp4")
        do {
            try videoData.write(to: tempURL)
        } catch {
            print("Failed to write video to temp file: \(error)")
            completeVideo()
            return
        }
        
        let playerItem = AVPlayerItem(url: tempURL)
        player = AVPlayer(playerItem: playerItem)
        
        // Monitor when we're near the end to start fade early
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard let duration = self.player?.currentItem?.duration,
                  duration.isValid && duration.isNumeric else { return }
            
            let currentSeconds = time.seconds
            let totalSeconds = duration.seconds
            
            // Start fade 0.5 seconds before the end
            if currentSeconds >= totalSeconds - 0.5 && currentSeconds < totalSeconds {
                self.completeVideo()
            }
        }
        
        // Also monitor actual completion as fallback
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            completeVideo()
        }
        
        // Start playing
        player?.play()
        
        // Add observer for errors
        playerItem.observe(\.status) { item, _ in
            if item.status == .failed {
                print("Video failed to load: \(item.error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async {
                    self.completeVideo()
                }
            }
        }
    }
    
    private func completeVideo() {
        guard !hasCompleted else { return }
        hasCompleted = true
        
        // Clean up and notify immediately - let parent handle fade
        player?.pause()
        player = nil
        NotificationCenter.default.removeObserver(self)
        onComplete?()
    }
}

// Custom AVPlayer view without controls
struct AVPlayerControllerRepresented: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill // Fill the screen
        view.showsFullScreenToggleButton = false
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

// Preview for development
struct VideoLaunchView_Previews: PreviewProvider {
    static var previews: some View {
        VideoLaunchView()
            .onVideoComplete {
                print("Video completed")
            }
    }
}