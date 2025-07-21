import SwiftUI
import AVKit
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

struct DebugView: View {
    @State private var batches = StorageManager.shared.allBatches()
    @State private var selected: Int64?
    @State private var player = AVPlayer()
    @State private var timelineCards: [TimelineCard] = []
    @State private var llmCalls: [LLMCall] = []
    @State private var composition: AVMutableComposition?
    @State private var isProcessing = false

    var body: some View {
        HStack(spacing: 0) {
            List(batches, id: \.id, selection: $selected) { b in
                VStack(alignment: .leading) {
                    Text("Batch \(b.id)").font(.headline)
                    Text("\(tsString(b.start)) – \(tsString(b.end))")
                        .font(.caption)
                    Text(b.status).font(.caption2)
                }
            }
            .frame(width: 220)
            .onChange(of: selected) { _, new in Task { await loadBatch(new) } }

            Divider()

            if let _ = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VideoPlayer(player: player)
                            .frame(height: 200)
                            .cornerRadius(8)
                        Button("Export Video…") { exportVideo() }
                            .disabled(composition == nil || isProcessing)

                        Button("Reprocess Batch") { triggerReprocessBatch() }
                            .disabled(isProcessing)
                            .padding(.top, 5)
                        
                        Button("Export Screenshots") { exportScreenshots() }
                            .disabled(composition == nil || isProcessing)
                            .padding(.top, 5)

                        if !timelineCards.isEmpty {
                            Text("Timeline Cards").font(.headline)
                            ForEach(timelineCards) { card in
                                TimelineCardRow(card: card)
                            }
                        }

                        if !llmCalls.isEmpty {
                            Text("LLM Calls").font(.headline)
                            ForEach(Array(llmCalls.enumerated()), id: \.offset) { index, call in
                                LLMCallRow(index: index, call: call, dateFormatter: dateFormatter, prettyJSON: prettyJSON)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                VStack { Spacer(); Text("Select a batch").foregroundColor(.secondary); Spacer() }
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { refresh() }
        .onDisappear { player.pause() }
    }

    private func refresh() { batches = StorageManager.shared.allBatches() }

    private func loadBatch(_ id: Int64?) async {
        player.pause()
        timelineCards = []
        llmCalls = []
        composition = nil

        guard let id else { return }
        let chunks = StorageManager.shared.chunksForBatch(id)
        if !chunks.isEmpty {
            let comp = AVMutableComposition()
            for c in chunks {
                let asset = AVURLAsset(url: URL(fileURLWithPath: c.fileUrl))
                do {
                    guard try await asset.load(.isPlayable) else { continue }
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    let altTracks = try await asset.loadTracks(withMediaType: .audio)
                    guard let track = tracks.first ?? altTracks.first else { continue }
                    let dur = try await asset.load(.duration)
                    try await comp.insertTimeRange(.init(start: .zero, duration: dur), of: asset, at: comp.duration)
                } catch {
                    print("Failed to process asset \(c.fileUrl): \(error)")
                }
            }
            if comp.tracks.first != nil {
                composition = comp
                player.replaceCurrentItem(with: AVPlayerItem(asset: comp))
            } else {
                composition = nil
            }
        } else {
            composition = nil
        }
        timelineCards = StorageManager.shared.fetchTimelineCards(forBatch: id)
        llmCalls = StorageManager.shared.fetchBatchLLMMetadata(batchId: id)
    }

    private func triggerReprocessBatch() {
        guard let batchId = selected, !isProcessing else { return }

        isProcessing = true
        print("Starting reprocessing for batch \(batchId)...")

        LLMService.shared.processBatch(batchId) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                switch result {
                case .success(let result):
                    print("Successfully reprocessed batch \(batchId). Found \(result.cards.count) cards.")
                case .failure(let error):
                    print("Failed to reprocess batch \(batchId): \(error.localizedDescription)")
                }
                self.refresh()
                Task {
                    await self.loadBatch(batchId)
                }
            }
        }
    }

    private func exportVideo() {
        guard let comp = composition else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Batch\(selected ?? 0).mp4"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await exportComposition(comp, to: url) }
        }
    }

