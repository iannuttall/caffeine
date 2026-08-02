import CaffeineCore
import Foundation

actor ProcessScanner {
    func scan(signatures: [AgentSignature], includeAppBundles: Bool = false) -> [RunningAgent] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm=,args="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return ProcessListParser.agents(
                in: output,
                signatures: signatures,
                includeAppBundles: includeAppBundles)
        } catch {
            return []
        }
    }

    func installed(signatures: [AgentSignature]) -> [InstalledAgent] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = [
            "\(home)/.local/bin",
            "\(home)/.opencode/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "\(home)/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
        ]

        return signatures.compactMap { signature in
            for directory in directories {
                let path = "\(directory)/\(signature.executable)"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return InstalledAgent(executable: signature.executable, label: signature.label, path: path)
                }
            }
            return nil
        }
    }
}
