//
//  OllamaProvider.swift
//  Dayflow
//

import Foundation
import AVFoundation
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

final class OllamaProvider: LLMProvider {
    private let endpoint: String
    private let frameExtractionInterval: TimeInterval = 60.0 // Extract frame every 60 seconds
    
    init(endpoint: String = "http://localhost:11434") {
        self.endpoint = endpoint
    }
    
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String, batchStartTime: Date, videoDuration: TimeInterval) async throws -> (observations: [Observation], log: LLMCall) {
        let callStart = Date()
        print("\n🚀 [OLLAMA] Starting observation generation at \(formatTime(callStart))")
        print("[OLLAMA] Video size: \(videoData.count / 1024 / 1024) MB")
        print("[OLLAMA] Batch start time: \(batchStartTime)")
        print("📹 [OLLAMA] Video duration: \(String(format: "%.2f", videoDuration)) seconds (\(String(format: "%.1f", videoDuration/60)) minutes)")
        
        // Save video to temporary file for processing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try videoData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Extract frames at intervals
        print("[OLLAMA] Extracting frames at \(frameExtractionInterval)s intervals...")
        let extractionStart = Date()
        let frames = try await extractFrames(from: tempURL)
        let extractionTime = Date().timeIntervalSince(extractionStart)
        print("[OLLAMA] Extracted \(frames.count) frames in \(String(format: "%.2f", extractionTime))s")
        
        // Process each frame with Ollama
        var observations: [Observation] = []
        print("[OLLAMA] Processing frames with Qwen 2.5 VL...")
        
        for (index, frame) in frames.enumerated() {
            let frameStart = Date()
            print("[OLLAMA] Processing frame \(index + 1)/\(frames.count) at timestamp \(frame.timestamp)s...")
            
            let observation = try await analyzeFrame(frame, batchStartTime: batchStartTime)
            observations.append(observation)
            
            let frameTime = Date().timeIntervalSince(frameStart)
            print("[OLLAMA] Frame \(index + 1) processed in \(String(format: "%.2f", frameTime))s")
            print("[OLLAMA] Observation: \(observation.observation)")
        }
        
        let totalTime = Date().timeIntervalSince(callStart)
        print("[OLLAMA] Total transcription time: \(String(format: "%.2f", totalTime))s")
        print("[OLLAMA] Average time per frame: \(String(format: "%.2f", totalTime / Double(frames.count)))s\n")
        
        let log = LLMCall(
            timestamp: callStart,
            latency: totalTime,
            input: "Frame extraction at \(frameExtractionInterval)s intervals",
            output: "Processed \(observations.count) frames in \(String(format: "%.2f", totalTime))s"
        )
        
        let duration = Date().timeIntervalSince(callStart)
        print("✅ [OLLAMA] Observation generation completed in \(String(format: "%.2f", duration)) seconds")
        
        return (observations, log)
    }
    
    func generateActivityCards(observations: [Observation], context: ActivityGenerationContext) async throws -> (cards: [ActivityCard], log: LLMCall) {
        let callStart = Date()
        print("\n🚀 [OLLAMA] Starting activity card generation at \(formatTime(callStart))")
        
        // Format observations for the prompt
        let observationsText = observations.map { obs in
            let startTime = formatTimestampForPrompt(obs.startTs)
            let endTime = formatTimestampForPrompt(obs.endTs)
            return "[\(startTime) - \(endTime)]: \(obs.observation)"
        }.joined(separator: "\n")
        
        let prompt = """
        Based on these observations, create activity cards that group related activities together.
        Each activity should be at least 5 minutes long. Sub-5 minute detours should be marked as distractions.
        
        Observations:
        \(observationsText)
        
        User taxonomy: \(context.userTaxonomy)
        
        Return a JSON array of activity cards:
        [
          {
            "startTime": "HH:MM AM/PM",
            "endTime": "HH:MM AM/PM",
            "category": "category name",
            "subcategory": "subcategory name",
            "title": "1-3 word title",
            "summary": "1-2 sentences about what was accomplished",
            "detailedSummary": "longer description for future context",
            "distractions": [
              {
                "startTime": "HH:MM AM/PM",
                "endTime": "HH:MM AM/PM",
                "title": "distraction title",
                "summary": "what happened"
              }
            ]
          }
        ]
        """
        
        let request = OllamaRequest(
            model: "qwen2.5vl:3b",
            prompt: prompt,
            images: []  // No images for this request
        )
        
        let response = try await callOllamaAPI(request)
        
        // Parse the response
        guard let responseData = response.response.data(using: .utf8) else {
            throw NSError(domain: "OllamaProvider", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }
        
        // Debug: Log raw response
        let rawResponse = String(data: responseData, encoding: .utf8) ?? "Unable to decode"
        print("[OLLAMA] Raw activity cards response: \(rawResponse.prefix(200))...")
        
        let cards = try parseActivityCards(from: responseData)
        
        let log = LLMCall(
            timestamp: callStart,
            latency: Date().timeIntervalSince(callStart),
            input: prompt,
            output: response.response
        )
        
        let duration = Date().timeIntervalSince(callStart)
        print("✅ [OLLAMA] Activity card generation completed in \(String(format: "%.2f", duration)) seconds")
        
        return (cards, log)
    }
    
    private func parseActivityCards(from data: Data) throws -> [ActivityCard] {
        // Define response structure
        struct ResponseCard: Codable {
            let startTime: String
            let endTime: String
            let category: String
            let subcategory: String
            let title: String
            let summary: String
            let detailedSummary: String
            let distractions: [ResponseDistraction]?
        }
        
        struct ResponseDistraction: Codable {
            let startTime: String
            let endTime: String
            let title: String
            let summary: String
        }
        
        // Helper function to convert ResponseCard to ActivityCard
        func convertCard(_ card: ResponseCard) -> ActivityCard {
            return ActivityCard(
                startTime: card.startTime,
                endTime: card.endTime,
                category: card.category,
                subcategory: card.subcategory,
                title: card.title,
                summary: card.summary,
                detailedSummary: card.detailedSummary,
                distractions: card.distractions?.map { d in
                    Distraction(
                        startTime: d.startTime,
                        endTime: d.endTime,
                        title: d.title,
                        summary: d.summary
                    )
                }
            )
        }
        
        // First try to decode as array
        do {
            let responseCards = try JSONDecoder().decode([ResponseCard].self, from: data)
            print("[OLLAMA] Successfully parsed \(responseCards.count) activity cards")
            return responseCards.map(convertCard)
        } catch {
            // Try to decode as single object
            do {
                let singleCard = try JSONDecoder().decode(ResponseCard.self, from: data)
                print("[OLLAMA] Successfully parsed single activity card")
                return [convertCard(singleCard)]
            } catch {
                // If that fails, try to extract JSON from the response
                print("[OLLAMA] Failed to parse directly, attempting to extract JSON...")
            
            guard let responseString = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "OllamaProvider", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to decode response as string"])
            }
            
            // Try to find JSON array in the response
            if let startIndex = responseString.firstIndex(of: "["),
               let endIndex = responseString.lastIndex(of: "]") {
                let jsonSubstring = responseString[startIndex...endIndex]
                if let jsonData = jsonSubstring.data(using: .utf8) {
                    let responseCards = try JSONDecoder().decode([ResponseCard].self, from: jsonData)
                    print("[OLLAMA] Successfully extracted and parsed \(responseCards.count) activity cards")
                    return responseCards.map(convertCard)
                }
            }
            
                throw NSError(domain: "OllamaProvider", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not find valid JSON array in response: \(error.localizedDescription)"])
            }
        }
    }
    
    // MARK: - Frame Extraction
    
    private struct FrameData {
        let image: Data  // Base64 encoded image
        let timestamp: TimeInterval  // Seconds from video start
    }
    
    private func extractFrames(from videoURL: URL) async throws -> [FrameData] {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        print("[OLLAMA] Video duration: \(String(format: "%.2f", durationSeconds))s (\(String(format: "%.2f", durationSeconds/60)) minutes)")
        
        guard durationSeconds > 0 else {
            throw NSError(domain: "OllamaProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video duration"])
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        
        var frames: [FrameData] = []
        var currentTime: TimeInterval = 0
        let expectedFrames = Int(durationSeconds / frameExtractionInterval) + 1
        print("[OLLAMA] Expecting to extract ~\(expectedFrames) frames")
        
        while currentTime < durationSeconds {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            
            do {
                let cgImage = try generator.copyCGImage(at: cmTime, actualTime: nil)
                
                // Convert CGImage to JPEG data
                // Downscale by 2/3 for optimal quality/size balance
                if let scaledImage = downscaleImage(cgImage: cgImage, scale: 2.0/3.0) {
                    if let imageData = cgImageToJPEGData(scaledImage) {
                        // Convert to base64
                        let base64String = imageData.base64EncodedString()
                        let base64Data = Data(base64String.utf8)
                        
                        frames.append(FrameData(image: base64Data, timestamp: currentTime))
                        print("[OLLAMA] Extracted frame \(frames.count) at \(String(format: "%.2f", currentTime))s")
                    }
                }
            } catch {
                print("[OLLAMA] WARNING: Failed to extract frame at \(currentTime)s: \(error)")
            }
            
            currentTime += frameExtractionInterval
        }
        
        print("[OLLAMA] Successfully extracted \(frames.count) frames")
        return frames
    }
    
    private func downscaleImage(cgImage: CGImage, scale: CGFloat) -> CGImage? {
        let targetWidth = Int(CGFloat(cgImage.width) * scale)
        let targetHeight = Int(CGFloat(cgImage.height) * scale)
        
        // Create CIImage and apply Lanczos scaling
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
        
        // Render with high quality
        let context = CIContext(options: [
            .highQualityDownsample: true
        ])
        
        return context.createCGImage(outputImage, from: outputImage.extent)
    }
    
    private func cgImageToJPEGData(_ cgImage: CGImage) -> Data? {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        // Higher quality JPEG for better text
        let jpegData = bitmapRep.representation(using: .jpeg, properties: [
            NSBitmapImageRep.PropertyKey.compressionFactor: 0.95
        ])
        
        if let data = jpegData {
            let sizeKB = Double(data.count) / 1024.0
            print("[OLLAMA] Frame size: \(cgImage.width)x\(cgImage.height) -> \(String(format: "%.1f", sizeKB)) KB")
        }
        
        return jpegData
    }
    
    // MARK: - Ollama API
    
    private struct OllamaRequest: Codable {
        let model: String
        let prompt: String
        let images: [String]  // Base64 encoded images
        let stream: Bool = false
        let format: String = "json"
    }
    
    private struct OllamaResponse: Codable {
        let response: String
        let done: Bool
    }
    
    private struct FrameAnalysis: Codable {
        let analysis: String
        let observation: String
    }
    
    private func analyzeFrame(_ frame: FrameData, batchStartTime: Date) async throws -> Observation {
        // Calculate actual timestamp
        let frameDate = batchStartTime.addingTimeInterval(frame.timestamp)
        let startTs = Int(frameDate.timeIntervalSince1970)
        let endTs = startTs + 30  // Each observation covers 30 seconds
        
        // Create prompt for Qwen 2.5 VL
        let prompt = """
        Analyze this screenshot and describe what the user is doing. Focus on their intent and task, not just what's visible.

        Provide a 1-3 sentence summary covering:
        - What they're trying to accomplish
        - The main app/website they're using
        - Any relevant context from other visible elements

        Return your response in this exact JSON format:
        {
          "analysis": "<your reasoning about what you see and what the user might be doing>",
          "observation": "<your final 1-3 sentence description of the user's activity>"
        }

        Examples:
        {
          "analysis": "Xcode is open with Swift code visible and there's an error or debugging interface. Another window shows documentation which suggests they're trying to solve a specific issue.",
          "observation": "User is debugging a Swift app in Xcode, focusing on fixing a freeze issue in the GeminiService class. Has documentation open in another window for reference."
        }

        {
          "analysis": "Gmail compose window is open and there's a spreadsheet visible with what looks like financial data. This combination suggests business communication about project metrics.",
          "observation": "User is writing a project status email in Gmail while referencing budget data from an Excel spreadsheet in another window."
        }

        Keep it brief and direct. Don't list UI elements in the observation.
        """
        
        // Convert base64 data back to string
        guard let base64String = String(data: frame.image, encoding: .utf8) else {
            throw NSError(domain: "OllamaProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image data"])
        }
        
        let request = OllamaRequest(
            model: "qwen2.5vl:3b",  // Using Qwen 2.5 VL
            prompt: prompt,
            images: [base64String]
        )
        
        let response = try await callOllamaAPI(request)
        
        // Parse the JSON response
        guard let responseData = response.response.data(using: .utf8),
              let analysis = try? JSONDecoder().decode(FrameAnalysis.self, from: responseData) else {
            throw NSError(domain: "OllamaProvider", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Ollama response"])
        }
        
        // Create observation
        let observation = Observation(
            id: nil,
            batchId: 0,  // Will be set when saved
            startTs: startTs,
            endTs: endTs,
            observation: analysis.observation,
            metadata: nil,  // No longer extracting application name separately
            llmModel: "qwen2.5vl:3b",
            createdAt: Date()
        )
        
        return observation
    }
    
    private func callOllamaAPI(_ request: OllamaRequest) async throws -> OllamaResponse {
        let url = URL(string: "\(endpoint)/api/generate")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let apiStart = Date()
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let apiTime = Date().timeIntervalSince(apiStart)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OllamaProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        print("[OLLAMA] API response: \(httpResponse.statusCode) in \(String(format: "%.2f", apiTime))s")
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[OLLAMA] API Error: \(errorBody)")
            throw NSError(domain: "OllamaProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Ollama API request failed: \(errorBody)"])
        }
        
        let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return ollamaResponse
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
