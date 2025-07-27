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
    private let frameExtractionInterval: TimeInterval = 30.0 // Extract frame every 30 seconds
    
    init(endpoint: String = "http://localhost:11434") {
        self.endpoint = endpoint
    }
    
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String, batchStartTime: Date, videoDuration: TimeInterval) async throws -> (observations: [Observation], log: LLMCall) {
        let callStart = Date()
        
        // Save video to temporary file for processing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try videoData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Step 1: Extract frames at intervals
        let extractionStart = Date()
        let frames = try await extractFrames(from: tempURL)
        let extractionTime = Date().timeIntervalSince(extractionStart)
        
        print("[OLLAMA] Extracted \(frames.count) frames in \(String(format: "%.2f", extractionTime))s")
        
        // Step 2: Get simple descriptions for each frame
        var frameDescriptions: [(timestamp: TimeInterval, description: String)] = []
        
        for (index, frame) in frames.enumerated() {
            let frameStart = Date()
            
            let description = try await getSimpleFrameDescription(frame)
            frameDescriptions.append((timestamp: frame.timestamp, description: description))
            
            let frameTime = Date().timeIntervalSince(frameStart)
            print("[OLLAMA] Frame \(index + 1)/\(frames.count) analyzed in \(String(format: "%.2f", frameTime))s")
        }
        
        // Step 3: Merge frame descriptions into coherent observations
        let mergeStart = Date()
        let observations = try await mergeFrameDescriptions(frameDescriptions, batchStartTime: batchStartTime, videoDuration: videoDuration)
        let mergeTime = Date().timeIntervalSince(mergeStart)
        
        print("[OLLAMA] Merged into \(observations.count) observations in \(String(format: "%.2f", mergeTime))s")
        
        let totalTime = Date().timeIntervalSince(callStart)
        
        let log = LLMCall(
            timestamp: callStart,
            latency: totalTime,
            input: "Two-stage processing: \(frames.count) frames → \(observations.count) observations",
            output: "Extracted \(frames.count) frames, merged into \(observations.count) observations in \(String(format: "%.2f", totalTime))s"
        )
        
        return (observations, log)
    }
    
    func generateActivityCards(observations: [Observation], context: ActivityGenerationContext) async throws -> (cards: [ActivityCard], log: LLMCall) {
        let callStart = Date()
        var logs: [String] = []
        
        // Process in 15-minute chunks (but since video batches are already 15 mins, this will be all observations)
        var finalCards: [ActivityCard] = []
        
        // Generate initial activity card
        let (titleSummary, firstLog) = try await generateTitleAndSummary(observations: observations)
        logs.append(firstLog)
        
        let initialCard = ActivityCard(
            startTime: formatTimestampForPrompt(observations.first!.startTs),
            endTime: formatTimestampForPrompt(observations.last!.endTs),
            category: titleSummary.category,
            subcategory: nil,
            title: titleSummary.title,
            summary: titleSummary.summary,
            detailedSummary: nil,
            distractions: nil
        )
        
        // Check if we should merge with previous cards
        if !context.existingCards.isEmpty, let lastExistingCard = context.existingCards.last {
            let (shouldMerge, mergeLog) = try await checkShouldMerge(previousCard: lastExistingCard, newCard: initialCard)
            logs.append(mergeLog)
            
            if shouldMerge {
                let (mergedCard, mergeCreateLog) = try await mergeTwoCards(previousCard: lastExistingCard, newCard: initialCard)
                logs.append(mergeCreateLog)
                
                // Replace the last existing card with the merged version
                var updatedCards = context.existingCards
                updatedCards[updatedCards.count - 1] = mergedCard
                finalCards = updatedCards
            } else {
                // Add as new card
                finalCards = context.existingCards + [initialCard]
            }
        } else {
            finalCards = [initialCard]
        }
        
        let totalLatency = Date().timeIntervalSince(callStart)
        let combinedLog = LLMCall(
            timestamp: callStart,
            latency: totalLatency,
            input: "Two-pass activity card generation",
            output: logs.joined(separator: "\n\n---\n\n")
        )
        
        return (finalCards, combinedLog)
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
            return responseCards.map(convertCard)
        } catch {
            // Try to decode as single object
            do {
                let singleCard = try JSONDecoder().decode(ResponseCard.self, from: data)
                return [convertCard(singleCard)]
            } catch {
                // If that fails, try to extract JSON from the response
            
            guard let responseString = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "OllamaProvider", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to decode response as string"])
            }
            
            // Try to find JSON array in the response
            if let startIndex = responseString.firstIndex(of: "["),
               let endIndex = responseString.lastIndex(of: "]") {
                let jsonSubstring = responseString[startIndex...endIndex]
                if let jsonData = jsonSubstring.data(using: .utf8) {
                    let responseCards = try JSONDecoder().decode([ResponseCard].self, from: jsonData)
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
        
        
        guard durationSeconds > 0 else {
            throw NSError(domain: "OllamaProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video duration"])
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        
        var frames: [FrameData] = []
        var currentTime: TimeInterval = 0
        
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
                    }
                }
            } catch {
                print("[OLLAMA] WARNING: Failed to extract frame at \(currentTime)s: \(error)")
            }
            
            currentTime += frameExtractionInterval
        }
        
        return frames
    }
    
    private func downscaleImage(cgImage: CGImage, scale: CGFloat) -> CGImage? {
        
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
    
    private func getSimpleFrameDescription(_ frame: FrameData) async throws -> String {
        // Simple prompt focused on just describing what's happening
        let prompt = """
        Describe what you see on this computer screen in 1-2 sentences.
        Focus on: what application is open, what the user is doing, and any relevant details visible.
        Be specific and factual.
        """
        
        // Convert base64 data back to string
        guard let base64String = String(data: frame.image, encoding: .utf8) else {
            throw NSError(domain: "OllamaProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image data"])
        }
        
        let request = OllamaRequest(
            model: "qwen2.5vl:3b",
            prompt: prompt,
            images: [base64String]
        )
        
        let response = try await callOllamaAPI(request)
        
        // Return the raw text response (no JSON parsing needed for simple descriptions)
        return response.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func callOllamaAPI(_ request: OllamaRequest) async throws -> OllamaResponse {
        let url = URL(string: "\(endpoint)/api/generate")!
        
        // Retry logic with exponential backoff
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
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
                
                
                guard httpResponse.statusCode == 200 else {
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("[OLLAMA] API Error: \(errorBody)")
                    throw NSError(domain: "OllamaProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Ollama API request failed: \(errorBody)"])
                }
                
                let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
                return ollamaResponse
                
            } catch {
                lastError = error
                print("[OLLAMA] Request failed (attempt \(attempt + 1)/\(maxRetries)): \(error)")
                
                // If it's not the last attempt, wait before retrying
                if attempt < maxRetries - 1 {
                    let backoffDelay = pow(2.0, Double(attempt)) * 2.0 // 2s, 4s, 8s
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? NSError(domain: "OllamaProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Request failed after \(maxRetries) attempts"])
    }
    
    // MARK: - Two-Pass Activity Card Generation
    
    private struct TitleSummaryResponse: Codable {
        let title: String
        let summary: String
        let category: String
    }
    
    private func generateTitleAndSummary(observations: [Observation]) async throws -> (TitleSummaryResponse, String) {
        let observationsText = observations.map { obs in
            let startTime = formatTimestampForPrompt(obs.startTs)
            let endTime = formatTimestampForPrompt(obs.endTs)
            return "[\(startTime) - \(endTime)]: \(obs.observation)"
        }.joined(separator: "\n")
        
        let prompt = """
        You are observing someone's computer activity from the last 15 minutes.
        
        Here are the observations:
        \(observationsText)
        
        Create a title and summary following these guidelines:
        
        Title guidelines:
        Write titles like you're texting a friend about what you did. Natural, conversational, direct.
        Rules:
        - Be specific and clear (not creative or vague)
        - Keep it short - aim for 5-10 words
        - Include main activity + distraction if relevant
        Good examples:
        - "Edited photos in Lightroom"
        - "Python tutorial on Codecademy"
        - "Watched 3 episodes on Netflix"
        - "Wrote blog post, kept checking Instagram"
        - "Researched flights to Tokyo"
        Bad examples:
        - "Early morning digital drift" (too vague/poetic)
        - "Extended Browsing Session" (too formal)
        
        Summary guidelines:
        Write brief factual summaries. First person perspective without "I".
        Rules:
        - State what happened directly - no lead-ins
        - Maximum 2-3 sentences
        - Just the facts: what you did, which tools/projects, major blockers
        Good examples:
        "Refactored the user auth module in React, added OAuth support. Debugged CORS issues with the backend API for an hour."
        "Designed new landing page mockups in Figma. Exported assets and started implementing in Next.js before getting pulled into a client meeting."
        
        Categories to use (pick ONLY ONE):
        - Work: Professional tasks, coding, documentation
        - Research: Learning, reading articles, watching tutorials
        - Communication: Email, messaging, social media interactions
        - Entertainment: Casual browsing, videos, social media consumption
        - Administrative: Account management, billing, settings
        
        Return JSON:
        {
          "title": "Your title here",
          "summary": "Your summary here",
          "category": "Category name"
        }
        """
        
        let request = OllamaRequest(
            model: "qwen2.5vl:3b",
            prompt: prompt,
            images: []
        )
        
        let response = try await callOllamaAPI(request)
        
        // Parse response
        guard let data = response.response.data(using: .utf8) else {
            throw NSError(domain: "OllamaProvider", code: 12, userInfo: [NSLocalizedDescriptionKey: "Failed to parse title/summary response"])
        }
        
        let result = try parseJSONResponse(TitleSummaryResponse.self, from: data)
        return (result, response.response)
    }
    
    private func checkShouldMerge(previousCard: ActivityCard, newCard: ActivityCard) async throws -> (Bool, String) {
        let prompt = """
        Look at these two consecutive activity periods and decide if they should be combined into one card.
        
        Previous activity (\(previousCard.startTime) - \(previousCard.endTime)):
        Title: \(previousCard.title)
        Summary: \(previousCard.summary)
        
        New activity (\(newCard.startTime) - \(newCard.endTime)):
        Title: \(newCard.title)
        Summary: \(newCard.summary)
        
        Should these be combined? ONLY if ALL true:
        - They are the SAME TYPE of activity (e.g., both coding, both watching videos)
        - They are working on the SAME specific task/project
        - BOTH activities are primarily focused (minimal distractions)
        - There's a smooth continuation with no major interruptions
        
        DO NOT combine if ANY true:
        - One is work and the other is entertainment/break
        - Either activity mentions significant distractions (YouTube, social media, etc.)
        - They involve different projects or different stages (e.g., coding vs testing)
        - There's any mention of taking a break or switching context
        
        Return JSON:
        {
          "combine": true or false,
          "reason": "Brief explanation"
        }
        """
        
        let request = OllamaRequest(
            model: "qwen2.5vl:3b",
            prompt: prompt,
            images: []
        )
        
        let response = try await callOllamaAPI(request)
        
        // Parse response
        struct MergeDecision: Codable {
            let combine: Bool
            let reason: String
        }
        
        guard let data = response.response.data(using: .utf8) else {
            throw NSError(domain: "OllamaProvider", code: 13, userInfo: [NSLocalizedDescriptionKey: "Failed to parse merge decision"])
        }
        
        let decision = try parseJSONResponse(MergeDecision.self, from: data)
        return (decision.combine, response.response)
    }
    
    private func mergeTwoCards(previousCard: ActivityCard, newCard: ActivityCard) async throws -> (ActivityCard, String) {
        let prompt = """
        Create a single activity card that covers both time periods.
        
        Activity 1 (\(previousCard.startTime) - \(previousCard.endTime)):
        Title: \(previousCard.title)
        Summary: \(previousCard.summary)
        
        Activity 2 (\(newCard.startTime) - \(newCard.endTime)):
        Title: \(newCard.title)
        Summary: \(newCard.summary)
        
        Create a unified title and summary that covers the entire period from \(previousCard.startTime) to \(newCard.endTime).
        
        Title guidelines:
        - Natural, conversational (5-10 words)
        - Cover the main activities across both periods
        - Don't just list both titles - synthesize them
        
        Summary guidelines:
        - First person without "I"
        - 2-3 sentences maximum
        - Tell the complete story from start to finish
        
        Return JSON:
        {
          "title": "Your merged title",
          "summary": "Your merged summary"
        }
        """
        
        let request = OllamaRequest(
            model: "qwen2.5vl:3b",
            prompt: prompt,
            images: []
        )
        
        let response = try await callOllamaAPI(request)
        
        // Parse response
        struct MergedContent: Codable {
            let title: String
            let summary: String
        }
        
        guard let data = response.response.data(using: .utf8) else {
            throw NSError(domain: "OllamaProvider", code: 14, userInfo: [NSLocalizedDescriptionKey: "Failed to parse merged card"])
        }
        
        let merged = try parseJSONResponse(MergedContent.self, from: data)
        
        let mergedCard = ActivityCard(
            startTime: previousCard.startTime,
            endTime: newCard.endTime,
            category: previousCard.category,
            subcategory: previousCard.subcategory,
            title: merged.title,
            summary: merged.summary,
            detailedSummary: previousCard.detailedSummary,
            distractions: previousCard.distractions
        )
        
        return (mergedCard, response.response)
    }
    
    private func parseJSONResponse<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        // First try direct parsing
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // Try to extract JSON from the response
            guard let responseString = String(data: data, encoding: .utf8) else {
                throw error
            }
            
            // Look for JSON object
            if let startIndex = responseString.firstIndex(of: "{"),
               let endIndex = responseString.lastIndex(of: "}") {
                let jsonSubstring = responseString[startIndex...endIndex]
                if let jsonData = jsonSubstring.data(using: .utf8) {
                    return try JSONDecoder().decode(type, from: jsonData)
                }
            }
            
            throw error
        }
    }
    
    private func formatTimestampForPrompt(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    // MARK: - New Merging Logic
    
    private struct VideoSegment: Codable {
        let startTimestamp: String  // MM:SS format
        let endTimestamp: String    // MM:SS format
        let description: String
    }
    
    private func mergeFrameDescriptions(_ frameDescriptions: [(timestamp: TimeInterval, description: String)], 
                                      batchStartTime: Date, 
                                      videoDuration: TimeInterval) async throws -> [Observation] {
        
        // Format frame descriptions for the prompt
        var formattedDescriptions = ""
        for frame in frameDescriptions {
            let minutes = Int(frame.timestamp) / 60
            let seconds = Int(frame.timestamp) % 60
            let timeStr = String(format: "%02d:%02d", minutes, seconds)
            formattedDescriptions += "[\(timeStr)] \(frame.description)\n"
        }
        
        // Format video duration for the prompt
        let durationMinutes = Int(videoDuration / 60)
        let durationSeconds = Int(videoDuration.truncatingRemainder(dividingBy: 60))
        let durationString = String(format: "%02d:%02d", durationMinutes, durationSeconds)
        
        let mergePrompt = """
        You have \(frameDescriptions.count) snapshots from a \(durationString) video showing someone's computer usage.
        
        CRITICAL TASK: Group these snapshots into EXACTLY 2-5 segments. DO NOT create more than 5 segments under any circumstances.
        
        <thinking>
        Plan how to group the snapshots before outputting. Consider which activities belong together and where natural breaks occur.
        </thinking>
        
        Here are the snapshots:
        \(formattedDescriptions)
        
        STRICT RULES:
        - You MUST create between 2 and 5 segments total (no more, no less)
        - Each segment should cover multiple consecutive snapshots
        - Brief interruptions should be absorbed into the main activity, not split out
        - Segments should tell a coherent story of what was accomplished
        - All timestamps MUST be within 00:00 to \(durationString)
        
        Return a JSON array with this exact format:
        [
          {
            "startTimestamp": "MM:SS",
            "endTimestamp": "MM:SS",
            "description": "Natural description of the activity"
          }
        ]
        
        Good examples:
        [
          {
            "startTimestamp": "00:00",
            "endTimestamp": "05:30",
            "description": "Drafted and sent client proposal email in Gmail, referencing budget spreadsheet and project timeline. Briefly checked Slack notifications twice."
          },
          {
            "startTimestamp": "05:30",
            "endTimestamp": "09:00",
            "description": "Implemented authentication feature in VS Code, debugging JWT token issues. Searched Stack Overflow for solutions and tested API endpoints in Postman."
          },
          {
            "startTimestamp": "09:00",
            "endTimestamp": "14:45",
            "description": "Research session on competitor pricing - compared features across multiple SaaS websites, took notes in Notion, and built comparison spreadsheet in Google Sheets."
          }
        ]
        
        REMEMBER: Output EXACTLY 2-5 segments. If you output more than 5 segments, you have failed the task.
        """
        
        let request = OllamaRequest(
            model: "qwen2.5vl:3b",
            prompt: mergePrompt,
            images: []  // No images needed for this text-based task
        )
        
        let response = try await callOllamaAPI(request)
        
        // Parse the JSON response
        guard let responseData = response.response.data(using: String.Encoding.utf8) else {
            throw NSError(domain: "OllamaProvider", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to parse merge response"])
        }
        
        // Try to extract JSON array from response
        let segments: [VideoSegment]
        do {
            segments = try JSONDecoder().decode([VideoSegment].self, from: responseData)
        } catch {
            // Try to find JSON in the response
            guard let startIndex = response.response.firstIndex(of: "["),
                  let endIndex = response.response.lastIndex(of: "]") else {
                throw NSError(domain: "OllamaProvider", code: 9, userInfo: [NSLocalizedDescriptionKey: "Could not find JSON array in merge response"])
            }
            
            let jsonSubstring = response.response[startIndex...endIndex]
            guard let jsonData = jsonSubstring.data(using: .utf8) else {
                throw NSError(domain: "OllamaProvider", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to extract JSON from response"])
            }
            
            segments = try JSONDecoder().decode([VideoSegment].self, from: jsonData)
        }
        
        // Convert segments to Observations
        let observations = segments.map { segment in
            let startSeconds = parseVideoTimestamp(segment.startTimestamp)
            let endSeconds = parseVideoTimestamp(segment.endTimestamp)
            
            let startDate = batchStartTime.addingTimeInterval(TimeInterval(startSeconds))
            let endDate = batchStartTime.addingTimeInterval(TimeInterval(endSeconds))
            
            return Observation(
                id: nil,
                batchId: 0,  // Will be set when saved
                startTs: Int(startDate.timeIntervalSince1970),
                endTs: Int(endDate.timeIntervalSince1970),
                observation: segment.description,
                metadata: nil,
                llmModel: "qwen2.5vl:3b",
                createdAt: Date()
            )
        }
        
        // Validate we got a reasonable number of observations
        if observations.isEmpty {
            throw NSError(domain: "OllamaProvider", code: 11, userInfo: [NSLocalizedDescriptionKey: "No observations generated from merge"])
        }
        
        if observations.count > 5 {
            print("[OLLAMA] Warning: Generated \(observations.count) observations, expected 2-5")
        }
        
        return observations
    }
}
