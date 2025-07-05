import XCTest
@testable import Dayflow // Make sure your app module is importable

class GeminiServiceTests: XCTestCase {

    var urlSession: URLSession!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Configure URLSession to use MockURLProtocol
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        urlSession = URLSession(configuration: configuration)
        // Assign this custom session to GeminiService if possible, or rely on global URLSession.shared being patched.
        // For this test, we assume GeminiService uses URLSession.shared internally for its await data(for:) calls
        // or that we can inject this session. If it directly uses URLSession.shared, this setup is enough for tests.
    }

    override func tearDownWithError() throws {
        MockURLProtocol.mockResponse = nil
        MockURLProtocol.requestCompletionHandler = nil
        urlSession = nil
        try super.tearDownWithError()
    }

    func testGenerateActivityCardsFromTranscript_SuccessfulResponse() async throws {
        // 1. Prepare Inputs
        let service = GeminiService.shared // Using the shared instance
        let apiKey = "TEST_API_KEY"
        let batchId: Int64 = 123

        let batchStartTime = Date(timeIntervalSince1970: 1700000000) // Fixed test time
        
        let sampleObservations = [
            Observation(id: nil, batchId: batchId, startTs: 1700000000, endTs: 1700000330, observation: "User was coding on Project X.", metadata: nil, llmModel: "gemini-2.5-flash-preview-04-17", createdAt: Date()),
            Observation(id: nil, batchId: batchId, startTs: 1700000330, endTs: 1700000360, observation: "User checked Twitter briefly.", metadata: nil, llmModel: "gemini-2.5-flash-preview-04-17", createdAt: Date()),
            Observation(id: nil, batchId: batchId, startTs: 1700000360, endTs: 1700000600, observation: "User resumed coding on Project X.", metadata: nil, llmModel: "gemini-2.5-flash-preview-04-17", createdAt: Date())
        ]
        
        // Format observations as they would appear in prompts
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone.current
        let transcriptText = sampleObservations.map { obs in
            let startTime = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(obs.startTs)))
            let endTime = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(obs.endTs)))
            return "[\\(startTime) - \\(endTime)]: \\(obs.observation)"
        }.joined(separator: "\\n")

        let previousSegmentsJSON = "[{\"category\":\"Work\",\"subcategory\":\"Meetings\",\"title\":\"Team Sync\",\"summary\":\"Discussed project milestones.\",\"detailedSummary\":\"Detailed discussion about project milestones and upcoming deadlines.\"}]"
        let userTaxonomy = "Productive Work: [\"Coding\", \"Design\"]\\nCommunication: [\"Email\", \"Slack\"]"
        let extractedTaxonomy = "Work: [\"Meetings\"]"

        // 2. Define Expected Output (that the mock will provide parts of)
        let expectedCards = [
            ActivityCard(startTime: "00:00", endTime: "10:00", category: "Productive Work", subcategory: "Coding", title: "Project X", summary: "Coded on Project X, with a brief Twitter check.", detailedSummary: "Focused on coding for Project X. Took a short break to check Twitter.", distractions: [
                ActivityCard.Distraction(startTime: "05:30", endTime: "06:00", title: "Twitter Check", summary: "Briefly checked Twitter.")
            ])
        ]
        let expectedCardsJSONText = #"[{"startTime":"00:00","endTime":"10:00","category":"Productive Work","subcategory":"Coding","title":"Project X","summary":"Coded on Project X, with a brief Twitter check.","detailedSummary":"Focused on coding for Project X. Took a short break to check Twitter.","distractions":[{"startTime":"05:30","endTime":"06:00","title":"Twitter Check","summary":"Briefly checked Twitter."}]}]"#

        // 3. Configure MockURLProtocol
        let mockAPIResponse = GeminiAPIResponse(
            candidates: [
                GeminiAPICandidate(
                    content: GeminiAPIContent(
                        parts: [GeminiAPIContentPart(text: expectedCardsJSONText)],
                        role: "model"
                    )
                )
            ]
        )
        let responseData = try JSONEncoder().encode(mockAPIResponse)
        MockURLProtocol.mockResponse = (
            data: responseData,
            urlResponse: HTTPURLResponse(url: URL(string: "https://generativelanguage.googleapis.com")!, statusCode: 200, httpVersion: nil, headerFields: nil),
            error: nil
        )

        let expectation = XCTestExpectation(description: "Generate activity cards from transcript completes")
        var receivedCards: [ActivityCard]?
        var receivedError: Error?
        var receivedLog: LLMCall?
        
        // Capture the request to verify the prompt
        var capturedRequest: URLRequest?
        MockURLProtocol.requestCompletionHandler = { request in
            capturedRequest = request
        }

        // 4. Call the method
        Task {
            do {
                // Note: This test needs to be updated as generateActivityCardsFromTranscript no longer exists
                // The new flow is through processBatch which handles everything internally
                // For now, marking this test as needing update
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test needs update for new architecture"])
                receivedCards = cards
                receivedLog = log
            } catch {
                receivedError = error
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        // 5. Assertions
        XCTAssertNil(receivedError, "generateActivityCardsFromTranscript should not throw an error: \\(receivedError?.localizedDescription ?? "Unknown error")")
        XCTAssertNotNil(receivedCards, "Should receive activity cards")
        XCTAssertEqual(receivedCards?.count, expectedCards.count, "Number of cards should match")
        
        // Deep comparison for card content (customize as needed based on Equatable conformance)
        if let firstReceived = receivedCards?.first, let firstExpected = expectedCards.first {
            XCTAssertEqual(firstReceived.startTime, firstExpected.startTime)
            XCTAssertEqual(firstReceived.endTime, firstExpected.endTime)
            XCTAssertEqual(firstReceived.category, firstExpected.category)
            XCTAssertEqual(firstReceived.subcategory, firstExpected.subcategory)
            XCTAssertEqual(firstReceived.title, firstExpected.title)
            XCTAssertEqual(firstReceived.summary, firstExpected.summary)
            XCTAssertEqual(firstReceived.detailedSummary, firstExpected.detailedSummary)
            XCTAssertEqual(firstReceived.distractions?.count, firstExpected.distractions?.count)
            if let firstReceivedDistraction = firstReceived.distractions?.first, let firstExpectedDistraction = firstExpected.distractions?.first {
                 XCTAssertEqual(firstReceivedDistraction.startTime, firstExpectedDistraction.startTime)
                 XCTAssertEqual(firstReceivedDistraction.endTime, firstExpectedDistraction.endTime)
                 XCTAssertEqual(firstReceivedDistraction.title, firstExpectedDistraction.title)
                 XCTAssertEqual(firstReceivedDistraction.summary, firstExpectedDistraction.summary)
            }
        }

        XCTAssertNotNil(receivedLog, "Should receive an LLMCall log")
        XCTAssertNotNil(capturedRequest, "Request should have been captured")
        
        if let logInput = receivedLog?.input, let requestBody = capturedRequest?.httpBody, let requestBodyString = String(data: requestBody, encoding: .utf8) {
            XCTAssertTrue(logInput.contains(transcriptText), "LLM log input should contain the transcript text")
            XCTAssertTrue(logInput.contains(previousSegmentsJSON), "LLM log input should contain previous segments JSON")
            XCTAssertTrue(logInput.contains(userTaxonomy), "LLM log input should contain user taxonomy")
            XCTAssertTrue(logInput.contains(extractedTaxonomy), "LLM log input should contain extracted taxonomy")
            
            // Verify the prompt structure from the request body as well
            // This is a bit more direct for checking what was sent
            XCTAssertTrue(requestBodyString.contains(transcriptText.replacingOccurrences(of: "\n", with: "\\n")), "Request body should contain the transcript text") // JSON escapes newlines
        }
        XCTAssertEqual(receivedLog?.output, expectedCardsJSONText, "LLM log output should match the mocked JSON text")
    }
}

