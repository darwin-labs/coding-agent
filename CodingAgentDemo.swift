import SwiftUI

struct CodingAgentDemo: View {
    @StateObject private var codingAgent = CodingAgent()
    @State private var taskDescription = ""
    @State private var isWorking = false
    @State private var feedback: [String] = []
    @State private var showFeedback = false
    @State private var showLogs = false
    @State private var filePath = ""
    @State private var fileContent = ""
    @State private var showFileContent = false
    @State private var codeToExecute = ""
    @State private var selectedCodeLanguage = CodeLanguage.swift
    @State private var codeExecutionResult: CodeExecutionResult?
    
    var body: some View {
        NavigationView {
            VStack {
                TabView {
                    // Task Planning Tab
                    TaskPlanningView(
                        codingAgent: codingAgent,
                        taskDescription: $taskDescription,
                        isWorking: $isWorking,
                        planTask: planTask,
                        executeTask: executeTask,
                        getFeedback: getFeedback,
                        resetAgent: resetAgent,
                        showLogs: $showLogs
                    )
                    .tabItem {
                        Label("Task Planning", systemImage: "list.bullet.clipboard")
                    }
                    
                    // File Operations Tab
                    FileOperationsView(
                        codingAgent: codingAgent,
                        isWorking: $isWorking,
                        filePath: $filePath,
                        fileContent: $fileContent,
                        readFile: readFile,
                        saveFile: saveFile,
                        deleteFile: deleteFile,
                        listDirectory: listDirectory
                    )
                    .tabItem {
                        Label("File Operations", systemImage: "folder")
                    }
                    
                    // Code Execution Tab
                    CodeExecutionView(
                        codeToExecute: $codeToExecute,
                        selectedCodeLanguage: $selectedCodeLanguage,
                        codeExecutionResult: $codeExecutionResult,
                        isWorking: $isWorking,
                        executeCode: executeCode
                    )
                    .tabItem {
                        Label("Code Execution", systemImage: "terminal")
                    }
                }
                
                // Current Output
                if !codingAgent.currentOutput.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Current Output")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        ScrollView {
                            Text(codingAgent.currentOutput)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Coding Agent Demo")
            .sheet(isPresented: $showLogs) {
                LogView(logs: codingAgent.logs)
            }
            .alert("Task Feedback", isPresented: $showFeedback) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(feedback.joined(separator: "\n\n"))
            }
            .alert("File Content", isPresented: $showFileContent) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(fileContent)
            }
        }
    }
    
    private func planTask() {
        guard !taskDescription.isEmpty else { return }
        
        isWorking = true
        
        Task {
            do {
                _ = try await codingAgent.planTask(task: taskDescription)
                await MainActor.run {
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    print("Error planning task: \(error)")
                }
            }
        }
    }
    
    private func executeTask() {
        isWorking = true
        
        Task {
            do {
                _ = try await codingAgent.executeTaskPlan()
                await MainActor.run {
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    print("Error executing task: \(error)")
                }
            }
        }
    }
    
    private func getFeedback() {
        isWorking = true
        
        Task {
            do {
                let taskFeedback = try await codingAgent.getTaskFeedback()
                await MainActor.run {
                    feedback = taskFeedback
                    showFeedback = true
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    print("Error getting feedback: \(error)")
                }
            }
        }
    }
    
    private func readFile() {
        guard !filePath.isEmpty else { return }
        
        isWorking = true
        fileContent = ""
        
        Task {
            do {
                let content = try await codingAgent.readFile(at: filePath)
                await MainActor.run {
                    fileContent = content
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    fileContent = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func saveFile() {
        guard !filePath.isEmpty && !fileContent.isEmpty else { return }
        
        isWorking = true
        
        Task {
            do {
                if FileManager.default.fileExists(atPath: filePath) {
                    try await codingAgent.updateFile(at: filePath, content: fileContent)
                } else {
                    try await codingAgent.createFile(at: filePath, content: fileContent)
                }
                await MainActor.run {
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    print("Error saving file: \(error)")
                }
            }
        }
    }
    
    private func deleteFile() {
        guard !filePath.isEmpty else { return }
        
        isWorking = true
        
        Task {
            do {
                try await codingAgent.deleteFile(at: filePath)
                await MainActor.run {
                    fileContent = ""
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    print("Error deleting file: \(error)")
                }
            }
        }
    }
    
    private func listDirectory() {
        guard !filePath.isEmpty else { return }
        
        isWorking = true
        
        Task {
            do {
                let files = try await codingAgent.listFiles(in: filePath)
                await MainActor.run {
                    fileContent = files.joined(separator: "\n")
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    fileContent = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func resetAgent() {
        codingAgent.resetTaskPlan()
        taskDescription = ""
    }
    
    private func executeCode() {
        guard !codeToExecute.isEmpty else { return }
        
        isWorking = true
        codeExecutionResult = nil
        
        Task {
            do {
                let result = try await codingAgent.executeCode(
                    code: codeToExecute,
                    language: selectedCodeLanguage
                )
                
                await MainActor.run {
                    codeExecutionResult = result
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    codeExecutionResult = CodeExecutionResult(
                        success: false,
                        output: "",
                        error: error.localizedDescription,
                        exitCode: -1,
                        timedOut: false
                    )
                    isWorking = false
                }
            }
        }
    }
}

// MARK: - Task Planning View

struct TaskPlanningView: View {
    @ObservedObject var codingAgent: CodingAgent
    @Binding var taskDescription: String
    @Binding var isWorking: Bool
    let planTask: () -> Void
    let executeTask: () -> Void
    let getFeedback: () -> Void
    let resetAgent: () -> Void
    @Binding var showLogs: Bool
    
    var body: some View {
        VStack {
            // Task Input Area
            VStack(alignment: .leading) {
                Text("Task Description")
                    .font(.headline)
                
                TextEditor(text: $taskDescription)
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.bottom)
                
                // Buttons
                HStack {
                    Button(action: planTask) {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("Plan Task")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(taskDescription.isEmpty || isWorking || codingAgent.isPlanning)
                    
                    Button(action: executeTask) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Execute Plan")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(codingAgent.taskPlan == nil || isWorking)
                    
                    Button(action: getFeedback) {
                        HStack {
                            Image(systemName: "bubble.left.fill")
                            Text("Get Feedback")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(codingAgent.taskPlan == nil || isWorking)
                    
                    Button(action: resetAgent) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                    
                    Button(action: { showLogs.toggle() }) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("Logs")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom)
            }
            .padding()
            
            // Task Plan & Progress
            if let plan = codingAgent.taskPlan {
                VStack(alignment: .leading) {
                    Text("Task Plan: \(plan.title)")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                                StepView(
                                    step: step,
                                    stepNumber: index + 1,
                                    isCurrentStep: index == plan.currentStepIndex
                                )
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding()
            } else if codingAgent.isPlanning {
                ProgressView("Planning task...")
                    .padding()
            } else {
                Text("Enter a task description and click 'Plan Task' to start")
                    .foregroundColor(.gray)
                    .padding()
            }
            
            Spacer()
        }
    }
}

// MARK: - File Operations View

struct FileOperationsView: View {
    @ObservedObject var codingAgent: CodingAgent
    @Binding var isWorking: Bool
    @Binding var filePath: String
    @Binding var fileContent: String
    let readFile: () -> Void
    let saveFile: () -> Void
    let deleteFile: () -> Void
    let listDirectory: () -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("File Operations")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack {
                TextField("File path", text: $filePath)
                    .textFieldStyle(.roundedBorder)
                
                Button("Read") {
                    readFile()
                }
                .buttonStyle(.bordered)
                .disabled(filePath.isEmpty || isWorking)
                
                Button("List") {
                    listDirectory()
                }
                .buttonStyle(.bordered)
                .disabled(filePath.isEmpty || isWorking)
            }
            
            if !fileContent.isEmpty {
                VStack(alignment: .leading) {
                    HStack {
                        Text("File Content")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Button("Save") {
                            saveFile()
                        }
                        .buttonStyle(.bordered)
                        .disabled(filePath.isEmpty || isWorking)
                        
                        Button("Delete") {
                            deleteFile()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                        .disabled(filePath.isEmpty || isWorking)
                    }
                    
                    TextEditor(text: $fileContent)
                        .font(.system(.body, design: .monospaced))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Code Execution View

struct CodeExecutionView: View {
    @Binding var codeToExecute: String
    @Binding var selectedCodeLanguage: CodeLanguage
    @Binding var codeExecutionResult: CodeExecutionResult?
    @Binding var isWorking: Bool
    let executeCode: () -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Code Execution")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack {
                Text("Language:")
                
                Picker("Language", selection: $selectedCodeLanguage) {
                    Text("Swift").tag(CodeLanguage.swift)
                    Text("Shell").tag(CodeLanguage.shell)
                    Text("Python").tag(CodeLanguage.python)
                    Text("JavaScript").tag(CodeLanguage.javascript)
                    Text("Ruby").tag(CodeLanguage.ruby)
                }
                .pickerStyle(.segmented)
            }
            .padding(.bottom)
            
            Text("Code:")
                .font(.subheadline)
            
            TextEditor(text: $codeToExecute)
                .font(.system(.body, design: .monospaced))
                .frame(height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            
            HStack {
                Spacer()
                
                Button(action: executeCode) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Execute Code")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(codeToExecute.isEmpty || isWorking)
            }
            .padding(.vertical)
            
            if isWorking {
                ProgressView("Executing code...")
                    .padding()
            } else if let result = codeExecutionResult {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? .green : .red)
                        
                        Text(result.success ? "Execution Successful" : "Execution Failed")
                            .font(.headline)
                            .foregroundColor(result.success ? .green : .red)
                        
                        if result.timedOut {
                            Text("(Timed Out)")
                                .foregroundColor(.orange)
                        }
                        
                        Spacer()
                        
                        Text("Exit Code: \(result.exitCode)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !result.output.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Output:")
                                .font(.subheadline)
                            
                            ScrollView {
                                Text(result.output)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(8)
                            }
                            .frame(height: 100)
                        }
                    }
                    
                    if !result.error.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Errors:")
                                .font(.subheadline)
                            
                            ScrollView {
                                Text(result.error)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.red)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(8)
                            }
                            .frame(height: 100)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct LogView: View {
    let logs: [String]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            HStack {
                Text("Agent Logs")
                    .font(.headline)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logs, id: \.self) { log in
                        Text(log)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct StepView: View {
    let step: TaskStep
    let stepNumber: Int
    let isCurrentStep: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Step Number and Status Icon
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 24, height: 24)
                    
                    if step.status == .completed {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .bold))
                    } else if step.status == .failed {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .bold))
                    } else if step.status == .inProgress {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    } else {
                        Text("\(stepNumber)")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                
                // Step Description
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.description)
                        .font(.body)
                        .fontWeight(isCurrentStep ? .bold : .regular)
                    
                    if let result = step.result, !result.isEmpty {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Text("Status: \(step.status.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrentStep ? Color.blue.opacity(0.1) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isCurrentStep ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var statusColor: Color {
        switch step.status {
        case .pending:
            return .gray
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

// Preview
struct CodingAgentDemo_Previews: PreviewProvider {
    static var previews: some View {
        CodingAgentDemo()
    }
} 