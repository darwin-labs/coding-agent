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
    
    var body: some View {
        NavigationView {
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
                
                // File Operations Area
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
                                .frame(height: 100)
                                .font(.system(.body, design: .monospaced))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
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
                
                Spacer()
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