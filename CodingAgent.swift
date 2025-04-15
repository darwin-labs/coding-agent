import Foundation
import Combine

// MARK: - Logger

/// Simple logger to track agent activities
class AgentLogger {
    static let shared = AgentLogger()
    private var logs: [String] = []
    
    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(message)"
        logs.append(logEntry)
        print(logEntry)
    }
    
    func getAllLogs() -> [String] {
        return logs
    }
    
    func clearLogs() {
        logs.removeAll()
    }
}

// MARK: - Task Step

/// Represents a single step in a multi-step coding task
struct TaskStep: Identifiable, Codable {
    let id: UUID
    let description: String
    var status: StepStatus
    var result: String?
    
    enum StepStatus: String, Codable {
        case pending
        case inProgress
        case completed
        case failed
    }
    
    init(id: UUID = UUID(), description: String, status: StepStatus = .pending, result: String? = nil) {
        self.id = id
        self.description = description
        self.status = status
        self.result = result
    }
}

// MARK: - Task Plan

/// Represents a complete plan for executing a complex coding task
struct TaskPlan: Codable {
    var steps: [TaskStep]
    var title: String
    var currentStepIndex: Int
    
    init(title: String, steps: [TaskStep], currentStepIndex: Int = 0) {
        self.title = title
        self.steps = steps
        self.currentStepIndex = currentStepIndex
    }
}

// MARK: - StepExecutionResult

/// Represents the result of executing a single step in the task
struct StepExecutionResult: Codable {
    let success: Bool
    let output: String
    let code: String?
    let nextAction: NextAction?
    
    enum NextAction: String, Codable {
        case continueToNext
        case retry
        case modifyPlan
        case complete
    }
}

// MARK: - CodingAgent

/// A multi-step coding agent capable of planning and executing complex coding tasks
class CodingAgent: ObservableObject {
    @Published var taskPlan: TaskPlan?
    @Published var isExecuting: Bool = false
    @Published var isPlanning: Bool = false
    @Published var currentOutput: String = ""
    @Published var logs: [String] = []
    
    private let feedbackGenerator = FeedbackGenerator()
    private var cancellables = Set<AnyCancellable>()
    private let logger = AgentLogger.shared
    
    // MARK: - Task Planning
    
    /// Creates a task plan for a given complex coding task
    /// - Parameter task: The description of the coding task to be performed
    /// - Returns: A TaskPlan containing the steps needed to complete the task
    func planTask(task: String) async throws -> TaskPlan {
        isPlanning = true
        logger.log("Starting task planning for: \(task)")
        defer { isPlanning = false }
        
        // Prompt for the LLM to generate a task plan
        let prompt = """
        I need to break down the following coding task into sequential steps:
        
        TASK: \(task)
        
        Please analyze this task and create a detailed plan with steps that:
        1. Are small enough to be executed individually
        2. Build upon each other logically
        3. Cover all aspects of the requested task
        4. Include any necessary setup, implementation, testing, and refinement steps
        
        You are in JSON Mode. Return your response in the following JSON format:
        {
          "title": "A concise title for the task",
          "steps": [
            {
              "description": "Detailed description of what needs to be done in this step"
            },
            ... additional steps ...
          ]
        }
        """
        
        // Generate the task plan using the LLM
        struct PlanResponse: Decodable {
            let title: String
            let steps: [StepDescription]
            
            struct StepDescription: Decodable {
                let description: String
            }
        }
        
        let model = CloudModel(name: "o3-mini", logo: "", publisher: "", modelPath: "openai/o3-mini", isPlusModel: false, modelType: .reasoning, provider: .openrouter)
        
        logger.log("Sending task to LLM for planning")
        let planResponse: PlanResponse = try await feedbackGenerator.generateObject(
            model: model,
            system: "You are a coding task planner that breaks down complex tasks into logical steps. You are operating in JSON Mode and must return results in the exact JSON format requested.",
            prompt: prompt,
            useJsonMode: true
        )
        
        // Convert the response to our TaskPlan model
        let taskSteps = planResponse.steps.map { step in
            TaskStep(description: step.description)
        }
        
        let plan = TaskPlan(title: planResponse.title, steps: taskSteps)
        logger.log("Plan created with \(taskSteps.count) steps: \(planResponse.title)")
        
        // Update the published property on the main thread
        await MainActor.run {
            self.taskPlan = plan
            self.logs = logger.getAllLogs()
        }
        
        return plan
    }
    
    // MARK: - Task Execution
    
