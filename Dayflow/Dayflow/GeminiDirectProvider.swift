//
//  GeminiDirectProvider.swift
//  Dayflow
//

import Foundation

final class GeminiDirectProvider: LLMProvider {
    private let apiKey: String
    private let genEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-04-17:generateContent"
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
        Your job is to act as an expert transcriber for someone's computer usage. your descriptions should capture context and intent of the what the user is doing. 
        for example, if the user is watching a youtube video, what's important is capturing the essence of what the video is about, not necessarily every invidiaul detail about the video. 
        Each transcription should include a timestamp range of the particular action eg (MM:SS - MM:SS). Each transcription should also be >30seconds long, although exercise your judgement.
         If you're going to start a separate transcription, it should be because of a big shift in context.
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
                llmModel: "gemini-2.5-flash-preview-04-17",
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
            return "[\(startTime) - \(endTime)]: \(obs.observation)"
        }.joined(separator: "\n")
        
        let activityGenerationPrompt = """
        You are Dayflow, an AI that converts screen recordings into a JSON timeline.
        –––––  OUTPUT  –––––
        Return only a JSON array of segments, each with:
        startTimestamp (video timestamp, like 1:32)
        endTimestamp
        category
        subcategory
        title  (max 3 words, should be 1-2 usually. Something like Coding or Twitter so the user has a quick high level understanding, more precise than subcategory)
        summary (1-2 casual sentences, **no "I"/first-person pronouns**; start with a verb and focus on what was accomplished)
        detailed summary (longer factual description used only as context for future analysis)
        distractions (optional array of {startTime, endTime, title, summary})
        –––––  CORE RULES  –––––
        Segments should always be 5+ minutes
        Strongly prioritize keeping all continuous work related to a single project, feature, or overall goal within one segment.
        Sub‑5 min detours → put in distractions.
        Segments must not overlap.
        Always try to adhere and use the user provided categories and subcategories wherever possible. If none fit, try adhering to the categories and subcategories in previous segments, which will be provided below. However, if the segment doesn't fit any of the provided taxonomy, or no taxonomy is provided, try to go with broad categories/subcategories. Some examples for reference Productive Work: [Coding, Writing, Design, Data Analysis, Project Management] Communication & Collaboration: [Email, Meetings, Slack] Distractions [Twitter, Social Media, Texting] Idle: [Idle]
        Try not to exceed 4 subcategories.
        Sometimes, users will be idle, in other words nothing will happen on the screen for 5+ minutes. we should create a new segment and label it Idle - Idle in that case.
        –––––  SCATTERED‑ACTIVITY RULE  –––––
        For any 5 + min window of rapid switching:
        • If one activity recurs most, make it the segment; others → distractions.
        –––––  DISTRACTION DETAILS  –––––
        Log any distraction ≥ 30 s and < 5 min. do not log distractions that are shorter than 30s
        –––––  CONTINUITY  –––––
        Examine the most recent previous Segment carefully. More likely than not, the first segment of this video analysis is a continuation of the previous segment. In that case, you should do your best to use the same category/subcategory.
        \(transcriptText)
        OUTPUT FORMAT: JSON array of ActivityCards. startTime/endTime as MM:SS strings.
            USER PREFERRED TAXONOMY:
            \(context.userTaxonomy)
            SYSTEM GENERATED TAXONOMY:
            \(context.extractedTaxonomy)
            PREVIOUS SEGMENT:
            \(context.previousSegmentsJSON)
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
        
        if fileSize <= 20 * 1024 * 1024 {
            print("[DEBUG] Using simple upload")
            uploadedFileURI = try await uploadSimple(data: fileData, mimeType: mimeType)
        } else {
            print("[DEBUG] Using resumable upload")
            uploadedFileURI = try await uploadResumable(data: fileData, mimeType: mimeType)
        }
        
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
        
        var request = URLRequest(url: URL(string: genEndpoint + "?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
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
        
        var request = URLRequest(url: URL(string: genEndpoint + "?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
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
