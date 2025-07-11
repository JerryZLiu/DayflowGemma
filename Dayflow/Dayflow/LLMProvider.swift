//
//  LLMProvider.swift
//  Dayflow
//

import Foundation

protocol LLMProvider {
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String, batchStartTime: Date) async throws -> (observations: [Observation], log: LLMCall)
    func generateActivityCards(observations: [Observation], context: ActivityGenerationContext) async throws -> (cards: [ActivityCard], log: LLMCall)
}

struct ActivityGenerationContext {
    let userTaxonomy: String
    let extractedTaxonomy: String
}

enum LLMProviderType: Codable {
    case geminiDirect(apiKey: String)
    case dayflowBackend(token: String, endpoint: String = "https://api.dayflow.app")
    case ollamaLocal(endpoint: String = "http://localhost:11434")
}

// MARK: - Data Models

struct ActivityCard: Codable {
    let startTime: String
    let endTime: String
    let category: String
    let subcategory: String
    let title: String
    let summary: String
    let detailedSummary: String
    let distractions: [Distraction]?
}

// Distraction is defined in StorageManager.swift
// LLMCall is defined in StorageManager.swift

// MARK: - Helper Extensions for Timestamp Conversion

extension LLMProvider {
    // Convert "MM:SS" to seconds from video start
    func parseVideoTimestamp(_ timestamp: String) -> Int {
        let components = timestamp.components(separatedBy: ":")
        guard components.count == 2,
              let minutes = Int(components[0]),
              let seconds = Int(components[1]) else {
            return 0
        }
        return minutes * 60 + seconds
    }
    
    // Convert Unix timestamp to "h:mm a" for prompts
    func formatTimestampForPrompt(_ unixTime: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixTime))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}