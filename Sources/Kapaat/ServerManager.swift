import Foundation
import Security
import Combine

@MainActor
final class ServerManager: ObservableObject {
    enum Status: Equatable {
        case stopped, starting, running, failed(String)

        var label: String {
            switch self {
            case .stopped:          return "Stopped"
            case .starting:         return "Starting…"
            case .running:          return "Running"
            case .failed(let msg):  return msg
            }
        }

        var isRunning: Bool { self == .running }
    }

    @Published private(set) var status: Status = .stopped
    /// Last stderr output captured from the server process; shown in the error UI.
    @Published private(set) var lastError: String = ""

    let port: Int = 8096
    var serverURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    private var process: Process?
    private var startTask: Task<Void, Never>?
    private var stderrPipe: Pipe?

    init() { start() }

    func start() {
        guard process == nil else { return }
        lastError = ""
        status = .starting

        startTask = Task {
            do {
                try await launchServer()
                await waitForServer()
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.start() }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        stderrPipe = nil
        process?.terminate()
        process = nil
        status = .stopped
    }

    // MARK: - Private

    private func launchServer() throws {
        // If a server is already answering on our port, adopt it instead of fighting it.
        if isPortResponding() {
            status = .running
            return
        }

        // Kill any stale process that has the port bound but isn't responding.
        freePort(port)

        let appDir = try resolveAppDirectory()
        let python  = try resolvePython(in: appDir)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = [
            "-m", "uvicorn", "app:app",
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--log-level", "info",
        ]
        p.currentDirectoryURL = URL(fileURLWithPath: appDir)
        p.environment = buildEnvironment(appDir: appDir)

        // Capture stderr so startup errors are visible in the UI
        let pipe = Pipe()
        p.standardError  = pipe
        p.standardOutput = pipe
        stderrPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.lastError += text }
        }

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                // Only mark as failed (not just stopped) on non-zero exit
                if proc.terminationStatus != 0 {
                    let detail = self.lastError.isEmpty
                        ? "Process exited with code \(proc.terminationStatus)"
                        : self.lastError.suffix(400).trimmingCharacters(in: .whitespacesAndNewlines)
                    self.status = .failed(detail)
                } else {
                    self.status = .stopped
                }
                self.process = nil
            }
        }

        try p.run()
        self.process = p
    }

    private func waitForServer() async {
        let healthURL = serverURL.appendingPathComponent("login")
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            // If the process already died, stop waiting
            if process == nil { return }
            if (try? await URLSession.shared.data(from: healthURL)) != nil {
                status = .running
                return
            }
        }
        if case .starting = status {
            status = .failed("Server did not respond within 30 s\n\n\(lastError)".trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Port helpers

    /// True if a Kapaat-like HTTP server is already answering on our port.
    private func isPortResponding() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/login") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 1)
        request.httpMethod = "HEAD"
        var responding = false
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, resp, _ in
            responding = (resp as? HTTPURLResponse) != nil
            sem.signal()
        }.resume()
        sem.wait()
        return responding
    }

    /// Kill any process that has the given TCP port bound (SIGTERM, then SIGKILL).
    private func freePort(_ port: Int) {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-ti", "tcp:\(port)"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError  = Pipe()   // discard
        guard (try? lsof.run()) != nil else { return }
        lsof.waitUntilExit()
        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for pidStr in raw.split(separator: "\n") {
            guard let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)), pid > 0 else { continue }
            kill(pid, SIGTERM)
        }
        // Brief pause so the OS releases the port before we try to bind it.
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Path resolution

    /// Search order: bundled Resources/kapaat → sibling of .app → ~/kapaat
    private func resolveAppDirectory() throws -> String {
        let candidates: [String] = [
            Bundle.main.resourceURL?.appendingPathComponent("kapaat").path,
            Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("kapaat").path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("kapaat").path,
        ].compactMap { $0 }

        for dir in candidates {
            if FileManager.default.fileExists(atPath: dir + "/app.py") {
                return dir
            }
        }
        // Surface all paths checked so the user knows where we looked
        let searched = candidates.joined(separator: "\n  ")
        throw AppError.appDirNotFound(searched: searched)
    }

    /// Prefer .venv inside appDir, then Homebrew / system Python
    private func resolvePython(in appDir: String) throws -> String {
        let candidates = [
            appDir + "/.venv/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        guard let found = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            throw AppError.pythonNotFound
        }
        return found
    }

    private func buildEnvironment(appDir: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["AUTH_SECRET_KEY"]  = persistentSecretKey()
        env["BASE_URL"]         = "http://127.0.0.1:\(port)"
        env["DB_PATH"]          = dataDirectory() + "/kapaat.db"
        env["PHOTOS_DIR"]       = dataDirectory() + "/photos"
        env["PYTHONUNBUFFERED"] = "1"
        // Ensure the venv site-packages are on the path
        env["PYTHONPATH"]       = appDir
        return env
    }

    private func dataDirectory() -> String {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Kapaat").path
        try? FileManager.default.createDirectory(atPath: dir,
            withIntermediateDirectories: true)
        // Also create photos subdirectory
        try? FileManager.default.createDirectory(atPath: dir + "/photos",
            withIntermediateDirectories: true)
        return dir
    }

    /// Generates once, persists in UserDefaults (app sandbox keeps it private)
    private func persistentSecretKey() -> String {
        let key = "KapaatAuthSecretKey"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let secret = Data(bytes).base64EncodedString()
        UserDefaults.standard.set(secret, forKey: key)
        return secret
    }

    enum AppError: LocalizedError {
        case appDirNotFound(searched: String)
        case pythonNotFound

        var errorDescription: String? {
            switch self {
            case .appDirNotFound(let searched):
                return "app.py not found. Run setup.sh first.\n\nLooked in:\n  \(searched)"
            case .pythonNotFound:
                return "Python 3 not found.\n\nInstall with Homebrew:\n  brew install python"
            }
        }
    }
}
