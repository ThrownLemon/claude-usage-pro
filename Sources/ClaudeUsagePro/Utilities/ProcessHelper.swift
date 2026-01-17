import Foundation

/// Helper for running external processes with timeout support.
enum ProcessHelper {
    /// Error thrown when a process times out.
    enum ProcessError: Error, LocalizedError {
        case timeout
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .timeout:
                "Process execution timed out"
            case let .executionFailed(message):
                "Process execution failed: \(message)"
            }
        }
    }

    /// Runs a process with a timeout.
    /// - Parameters:
    ///   - executablePath: Path to the executable
    ///   - arguments: Command line arguments
    ///   - timeout: Timeout in seconds (defaults to Constants.Timeouts.processExecutionTimeout)
    /// - Returns: Tuple of (stdout data, stderr data, exit status)
    /// - Throws: ProcessError.timeout if the process exceeds the timeout
    static func run(
        executablePath: String,
        arguments: [String] = [],
        timeout: TimeInterval = Constants.Timeouts.processExecutionTimeout
    ) throws -> (stdout: Data, stderr: Data, exitStatus: Int32) {
        let task = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        // Set up timeout handling
        let timeoutWorkItem = DispatchWorkItem {
            if task.isRunning {
                Log.warning(Log.Category.app, "Process timed out after \(timeout)s: \(executablePath)")
                task.terminate()
            }
        }

        // Schedule timeout
        DispatchQueue.global().asyncAfter(
            deadline: .now() + timeout,
            execute: timeoutWorkItem
        )

        // Read pipes concurrently before waiting to avoid deadlock if child process fills the buffer
        var stdoutData = Data()
        var stderrData = Data()

        do {
            try task.run()

            // Read from pipes concurrently with process execution to prevent deadlock.
            // If we wait for the process to exit first, and it fills the pipe buffer,
            // the process will block waiting for us to read, causing a deadlock.
            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading

            let readGroup = DispatchGroup()

            readGroup.enter()
            DispatchQueue.global().async {
                stdoutData = stdoutHandle.readDataToEndOfFile()
                readGroup.leave()
            }

            readGroup.enter()
            DispatchQueue.global().async {
                stderrData = stderrHandle.readDataToEndOfFile()
                readGroup.leave()
            }

            // Wait for reads to complete (they will complete when the process closes the pipes)
            readGroup.wait()

            // Now wait for process to fully exit
            task.waitUntilExit()

            // Cancel timeout if process completed
            timeoutWorkItem.cancel()

            // Check if we timed out (terminated with SIGTERM = 15)
            if task.terminationReason == .uncaughtSignal, task.terminationStatus == 15 {
                throw ProcessError.timeout
            }

            return (stdoutData, stderrData, task.terminationStatus)
        } catch let error as ProcessError {
            throw error
        } catch {
            timeoutWorkItem.cancel()
            throw ProcessError.executionFailed(error.localizedDescription)
        }
    }

    /// Runs a process and returns stdout as a string.
    /// - Parameters:
    ///   - executablePath: Path to the executable
    ///   - arguments: Command line arguments
    ///   - timeout: Timeout in seconds
    /// - Returns: stdout as a trimmed string, or nil if execution failed
    static func runAndGetOutput(
        executablePath: String,
        arguments: [String] = [],
        timeout: TimeInterval = Constants.Timeouts.processExecutionTimeout
    ) -> String? {
        do {
            let result = try run(executablePath: executablePath, arguments: arguments, timeout: timeout)
            guard result.exitStatus == 0 else { return nil }
            return String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
