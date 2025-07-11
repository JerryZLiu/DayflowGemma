//
//  GeminiDirectProvider.swift
//  Dayflow
//

import Foundation

final class GeminiDirectProvider: LLMProvider {
    private let apiKey: String
    private let genEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    private let fileEndpoint = "https://generativelanguage.googleapis.com/upload/v1beta/files"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String, batchStartTime: Date) async throws -> (observations: [Observation], log: LLMCall) {
        let callStart = Date()
        
        // First, save video data to a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try videoData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let fileURI = try await uploadAndAwait(tempURL, mimeType: mimeType, key: apiKey).1
        
        let finalTranscriptionPrompt = """
        # Video Transcription Prompt

        Your job is to transcribe someone's computer usage into a small number of meaningful activity segments.

        ## Golden Rule: Aim for 3-5 segments per 15-minute video (fewer is better than more)

        ## Core Principles:
        1. **Group by purpose, not by platform** - If someone is planning a trip across 5 websites, that's ONE segment
        2. **Include interruptions in the description** - Don't create segments for brief distractions
        3. **Only split when context changes for 2-3+ minutes** - Quick checks don't count as context switches
        4. **Combine related activities** - Multiple videos on the same topic = one segment
        5. **Think in terms of "sessions"** - What would you tell a friend you spent time doing?

        ## When to create a new segment:
        Only when the user switches to a COMPLETELY different purpose for MORE than 2-3 minutes:
        - Entertainment → Work
        - Learning → Shopping  
        - Project A → Project B
        - Topic X → Unrelated Topic Y

        ## Format:
        ```json
        [
          {
            "startTimestamp": "MM:SS",
            "endTimestamp": "MM:SS", 
            "description": "1-3 sentences describing what the user accomplished"
          }
        ]
        ```

        ## Examples:

        **GOOD - Properly condensed:**
        ```json
        [
          {
            "startTimestamp": "00:00",
            "endTimestamp": "06:45",
            "description": "User plans a trip to Japan, researching flights on multiple booking sites, reading hotel reviews, and watching YouTube videos about Tokyo neighborhoods. They briefly check email twice and respond to a text message during their research."
          },
          {
            "startTimestamp": "06:45", 
            "endTimestamp": "10:30",
            "description": "User takes an online Spanish course, completing lesson exercises and watching grammar explanation videos. They use Google Translate to verify some phrases and briefly check Reddit when they get stuck on a difficult concept."
          },
          {
            "startTimestamp": "10:30",
            "endTimestamp": "14:58",
            "description": "User shops for home gym equipment, comparing prices across Amazon, fitness retailer sites, and watching product review videos. They check their banking app to verify their budget midway through."
          }
        ]
        ```

        **BAD - Too many segments:**
        ```json
        [
          {
            "startTimestamp": "00:00",
            "endTimestamp": "02:00",
            "description": "User searches for flights to Tokyo"
          },
          {
            "startTimestamp": "02:00",
            "endTimestamp": "02:30", 
            "description": "User checks email"
          },
          {
            "startTimestamp": "02:30",
            "endTimestamp": "04:00",
            "description": "User looks at hotels in Tokyo"
          },
          {
            "startTimestamp": "04:00",
            "endTimestamp": "05:00",
            "description": "User watches a Tokyo travel video"
          }
        ]
        ```

        **ALSO BAD - Splitting brief interruptions:**
        ```json
        [
          {
            "startTimestamp": "00:00",
            "endTimestamp": "05:00",
            "description": "User shops for gym equipment"
          },
          {
            "startTimestamp": "05:00",
            "endTimestamp": "05:45",
            "description": "User checks their bank balance"
          },
          {
            "startTimestamp": "05:45",
            "endTimestamp": "10:00",
            "description": "User continues shopping for gym equipment"
          }
        ]
        ```

        **CORRECT way to handle the above:**
        ```json
        [
          {
            "startTimestamp": "00:00",
            "endTimestamp": "10:00",
            "description": "User shops for home gym equipment across multiple retailers, comparing dumbbells, benches, and resistance bands. They briefly check their bank balance around the 5-minute mark to confirm their budget before continuing."
          }
        ]
        ```

        Remember: The goal is to tell the story of what someone accomplished, not log every click. Group aggressively and only split when they truly change what they're doing for an extended period. If an activity is less than 2-3 minutes, it almost never deserves its own segment.
        """
        
        let response = try await geminiTranscribeRequest(
            fileURI: fileURI,
            mimeType: mimeType,
            prompt: finalTranscriptionPrompt
        )
        
        let videoTranscripts = try parseTranscripts(response)
        
        // Convert video transcripts to observations with proper Unix timestamps
        let observations = videoTranscripts.map { chunk in
            let startSeconds = parseVideoTimestamp(chunk.startTimestamp)
            let endSeconds = parseVideoTimestamp(chunk.endTimestamp)
            let startDate = batchStartTime.addingTimeInterval(TimeInterval(startSeconds))
            let endDate = batchStartTime.addingTimeInterval(TimeInterval(endSeconds))
            
            return Observation(
                id: nil,
                batchId: 0, // Will be set when saved
                startTs: Int(startDate.timeIntervalSince1970),
                endTs: Int(endDate.timeIntervalSince1970),
                observation: chunk.description,
                metadata: nil,
                llmModel: "gemini-2.5-flash",
                createdAt: Date()
            )
        }
        
        let log = LLMCall(
            timestamp: callStart,
            latency: Date().timeIntervalSince(callStart),
            input: finalTranscriptionPrompt,
            output: response
        )
        
        return (observations, log)
    }
    
    func generateActivityCards(observations: [Observation], context: ActivityGenerationContext) async throws -> (cards: [ActivityCard], log: LLMCall) {
        let callStart = Date()
        
        // Convert observations to human-readable format for the prompt
        let transcriptText = observations.map { obs in
            let startTime = formatTimestampForPrompt(obs.startTs)
            let endTime = formatTimestampForPrompt(obs.endTs)
            print("[\(startTime) - \(endTime)]: \(obs.observation)")
            return "[" + startTime + " - " + endTime + "]: " + obs.observation
        }.joined(separator: "\n")
        
        print("[DEBUG-GEMINI] Building transcript text from \(observations.count) observations")
        print("[DEBUG-GEMINI] First 3 observations in prompt format:")
        for (index, obs) in observations.prefix(3).enumerated() {
            let startTime = formatTimestampForPrompt(obs.startTs)
            let endTime = formatTimestampForPrompt(obs.endTs)
            print("[DEBUG-GEMINI] Observation \(index): [\(startTime) - \(endTime)]: \(obs.observation.prefix(100))...")
        }
        
        print("transcript_text: \(transcriptText)")
        
        // Convert existing cards to JSON string
        let existingCardsJSON = try JSONEncoder().encode(context.existingCards)
        let existingCardsString = String(data: existingCardsJSON, encoding: .utf8) ?? "[]"
        
        // Format current time
        let formatter = ISO8601DateFormatter()
        let currentTimeStr = formatter.string(from: context.currentTime)
        
        // Get the last card title for continuity hint
        let lastCardTitle = context.existingCards.last?.title ?? "None"
        
        let activityGenerationPrompt = """
        You are a digital anthropologist, observing a user's raw activity log. Your goal is to synthesize this log into a high-level, human-readable story of their session, presented as a series of timeline cards.
        THE GOLDEN RULE:
        Your primary objective is to create long, meaningful cards that represent a cohesive session of activity, ideally 30-60 minutes or longer. Avoid creating cards shorter than 15-20 minutes unless a major context switch forces it.
        CRITICAL DATA INTEGRITY RULE:
        When you decide to extend a card, its original startTime is IMMUTABLE. You MUST carry over the startTime from the previous_card you are extending.
        YOUR THINKING PROCESS:
        Before providing your final JSON output, you must follow this internal monologue process:
        Step 1: Identify Key Narrative Chapters.
        First, scan all the observations. Identify the primary "chapters" of the user's session. For this specific log, the major chapters are:
        Initial Car Research (approx. 5:00-6:05)
        Software Development Work (approx. 6:05-6:37)
        Financial Car Research (approx. 6:37-6:58)
        Form a plan to group the activities into these three main narrative arcs.
        Step 2: Generate a Draft Timeline.
        Create a draft timeline based on your plan. As you process the log, apply the following logic:
        Extend by Default: Your first instinct should be to extend the current card if the new observations are part of the same chapter you identified in Step 1.
        Split on Chapter Boundaries: Create a new card only when the user clearly transitions from one of the major chapters to the next (e.g., from Initial Car Research to Software Development Work).
        Handle Distractions: A brief, unrelated pivot (<10 min) where the user quickly returns to the chapter's main theme is a distraction, not a reason to split.
        Step 3: Final Review and Self-Correction.
        Before finalizing, review your generated draft against the rules and your plan from Step 1. Ask yourself:
        Narrative Check: Does this timeline tell a clear story with three distinct chapters?
        Boundary Check: Are the boundaries between the chapters clean? Have I accidentally merged the work session with car research?
        Golden Rule Check: Are the cards a meaningful length? Have I avoided creating tiny, fragmented cards?
        Integrity Check: Does the timeline start at 5:00 AM and cover the full duration?
        If your draft fails any of these checks, revise it until it is a high-quality, A-Grade summary. Only then, provide the final JSON output.
        INPUTS:
        Previous cards: \(existingCardsString)
        New observations: \(transcriptText)
        """
        
        print(activityGenerationPrompt)
        
        let response = try await geminiCardsRequest(
            prompt: activityGenerationPrompt
        )
        
        let cards = try parseActivityCards(response)
        
        let log = LLMCall(
            timestamp: callStart,
            latency: Date().timeIntervalSince(callStart),
            input: activityGenerationPrompt,
            output: response
        )
        
        return (cards, log)
    }
    
    // MARK: - Gemini-specific methods (from original GeminiService)
    
    private func uploadAndAwait(_ fileURL: URL, mimeType: String, key: String, maxWaitTime: TimeInterval = 6 * 60) async throws -> (fileSize: Int64, fileURI: String) {
        let fileData = try Data(contentsOf: fileURL)
        let fileSize = fileData.count
        var uploadedFileURI: String? = nil
        
        print("[DEBUG] Uploading file of size: \(fileSize / 1024 / 1024) MB")
        
        // Always use resumable upload
        print("[DEBUG] Using resumable upload")
        uploadedFileURI = try await uploadResumable(data: fileData, mimeType: mimeType)
        
        guard let fileURI = uploadedFileURI else {
            throw NSError(domain: "GeminiError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to upload file"])
        }
        
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < maxWaitTime {
            let status = try await getFileStatus(fileURI: fileURI)
            if status == "ACTIVE" {
                return (Int64(fileSize), fileURI)
            }
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
        
        throw NSError(domain: "GeminiError", code: 2, userInfo: [NSLocalizedDescriptionKey: "File processing timeout"])
    }
    
    private func uploadSimple(data: Data, mimeType: String) async throws -> String {
        var request = URLRequest(url: URL(string: fileEndpoint + "?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        
        if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let file = json["file"] as? [String: Any],
           let uri = file["uri"] as? String {
            return uri
        }
        
        throw NSError(domain: "GeminiError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse upload response"])
    }
    
private func uploadResumable(data: Data, mimeType: String) async throws -> String {
        let metadata = GeminiFileMetadata(file: GeminiFileInfo(displayName: "dayflow_video"))
        let boundary = UUID().uuidString
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(try JSONEncoder().encode(metadata))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        var request = URLRequest(url: URL(string: fileEndpoint + "?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Raw-Size")
        request.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(metadata)
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        print("[DEBUG] Resumable upload init response status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        if let httpResponse = response as? HTTPURLResponse {
            print("[DEBUG] Response headers: \(httpResponse.allHeaderFields)")
        }
        if let responseString = String(data: responseData, encoding: .utf8) {
            print("[DEBUG] Response body: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              let uploadURL = httpResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL") else {
            throw NSError(domain: "GeminiError", code: 4, userInfo:  [NSLocalizedDescriptionKey: "No upload URL in response"])
        }
        
        var uploadRequest = URLRequest(url: URL(string: uploadURL)!)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.httpBody = data
        
        let (uploadResponseData, _) = try await URLSession.shared.data(for: uploadRequest)
        
        if let json = try JSONSerialization.jsonObject(with: uploadResponseData) as? [String: Any],
           let file = json["file"] as? [String: Any],
           let uri = file["uri"] as? String {
            return uri
        }
        
        throw NSError(domain: "GeminiError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse upload response"])
    }
    
    private func getFileStatus(fileURI: String) async throws -> String {
        guard let url = URL(string: fileURI + "?key=\(apiKey)") else {
            throw NSError(domain: "GeminiError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid file URI"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let state = json["state"] as? String {
            return state
        }
        
        return "UNKNOWN"
    }
    
    private func geminiTranscribeRequest(fileURI: String, mimeType: String, prompt: String) async throws -> String {
        let transcriptionSchema: [String:Any] = [
          "type":"ARRAY",
          "items": [
            "type":"OBJECT",
            "properties":[
              "startTimestamp":["type":"STRING"],
              "endTimestamp":  ["type":"STRING"],
              "description":   ["type":"STRING"]
            ],
            "required":["startTimestamp","endTimestamp","description"],
            "propertyOrdering":["startTimestamp","endTimestamp","description"]
          ]
        ]
        
        let generationConfig: [String: Any] = [
            "temperature": 0.3,
            "maxOutputTokens": 65536,
            "responseMimeType": "application/json",
            "responseSchema": transcriptionSchema,
            "thinkingConfig": [
                "thinkingBudget": 24576
            ]
        ]

        let requestBody: [String: Any] = [
            "contents": [["parts": [
                ["file_data": ["mime_type": mimeType, "file_uri": fileURI]],
                ["text": prompt]
            ]]],
            "generationConfig": generationConfig
        ]
        
        // Retry logic with exponential backoff
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                var request = URLRequest(url: URL(string: genEndpoint + "?key=\(apiKey)")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                request.timeoutInterval = 120 // 2 minutes timeout
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Check for rate limiting
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    let delay = TimeInterval(retryAfter ?? "60") ?? 60
                    print("[DEBUG] Rate limited, retrying after \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    throw NSError(domain: "GeminiError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                }
                
                return text
                
            } catch {
                lastError = error
                
                // If it's not the last attempt, wait before retrying
                if attempt < maxRetries - 1 {
                    let backoffDelay = pow(2.0, Double(attempt)) * 5.0 // 5s, 10s, 20s
                    print("[DEBUG] Gemini transcribe request failed (attempt \(attempt + 1)/\(maxRetries)): \(error.localizedDescription)")
                    print("[DEBUG] Retrying in \(backoffDelay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                }
            }
        }
        
        print("[DEBUG] Gemini transcribe request failed after \(maxRetries) attempts")
        throw lastError ?? NSError(domain: "GeminiError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Request failed after \(maxRetries) attempts"])
    }
    
    // Temporary struct for parsing Gemini response
    private struct VideoTranscriptChunk: Codable {
        let startTimestamp: String   // MM:SS
        let endTimestamp: String     // MM:SS
        let description: String
    }
    
    private func parseTranscripts(_ response: String) throws -> [VideoTranscriptChunk] {
        guard let data = response.data(using: .utf8) else {
            throw NSError(domain: "GeminiError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid response encoding"])
        }
        
        let transcripts = try JSONDecoder().decode([VideoTranscriptChunk].self, from: data)
        return transcripts
    }
    
    private func geminiCardsRequest(prompt: String) async throws -> String {
        let distractionSchema: [String: Any] = [
            "type": "OBJECT", "properties": ["startTime": ["type": "STRING"], "endTime": ["type": "STRING"], "title": ["type": "STRING"], "summary": ["type": "STRING"]],
            "required": ["startTime", "endTime", "title", "summary"], "propertyOrdering": ["startTime", "endTime", "title", "summary"]
        ]
        
        let cardSchema: [String: Any] = [
            "type": "ARRAY", "items": [
                "type": "OBJECT", "properties": [
                    "startTimestamp": ["type": "STRING"], "endTimestamp": ["type": "STRING"], "category": ["type": "STRING"],
                    "subcategory": ["type": "STRING"], "title": ["type": "STRING"], "summary": ["type": "STRING"],
                    "detailedSummary": ["type": "STRING"], "distractions": ["type": "ARRAY", "items": distractionSchema]
                ],
                "required": ["startTimestamp", "endTimestamp", "category", "subcategory", "title", "summary", "detailedSummary"],
                "propertyOrdering": ["startTimestamp", "endTimestamp", "category", "subcategory", "title", "summary", "detailedSummary", "distractions"]
            ]
        ]
        
        let generationConfig: [String: Any] = [
            "temperature": 0.3,
            "maxOutputTokens": 65536,
            "responseMimeType": "application/json",
            "responseSchema": cardSchema,
            "thinkingConfig": [
                "thinkingBudget": 24576
            ]
        ]
        
        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": generationConfig
        ]
        
        // Retry logic with exponential backoff
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                var request = URLRequest(url: URL(string: genEndpoint + "?key=\(apiKey)")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                request.timeoutInterval = 120 // 2 minutes timeout
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Check for rate limiting
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    let delay = TimeInterval(retryAfter ?? "60") ?? 60
                    print("[DEBUG] Rate limited, retrying after \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    throw NSError(domain: "GeminiError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                }
                
                return text
                
            } catch {
                lastError = error
                
                // If it's not the last attempt, wait before retrying
                if attempt < maxRetries - 1 {
                    let backoffDelay = pow(2.0, Double(attempt)) * 5.0 // 5s, 10s, 20s
                    print("[DEBUG] Gemini cards request failed (attempt \(attempt + 1)/\(maxRetries)): \(error.localizedDescription)")
                    print("[DEBUG] Retrying in \(backoffDelay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                }
            }
        }
        
        print("[DEBUG] Gemini cards request failed after \(maxRetries) attempts")
        throw lastError ?? NSError(domain: "GeminiError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Request failed after \(maxRetries) attempts"])
    }
    
    private func parseActivityCards(_ response: String) throws -> [ActivityCard] {
        guard let data = response.data(using: .utf8) else {
            throw NSError(domain: "GeminiError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid response encoding"])
        }
        
        // Need to map the response format to our ActivityCard format
        struct GeminiActivityCard: Codable {
            let startTimestamp: String
            let endTimestamp: String
            let category: String
            let subcategory: String
            let title: String
            let summary: String
            let detailedSummary: String
            let distractions: [GeminiDistraction]?
        }
        
        struct GeminiDistraction: Codable {
            let startTime: String
            let endTime: String
            let title: String
            let summary: String
        }
        
        let geminiCards = try JSONDecoder().decode([GeminiActivityCard].self, from: data)
        
        // Convert to our ActivityCard format
        return geminiCards.map { geminiCard in
            ActivityCard(
                startTime: geminiCard.startTimestamp,
                endTime: geminiCard.endTimestamp,
                category: geminiCard.category,
                subcategory: geminiCard.subcategory,
                title: geminiCard.title,
                summary: geminiCard.summary,
                detailedSummary: geminiCard.detailedSummary,
                distractions: geminiCard.distractions?.map { d in
                    Distraction(
                        startTime: d.startTime,
                        endTime: d.endTime,
                        title: d.title,
                        summary: d.summary
                    )
                }
            )
        }
    }
}

// MARK: - Gemini-specific types

private struct GeminiFileMetadata: Codable {
    let file: GeminiFileInfo
}

private struct GeminiFileInfo: Codable {
    let displayName: String
    
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}
