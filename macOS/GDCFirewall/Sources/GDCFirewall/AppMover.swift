import AppKit

/// Mută aplicația în `/Applications` la prima pornire din altă parte (ex.
/// Downloads, după dezarhivare) — echivalentul LetsMove, fără dependință
/// externă. Pentru GDC Firewall nu e o comoditate: macOS activează extensia
/// de rețea DOAR dintr-o aplicație aflată în `/Applications` (nici
/// `~/Applications` nu e acceptat), deci mutarea se face înainte de activare.
enum AppMover {
    private static let log = DiagnosticLog("appmover")
    private static let destination = URL(fileURLWithPath: "/Applications/GDC Firewall.app")

    /// Apelat o singură dată, la lansare, înaintea activării extensiei.
    static func promptIfNeeded() {
        let current = Bundle.main.bundleURL
        guard current.deletingLastPathComponent().path != "/Applications" else { return }
        guard !isRunningFromDevelopmentBuild(current) else { return }
        let original = originalLocation(of: current)
        log.info("Pornită din afara /Applications: \(original.path)" + (original == current ? "" : " (App Translocation)"))

        let alert = NSAlert()
        alert.messageText = L("Mută în folderul Aplicații?")
        alert.informativeText = L("GDC Firewall trebuie să ruleze din folderul Aplicații: macOS pornește filtrul de rețea doar de acolo. Aplicația se mută și repornește singură.")
        alert.addButton(withTitle: L("Mută în folderul Aplicații"))
        alert.addButton(withTitle: L("Nu acum"))
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            log.info("Mutarea a fost refuzată; filtrul nu poate porni din această locație")
            return
        }
        move(from: current, original: original)
    }

    private static func isRunningFromDevelopmentBuild(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/DerivedData/") || path.contains("/.build/") || path.contains("/Build/engine/")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func move(from source: URL, original: URL) {
        do {
            try install(source)
            let installed = Bundle(url: destination)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            guard installed == AppVersion.current else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: L("copia din /Applications are versiunea %@", installed ?? "?")])
            }
            log.info("Copiată în \(destination.path)")
            relaunchAfterExit()
            // Originalul la Coș (recuperabil). Dintr-o imagine disc sau o locație
            // protejată nu se poate — rămâne, fără alt efect.
            do {
                try FileManager.default.trashItem(at: original, resultingItemURL: nil)
                log.info("Originalul mutat la Coș: \(original.path)")
            } catch {
                log.warning("Originalul rămâne în \(original.path): \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        } catch {
            log.error("Mutarea în /Applications a eșuat: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = L("Mutare eșuată")
            alert.informativeText = L("Nu am putut muta aplicația automat (%@). Mut-o manual în /Applications din Finder.", error.localizedDescription)
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// Copie alături + înlocuire, ca o copie veche să nu dispară înainte ca cea
    /// nouă să fie completă. O copie veche deținută de root (instalată de
    /// actualizarea automată) cere parola de administrator.
    private static func install(_ source: URL) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".GDC Firewall.app.new")
        let existingWritable = !fm.fileExists(atPath: destination.path) || fm.isWritableFile(atPath: destination.path)
        if existingWritable, fm.isWritableFile(atPath: "/Applications") {
            try? fm.removeItem(at: staging)
            try fm.copyItem(at: source, to: staging)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staging, to: destination)
            return
        }
        log.info("Copia existentă nu poate fi înlocuită fără administrator")
        let q = { (url: URL) in "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let shell = "rm -rf \(q(staging)) && /usr/bin/ditto \(q(source)) \(q(staging)) && rm -rf \(q(destination)) && mv \(q(staging)) \(q(destination))"
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? L("acces refuzat") : message])
        }
    }

    /// `open` cât timp procesul ăsta încă rulează ar reactiva instanța curentă
    /// (același bundle ID) în loc să pornească copia nouă — așteptăm ieșirea.
    private static func relaunchAfterExit() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$1\"", "sh", destination.path]
        try? task.run()
    }

    /// Sub App Translocation (aplicație din carantină pornită din Downloads),
    /// macOS o rulează dintr-o copie temporară doar-citire; originalul — cel de
    /// dus la Coș — se află prin Security.framework (API fără header public,
    /// același pe care îl folosește LetsMove).
    private static func originalLocation(of url: URL) -> URL {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutableRawPointer?) -> DarwinBoolean
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutableRawPointer?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else { return url }
        defer { dlclose(handle) }
        guard let isSymbol = dlsym(handle, "SecTranslocateIsTranslocatedURL"),
              let originalSymbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return url }
        var translocated = false
        guard unsafeBitCast(isSymbol, to: IsTranslocated.self)(url as CFURL, &translocated, nil).boolValue, translocated,
              let original = unsafeBitCast(originalSymbol, to: OriginalPath.self)(url as CFURL, nil)?.takeRetainedValue()
        else { return url }
        return original as URL
    }
}
