//
//  LLMService.swift
//  Dayflow
//

import Foundation
import Combine
import AppKit
import AVFoundation
import SwiftUI
import GRDB

protocol GeminiServicing {
    func processBatch(_ batchId: Int64, completion: @escaping (Result<[ActivityCard], Error>) -> Void)
}

final class LLMService: GeminiServicing {
    static let shared: GeminiServicing = LLMService()
    
    private var providerType: LLMProviderType {
        // Read directly from UserDefaults each time
        guard let savedData = UserDefaults.standard.data(forKey: "llmProviderType") else {
            print("[LLMService] DEBUG: No saved data found in UserDefaults for key 'llmProviderType'")
            // Default to Gemini with empty API key
            return .geminiDirect(apiKey: "")
        }
        
        print("[LLMService] DEBUG: Found saved data of size: \(savedData.count) bytes")
        
        do {
            let decoded = try JSONDecoder().decode(LLMProviderType.self, from: savedData)
            print("[LLMService] DEBUG: Successfully decoded provider type: \(decoded)")
            return decoded
        } catch {
            print("[LLMService] DEBUG: Failed to decode provider type: \(error)")
            print("[LLMService] DEBUG: Raw data as string: \(String(data: savedData, encoding: .utf8) ?? "unable to convert to string")")
            // Default to Gemini with empty API key
            return .geminiDirect(apiKey: "")
        }
    }
    
    private var provider: LLMProvider? {
        switch providerType {
        case .geminiDirect(let apiKey):
            guard !apiKey.isEmpty else { return nil }
            return GeminiDirectProvider(apiKey: apiKey)
        case .dayflowBackend(let token, let endpoint):
            guard !token.isEmpty else { return nil }
            return DayflowBackendProvider(token: token, endpoint: endpoint)
        case .ollamaLocal(let endpoint):
            return OllamaProvider(endpoint: endpoint)
        }
    }
    
    // Keep the existing processBatch implementation for backward compatibility
    func processBatch(_ batchId: Int64, completion: @escaping (Result<[ActivityCard], Error>) -> Void) {
        guard let provider = provider else {
            completion(.failure(NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No LLM provider configured. Please configure in settings."])))
            return
        }
        
        Task {
            do {
                // Get batch info from StorageManager
                let batches = StorageManager.shared.allBatches()
                guard let batchInfo = batches.first(where: { $0.0 == batchId }) else {
                    throw NSError(domain: "LLMService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Batch not found"])
                }
                
                let (_, batchStartTs, batchEndTs, _) = batchInfo
                
                // Mark batch as processing
                StorageManager.shared.updateBatch(batchId, status: "processing")
                
                // Get chunk file paths for this batch
                let chunkFiles = StorageManager.shared.getChunkFilesForBatch(batchId: batchId)
                
                guard !chunkFiles.isEmpty else {
                    throw NSError(domain: "LLMService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No recordings in batch"])
                }
                
                // Combine all video files
                
                // Create a combined video for transcription
                let composition = AVMutableComposition()
                var currentTime = CMTime.zero
                
                print("[DEBUG] Combining \(chunkFiles.count) video chunks")
                
                // Create a single video track for all chunks
                guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw NSError(domain: "LLMService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition track"])
                }
                
                for (index, filePath) in chunkFiles.enumerated() {
                    let url = URL(fileURLWithPath: filePath)
                    
                    let asset = AVAsset(url: url)
                    let duration = try await asset.load(.duration)
                    let durationSeconds = CMTimeGetSeconds(duration)
                    
                    print("[DEBUG] Chunk \(index): duration=\(durationSeconds)s, insertAt=\(CMTimeGetSeconds(currentTime))s")
                    
                    if let track = try await asset.loadTracks(withMediaType: .video).first {
                        try compositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: currentTime)
                    }
                    
                    currentTime = CMTimeAdd(currentTime, duration)
                }
                
                let totalDuration = CMTimeGetSeconds(currentTime)
                print("[DEBUG] Total composition duration: \(totalDuration) seconds (\(totalDuration/60) minutes)")
                
