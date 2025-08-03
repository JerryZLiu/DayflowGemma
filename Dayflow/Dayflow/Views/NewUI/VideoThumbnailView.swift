//
//  VideoThumbnailView.swift
//  Dayflow
//
//  Video player component for the new UI
//

import SwiftUI
import AVKit

struct VideoThumbnailView: View {
    let videoURL: String
    @State private var player: AVPlayer?
    
    var body: some View {
        GeometryReader { geometry in
            if let url = URL(string: videoURL) {
                VideoPlayer(player: player)
                    .onAppear {
                        player = AVPlayer(url: url)
                        player?.isMuted = true
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
                    .cornerRadius(12)
                    .overlay(
                        // Play button overlay
                        Button(action: {
                            if player?.timeControlStatus == .playing {
                                player?.pause()
                            } else {
                                player?.play()
                            }
                        }) {
                            Image(systemName: player?.timeControlStatus == .playing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.8))
                                .background(Circle().fill(Color.black.opacity(0.3)))
                        }
                        .buttonStyle(PlainButtonStyle())
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .overlay(
                        Text("Invalid video URL")
                            .foregroundColor(.white)
                    )
            }
        }
    }
}