    private func exportComposition(_ comp: AVMutableComposition, to url: URL) async {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            guard let exp = AVAssetExportSession(asset: comp,
                                                presetName: AVAssetExportPresetPassthrough) else { return }
            exp.outputURL = url
            exp.outputFileType = .mp4
            await withCheckedContinuation { cont in
                exp.exportAsynchronously { cont.resume() }
            }
        } catch {
            print("Export failed: \(error)")
        }
    }
    
    private func exportScreenshots() {
        guard let comp = composition else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose directory to export screenshots"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                await extractScreenshots(from: comp, to: url)
            }
        }
    }
    
    private func extractScreenshots(from composition: AVMutableComposition, to directory: URL) async {
        isProcessing = true
        defer { isProcessing = false }
        
        let duration = CMTimeGetSeconds(composition.duration)
        let frameInterval: TimeInterval = 60.0 // Extract frame every 60 seconds
        
        print("[Export] Starting screenshot extraction...")
        print("[Export] Video duration: \(String(format: "%.2f", duration))s (\(String(format: "%.2f", duration/60)) minutes)")
        
        let generator = AVAssetImageGenerator(asset: composition)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        
        var currentTime: TimeInterval = 0
        var frameCount = 0
        
        // Create batch folder
        let batchFolder = directory.appendingPathComponent("Batch_\(selected ?? 0)_Screenshots")
        try? FileManager.default.createDirectory(at: batchFolder, withIntermediateDirectories: true)
        
        while currentTime < duration {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            
            do {
                let cgImage = try generator.copyCGImage(at: cmTime, actualTime: nil)
                
                // Downscale by 2/3 for consistency with Ollama
                if let scaledImage = downscaleImage(cgImage: cgImage, scale: 2.0/3.0) {
                    frameCount += 1
                    
                    // Save as JPEG
                    let filename = String(format: "frame_%03d_%02dm%02ds.jpg", frameCount, Int(currentTime/60), Int(currentTime.truncatingRemainder(dividingBy: 60)))
                    let jpegURL = batchFolder.appendingPathComponent(filename)
                    
                    if let dest = CGImageDestinationCreateWithURL(jpegURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                        let props = [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary
                        CGImageDestinationAddImage(dest, scaledImage, props)
                        CGImageDestinationFinalize(dest)
                    }
                    
                    print("[Export] Saved frame \(frameCount) at \(String(format: "%.2f", currentTime))s")
                }
            } catch {
                print("[Export] Failed to extract frame at \(currentTime)s: \(error)")
            }
            
            currentTime += frameInterval
        }
        
        print("[Export] Completed! Exported \(frameCount) screenshots to \(batchFolder.path)")
        
        // Open folder in Finder
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: batchFolder.path)
    }
    
    private func downscaleImage(cgImage: CGImage, scale: CGFloat) -> CGImage? {
        let targetWidth = Int(CGFloat(cgImage.width) * scale)
        let targetHeight = Int(CGFloat(cgImage.height) * scale)
        
        let ciImage = CIImage(cgImage: cgImage)
        
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        
        guard var outputImage = filter.outputImage else { return nil }
        
        // Apply slight sharpening for text clarity
        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(outputImage, forKey: kCIInputImageKey)
            sharpen.setValue(0.3, forKey: "inputSharpness")
            outputImage = sharpen.outputImage ?? outputImage
        }
        
        let context = CIContext(options: [.highQualityDownsample: true])
        return context.createCGImage(outputImage, from: outputImage.extent)
    }

    private func tsString(_ ts: Int) -> String {
        dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }

    private func videoURL(from path: String) -> URL? {
        if path.hasPrefix("file://") {
            return URL(string: path)
        }
        return URL(string: "file://" + path)
    }

    private func prettyJSON(_ text: String?) -> String {
        guard let text, !text.isEmpty,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return text ?? ""
        }
        return prettyString
    }
}

struct TimelineCardRow: View {
    let card: TimelineCard

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(card.startTimestamp) – \(card.endTimestamp)")
                    .font(.caption)
                Text(card.category + " / " + card.subcategory)
                    .font(.caption2)
                Text(card.summary).font(.caption)

                if let path = card.videoSummaryURL,
                   !path.isEmpty,
                   let url = videoURL(from: path) {
                    InlineVideoPlayer(url: url)
                        .frame(height: 120)
                        .cornerRadius(6)
                }

                if let distractions = card.distractions,
                   !distractions.isEmpty {
                    Text("Distractions").font(.subheadline)
                    ForEach(distractions) { d in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.title).bold().font(.caption)
                            Text("\(d.startTime) – \(d.endTime)")
                                .font(.caption2)
                            Text(d.summary).font(.caption2)
                            if let dPath = d.videoSummaryURL,
                               !dPath.isEmpty,
                               let dUrl = videoURL(from: dPath) {
                                InlineVideoPlayer(url: dUrl)
                                    .frame(height: 80)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            Text(card.title).bold()
        }
        .padding(.bottom, 4)
    }

    private func videoURL(from path: String) -> URL? {
        if path.hasPrefix("file://") {
            return URL(string: path)
        }
        return URL(string: "file://" + path)
    }
}

struct LLMCallRow: View {
    let index: Int
    let call: LLMCall
    let dateFormatter: DateFormatter
    let prettyJSON: (String?) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Call \(index + 1) – " + dateFormatter.string(from: call.timestamp ?? Date()))
                .font(.subheadline)
            Text(String(format: "Latency %.2fs", call.latency ?? 0.0))
                .font(.caption2)
            Text("Input:")
                .font(.caption2)
            Text(prettyJSON(call.input))
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            Text("Output:")
                .font(.caption2)
            Text(prettyJSON(call.output))
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.bottom, 6)
    }
}

private struct InlineVideoPlayer: View {
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
            .onDisappear { player.pause() }
    }
}