// Dummy Codable structs for GeminiAPIResponse if not accessible or to simplify testing
// Ensure these match the structure used in GeminiService.swift or that the actual ones are accessible.
private struct GeminiAPIResponse: Codable {
    let candidates: [GeminiAPICandidate]
}
private struct GeminiAPICandidate: Codable {
    let content: GeminiAPIContent
}
private struct GeminiAPIContent: Codable {
    let parts: [GeminiAPIContentPart]
    let role: String?
}
private struct GeminiAPIContentPart: Codable {
    let text: String
}

// Make ActivityCard and its Distraction Equatable for easier comparison in tests
// This might already be the case or you might need to add it.
extension ActivityCard: Equatable {
    public static func == (lhs: ActivityCard, rhs: ActivityCard) -> Bool {
        return lhs.startTime == rhs.startTime &&
               lhs.endTime == rhs.endTime &&
               lhs.category == rhs.category &&
               lhs.subcategory == rhs.subcategory &&
               lhs.title == rhs.title &&
               lhs.summary == rhs.summary &&
               lhs.detailedSummary == rhs.detailedSummary &&
               lhs.distractions == rhs.distractions
    }
}

extension ActivityCard.Distraction: Equatable {
    public static func == (lhs: ActivityCard.Distraction, rhs: ActivityCard.Distraction) -> Bool {
        return lhs.startTime == rhs.startTime &&
               lhs.endTime == rhs.endTime &&
               lhs.title == rhs.title &&
               lhs.summary == rhs.summary
    }
} 