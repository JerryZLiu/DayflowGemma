//
//  DayflowApp.swift
//  Dayflow
//
//  Created by Jerry Liu on 4/20/25.
//

import SwiftUI
import Sparkle

// MARK: - App View Enum (for top-level navigation)
enum AppView: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case newTimeline = "New Timeline"
    case dashboard = "Dashboard"
    case settings = "Settings"
    case debug = "Debug"
    var id: String { self.rawValue }
}

// MARK: - New Blank UI Components
struct BlankView: View {
    let title: String
    
    var body: some View {
        VStack {
            Spacer()
            Text(title)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Blank UI Root View
struct BlankUIRootView: View {
    var body: some View {
        GeometryReader { geometry in
            Image("Dayflow")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Placeholder Settings View

// Struct to manage category settings in the UI
struct CategorySetting: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var subcategories: [String]
}

struct SettingsView: View {
    @State private var managedCategories: [CategorySetting] = []
    
    // State for modal sheets
    @State private var showingAddCategorySheet = false
    @State private var showingAddSubcategorySheet = false
    @State private var categoryToEditOrAddSubsTo: CategorySetting? // For context when adding/editing subcategories
    @State private var nameInput: String = "" // Reusable for various name inputs

    // State for confirmation dialogs
    @State private var showingDeleteCategoryConfirm: CategorySetting? = nil // Store category to delete

    private let taxonomyKey = "userDefinedTaxonomyJSON"
    
    // LLM Provider settings
    @State private var selectedProvider: LLMProviderTypeSelection = .geminiDirect
    @State private var geminiApiKey: String = ""
    @State private var dayflowToken: String = ""
    @State private var dayflowEndpoint: String = "https://api.dayflow.app"
    @State private var ollamaEndpoint: String = "http://localhost:11434"
    @AppStorage("llmProviderType") private var savedProviderData: Data = Data()
    
    enum LLMProviderTypeSelection: String, CaseIterable {
        case geminiDirect = "Gemini Direct"
        case dayflowBackend = "Dayflow Backend"
        case ollamaLocal = "Ollama Local"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header area
            HStack {
                Text("Settings")
                    .font(.largeTitle)
                    .padding([.top, .leading])
                Spacer()
                Button("Save Changes") {
                    saveTaxonomy()
                    saveLLMProvider()
                }
                .padding([.top, .trailing])
            }
            .padding(.bottom)
            
            Divider()

            // Main content area
            List {
                // LLM Provider Section
                Section {
                    Picker("LLM Provider", selection: $selectedProvider) {
                        ForEach(LLMProviderTypeSelection.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                    
                    switch selectedProvider {
                    case .geminiDirect:
                        HStack {
                            Text("API Key:")
                                .frame(width: 100, alignment: .trailing)
                            SecureField("Enter Gemini API Key", text: $geminiApiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                    case .dayflowBackend:
                        HStack {
                            Text("Token:")
                                .frame(width: 100, alignment: .trailing)
                            SecureField("Enter Dayflow Token", text: $dayflowToken)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        HStack {
                            Text("Endpoint:")
                                .frame(width: 100, alignment: .trailing)
                            TextField("Enter Endpoint URL", text: $dayflowEndpoint)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                    case .ollamaLocal:
                        HStack {
                            Text("Endpoint:")
                                .frame(width: 100, alignment: .trailing)
                            TextField("Enter Ollama URL", text: $ollamaEndpoint)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        Text("Make sure Ollama is running and you have pulled qwen2-vl:7b")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("LLM Provider Configuration")
                        .font(.title2)
                }
                
                Divider()
                    .padding(.vertical)
                
                // Taxonomy Section Header
                Text("Taxonomy Configuration")
                    .font(.title2)
                    .padding(.top)
                ForEach($managedCategories) { $category in
                    Section {
                        // Category Header with Delete Button
                        HStack {
                            Text(category.name)
                                .font(.title2)
                            Spacer()
                            Button {
                                showingDeleteCategoryConfirm = category
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle()) // To make it look like a simple icon button
                        }
                        .padding(.vertical, 4)

                        // Subcategories List
                        ForEach(category.subcategories, id: \.self) { subcategoryName in
                            HStack {
                                Text(subcategoryName)
                                Spacer()
                                Button {
                                    // Action to remove subcategory
                                    removeSubcategory(subcategoryName, from: category)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .onDelete { offsets in // Alternative: Swipe to delete subcategories
                            removeSubcategory(at: offsets, from: category)
                        }

                        // Add Subcategory Button for this Category
                        Button("+ Add Subcategory") {
                            categoryToEditOrAddSubsTo = category
                            nameInput = ""
                            showingAddSubcategorySheet = true
                        }
                        .padding(.top, 5)
                    }
                }
                
                // Add New Category Button at the bottom of the List content
                Button("Add New Category") {
                    nameInput = ""
                    showingAddCategorySheet = true
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listStyle(.plain) // For a cleaner look, potentially helps with white background
        }
        .background(Color.white) // Ensure the whole view has a white background
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadTaxonomy()
            loadLLMProvider()
        }
        .sheet(isPresented: $showingAddCategorySheet) {
            AddCategorySheetView(nameInput: $nameInput) {
                if !nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    addCategory(name: nameInput)
                }
                showingAddCategorySheet = false
            }
        }
        .sheet(item: $categoryToEditOrAddSubsTo) { category in
             AddSubcategorySheetView(categoryName: category.name, nameInput: $nameInput) {
                if !nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    addSubcategory(nameInput, to: category)
                }
                showingAddSubcategorySheet = false
            }
        }
        .confirmationDialog(
            "Delete Category?",
            isPresented: .constant(showingDeleteCategoryConfirm != nil),
            presenting: showingDeleteCategoryConfirm
        ) {
            categoryToDelete in
            Button("Delete \"\(categoryToDelete.name)\" and all its subcategories", role: .destructive) {
                removeCategory(categoryToDelete)
                showingDeleteCategoryConfirm = nil
            }
            Button("Cancel", role: .cancel) {
                showingDeleteCategoryConfirm = nil
            }
        } message: {
             categoryToDelete in
             Text("Are you sure you want to delete this category? This action cannot be undone.")
        }
    }

    // --- Data Management Functions ---
    func loadTaxonomy() {
        guard let jsonString = UserDefaults.standard.string(forKey: taxonomyKey),
              !jsonString.isEmpty,
              let jsonData = jsonString.data(using: .utf8) else {
            self.managedCategories = []
            print("Taxonomy not found in UserDefaults or is empty, starting fresh.")
            return
        }
        do {
            let decoded = try JSONDecoder().decode([String: [String]].self, from: jsonData)
            self.managedCategories = decoded.map { key, value in
                CategorySetting(name: key, subcategories: value.sorted())
            }.sorted(by: { $0.name < $1.name })
        } catch {
            print("Failed to decode taxonomy from UserDefaults: \(error.localizedDescription)")
            self.managedCategories = []
        }
    }

    func saveTaxonomy() {
        let dictToSave = Dictionary(uniqueKeysWithValues: managedCategories.map { ($0.name, $0.subcategories) })
        do {
            let jsonData = try JSONEncoder().encode(dictToSave)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                UserDefaults.standard.set(jsonString, forKey: taxonomyKey)
                print("Taxonomy saved to UserDefaults: \(jsonString)")
            }
        } catch {
            print("Failed to encode taxonomy: \(error.localizedDescription)")
        }
    }
    
    func addCategory(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && !managedCategories.contains(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
            managedCategories.append(CategorySetting(name: trimmedName, subcategories: []))
            managedCategories.sort(by: { $0.name.lowercased() < $1.name.lowercased() })
        }
    }

    func removeCategory(_ categoryToRemove: CategorySetting) {
        managedCategories.removeAll { $0.id == categoryToRemove.id }
    }

    func addSubcategory(_ subcategoryName: String, to category: CategorySetting) {
        let trimmedName = subcategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        if let index = managedCategories.firstIndex(where: { $0.id == category.id }) {
            if !managedCategories[index].subcategories.contains(where: {$0.lowercased() == trimmedName.lowercased()}) {
                managedCategories[index].subcategories.append(trimmedName)
                managedCategories[index].subcategories.sort(by: { $0.lowercased() < $1.lowercased() })
            }
        }
    }

    func removeSubcategory(_ subcategoryName: String, from category: CategorySetting) {
        if let categoryIndex = managedCategories.firstIndex(where: { $0.id == category.id }) {
            managedCategories[categoryIndex].subcategories.removeAll { $0 == subcategoryName }
        }
    }
    
    func removeSubcategory(at offsets: IndexSet, from category: CategorySetting) {
        if let categoryIndex = managedCategories.firstIndex(where: { $0.id == category.id }) {
            managedCategories[categoryIndex].subcategories.remove(atOffsets: offsets)
        }
    }
    
    // MARK: - LLM Provider Management
    
    func loadLLMProvider() {
        if let decoded = try? JSONDecoder().decode(LLMProviderType.self, from: savedProviderData) {
            switch decoded {
            case .geminiDirect(let apiKey):
                selectedProvider = .geminiDirect
                geminiApiKey = apiKey
            case .dayflowBackend(let token, let endpoint):
                selectedProvider = .dayflowBackend
                dayflowToken = token
                dayflowEndpoint = endpoint
            case .ollamaLocal(let endpoint):
                selectedProvider = .ollamaLocal
                ollamaEndpoint = endpoint
            }
        }
    }
    
    func saveLLMProvider() {
        let providerType: LLMProviderType
        
        switch selectedProvider {
        case .geminiDirect:
            providerType = .geminiDirect(apiKey: geminiApiKey)
        case .dayflowBackend:
            providerType = .dayflowBackend(token: dayflowToken, endpoint: dayflowEndpoint)
        case .ollamaLocal:
            providerType = .ollamaLocal(endpoint: ollamaEndpoint)
        }
        
        if let encoded = try? JSONEncoder().encode(providerType) {
            savedProviderData = encoded
        }
    }
}

// MARK: - Sheet Views for Adding Category/Subcategory

struct AddCategorySheetView: View {
    @Binding var nameInput: String
    var onAdd: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Add New Category")
                .font(.title2)
            TextField("Category Name", text: $nameInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Add Category") {
                    onAdd()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
}

struct AddSubcategorySheetView: View {
    var categoryName: String
    @Binding var nameInput: String
    var onAdd: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Subcategory to \"\(categoryName)\"")
                .font(.title2)
            TextField("Subcategory Name", text: $nameInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Add Subcategory") {
                    onAdd()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
}


// MARK: - New Root View with Toggle
struct AppRootView: View {
    @State private var currentAppView: AppView = .timeline

    var body: some View {
        ZStack {
            // Main content fills the entire window
            Group {
                if currentAppView == .timeline {
                    ContentView()
                        .environmentObject(AppState.shared)
                } else if currentAppView == .newTimeline {
                    TimelineView()
                } else if currentAppView == .dashboard {
                    DashboardView()
                } else if currentAppView == .settings {
                    SettingsView()
                } else {
                    DebugView()
                }
            }
            
            // Floating toolbar at the top
            VStack {
                HStack {
                    // Space for traffic lights - adjust based on your needs
                    Color.clear
                        .frame(width: 70, height: 1)
                    
                    Spacer()
                    
                    // Centered navigation with background
                    Picker("View", selection: $currentAppView) {
                        ForEach(AppView.allCases) { viewCase in
                            Text(viewCase.rawValue).tag(viewCase)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 400)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    )
                    
                    Spacer()
                    
                    // Balance the right side
                    Color.clear
                        .frame(width: 70, height: 1)
                }
                .padding(.top, 8) // Small top padding to avoid traffic lights
                
                Spacer()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .ignoresSafeArea() // Extend content into title bar area
    }
}

// Alternative: Borderless Window Root View (no toolbar at all)
struct BorderlessAppRootView: View {
    @State private var currentAppView: AppView = .timeline

    var body: some View {
        ZStack {
            // Main content
            if currentAppView == .timeline {
                ContentView()
                    .environmentObject(AppState.shared)
            } else if currentAppView == .newTimeline {
                TimelineView()
            } else if currentAppView == .dashboard {
                DashboardView()
            } else if currentAppView == .settings {
                SettingsView()
            } else {
                DebugView()
            }
            
            // Floating view switcher in top-right corner
            VStack {
                HStack {
                    Spacer()
                    Picker("View", selection: $currentAppView) {
                        ForEach(AppView.allCases) { viewCase in
                            Text(viewCase.rawValue).tag(viewCase)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 300)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                            .shadow(radius: 2)
                    )
                }
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .ignoresSafeArea()
    }
}

// Visual Effect View for native macOS blur effect
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .headerView
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = blendingMode
        view.material = material
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// Alternative minimalist root view
struct MinimalistAppRootView: View {
    @State private var currentAppView: AppView = .timeline
    
    var body: some View {
        VStack(spacing: 0) {
            // Minimal toolbar with integrated background
            HStack(spacing: 20) {
                // Traffic light space
                Color.clear
                    .frame(width: 70, height: 40)
                
                // Navigation buttons as individual toggles
                ForEach(AppView.allCases) { viewCase in
                    Button(action: { currentAppView = viewCase }) {
                        Text(viewCase.rawValue)
                            .font(.system(size: 13, weight: currentAppView == viewCase ? .semibold : .regular))
                            .foregroundColor(currentAppView == viewCase ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                currentAppView == viewCase ?
                                Color.accentColor.opacity(0.1) : Color.clear
                            )
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
                .opacity(0.2)
            
            // Content
            Group {
                if currentAppView == .timeline {
                    ContentView()
                        .environmentObject(AppState.shared)
                } else if currentAppView == .newTimeline {
                    TimelineView()
                } else if currentAppView == .dashboard {
                    DashboardView()
                } else if currentAppView == .settings {
                    SettingsView()
                } else {
                    DebugView()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

@main
struct DayflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("useBlankUI") private var useBlankUI = false
    
    init() {
        // Always reset onboarding for testing
        UserDefaults.standard.set(false, forKey: "didOnboard")
    }
    
    // Sparkle updater
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup {
            if didOnboard {
                // Switch between old and new UI
                if useBlankUI {
                    BlankUIRootView()
                } else {
                    AppRootView()
                }
            } else {
                OnboardingFlow()
                    .environmentObject(AppState.shared)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Remove the "New Window" command if you want a single window app
            CommandGroup(replacing: .newItem) { }
            
            // Add View menu to toggle UI
            CommandMenu("View") {
                Toggle("Use Blank UI", isOn: $useBlankUI)
                    .keyboardShortcut("B", modifiers: [.command, .shift])
            }
            
            // Add Sparkle's update menu item
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterController.updater.checkForUpdates()
                }
            }
        }
        .defaultSize(width: 1200, height: 800)
    }
}
