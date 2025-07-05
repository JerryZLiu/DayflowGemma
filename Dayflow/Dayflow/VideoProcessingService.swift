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
    private let persistentSummariesRootURL: URL

    init() {
        self.temporaryDirectoryURL = fileManager.temporaryDirectory

        // Create a persistent directory for summaries within Application Support
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.persistentSummariesRootURL = appSupportURL.appendingPathComponent("Dayflow/summaries", isDirectory: true)

        // Ensure the root summaries directory exists
        do {
            try fileManager.createDirectory(at: self.persistentSummariesRootURL,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
        } catch {
            // Log this, but don't fail initialization.
            print("Error creating persistent summaries root directory: \(self.persistentSummariesRootURL.path). Error: \(error)")
        }
    }

    private func newTemporaryFileURL(`extension` ext: String = "mp4") -> URL {
        temporaryDirectoryURL.appendingPathComponent(UUID().uuidString + "." + ext)
    }

    func generatePersistentSummaryURL(for date: Date,
                                      originalFileName: String) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let dateSpecificDir = persistentSummariesRootURL
            .appendingPathComponent(dateString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: dateSpecificDir,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
        } catch {
            print("Error creating date-specific summary directory: \(dateSpecificDir.path). Error: \(error)")
            return persistentSummariesRootURL
                .appendingPathComponent(originalFileName + "_summary.mp4")
        }

        return dateSpecificDir
            .appendingPathComponent(originalFileName + "_summary.mp4")
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

    /// Pick every N‑th frame and re‑encode at `outputFPS`.
    func generateVideoSummary(sourceVideoURL: URL,
                              outputSummaryFileURL: URL,
                              inputFramePickIntervalFactorN: Int,
                              outputFPS: Int = 2) async throws {
        let asset = AVURLAsset(url: sourceVideoURL)
        guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else {
            print("Error: No video track in \(sourceVideoURL.lastPathComponent)")
            throw VideoProcessingError.noVideoTracks
        }

        // Resolve dimensions after transform
        let naturalSize = try await assetTrack.load(.naturalSize)
        let preferredTransform = try await assetTrack.load(.preferredTransform)
        let actualSize = naturalSize.applying(preferredTransform)
        let width = Int(abs(actualSize.width))
        let height = Int(abs(actualSize.height))

        // Reader
        let assetReader = try AVAssetReader(asset: asset)
        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
        ]
        let readerVideoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [assetTrack],
                                                                    videoSettings: readerOutputSettings)

        // Apply transform via a composition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: width, height: height)
        let fps = max(1, Int(try await assetTrack.load(.nominalFrameRate)))
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: Int32(fps))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero,
                                            duration: try await asset.load(.duration))

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: assetTrack)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        readerVideoOutput.videoComposition = videoComposition
        guard assetReader.canAdd(readerVideoOutput) else {
            throw VideoProcessingError.assetReaderCreationFailed(nil)
        }
        assetReader.add(readerVideoOutput)

        // Writer
        let outputDir = outputSummaryFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: outputDir.path) {
            try? fileManager.createDirectory(at: outputDir,
                                             withIntermediateDirectories: true,
                                             attributes: nil)
        }
        if fileManager.fileExists(atPath: outputSummaryFileURL.path) {
            try? fileManager.removeItem(at: outputSummaryFileURL)
        }

        let assetWriter = try AVAssetWriter(outputURL: outputSummaryFileURL,
                                            fileType: .mp4)
        let writerInputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video,
                                             outputSettings: writerInputSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard assetWriter.canAdd(writerInput) else {
            throw VideoProcessingError.assetWriterInputCreationFailed
        }
        assetWriter.add(writerInput)
        guard assetWriter.startWriting() else {
            throw VideoProcessingError.assetWriterStartFailed(assetWriter.error)
        }
        assetWriter.startSession(atSourceTime: .zero)

        // Read & write
        var inputFrameCount: Int64 = 0
        var outputFrameCount: Int64 = 0
        assetReader.startReading()

        while assetReader.status == .reading,
              let sampleBuffer = readerVideoOutput.copyNextSampleBuffer() {

            if inputFrameCount % Int64(inputFramePickIntervalFactorN) == 0,
               writerInput.isReadyForMoreMediaData {

                var timing = CMSampleTimingInfo(
                    duration: CMSampleBufferGetDuration(sampleBuffer),
                    presentationTimeStamp: CMTime(value: outputFrameCount,
                                                  timescale: Int32(outputFPS)),
                    decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
                )
                var newBuffer: CMSampleBuffer?
                let status = CMSampleBufferCreateCopyWithNewTiming(
                    allocator: kCFAllocatorDefault,
                    sampleBuffer: sampleBuffer,
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: &timing,
                    sampleBufferOut: &newBuffer
                )
                if status == noErr, let final = newBuffer {
                    writerInput.append(final)
                    outputFrameCount += 1
                }
            }
            inputFrameCount += 1
        }

        writerInput.markAsFinished()
        await assetWriter.finishWriting()

        if assetWriter.status != .completed {
            throw VideoProcessingError.exportFailed(assetWriter.error)
        }
    }

    func cleanupTemporaryFile(at url: URL) {
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