    /// Executes the current task plan step by step
    /// - Returns: The final output of the completed task
    func executeTaskPlan() async throws -> String {
        guard let plan = taskPlan, plan.currentStepIndex < plan.steps.count else {
            logger.log("ERROR: No valid task plan to execute")
            throw NSError(domain: "CodingAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "No valid task plan to execute"])
        }
        
        logger.log("Starting execution of task plan: \(plan.title)")
        await MainActor.run {
            isExecuting = true
            logs = logger.getAllLogs()
        }
        
        defer {
            Task { @MainActor in
                self.isExecuting = false
                self.logs = logger.getAllLogs()
            }
        }
        
        var currentPlan = plan
        var finalOutput = ""
        
        // Execute steps sequentially
        while currentPlan.currentStepIndex < currentPlan.steps.count {
            let stepIndex = currentPlan.currentStepIndex
            var step = currentPlan.steps[stepIndex]
            
            logger.log("Executing step \(stepIndex + 1)/\(currentPlan.steps.count): \(step.description)")
            
            // Update step status
            step.status = .inProgress
            await updateStep(at: stepIndex, with: step)
            
            // Execute the current step
            let result = try await executeStep(step: step, context: buildExecutionContext(for: currentPlan))
            
            // Update step with result
            step.result = result.output
            step.status = result.success ? .completed : .failed
            logger.log("Step \(stepIndex + 1) \(result.success ? "completed" : "failed"): \(result.output.prefix(100))...")
            await updateStep(at: stepIndex, with: step)
            
            // Handle next action based on execution result
            switch result.nextAction {
            case .continueToNext:
                logger.log("Moving to next step")
                currentPlan.currentStepIndex += 1
                await updateCurrentStepIndex(to: currentPlan.currentStepIndex)
                
            case .retry:
                logger.log("Retrying current step")
                // Keep the same step index to retry
                continue
                
            case .modifyPlan:
                logger.log("Modifying plan due to step failure")
                // Regenerate the plan from the current point
                let newPlan = try await regeneratePlan(from: currentPlan, at: stepIndex)
                currentPlan = newPlan
                await updateTaskPlan(with: newPlan)
                
            case .complete, nil:
                logger.log("Task marked as complete")
                // Mark task as complete regardless of remaining steps
                currentPlan.currentStepIndex = currentPlan.steps.count
                await updateCurrentStepIndex(to: currentPlan.currentStepIndex)
                finalOutput = result.output
                break
            }
            
            // If we just completed the last step, set the final output
            if result.success && stepIndex == currentPlan.steps.count - 1 {
                finalOutput = result.output
                logger.log("All steps completed successfully")
            }
            
            await MainActor.run {
                logs = logger.getAllLogs()
            }
        }
        
        return finalOutput
    }
    
    /// Executes a single step of the task
    /// - Parameters:
    ///   - step: The task step to execute
    ///   - context: The context from previous steps
    /// - Returns: The result of the step execution
    private func executeStep(step: TaskStep, context: String) async throws -> StepExecutionResult {
        // Prompt for the LLM to execute the step
        let prompt = """
        I need to execute the following step in a coding task:
        
        STEP: \(step.description)
        
        PREVIOUS CONTEXT:
        \(context)
        
        Please execute this step and provide:
        1. Whether the step was completed successfully
        2. The output or result of the step
        3. Any code produced during this step
        4. The next action to take (continue to next step, retry this step, modify the plan, or mark the task as complete)
        
        You are in JSON Mode. Return your response in the following JSON format:
        {
          "success": true/false,
          "output": "The textual output or result of this step",
          "code": "Any code produced during this step (optional)",
          "nextAction": "One of: continueToNext, retry, modifyPlan, complete"
        }
        """
        
        // Generate the step execution using the LLM
        struct ExecutionResponse: Decodable {
            let success: Bool
            let output: String
            let code: String?
            let nextAction: String
        }
        
        let model = CloudModel(name: "o3-mini", logo: "", publisher: "", modelPath: "openai/o3-mini", isPlusModel: false, modelType: .reasoning, provider: .openrouter)
        
        logger.log("Sending step to LLM for execution")
        let executionResponse: ExecutionResponse = try await feedbackGenerator.generateObject(
            model: model,
            system: "You are a coding step executor that implements individual steps of a larger coding task. You are operating in JSON Mode and must return results in the exact JSON format requested.",
            prompt: prompt,
            useJsonMode: true
        )
        
        // Update the current output on the main thread
        await MainActor.run {
            self.currentOutput = executionResponse.output
            self.logs = logger.getAllLogs()
        }
        
        // Convert the response to our StepExecutionResult model
        return StepExecutionResult(
            success: executionResponse.success,
            output: executionResponse.output,
            code: executionResponse.code,
            nextAction: StepExecutionResult.NextAction(rawValue: executionResponse.nextAction)
        )
    }
    
    /// Regenerates the task plan from a specific point
    /// - Parameters:
    ///   - plan: The current task plan
    ///   - index: The index from which to regenerate
    /// - Returns: A new task plan
    private func regeneratePlan(from plan: TaskPlan, at index: Int) async throws -> TaskPlan {
        let completedSteps = plan.steps.prefix(index).map { $0 }
        let failedStep = plan.steps[index]
        
        logger.log("Regenerating plan from step \(index + 1)")
        
        // Build context from completed steps
        let context = completedSteps.compactMap { $0.result }.joined(separator: "\n\n")
        
        // Prompt for the LLM to regenerate the plan
        let prompt = """
        I need to revise a coding task plan because a step failed:
        
        ORIGINAL TASK: \(plan.title)
        
        COMPLETED STEPS:
        \(completedSteps.enumerated().map { index, step in "Step \(index + 1): \(step.description)\nResult: \(step.result ?? "No result")" }.joined(separator: "\n\n"))
        
        FAILED STEP:
        \(failedStep.description)
        
        FAILURE DETAILS:
        \(failedStep.result ?? "No details available")
        
        Please create a new plan that:
        1. Takes into account what has been successfully completed
        2. Addresses the issues in the failed step
        3. Provides a clear path forward to complete the original task
        
        You are in JSON Mode. Return your response in the following JSON format:
        {
          "steps": [
            {
              "description": "Detailed description of what needs to be done in this step"
            },
            ... additional steps ...
          ]
        }
        """
        
        // Generate the revised plan using the LLM
        struct RegenerationResponse: Decodable {
            let steps: [StepDescription]
            
            struct StepDescription: Decodable {
                let description: String
            }
        }
        
        let model = CloudModel(name: "o3-mini", logo: "", publisher: "", modelPath: "openai/o3-mini", isPlusModel: false, modelType: .reasoning, provider: .openrouter)
        
        logger.log("Sending regeneration request to LLM")
        let regenerationResponse: RegenerationResponse = try await feedbackGenerator.generateObject(
            model: model,
            system: "You are a coding task planner that revises plans when steps fail. You are operating in JSON Mode and must return results in the exact JSON format requested.",
            prompt: prompt,
            useJsonMode: true
        )
        
        // Create new task steps
        let newSteps = regenerationResponse.steps.map { step in
            TaskStep(description: step.description)
        }
        
        // Combine completed steps with new steps
        var allSteps = completedSteps
        allSteps.append(contentsOf: newSteps)
        
        logger.log("Plan regenerated with \(newSteps.count) new steps")
        
        return TaskPlan(title: plan.title, steps: allSteps, currentStepIndex: index)
    }
    
    // MARK: - Code Execution
    
    /// Executes code in various languages
    /// - Parameters:
    ///   - code: The code to execute
    ///   - language: The programming language of the code
    ///   - timeout: Maximum execution time in seconds (default: 30)
    /// - Returns: The execution result with output, errors, and status
    func executeCode(code: String, language: CodeLanguage, timeout: Int = 30) async throws -> CodeExecutionResult {
        logger.log("Executing \(language.rawValue) code (timeout: \(timeout)s)")
        
        switch language {
        case .swift:
            return try await executeSwiftCode(code: code, timeout: timeout)
        case .shell:
            return try await executeShellCommand(command: code, timeout: timeout)
        case .python:
            return try await executePythonCode(code: code, timeout: timeout)
        case .javascript:
            return try await executeJavaScriptCode(code: code, timeout: timeout)
        case .ruby:
            return try await executeRubyCode(code: code, timeout: timeout)
        }
    }
    
    /// Executes Swift code using a temporary file and subprocess
    private func executeSwiftCode(code: String, timeout: Int) async throws -> CodeExecutionResult {
        // Create a temporary directory for the code
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent("code.swift")
        
        logger.log("Created temporary Swift file at: \(tempFile.path)")
        
        // Write the code to a temporary file
        try code.write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Execute the Swift code
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [tempFile.path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Create a timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            if process.isRunning {
                logger.log("Swift code execution timed out after \(timeout) seconds")
                process.terminate()
                return true
            }
            return false
        }
        
        logger.log("Starting Swift code execution")
        try process.run()
        
        // Wait for process to complete or timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                process.waitUntilExit()
                
                // Cancel the timeout task
                timeoutTask.cancel()
                
                // Get output and error
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let exitCode = process.terminationStatus
                let wasTimedOut = process.terminationReason == .uncaughtSignal
                
                // Clean up
                try? FileManager.default.removeItem(at: tempDir)
                
                let success = exitCode == 0 && !wasTimedOut
                self.logger.log("Swift code execution \(success ? "succeeded" : "failed") with exit code \(exitCode)")
                
                let result = CodeExecutionResult(
                    success: success,
                    output: output,
                    error: error,
                    exitCode: Int(exitCode),
                    timedOut: wasTimedOut
                )
                
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Executes a shell command
    private func executeShellCommand(command: String, timeout: Int) async throws -> CodeExecutionResult {
        // Create a process to run the shell command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Create a timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            if process.isRunning {
                logger.log("Shell command execution timed out after \(timeout) seconds")
                process.terminate()
                return true
            }
            return false
        }
        
        logger.log("Executing shell command: \(command)")
        try process.run()
        
        // Wait for process to complete or timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                process.waitUntilExit()
                
                // Cancel the timeout task
                timeoutTask.cancel()
                
                // Get output and error
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let exitCode = process.terminationStatus
                let wasTimedOut = process.terminationReason == .uncaughtSignal
                
                let success = exitCode == 0 && !wasTimedOut
                self.logger.log("Shell command execution \(success ? "succeeded" : "failed") with exit code \(exitCode)")
                
                let result = CodeExecutionResult(
                    success: success,
                    output: output,
                    error: error,
                    exitCode: Int(exitCode),
                    timedOut: wasTimedOut
                )
                
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Executes Python code using a temporary file and subprocess
    private func executePythonCode(code: String, timeout: Int) async throws -> CodeExecutionResult {
        // Create a temporary directory for the code
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent("code.py")
        
        logger.log("Created temporary Python file at: \(tempFile.path)")
        
        // Write the code to a temporary file
        try code.write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Execute the Python code
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [tempFile.path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Create a timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            if process.isRunning {
                logger.log("Python code execution timed out after \(timeout) seconds")
                process.terminate()
                return true
            }
            return false
        }
        
        logger.log("Starting Python code execution")
        try process.run()
        
        // Wait for process to complete or timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                process.waitUntilExit()
                
                // Cancel the timeout task
                timeoutTask.cancel()
                
                // Get output and error
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let exitCode = process.terminationStatus
                let wasTimedOut = process.terminationReason == .uncaughtSignal
                
                // Clean up
                try? FileManager.default.removeItem(at: tempDir)
                
                let success = exitCode == 0 && !wasTimedOut
                self.logger.log("Python code execution \(success ? "succeeded" : "failed") with exit code \(exitCode)")
                
                let result = CodeExecutionResult(
                    success: success,
                    output: output,
                    error: error,
                    exitCode: Int(exitCode),
                    timedOut: wasTimedOut
                )
                
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Executes JavaScript code using Node.js
    private func executeJavaScriptCode(code: String, timeout: Int) async throws -> CodeExecutionResult {
        // Create a temporary directory for the code
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent("code.js")
        
        logger.log("Created temporary JavaScript file at: \(tempFile.path)")
        
        // Write the code to a temporary file
        try code.write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Execute the JavaScript code with Node.js
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/node")
        process.arguments = [tempFile.path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Create a timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            if process.isRunning {
                logger.log("JavaScript code execution timed out after \(timeout) seconds")
                process.terminate()
                return true
            }
            return false
        }
        
        logger.log("Starting JavaScript code execution")
        try process.run()
        
        // Wait for process to complete or timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                process.waitUntilExit()
                
                // Cancel the timeout task
                timeoutTask.cancel()
                
                // Get output and error
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let exitCode = process.terminationStatus
                let wasTimedOut = process.terminationReason == .uncaughtSignal
                
                // Clean up
                try? FileManager.default.removeItem(at: tempDir)
                
                let success = exitCode == 0 && !wasTimedOut
                self.logger.log("JavaScript code execution \(success ? "succeeded" : "failed") with exit code \(exitCode)")
                
                let result = CodeExecutionResult(
                    success: success,
                    output: output,
                    error: error,
                    exitCode: Int(exitCode),
                    timedOut: wasTimedOut
                )
                
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Executes Ruby code
    private func executeRubyCode(code: String, timeout: Int) async throws -> CodeExecutionResult {
        // Create a temporary directory for the code
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent("code.rb")
        
        logger.log("Created temporary Ruby file at: \(tempFile.path)")
        
        // Write the code to a temporary file
        try code.write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Execute the Ruby code
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [tempFile.path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Create a timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            if process.isRunning {
                logger.log("Ruby code execution timed out after \(timeout) seconds")
                process.terminate()
                return true
            }
            return false
        }
        
        logger.log("Starting Ruby code execution")
        try process.run()
        
        // Wait for process to complete or timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                process.waitUntilExit()
                
                // Cancel the timeout task
                timeoutTask.cancel()
                
                // Get output and error
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let exitCode = process.terminationStatus
                let wasTimedOut = process.terminationReason == .uncaughtSignal
                
                // Clean up
                try? FileManager.default.removeItem(at: tempDir)
                
                let success = exitCode == 0 && !wasTimedOut
                self.logger.log("Ruby code execution \(success ? "succeeded" : "failed") with exit code \(exitCode)")
                
                let result = CodeExecutionResult(
                    success: success,
                    output: output,
                    error: error,
                    exitCode: Int(exitCode),
                    timedOut: wasTimedOut
                )
                
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - File Operations
    
    /// Reads the content of a file
    /// - Parameter path: The path to the file
    /// - Returns: The content of the file as a string
    func readFile(at path: String) async throws -> String {
        logger.log("Reading file at: \(path)")
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path) else {
            logger.log("ERROR: File not found at \(path)")
            throw NSError(domain: "CodingAgent", code: 4, userInfo: [NSLocalizedDescriptionKey: "File not found at \(path)"])
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let content = String(data: data, encoding: .utf8) else {
                logger.log("ERROR: Could not decode file content as UTF-8")
                throw NSError(domain: "CodingAgent", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not decode file content as UTF-8"])
            }
            logger.log("Successfully read file (\(data.count) bytes)")
            return content
        } catch {
            logger.log("ERROR: Failed to read file: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Creates a new file with the given content
    /// - Parameters:
    ///   - path: The path where the file should be created
    ///   - content: The content to write to the file
    func createFile(at path: String, content: String) async throws {
        logger.log("Creating file at: \(path)")
        let fileManager = FileManager.default
        
        // Create directory if it doesn't exist
        let directory = (path as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: directory) {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            logger.log("Created directory: \(directory)")
        }
        
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            logger.log("Successfully created file (\(content.count) characters)")
        } catch {
            logger.log("ERROR: Failed to create file: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Updates an existing file with new content
    /// - Parameters:
    ///   - path: The path to the file to update
    ///   - content: The new content for the file
    func updateFile(at path: String, content: String) async throws {
        logger.log("Updating file at: \(path)")
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path) else {
            logger.log("ERROR: File not found at \(path)")
            throw NSError(domain: "CodingAgent", code: 4, userInfo: [NSLocalizedDescriptionKey: "File not found at \(path)"])
        }
        
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            logger.log("Successfully updated file (\(content.count) characters)")
        } catch {
            logger.log("ERROR: Failed to update file: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Deletes a file at the specified path
    /// - Parameter path: The path to the file to delete
    func deleteFile(at path: String) async throws {
        logger.log("Deleting file at: \(path)")
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path) else {
            logger.log("WARNING: File not found at \(path), nothing to delete")
            return
        }
        
        do {
            try fileManager.removeItem(atPath: path)
            logger.log("Successfully deleted file")
        } catch {
            logger.log("ERROR: Failed to delete file: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Lists files in a directory
    /// - Parameter path: The directory path
    /// - Returns: An array of file paths
    func listFiles(in directory: String) async throws -> [String] {
        logger.log("Listing files in directory: \(directory)")
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: directory) else {
            logger.log("ERROR: Directory not found at \(directory)")
            throw NSError(domain: "CodingAgent", code: 6, userInfo: [NSLocalizedDescriptionKey: "Directory not found at \(directory)"])
        }
        
        do {
            let files = try fileManager.contentsOfDirectory(atPath: directory)
            logger.log("Found \(files.count) files")
            return files.map { directory + "/" + $0 }
        } catch {
            logger.log("ERROR: Failed to list files: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    /// Builds the execution context for a step based on previous steps
    /// - Parameter plan: The current task plan
    /// - Returns: A string containing the context from previous steps
    private func buildExecutionContext(for plan: TaskPlan) -> String {
        let completedSteps = plan.steps.prefix(plan.currentStepIndex).filter { $0.status == .completed }
        
        if completedSteps.isEmpty {
            return "No previous steps completed yet."
        }
        
        return completedSteps.enumerated().map { index, step in
            """
            STEP \(index + 1): \(step.description)
            RESULT:
            \(step.result ?? "No result")
            """
        }.joined(separator: "\n\n")
    }
    
    /// Updates a step at a specific index
    /// - Parameters:
    ///   - index: The index of the step to update
    ///   - step: The updated step
    @MainActor
    private func updateStep(at index: Int, with step: TaskStep) {
        guard var plan = taskPlan, index < plan.steps.count else { return }
        plan.steps[index] = step
        taskPlan = plan
    }
    
    /// Updates the current step index
    /// - Parameter index: The new current step index
    @MainActor
    private func updateCurrentStepIndex(to index: Int) {
        guard var plan = taskPlan else { return }
        plan.currentStepIndex = index
        taskPlan = plan
    }
    
    /// Updates the entire task plan
    /// - Parameter plan: The new task plan
    @MainActor
    private func updateTaskPlan(with plan: TaskPlan) {
        taskPlan = plan
    }
    
    // MARK: - Public Methods
    
    /// Get feedback on the current state of the task
    /// - Returns: Feedback on the current task state
    func getTaskFeedback() async throws -> [String] {
        guard let plan = taskPlan else {
            logger.log("ERROR: No task plan available for feedback")
            throw NSError(domain: "CodingAgent", code: 3, userInfo: [NSLocalizedDescriptionKey: "No task plan available"])
        }
        
        logger.log("Requesting feedback for task: \(plan.title)")
        
        let prompt = """
        I'm working on a coding task: "\(plan.title)"
        
        Current progress:
        \(plan.steps.enumerated().map { index, step in
            "Step \(index + 1): \(step.description) - Status: \(step.status.rawValue)"
        }.joined(separator: "\n"))
        
        Based on this information, what should I consider next? What potential issues might I encounter?
        
        You are in JSON Mode. Return your response in the following JSON format:
        {
          "questions": [
            "First follow-up question or suggestion",
            "Second follow-up question or suggestion",
            ... additional questions or suggestions ...
          ]
        }
        """
        
        let feedback = try await feedbackGenerator.generateFeedback(
            query: prompt,
            numQuestions: 3,
            useJsonMode: true
        )
        
        logger.log("Received \(feedback.count) feedback items")
        
        await MainActor.run {
            logs = logger.getAllLogs()
        }
        
        return feedback
    }
    
    /// Reset the current task plan
    func resetTaskPlan() {
        logger.log("Resetting task plan")
        Task { @MainActor in
            taskPlan = nil
            isExecuting = false
            isPlanning = false
            currentOutput = ""
            logs = logger.getAllLogs()
        }
    }
}

// MARK: - CloudModel Extension

/// Extension to represent cloud LLM models
struct CloudModel {
    let name: String
    let logo: String
    let publisher: String
    let modelPath: String
    let isPlusModel: Bool
    let modelType: ModelType
    let provider: ProviderType
    
    enum ModelType {
        case reasoning
        case code
        case chat
        case embeddings
    }
    
    enum ProviderType {
        case openrouter
        case groq
    }
}

// MARK: - ProcessedFileContext Struct

/// Struct to hold processed file context information
struct ProcessedFileContext {
    var filesDescriptionString: String = ""
    var attachedImages: [Data] = []
}

// MARK: - ProcessedPrompt Struct

/// Struct to hold processed prompt information
struct ProcessedPrompt {
    var shouldGenerateImage: Bool
    var imageGenerationPrompt: String
    var performWebSearch: Bool
    var searchQuery: String
    var userMemories: [String]
}

// MARK: - ToolCaller Class

/// Class to process files and perform tool calls
class ToolCaller {
    let processedPrompt: ProcessedPrompt
    let prompt: String
    
    init(processedPrompt: ProcessedPrompt, prompt: String) {
        self.processedPrompt = processedPrompt
        self.prompt = prompt
    }
    
    func processFiles(fileURLs: [String]) -> ProcessedFileContext {
        // Simplified implementation - in a real app, this would process files
        var context = ProcessedFileContext()
        
        if !fileURLs.isEmpty {
            context.filesDescriptionString = "Files provided: \(fileURLs.joined(separator: ", "))"
        }
        
        return context
    }
}

// MARK: - APIKeyManager Class

/// Class to manage API keys for different providers
class APIKeyManager {
    enum Provider {
        case openrouter
        case groq
    }
    
    func getAPIKey(provider: Provider) -> String {
        switch provider {
        case .openrouter:
            return UserDefaults.standard.string(forKey: "openrouterAPIKey") ?? ""
        case .groq:
            return UserDefaults.standard.string(forKey: "groqAPIKey") ?? ""
        }
    }
    
    func setAPIKey(provider: Provider, key: String) {
        switch provider {
        case .openrouter:
            UserDefaults.standard.set(key, forKey: "openrouterAPIKey")
        case .groq:
            UserDefaults.standard.set(key, forKey: "groqAPIKey")
        }
    }
}

// MARK: - FeedbackGenerator Class

/// Class to generate feedback from LLM and handle API communication
class FeedbackGenerator: ObservableObject {

  private let apiKeyManager: APIKeyManager = APIKeyManager()

  /// Returns the system prompt string.
  /// Replace with your actual prompt if needed.
  func systemPrompt() -> String {
      return "System prompt"
  }

  // MARK: - generateObject Implementation

  /// Streams a chat completion from the OpenRouter API, accumulates the response text,
  /// and decodes it into an object of type T using the provided JSON schema.
  /// - Parameters:
  ///   - model: A CloudModel describing the model to use.
  ///   - system: The system prompt string.
  ///   - prompt: The user prompt string.
  ///   - schema: The expected type of the JSON response (used for decoding).
  ///   - fileContext: Optional file context to include in the prompt.
  ///   - history: Optional conversation history.
  ///   - useJsonMode: Whether to explicitly use JSON mode in the API call.
  /// - Returns: An instance of type T decoded from the streamed JSON response.
  func generateObject<T: Decodable>(model: CloudModel,
                                    system: String,
                                    prompt: String,
                                    schema: [String: Any]? = nil,
                                    fileContext: ProcessedFileContext? = nil,
                                    history: [[String: Any]] = [[:]], 
                                    useJsonMode: Bool = false) async throws -> T {


      // Retrieve and sanitize the API key.
      var openrouterAPIKey = apiKeyManager.getAPIKey(provider: .openrouter)
      var groqAPIKey = apiKeyManager.getAPIKey(provider: .groq)
      openrouterAPIKey = openrouterAPIKey.replacingOccurrences(of: "\"", with: "")
      groqAPIKey = groqAPIKey.replacingOccurrences(of: "\"", with: "")


      print("Open router api key: \(openrouterAPIKey)")

      var systemPrompt = system
      if useJsonMode {
          systemPrompt = "You are operating in JSON Mode. Please provide all responses exclusively in the provided JSON format, adhering strictly to the specified schema. \(system)"
      }
      
      var promptHistory: [[String: Any]] = []

      if fileContext != nil {
        systemPrompt += fileContext!.filesDescriptionString
      }

      promptHistory.append([
          "role": "system",
          "content": systemPrompt
      ])

      promptHistory += history

      promptHistory.append([
        "role": "user",
        "content": prompt
      ])

      if let fileContext = fileContext {

        systemPrompt += fileContext.filesDescriptionString

        for img in fileContext.attachedImages {
          let base64EncodedImgData = img.base64EncodedString()
          promptHistory.append(["type": "image_url",
                          "image_url": ["url": "data:image/jpeg;base64,\(base64EncodedImgData)"]
          ])

        }
      }

      // Define parameters for the request.
      let maxTokens = 1024
      let temperature = 0.7
      let topP = 0.7
      let topK = 50
      let repetitionPenalty = 1.0
      let streamTokens = false

      var url = URL(string: "https://openrouter.ai/api/v1/chat/completions")

      if model.provider == .groq {
        url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
      }

      guard let url = url else {
        throw NSError(domain: "generateObject", code: 1, userInfo: [NSLocalizedDescriptionKey: "URL nil"])
      }

      // Prepare the payload.
      var payload: [String: Any] = [
        "model": model.modelPath,
        "messages": promptHistory
      ]

      if model.provider == .groq {
        payload = [
          "model": model.modelPath,
          "messages": history,
          "temperature": temperature,
          "max_completion_tokens": maxTokens,
          "top_p": topP,
          "stream": streamTokens,
          "stop": NSNull()
        ]
      }
      
      // Add response_format for JSON mode
      if useJsonMode {
          payload["response_format"] = ["type": "json_object"]
      }

      print("Payload: \(payload)")

      // Build the URLRequest.
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("Bearer \(model.provider == .groq ? groqAPIKey : openrouterAPIKey)", forHTTPHeaderField: "Authorization")
      request.httpBody = try JSONSerialization.data(withJSONObject: payload)

      print("Request to API: \(request)")

      // Create a URLSession with a default configuration.
      let session = URLSession(configuration: .default)
      defer { session.invalidateAndCancel() }

      // Open a URLSession stream.
      let (stream, response) = try await URLSession.shared.bytes(for: request)

      // Check for a valid HTTP response.
      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        print("Response: \(response)")
          throw NSError(domain: "generateObject", code: 2, userInfo: [NSLocalizedDescriptionKey: "HTTP error in response"])
      }

      var accumulatedText = ""

      for try await line in stream.lines {
            accumulatedText.append(line)
        }

        // Convert the accumulated text into Data.
      guard let responseData = accumulatedText.data(using: .utf8) else {
            throw NSError(domain: "generateObject", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to encode response text"])
        }


        // Decode the full response into a dictionary and extract the "content" field inline.
        let jsonObject = try JSONSerialization.jsonObject(with: responseData, options: [])
        guard let jsonDict = jsonObject as? [String: Any],
              let choices = jsonDict["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "generateObject", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to extract content from response"])
        }


      let cleanJSON: String
      if useJsonMode {
          cleanJSON = content
      } else {
          guard let extractedJSON = extractJSON(from: content) else {
              throw NSError(domain: "generateObject", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unable to extract JSON from response string"])
          }
          cleanJSON = extractedJSON
      }
      print("JSON Content: \(cleanJSON)")


        // If T is String, return the content directly; otherwise decode the content string into T.
        if T.self == String.self {
          return cleanJSON as! T
        } else {
          guard let contentData = cleanJSON.data(using: .utf8) else {
                throw NSError(domain: "generateObject", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to encode content"])
            }
            let decoder = JSONDecoder()
            let decodedObject = try decoder.decode(T.self, from: contentData)
            return decodedObject
        }
  }

  @MainActor func processAttachments(fileURLs: [String] = [], images: [Data]) -> ProcessedFileContext {
    var fileContext = ToolCaller(processedPrompt: ProcessedPrompt(shouldGenerateImage: false, imageGenerationPrompt: "", performWebSearch: false, searchQuery: "", userMemories: []), prompt: "").processFiles(fileURLs: fileURLs)

    fileContext.attachedImages.append(contentsOf: images)

    return fileContext
  }

  func extractJSON(from input: String) -> String? {
      // Patterns to match a JSON object and a JSON array
      let patterns = [
          "\\{.*\\}", // JSON object
          "\\[.*\\]"  // JSON array
      ]

      // Try each pattern in order
      for pattern in patterns {
          do {
              let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
              let range = NSRange(location: 0, length: input.utf16.count)
              if let match = regex.firstMatch(in: input, options: [], range: range),
                 let matchedRange = Range(match.range, in: input) {
                  return String(input[matchedRange])
              }
          } catch {
              print("Regex error: \(error)")
          }
      }

      // No JSON substring found
      return nil
  }

  // MARK: - Generate Feedback Function

  /// Generates follow-up questions to clarify the research direction based on the given query.
  /// - Parameters:
  ///   - query: The user's query.
  ///   - numQuestions: The maximum number of follow-up questions to generate (default is 3).
  ///   - modelId: The model identifier to use (default is "o3-mini").
  ///   - apiKey: An optional API key for the model.
  ///   - useJsonMode: Whether to explicitly use JSON mode in the API call.
  /// - Returns: An array of follow-up questions.
  func generateFeedback(query: String,
                        numQuestions: Int = 3,
                        modelId: String = "o3-mini",
                        apiKey: String? = nil,
                        useJsonMode: Bool = false) async throws -> [String] {
      // Create the CloudModel instance (assumes createModel is defined elsewhere)

    let defaultModel = CloudModel(name: "o3-mini", logo: "", publisher: "", modelPath: "openai/o3-mini", isPlusModel: false, modelType: .reasoning, provider: .openrouter)

      // Build the prompt to ask follow-up questions.
      let prompt = """
      Given the following query from the user, ask some follow up questions to clarify the research direction. Return a maximum of \(numQuestions) questions, but feel free to return less if the original query is clear: <query>\(query)</query>
      """

      // Prepare the JSON schema for the expected response.
      let schema: [String: Any] = [
          "type": "object",
          "strict": true,
          "properties": [
              "questions": [
                  "type": "array",
                  "items": ["type": "string"],
                  "description": "Follow up questions to clarify the research direction, max of \(numQuestions)"
              ]
          ],
          "required": ["questions"]
      ]

      // Define the expected response structure.
      struct FeedbackResponse: Decodable {
          let questions: [String]
      }

      // Call generateObject to get the feedback.
    let feedback: FeedbackResponse = try await generateObject(
        model: defaultModel,
        system: systemPrompt(),
        prompt: prompt,
        schema: schema,
        useJsonMode: useJsonMode
    )

      // Return up to numQuestions follow-up questions.
      return Array(feedback.questions.prefix(numQuestions))
  }
}

// MARK: - CodeLanguage Enum

/// Supported programming languages for code execution
enum CodeLanguage: String, Codable {
    case swift = "Swift"
    case shell = "Shell"
    case python = "Python"
    case javascript = "JavaScript"
    case ruby = "Ruby"
}

// MARK: - CodeExecutionResult Struct

/// Represents the result of executing code
struct CodeExecutionResult: Codable {
    let success: Bool
    let output: String
    let error: String
    let exitCode: Int
    let timedOut: Bool
} 