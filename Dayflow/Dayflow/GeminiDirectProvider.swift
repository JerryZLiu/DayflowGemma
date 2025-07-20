//
//  GeminiDirectProvider.swift
//  Dayflow
//

import Foundation

final class GeminiDirectProvider: LLMProvider {
    private let apiKey: String
    private let genEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent"
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
        
        print("\n📄 Raw Gemini Observation Generation Output:")
        print(String(repeating: "=", count: 80))
        print(response)
        print(String(repeating: "=", count: 80))
        print("\n")
        
        let videoTranscripts = try parseTranscripts(response)
        
        // Convert video transcripts to observations with proper Unix timestamps
        let observations = videoTranscripts.map { chunk in
            let startSeconds = parseVideoTimestamp(chunk.startTimestamp)
            let endSeconds = parseVideoTimestamp(chunk.endTimestamp)
            let startDate = batchStartTime.addingTimeInterval(TimeInterval(startSeconds))
            let endDate = batchStartTime.addingTimeInterval(TimeInterval(endSeconds))
            
            print("\n🔍 Observation Timestamp Conversion:")
            print("  Video timestamp: \(chunk.startTimestamp) - \(chunk.endTimestamp)")
            print("  Seconds from video start: \(startSeconds) - \(endSeconds)")
            print("  Batch start time: \(batchStartTime)")
            print("  Calculated dates: \(startDate) - \(endDate)")
            print("  Unix timestamps: \(Int(startDate.timeIntervalSince1970)) - \(Int(endDate.timeIntervalSince1970))")
            
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
            
            print("\n🕐 Activity Card Generation - Timestamp Conversion:")
            print("  Unix timestamps from DB: \(obs.startTs) - \(obs.endTs)")
            print("  Converted to dates: \(Date(timeIntervalSince1970: TimeInterval(obs.startTs))) - \(Date(timeIntervalSince1970: TimeInterval(obs.endTs)))")
            print("  Formatted for prompt: [\(startTime) - \(endTime)]")
            print("  Observation: \(obs.observation)")
            
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
        
        // Convert existing cards to JSON string with pretty printing
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let existingCardsJSON = try encoder.encode(context.existingCards)
        let existingCardsString = String(data: existingCardsJSON, encoding: .utf8) ?? "[]"
        
        let activityGenerationPrompt = """
        You are a digital anthropologist, observing a user's raw activity log. Your goal is to synthesize this log into a high-level, human-readable story of their session, presented as a series of timeline cards.
        THE GOLDEN RULE:
        Your primary objective is to create long, meaningful cards that represent a cohesive session of activity, ideally 30-60 minutes. However, thematic coherence is essential - a card must tell a coherent story. Avoid creating cards shorter than 15-20 minutes unless a major context switch forces it. 
        CRITICAL DATA INTEGRITY RULE:
        When you decide to extend a card, its original startTime is IMMUTABLE. You MUST carry over the startTime from the previous_card you are extending. Failure to preserve the original startTime is a critical error.
        CORE DIRECTIVES:

        Extend by Default: Your first instinct should be to extend the last card. When extending, you must perform these steps:
        a. Preserve the original startTime of the card you are extending. NEVER MODIFY THE START TIMES OF CARDS
        b. Update the endTime to reflect the latest observation.
        c. Rewrite the summary and detailedSummary to tell the complete, unified story from the original start to the new end.
        Group Thematically: Group activities that share a common purpose or topic. If extending would require fundamentally changing the card's title or theme, create a new card instead. Acknowledge the messy reality of multitasking within the summary.
        Tell a Story: The title and summary of each card should tell a coherent story. How did the session start? Where did it pivot? What was the user's apparent goal or rabbit hole?
        Title guidelines:
        Write titles like you're texting a friend about what you did. Natural, conversational, direct.

        Rules:
        - Be specific and clear (not creative or vague)
        - Keep it short - aim for 5-10 words
        - Don't reference other cards or assume context
        - Include main activity + distraction if relevant

        Good examples:
        - "Edited photos in Lightroom"
        - "Python tutorial on Codecademy"
        - "Watched 3 episodes on Netflix"
        - "Wrote blog post, kept checking Instagram"
        - "Researched flights to Tokyo"

        Bad examples:
        - "Early morning digital drift" (too vague/poetic)
        - "Fell down a rabbit hole after lunch" (too long, assumes context)
        - "Extended Browsing Session" (too formal)
        - "Random browsing and activities" (not specific)
        - "Continuing from earlier" (references other cards)

        Summary guidelines:
        Write summaries like journal entries - first person without using "I". Natural, conversational, factual.

        Rules:
        - 2-3 sentences that add context beyond the title
        - Connect to earlier/later activities when relevant ("continued from earlier", "finally got back to")
        - Be specific about what happened without listing every detail
        - Include subtle context words that feel natural ("ended up", "kept getting distracted", "spent way too long")
        - Never assume the user's feelings or intentions ("loved it", "got frustrated", "decided to buy")

        Good examples:
        - "Watched several React tutorials on YouTube before switching to the official docs. Ended up refactoring components in VS Code while referencing the useEffect documentation."
        - "Read through NVIDIA's investor relations page, focusing on their latest quarterly filing. Then pulled up AMD's earnings for comparison and took notes in Notion."
        - "Browsed meal prep ideas on Pinterest and various food blogs. Started a grocery list in Notes and looked up several chicken recipes for the week."
        - "Spent the morning on Zillow and StreetEasy looking at apartments near subway lines. Created a spreadsheet to compare options and started bookmarking promising listings."

        Bad examples:
        - "The user conducted extensive research..." (too formal, third person)
        - "Started with X, then did Y, then moved to Z" (formulaic)
        - "Loved the reviews and decided to buy one" (assumes feelings)
        - "Looked at 47 different websites" (false precision)

        YOUR MENTAL MODEL (How to Decide):
        Before making a decision, ask yourself these questions in order:

        What is the dominant theme of the current card?
        Do the new observations continue or relate to this theme? If yes, extend the card by following the procedure in Core Directive #1.
        Is this a brief (<5 min) and unrelated pivot? If yes, add it as a distraction to the current card and continue extending.
        Is this a sustained shift in focus (>15 min) that represents a different activity category or goal? If yes, create a new card regardless of the current card's length.

        DISTRACTIONS:
        A "distraction" is a brief (<5 min) and unrelated activity that interrupts the main theme of a card. Sustained activities (>5 min) are NOT distractions - they either belong to the current theme or warrant a new card. Don't label related sub-tasks as distractions.

        INPUTS:
        Previous cards: \(existingCardsString)
        New observations: \(transcriptText)
        Return ONLY a JSON array with this EXACT structure:
                
                [
                  {
                    "startTime": "1:12 AM",
                    "endTime": "1:30 AM",
                    "category": "Productive Work",
                    "subcategory": "Coding",
                    "title": "Working on auth bug in Dayflow",
                    "summary": "Fixed authentication bug in the login flow and added error handling",
                    "detailedSummary": "Debugged issue where users were getting logged out unexpectedly. Traced problem to JWT token expiration handling. Added proper error boundaries and user-friendly error messages. Tested with multiple user accounts.",
                    "distractions": [
                      {
                        "startTime": "1:15 AM",
                        "endTime": "1:18 AM",
                        "title": "Twitter",
                        "summary": "Checked notifications and scrolled feed"
                      }
                    ]
                  }
                ]
        """
        
        print(activityGenerationPrompt)
        
        // Initial request
        var response = try await geminiCardsRequest(
            prompt: activityGenerationPrompt
        )
        
        var cards = try parseActivityCards(response)
        
        // Combined validation and retry loop
        var retryCount = 0
        let maxRetries = 3
        
        while retryCount < maxRetries {
            // Run both validations
            let (coverageValid, coverageError) = validateTimeCoverage(existingCards: context.existingCards, newCards: cards)
            let (durationValid, durationError) = validateTimeline(cards)
            
            // Check if both validations pass
            if coverageValid && durationValid {
                if retryCount > 0 {
                    print("✅ All validations passed after \(retryCount) retries")
                } else {
                    print("✅ All validations passed on first attempt")
                }
                break
            }
            
            retryCount += 1
            
            // Build error message combining both validation failures
            var errorMessages: [String] = []
            
            if !coverageValid && coverageError != nil {
                print("⚠️ Time coverage validation failed: \(coverageError!)")
                errorMessages.append("""
                TIME COVERAGE ERROR:
                \(coverageError!)
                
                You MUST ensure your output cards collectively cover ALL time periods from the input cards. Do not drop any time segments.
                """)
            }
            
            if !durationValid && durationError != nil {
                print("⚠️ Timeline duration validation failed: \(durationError!)")
                if !coverageValid || retryCount == 1 {
                    // Print raw output on first failure or if both validations fail
                    print("\n📄 Raw LLM output:")
                    print(response)
                }
                errorMessages.append("""
                DURATION ERROR:
                \(durationError!)
                
                REMINDER: All cards except the last one must be at least 10 minutes long. Please merge short activities into longer, more meaningful cards that tell a coherent story.
                """)
            }
            
            if retryCount >= maxRetries {
                print("⚠️ Validation failed after \(maxRetries) retries. Proceeding with best effort.")
                break
            }
            
            print("🔄 Retrying with enhanced prompt (attempt \(retryCount)/\(maxRetries))...")
            
            // Enhanced prompt with all error details
            let retryPrompt = activityGenerationPrompt + """
            
            
            PREVIOUS ATTEMPT FAILED - CRITICAL REQUIREMENTS NOT MET:
            
            \(errorMessages.joined(separator: "\n\n"))
            
            Please fix these issues and ensure your output meets all requirements.
            """
            
            // Retry with enhanced prompt
            response = try await geminiCardsRequest(prompt: retryPrompt)
            cards = try parseActivityCards(response)
        }
        
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
    
    // MARK: - Validation Helpers
    
    private struct TimeRange {
        let start: Double  // minutes from midnight
        let end: Double
    }
    
    private func timeToMinutes(_ timeStr: String) -> Double {
        // Handle both "10:30 AM" and "05:30" formats
        if timeStr.contains("AM") || timeStr.contains("PM") {
            // Clock format - parse as date
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            
            if let date = formatter.date(from: timeStr) {
                let calendar = Calendar.current
                let components = calendar.dateComponents([.hour, .minute], from: date)
                return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
            return 0
        } else {
            // MM:SS format - convert to minutes
            let seconds = parseVideoTimestamp(timeStr)
            return Double(seconds) / 60.0
        }
    }
    
    private func mergeOverlappingRanges(_ ranges: [TimeRange]) -> [TimeRange] {
        guard !ranges.isEmpty else { return [] }
        
        // Sort by start time
        let sorted = ranges.sorted { $0.start < $1.start }
        var merged: [TimeRange] = []
        
        for range in sorted {
            if merged.isEmpty || range.start > merged.last!.end + 1 {
                // No overlap - add as new range
                merged.append(range)
            } else {
                // Overlap or adjacent - merge with last range
                let last = merged.removeLast()
                merged.append(TimeRange(start: last.start, end: max(last.end, range.end)))
            }
        }
        
        return merged
    }
    
    private func validateTimeCoverage(existingCards: [ActivityCard], newCards: [ActivityCard]) -> (isValid: Bool, error: String?) {
        guard !existingCards.isEmpty else {
            return (true, nil)
        }
        
        // Extract time ranges from input cards
        var inputRanges: [TimeRange] = []
        for card in existingCards {
            let startMin = timeToMinutes(card.startTime)
            var endMin = timeToMinutes(card.endTime)
            if endMin < startMin {  // Handle day rollover
                endMin += 24 * 60
            }
            inputRanges.append(TimeRange(start: startMin, end: endMin))
        }
        
        // Merge overlapping/adjacent ranges
        let mergedInputRanges = mergeOverlappingRanges(inputRanges)
        
        // Extract time ranges from output cards
        var outputRanges: [TimeRange] = []
        for card in newCards {
            let startMin = timeToMinutes(card.startTime)
            var endMin = timeToMinutes(card.endTime)
            if endMin < startMin {  // Handle day rollover
                endMin += 24 * 60
            }
            outputRanges.append(TimeRange(start: startMin, end: endMin))
        }
        
        // Check coverage with 3-minute flexibility
        let flexibility = 3.0  // minutes
        var uncoveredSegments: [(start: Double, end: Double)] = []
        
        for inputRange in mergedInputRanges {
            // Check if this input range is covered by output ranges
            var coveredStart = inputRange.start
            
            while coveredStart < inputRange.end {
                // Find an output range that covers this point
                var foundCoverage = false
                
                for outputRange in outputRanges {
                    // Check if this output range covers the current point (with flexibility)
                    if outputRange.start - flexibility <= coveredStart && coveredStart <= outputRange.end + flexibility {
                        // Move coveredStart to the end of this output range
                        coveredStart = outputRange.end
                        foundCoverage = true
                        break
                    }
                }
                
                if !foundCoverage {
                    // Find the next covered point
                    var nextCovered = inputRange.end
                    for outputRange in outputRanges {
                        if outputRange.start > coveredStart && outputRange.start < nextCovered {
                            nextCovered = outputRange.start
                        }
                    }
                    
                    // Add uncovered segment
                    if nextCovered > coveredStart {
                        uncoveredSegments.append((start: coveredStart, end: min(nextCovered, inputRange.end)))
                        coveredStart = nextCovered
                    } else {
                        // No more coverage found, add remaining segment and break
                        uncoveredSegments.append((start: coveredStart, end: inputRange.end))
                        break
                    }
                }
            }
        }
        
        // Check if uncovered segments are significant
        if !uncoveredSegments.isEmpty {
            var uncoveredDesc: [String] = []
            for segment in uncoveredSegments {
                let duration = segment.end - segment.start
                if duration > flexibility {  // Only report significant gaps
                    let startTime = minutesToTimeString(segment.start)
                    let endTime = minutesToTimeString(segment.end)
                    uncoveredDesc.append("\(startTime)-\(endTime) (\(Int(duration)) min)")
                }
            }
            
            if !uncoveredDesc.isEmpty {
                // Build detailed error message with input/output cards
                var errorMsg = "Missing coverage for time segments: \(uncoveredDesc.joined(separator: ", "))"
                errorMsg += "\n\n📥 INPUT CARDS:"
                for (i, card) in existingCards.enumerated() {
                    errorMsg += "\n  \(i+1). \(card.startTime) - \(card.endTime): \(card.title)"
                }
                errorMsg += "\n\n📤 OUTPUT CARDS:"
                for (i, card) in newCards.enumerated() {
                    errorMsg += "\n  \(i+1). \(card.startTime) - \(card.endTime): \(card.title)"
                }
                
                return (false, errorMsg)
            }
        }
        
        return (true, nil)
    }
    
    private func validateTimeline(_ cards: [ActivityCard]) -> (isValid: Bool, error: String?) {
        for (index, card) in cards.enumerated() {
            let startTime = card.startTime
            let endTime = card.endTime
            
            var durationMinutes: Double = 0
            
            // Check if times are in clock format (contains AM/PM)
            if startTime.contains("AM") || startTime.contains("PM") {
                // Parse clock times
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                
                if let startDate = formatter.date(from: startTime),
                   let endDate = formatter.date(from: endTime) {
                    
                    var adjustedEndDate = endDate
                    // Handle day rollover (e.g., 11:30 PM to 12:30 AM)
                    if endDate < startDate {
                        adjustedEndDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
                    }
                    
                    durationMinutes = adjustedEndDate.timeIntervalSince(startDate) / 60.0
                } else {
                    print("[DEBUG] Failed to parse clock times: \(startTime) - \(endTime)")
                    durationMinutes = 0
                }
            } else {
                // Parse MM:SS format
                let startSeconds = parseVideoTimestamp(startTime)
                let endSeconds = parseVideoTimestamp(endTime)
                durationMinutes = Double(endSeconds - startSeconds) / 60.0
            }
            
            // Check if card is too short (except for last card)
            if durationMinutes < 10 && index < cards.count - 1 {
                return (false, "Card \(index + 1) '\(card.title)' is only \(String(format: "%.1f", durationMinutes)) minutes long")
            }
        }
        
        return (true, nil)
    }
    
    private func minutesToTimeString(_ minutes: Double) -> String {
        let hours = (Int(minutes) / 60) % 24  // Handle > 24 hours
        let mins = Int(minutes) % 60
        let period = hours < 12 ? "AM" : "PM"
        var displayHour = hours % 12
        if displayHour == 0 {
            displayHour = 12
        }
        return String(format: "%d:%02d %@", displayHour, mins, period)
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
