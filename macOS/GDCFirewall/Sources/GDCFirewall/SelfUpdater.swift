import AppKit

/// Descarcă și instalează automat un update de aplicație, fără să mai
/// treacă prin browser/pagina de GitHub — port 1:1 al SelfUpdater.swift
/// din GDCVault/DataMover/CGConvertor/CursorPro (vezi CLAUDE.md Partea 1,
/// Regula 20). `pkgURL` vine din `update.json.download_url.mac` și poate fi
/// un `.pkg` sau arhiva `.zip` de pe gordas.dev (singurul format publicat
/// până există un `.pkg` semnat).
///
/// WARNING: pasul de instalare (promptul de parolă admin) NU poate fi
/// verificat automat — cere interacțiune fizică reală. Verificat
/// automat doar descărcarea (HTTP 200, fișier integru pe disc).
enum SelfUpdater {

    enum UpdateError: LocalizedError {
        case downloadFailed(String)
        case installScriptFailed(String)
        case archiveInvalid(String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let detail): return "Descărcarea a eșuat: \(detail)"
            case .archiveInvalid(let detail): return "Arhiva descărcată nu e validă: \(detail)"
            case .installScriptFailed(let detail): return "Nu am putut porni instalarea: \(detail)"
            }
        }
    }

    @MainActor
    static func downloadAndInstall(pkgURL: URL, version: String) async {
        let progress = UpdateProgressWindow(version: version)
        progress.show()

        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("gdcfirewall-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            // Fără distincția asta, o arhivă .zip ar ajunge la `installer -pkg`
            // și ar eșua abia după ce aplicația s-a închis — fără niciun mesaj.
            let isZip = pkgURL.pathExtension.lowercased() == "zip"
            let downloaded = tempDir.appendingPathComponent("GDCFirewall-\(version).\(isZip ? "zip" : "pkg")")

            progress.setStatus("Se descarcă actualizarea…")
            try await download(from: pkgURL, to: downloaded)

            progress.setStatus("Se instalează…")
            if isZip {
                let newApp = try await Task.detached { try extractApp(fromZip: downloaded, into: tempDir, expectedVersion: version) }.value
                let target = installTarget(for: newApp).path
                try runInstallScript(
                    command: "ditto \"\(newApp.path)\" \"\(target).new\" && rm -rf \"\(target)\" && mv \"\(target).new\" \"\(target)\"",
                    tempDir: tempDir)
            } else {
                try runInstallScript(command: "installer -pkg \"\(downloaded.path)\" -target /", tempDir: tempDir)
            }

            progress.close()
            NSApp.terminate(nil)
        } catch {
            progress.close()
            presentFailure(error, fallbackURL: releasesPageURLForFallback)
        }
    }

    // MARK: - Descarcare

    private static func download(from url: URL, to destination: URL) async throws {
        let (tempLocation, response): (URL, URLResponse)
        do {
            (tempLocation, response) = try await URLSession.shared.download(from: url)
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateError.downloadFailed("HTTP \(code)")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempLocation, to: destination)
    }

    // MARK: - Arhivă .zip

    private static func extractApp(fromZip zip: URL, into tempDir: URL, expectedVersion: String) throws -> URL {
        let dest = tempDir.appendingPathComponent("extracted", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, dest.path]
        do {
            try ditto.run()
        } catch {
            throw UpdateError.archiveInvalid(error.localizedDescription)
        }
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw UpdateError.archiveInvalid("dezarhivarea a eșuat (cod \(ditto.terminationStatus))")
        }

        let items = (try? FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)) ?? []
        guard let app = items.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.archiveInvalid("nu conține aplicația")
        }
        // O arhivă rămasă în urmă pe server ar reinstala versiunea veche, iar
        // pop-up-ul de update ar reapărea la nesfârșit.
        let found = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard found == expectedVersion else {
            throw UpdateError.archiveInvalid("conține versiunea \(found ?? "necunoscută"), nu \(expectedVersion)")
        }
        return app
    }

    /// Înlocuiește aplicația acolo unde rulează, dacă e într-un folder
    /// Aplicații; altfel (ex. pornită din Downloads) o pune în /Applications.
    private static func installTarget(for newApp: URL) -> URL {
        let current = Bundle.main.bundleURL
        let parent = current.deletingLastPathComponent().path
        if parent == "/Applications" || parent == NSHomeDirectory() + "/Applications" {
            return current
        }
        return URL(fileURLWithPath: "/Applications").appendingPathComponent(newApp.lastPathComponent)
    }

    // MARK: - Instalare

    private static func runInstallScript(command: String, tempDir: URL) throws {
        let logPath = tempDir.appendingPathComponent("gdcfirewall_update.log")
        let scriptPath = tempDir.appendingPathComponent("gdcfirewall_update.sh")

        let scriptContent = """
        #!/bin/bash
        exec > "\(logPath.path)" 2>&1
        sleep 2
        echo "Instalez actualizarea..."
        \(command)
        status=$?
        if [ $status -ne 0 ]; then
            echo "Instalarea a esuat (cod $status)."
            exit $status
        fi
        echo "Pornesc aplicatia actualizata..."
        open -b "\(Bundle.main.bundleIdentifier ?? "dev.gordas.GDCFirewall")"
        rm -rf "\(tempDir.path)"
        """
        do {
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        } catch {
            throw UpdateError.installScriptFailed(error.localizedDescription)
        }

        let escapedPath = scriptPath.path.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escapedPath)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        do {
            try process.run()
        } catch {
            throw UpdateError.installScriptFailed(error.localizedDescription)
        }
    }

    // MARK: - Eroare

    private static let releasesPageURLForFallback = URL(string: "https://gordas.dev/gdc-firewall/")!

    @MainActor
    private static func presentFailure(_ error: Error, fallbackURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Actualizarea a eșuat"
        alert.informativeText = "\(error.localizedDescription)\n\nPoți descărca manual ultima versiune de pe gordas.dev."
        alert.addButton(withTitle: "Deschide pagina")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(fallbackURL)
        }
    }
}

/// Fereastra minimala de progres (AppKit) — text + spinner indeterminat.
@MainActor
final class UpdateProgressWindow {
    private let window: NSWindow
    private let statusLabel: NSTextField
    private let spinner: NSProgressIndicator

    init(version: String) {
        let contentRect = NSRect(x: 0, y: 0, width: 360, height: 110)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Actualizare"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let container = NSView(frame: contentRect)

        let titleLabel = NSTextField(labelWithString: "GDC Firewall \(version)")
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 20, y: 70, width: 320, height: 20)
        container.addSubview(titleLabel)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.frame = NSRect(x: 20, y: 30, width: 320, height: 34)
        container.addSubview(statusLabel)

        spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 12, width: 320, height: 6))
        spinner.style = .bar
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        container.addSubview(spinner)

        window.contentView = container
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func close() {
        spinner.stopAnimation(nil)
        window.close()
    }
}
