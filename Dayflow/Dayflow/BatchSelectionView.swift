//
//  BatchSelectionView.swift
//  Dayflow
//
//  Created by Assistant on 2025-07-20.
//

import SwiftUI

struct BatchSelectionView: View {
    let day: String
    @State private var batches: [(id: Int64, startTs: Int, endTs: Int, status: String)] = []
    @State private var selectedBatchIds: Set<Int64> = []
    @State private var isLoading = false
    @State private var progressMessage = ""
    @State private var showingProgress = false
    
    @Environment(\.dismiss) var dismiss
    let analysisManager: AnalysisManaging
    let onCompletion: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Select Batches to Reprocess")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Day: \(day)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Batch list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(batches, id: \.id) { batch in
                        BatchRowView(
                            batch: batch,
                            isSelected: selectedBatchIds.contains(batch.id),
                            onToggle: { toggleSelection(batch.id) }
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Text("\(selectedBatchIds.count) of \(batches.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Reprocess Selected") {
                    reprocessSelectedBatches()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedBatchIds.isEmpty || isLoading)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .onAppear {
            loadBatches()
        }
        .sheet(isPresented: $showingProgress) {
            ProgressView {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    
                    Text(progressMessage)
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .padding(40)
            }
        }
    }
    
    private func loadBatches() {
        batches = StorageManager.shared.fetchBatches(forDay: day)
        // Don't pre-select any batches - let user choose
    }
    
    private func toggleSelection(_ batchId: Int64) {
        if selectedBatchIds.contains(batchId) {
            selectedBatchIds.remove(batchId)
        } else {
            selectedBatchIds.insert(batchId)
        }
    }
    
    private func reprocessSelectedBatches() {
        let batchIds = Array(selectedBatchIds)
        isLoading = true
        showingProgress = true
        
        analysisManager.reprocessSpecificBatches(batchIds, progressHandler: { message in
            DispatchQueue.main.async {
                self.progressMessage = message
            }
        }) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                self.showingProgress = false
                
                switch result {
                case .success:
                    self.onCompletion()
                    self.dismiss()
                case .failure(let error):
                    // Handle error - you might want to show an alert
                    print("Error reprocessing batches: \(error)")
                }
            }
        }
    }
}

struct BatchRowView: View {
    let batch: (id: Int64, startTs: Int, endTs: Int, status: String)
    let isSelected: Bool
    let onToggle: () -> Void
    
    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current  // Use the system's current timezone
        
        let start = Date(timeIntervalSince1970: TimeInterval(batch.startTs))
        let end = Date(timeIntervalSince1970: TimeInterval(batch.endTs))
        
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    
    private var duration: String {
        let seconds = batch.endTs - batch.startTs
        let minutes = seconds / 60
        return "\(minutes) min"
    }
    
    private var statusColor: Color {
        switch batch.status {
        case "completed", "analyzed":
            return .green
        case "failed", "failed_empty":
            return .red
        case "processing":
            return .blue
        case "pending":
            return .orange
        case "skipped_short":
            return .gray
        default:
            return .secondary
        }
    }
    
    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in onToggle() }
            ))
            .toggleStyle(CheckboxToggleStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Batch #\(batch.id)")
                    .font(.system(size: 14, weight: .medium))
                
                HStack {
                    Text(timeRange)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(duration)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(batch.status)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture {
            onToggle()
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square" : "square")
                .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                .font(.system(size: 16))
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
        }
    }
}

#Preview {
    BatchSelectionView(
        day: "2025-01-20",
        analysisManager: AnalysisManager.shared,
        onCompletion: {}
    )
}