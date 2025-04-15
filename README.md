# Swift Multi-Step Coding Agent

This project implements a multi-step coding agent in Swift that can break down and execute complex coding tasks. The agent is powered by large language models through the OpenRouter and Groq APIs.

## Features

- **Task Planning**: Breaks down complex tasks into smaller, logical steps
- **Step Execution**: Sequentially executes each step of the plan
- **Adaptive Planning**: Can modify the plan if a step fails
- **Feedback Generation**: Provides feedback on the current state of the task
- **Logging System**: Detailed logging of all agent activities
- **File Operations**: Read, create, update, and delete files
- **Code Execution**: Run code in multiple programming languages (Swift, Python, JavaScript, Ruby, Shell)
- **SwiftUI Interface**: Includes a demo app with a complete user interface

## Architecture

The agent is built on several key components:

1. **CodingAgent**: The main class that orchestrates task planning and execution
2. **FeedbackGenerator**: Handles communication with LLM services
3. **TaskPlan & TaskStep**: Data structures to represent the planned steps
4. **StepExecutionResult**: Represents the result of executing a single step
5. **AgentLogger**: Tracks and records all agent activities
6. **CodeExecutionResult**: Captures the output of executed code

## How It Works

1. The user provides a description of a complex coding task
2. The agent uses an LLM to analyze the task and create a plan with discrete steps
3. The agent executes each step sequentially, using the LLM to generate code or perform other actions
4. If a step fails, the agent can regenerate the plan from that point
5. The agent provides ongoing feedback and results for each step
6. All actions are logged for transparency and debugging

## File Operations

The agent can interact with the file system to:

- Read existing files
- Create new files
- Update file contents
- Delete files
- List contents of directories

These operations allow the agent to examine and modify code as needed to complete tasks.

## Code Execution

The agent can execute code in multiple programming languages:

- **Swift**: Native Swift code execution
- **Shell**: Terminal commands and scripts
- **Python**: Python 3 scripts
- **JavaScript**: Node.js based JavaScript execution
- **Ruby**: Ruby scripts

Each execution is sandboxed and includes:
- Timeout protection
- Capture of standard output and error streams
- Error handling
- Temporary file management

## Usage

```swift
// Create a coding agent
let agent = CodingAgent()

// Plan a complex task
let plan = try await agent.planTask(task: "Create a RESTful API that manages a to-do list with CRUD operations")

// Execute the plan
let result = try await agent.executeTaskPlan()

// Get feedback on the current state
let feedback = try await agent.getTaskFeedback()

// File operations
let fileContent = try await agent.readFile(at: "/path/to/file.swift")
try await agent.createFile(at: "/path/to/newfile.swift", content: "// New file content")
try await agent.updateFile(at: "/path/to/file.swift", content: "// Updated content")
try await agent.deleteFile(at: "/path/to/file.swift")
let files = try await agent.listFiles(in: "/path/to/directory")

// Code execution
let swiftResult = try await agent.executeCode(
    code: "print(\"Hello, world!\")",
    language: .swift,
    timeout: 30
)

let pythonResult = try await agent.executeCode(
    code: "print('Hello from Python')",
    language: .python
)

// View logs
let logs = agent.logs
```

## Demo App

The project includes a SwiftUI app that demonstrates the agent's capabilities through a tabbed interface:

### Task Planning Tab
1. Enter a task description in the text field
2. Click "Plan Task" to generate a step-by-step plan
3. Click "Execute Plan" to run through each step sequentially
4. Use "Get Feedback" to receive suggestions about the current state

### File Operations Tab
5. Enter a file path and use the buttons to read, list, save, or delete files

### Code Execution Tab
6. Choose a programming language
7. Enter code to execute
8. View execution results including output and errors

The interface also provides:
- Detailed logs of agent activities with the "Logs" button
- A reset button to start over with a new task

## Requirements

- Swift 5.5+
- iOS 15.0+ / macOS 12.0+
- API keys for OpenRouter or Groq

## Setup

1. Clone the repository
2. Set up your API keys in the system keychain or UserDefaults
3. Build and run the project

## License

MIT 