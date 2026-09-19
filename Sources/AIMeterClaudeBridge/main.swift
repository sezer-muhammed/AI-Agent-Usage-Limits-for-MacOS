import AIMeterCore
import AIMeterProviders
import Foundation

// aimeter-claude-bridge
//
// Claude Code runs this as its status-line command. It does four things and
// nothing else:
//
//   1. read the status-line JSON Claude Code sends on stdin
//   2. extract only usage metadata (model, 5-hour / 7-day / spend windows)
//   3. atomically write that sanitized subset for AI Meter to read
//   4. optionally forward the original stdin to the user's previous status-line
//      command and pass its output through unchanged
//
// It never reads Claude's credentials, never touches the transcript, and never
// makes a network request. If anything fails, it exits 0 with no output so a
// broken bridge can never break the user's status line.
//
// Usage:
//   aimeter-claude-bridge [--out <path>] [--forward <shell command>]

struct Arguments {
    var outputURL: URL = ClaudeTelemetry.defaultURL()
    var forwardCommand: String?

    init(_ raw: [String]) {
        var index = 0
        while index < raw.count {
            switch raw[index] {
            case "--out" where index + 1 < raw.count:
                outputURL = URL(fileURLWithPath: raw[index + 1])
                index += 2
            case "--forward" where index + 1 < raw.count:
                forwardCommand = raw[index + 1]
                index += 2
            default:
                index += 1
            }
        }
    }
}

/// Runs the user's previous status-line command with the same stdin and relays
/// its stdout, so their status line renders exactly as it did before.
func forward(_ command: String, input: Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    // The command comes from the user's own settings.json, not from any payload.
    process.arguments = ["-c", command]

    let stdin = Pipe()
    let stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        return
    }

    stdin.fileHandleForWriting.write(input)
    try? stdin.fileHandleForWriting.close()

    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    FileHandle.standardOutput.write(output)
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
let input = FileHandle.standardInput.readDataToEndOfFile()

if let telemetry = try? ClaudeTelemetrySanitizer().sanitize(statusLineJSON: input),
    let encoded = try? DateFormatting.makeEncoder(prettyPrinted: true).encode(telemetry)
{
    try? AtomicFileWriter().write(encoded, to: arguments.outputURL)
}

if let forwardCommand = arguments.forwardCommand, !forwardCommand.isEmpty {
    forward(forwardCommand, input: input)
}
