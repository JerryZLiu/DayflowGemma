import AVFoundation
import Foundation

enum VideoProcessingError: Error {
    case invalidInputURL
    case assetLoadFailed(Error?)
    case noVideoTracks
    case trackInsertionFailed
    case exportSessionCreationFailed
    case exportFailed(Error?)
    case exportStatusNotCompleted(AVAssetExportSession.Status)
    case assetReaderCreationFailed(Error?)
    case assetWriterCreationFailed(Error?)
    case assetWriterInputCreationFailed
    case assetWriterStartFailed(Error?)
    case frameReadFailed
    case frameAppendFailed
    case directoryCreationFailed(Error?)
    case fileSaveFailed(Error?)
}

actor VideoProcessingService {
    private let fileManager = FileManager.default
    private let temporaryDirectoryURL: URL
    private let persistentTimelapsesRootURL: URL

    init() {
        self.temporaryDirectoryURL = fileManager.temporaryDirectory

        // Create a persistent directory for timelapses within Application Support
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.persistentTimelapsesRootURL = appSupportURL.appendingPathComponent("Dayflow/timelapses", isDirectory: true)

        // Ensure the root timelapses directory exists
        do {
            try fileManager.createDirectory(at: self.persistentTimelapsesRootURL,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
        } catch {
            // Log this, but don't fail initialization.
            print("Error creating persistent timelapses root directory: \(self.persistentTimelapsesRootURL.path). Error: \(error)")
        }
    }

    private func newTemporaryFileURL(`extension` ext: String = "mp4") -> URL {
        temporaryDirectoryURL.appendingPathComponent(UUID().uuidString + "." + ext)
    }

    func generatePersistentTimelapseURL(for date: Date,
                                      originalFileName: String) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let dateSpecificDir = persistentTimelapsesRootURL
            .appendingPathComponent(dateString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: dateSpecificDir,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
        } catch {
            print("Error creating date-specific timelapse directory: \(dateSpecificDir.path). Error: \(error)")
            return persistentTimelapsesRootURL
                .appendingPathComponent(originalFileName + "_timelapse.mp4")
        }

        return dateSpecificDir
            .appendingPathComponent(originalFileName + "_timelapse.mp4")
    }

    /// If multiple URLs, stitches them; if one, copies it to a temp location.
    func prepareVideoForProcessing(urls: [URL]) async throws -> URL {
        guard !urls.isEmpty else { throw VideoProcessingError.invalidInputURL }
        let tempOutputURL = newTemporaryFileURL()

        // Single‑file fast path
        if urls.count == 1, let singleURL = urls.first {
            do {
                if fileManager.fileExists(atPath: tempOutputURL.path) {
                    try fileManager.removeItem(at: tempOutputURL)
                }
                try fileManager.copyItem(at: singleURL, to: tempOutputURL)
                return tempOutputURL
            } catch {
                print("Error copying single video to temporary location: \(error)")
                throw VideoProcessingError.fileSaveFailed(error)
            }
        }

        // Stitch multiple files
        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw VideoProcessingError.noVideoTracks }

        var currentTime = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                print("Warning: No video track in asset: \(url.lastPathComponent)")
                continue
            }

            let timeRange = CMTimeRange(start: .zero,
                                        duration: try await asset.load(.duration))
            do {
                try videoTrack.insertTimeRange(timeRange,
                                               of: assetVideoTrack,
                                               at: currentTime)
                currentTime = currentTime + timeRange.duration
            } catch {
                print("Error inserting asset \(url.lastPathComponent): \(error)")
                throw VideoProcessingError.trackInsertionFailed
            }
        }

        guard
            let exportSession = AVAssetExportSession(asset: composition,
                                                     presetName: AVAssetExportPresetPassthrough)
        else { throw VideoProcessingError.exportSessionCreationFailed }

        exportSession.outputURL = tempOutputURL
                exportSession.outputFileType = .mp4
                await exportSession.export()

                guard exportSession.status == .completed else {
                    print("Stitching export failed. Status: \(exportSession.status). Error: \(exportSession.error?.localizedDescription ?? "No error description available")")
                    throw VideoProcessingError.exportFailed(exportSession.error)
                }

        return tempOutputURL
    }

    /// Extract a single segment from `sourceVideoURL`.
    func extractSegment(from sourceVideoURL: URL,
                        startTime: TimeInterval,
                        duration: TimeInterval) async throws -> URL {
        let asset = AVURLAsset(url: sourceVideoURL)
        let tempOutputURL = newTemporaryFileURL()

        guard
            let exportSession = AVAssetExportSession(asset: asset,
                                                     presetName: AVAssetExportPresetPassthrough)
        else { throw VideoProcessingError.exportSessionCreationFailed }

        let assetDuration = try await asset.load(.duration)
        let timescale = assetDuration.timescale

        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: timescale),
            duration: CMTime(seconds: duration, preferredTimescale: timescale)
        )
        exportSession.outputURL = tempOutputURL
                exportSession.outputFileType = .mp4
                await exportSession.export()

                guard exportSession.status == .completed else {
                    print("Stitching export failed. Status: \(exportSession.status). Error: \(exportSession.error?.localizedDescription ?? "No error description available")")
                    throw VideoProcessingError.exportFailed(exportSession.error)
                }

        return tempOutputURL
    }

    /// Generate a timelapse video by picking frames at interval and re-encoding at higher FPS
    func generateTimelapse(sourceVideoURL: URL,
                          outputTimelapseFileURL: URL,
                          speedupFactor: Int = 8,
                          outputFPS: Int = 30) async throws {
        let asset = AVURLAsset(url: sourceVideoURL)
        guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else {
            print("Error: No video track in \(sourceVideoURL.lastPathComponent)")
            throw VideoProcessingError.noVideoTracks
        }

        // Get video properties
        let duration = try await asset.load(.duration)
        let naturalSize = try await assetTrack.load(.naturalSize)
        let preferredTransform = try await assetTrack.load(.preferredTransform)
        let actualSize = naturalSize.applying(preferredTransform)
        let width = Int(abs(actualSize.width))
        let height = Int(abs(actualSize.height))
        let nominalFrameRate = try await assetTrack.load(.nominalFrameRate)
        
        // Create composition with time mapping for speedup
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video,
                                                                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoProcessingError.noVideoTracks
        }
        
        // Calculate new duration after speedup
        let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / Double(speedupFactor))
        
        // Insert the entire video but we'll use time mapping
        try compositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                           of: assetTrack,
                                           at: .zero)
        
        // Scale the time to achieve speedup
        compositionTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: duration),
                                       toDuration: scaledDuration)
        
        // Set up export session
        guard let exportSession = AVAssetExportSession(asset: composition,
                                                      presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoProcessingError.exportSessionCreationFailed
        }
        
        // Ensure output directory exists
        let outputDir = outputTimelapseFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: outputDir.path) {
            try? fileManager.createDirectory(at: outputDir,
                                           withIntermediateDirectories: true,
                                           attributes: nil)
        }
        if fileManager.fileExists(atPath: outputTimelapseFileURL.path) {
            try? fileManager.removeItem(at: outputTimelapseFileURL)
        }
        
        // Configure export
        exportSession.outputURL = outputTimelapseFileURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Set up video composition to maintain proper dimensions and apply transform
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: width, height: height)
        videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(outputFPS))
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: scaledDuration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        exportSession.videoComposition = videoComposition
        
        // Export
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            print("Timelapse export failed. Status: \(exportSession.status). Error: \(exportSession.error?.localizedDescription ?? "No error description available")")
            throw VideoProcessingError.exportFailed(exportSession.error)
        }
    }

    func cleanupTemporaryFile(at url: URL) {
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
