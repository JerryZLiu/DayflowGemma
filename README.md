# Dayflow

Dayflow is a macOS application that records the user's screen, analyzes the footage with the Gemini API, and displays a timeline of activities. Recordings are split into chunks, grouped into analysis batches, and processed in the background. A debug interface lets developers inspect each batch.

## Building
Open `Dayflow.xcodeproj` with Xcode 15 or later. The project targets macOS and uses SwiftUI.

## Debug View
Select **Debug** from the top segmented control to review analysis batches. The view lets you play back the full batch video and expand individual timeline cards to see their summaries. If a card or its distractions include a video summary, it is displayed inline. The Debug view also lists every LLM call for the batch showing the full request and response with JSON prettified when possible.