                // Export combined video to temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
                
                guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                    throw NSError(domain: "LLMService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create video exporter"])
                }
                
                exporter.outputURL = tempURL
                exporter.outputFileType = .mp4
                
                await exporter.export()
                
                guard exporter.status == .completed else {
                    throw NSError(domain: "LLMService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to export combined video"])
                }
                
                // Load video data
                let videoData = try Data(contentsOf: tempURL)
                let mimeType = "video/mp4"
                print("[DEBUG] Exported video size: \(videoData.count / 1024 / 1024) MB")
                
                // Clean up temp file
                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                
                // Get batch start time for timestamp conversion
                let batchStartDate = Date(timeIntervalSince1970: TimeInterval(batchStartTs))
                
                // Transcribe video
                let (observations, transcribeLog) = try await provider.transcribeVideo(
                    videoData: videoData,
                    mimeType: mimeType,
                    prompt: "Transcribe this video", // Provider will use its own prompt
                    batchStartTime: batchStartDate
                )
                
                // Save observations to database
                StorageManager.shared.saveObservations(batchId: batchId, observations: observations)
                
                // Save transcription log as batch metadata
                if let logData = try? JSONEncoder().encode(transcribeLog),
                   let logString = String(data: logData, encoding: .utf8) {
                    StorageManager.shared.updateBatchMetadata(batchId, metadata: logString)
                }
                
                // If no observations, mark batch as complete with no activities
                guard !observations.isEmpty else {
                    StorageManager.shared.updateBatch(batchId, status: "analyzed")
                    completion(.success([]))
                    return
                }
                
                // Fetch context for activity generation
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let todayString = StorageManager.shared.dateFormatter.string(from: today)
                
                let previousCards = StorageManager.shared.fetchTimelineCards(forDay: todayString)
                let previousSegmentsJSON = previousCards.isEmpty ? "[]" : (try? String(data: JSONEncoder().encode(previousCards), encoding: .utf8)) ?? "[]"
                
                let userTaxonomy = UserDefaults.standard.string(forKey: "userTaxonomy") ?? ""
                let extractedTaxonomy = UserDefaults.standard.string(forKey: "extractedTaxonomy") ?? ""
                
                let context = ActivityGenerationContext(
                    previousSegmentsJSON: previousSegmentsJSON,
                    userTaxonomy: userTaxonomy,
                    extractedTaxonomy: extractedTaxonomy
                )
                
                // Generate activity cards
                let (cards, cardsLog) = try await provider.generateActivityCards(
                    observations: observations,
                    context: context
                )
                
                // Save activity cards as timeline cards
                for card in cards {
                    let timelineCard = TimelineCardShell(
                        startTimestamp: card.startTime,
                        endTimestamp: card.endTime,
                        category: card.category,
                        subcategory: card.subcategory,
                        title: card.title,
                        summary: card.summary,
                        detailedSummary: card.detailedSummary,
                        day: todayString,
                        distractions: card.distractions
                    )
                    
                    _ = StorageManager.shared.saveTimelineCardShell(batchId: batchId, card: timelineCard)
                }
                
                // Mark batch as complete
                StorageManager.shared.updateBatch(batchId, status: "analyzed")
                
                // Extract and save taxonomy
                let allHighlights = cards.flatMap { card in
                    // Extract key terms from summary and detailed summary
                    let words = (card.summary + " " + card.detailedSummary)
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { $0.count > 3 }
                    return words
                }
                
                let extractedTerms = Array(Set(allHighlights))
                    .prefix(50)
                    .joined(separator: ", ")
                
                if !extractedTerms.isEmpty {
                    UserDefaults.standard.set(extractedTerms, forKey: "extractedTaxonomy")
                }
                
                completion(.success(cards))
                
            } catch {
                print("Error processing batch: \(error)")
                
                // Mark batch as failed
                StorageManager.shared.updateBatch(batchId, status: "failed", reason: error.localizedDescription)
                
                completion(.failure(error))
            }
        }
    }
}

