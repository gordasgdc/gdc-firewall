import AppKit
import Darwin

/// Mută aplicația în `/Applications/GDC Firewall.app` la pornirea din orice alt
/// loc (Downloads, alt nume, `~/Applications`) — echivalentul LetsMove, fără
/// dependință externă. Pentru GDC Firewall nu e o comoditate: macOS activează
/// extensia de rețea DOAR dintr-o aplicație aflată în `/Applications`.
///
/// App Translocation (verificat empiric, 2026-09-18, macOS 26): o aplicație
/// cu bitul 0x0080 în `com.apple.quarantine` (pus de browser: `0083`, `0081`)
/// rulează dintr-o copie izolată doar-citire, ORIUNDE s-ar afla — și după o
/// copiere cu FileManager, și după o mutare prin Finder/AppleScript. Fără bitul
/// ăsta (`0003`, `0043`) rulează pe loc. Copia din `/Applications` primește
/// deci atributul fără bitul de izolare: carantina rămâne (Gatekeeper o
/// verifică în continuare), dispare doar izolarea — ce face Finder la o
/// mutare făcută de utilizator. Fără pasul ăsta, copia din `/Applications`
/// pornea tot izolată, cerea mutarea din nou, iar a doua mutare ducea
/// aplicația instalată la Coș (reprodus în 2.3.2).
enum AppMover {
    private static let log = DiagnosticLog("appmover")
    static let destination = URL(fileURLWithPath: "/Applications/GDC Firewall.app")
    private static let quarantineKey = "com.apple.quarantine"
    private static let translocateFlag: UInt32 = 0x0080

    /// Apelat o singură dată, la lansare, înaintea activării extensiei.
    static func promptIfNeeded() {
        let running = Bundle.main.bundleURL
        guard !isRunningFromDevelopmentBuild(running) else { return }
        let original = originalLocation(of: running)
        let translocated = original.standardizedFileURL != running.standardizedFileURL

        if isSameFile(original, destination) {
            guard translocated else { return }
            log.warning("Rulează izolată (App Translocation) din \(destination.path) — repar pe loc")
            repairInPlace()
            return
        }
        log.info("Pornită din afara /Applications: \(original.path)" + (translocated ? " (App Translocation)" : ""))
        guard askToMove() else {
            log.info("Mutarea a fost refuzată; filtrul nu poate porni din această locație")
            return
        }
        move(from: running, original: original)
    }

    // MARK: - Pași

    /// Aplicație de bara de meniu (LSUIElement): fără fereastră și fără Dock,
    /// un NSAlert la pornire poate rămâne în spatele altor ferestre — utilizatorul
    /// nu vede nimic. Pe durata întrebării aplicația devine una obișnuită.
    private static func askToMove() -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Mută în folderul Aplicații?")
        alert.informativeText = L("GDC Firewall trebuie să ruleze din folderul Aplicații: macOS pornește filtrul de rețea doar de acolo. Aplicația se mută și repornește singură.")
        alert.addButton(withTitle: L("Mută în folderul Aplicații"))
        alert.addButton(withTitle: L("Nu acum"))
        alert.alertStyle = .informational
        alert.window.level = .floating
        let accepted = alert.runModal() == .alertFirstButtonReturn
        if !accepted { NSApp.setActivationPolicy(.accessory) }
        return accepted
    }

    private static func move(from source: URL, original: URL) {
        do {
            terminateOtherInstances()
            try install(source)
            let installed = Bundle(url: destination)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            guard installed == AppVersion.current else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: L("copia din /Applications are versiunea %@", installed ?? "?")])
            }
            log.info("Copiată în \(destination.path)" + (quarantineFlags(destination).map { String(format: " (carantină %04x)", $0) } ?? ""))
            relaunchAfterExit()
            // Originalul la Coș (recuperabil) — niciodată copia tocmai instalată.
            if !isSameFile(original, destination) {
                do {
                    try FileManager.default.trashItem(at: original, resultingItemURL: nil)
                    log.info("Originalul mutat la Coș: \(original.path)")
                } catch {
                    log.warning("Originalul rămâne în \(original.path): \(error.localizedDescription)")
                }
            }
            NSApp.terminate(nil)
        } catch {
            fail(error)
        }
    }

    /// Deja în /Applications, dar izolată: doar atributul, apoi repornire.
    private static func repairInPlace() {
        do {
            if let value = quarantineWithoutTranslocation(at: destination) {
                if FileManager.default.isWritableFile(atPath: destination.path) {
                    try writeQuarantine(value, to: destination)
                } else {
                    try runAsAdmin("/usr/bin/xattr -w \(quarantineKey) \(shellQuote(value)) \(shellQuote(destination.path))")
                }
            }
            log.info("Izolarea scoasă; repornesc din \(destination.path)")
            relaunchAfterExit()
            NSApp.terminate(nil)
        } catch {
            fail(error)
        }
    }

    private static func fail(_ error: Error) {
        log.error("Mutarea în /Applications a eșuat: \(error.localizedDescription)")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Mutare eșuată")
        alert.informativeText = L("Nu am putut muta aplicația automat (%@). Mut-o manual în /Applications din Finder.", error.localizedDescription)
        alert.alertStyle = .warning
        alert.runModal()
        NSApp.setActivationPolicy(.accessory)
    }

    /// O instanță care rulează deja (ex. o versiune veche din /Applications)
    /// ar fi reactivată de `open` în locul copiei noi.
    private static func terminateOtherInstances() {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return }
        log.info("Închid instanțele care rulează deja: \(others.map { String($0.processIdentifier) }.joined(separator: ", "))")
        others.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while others.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    /// Copie alături + înlocuire, ca o copie veche să nu dispară înainte ca cea
    /// nouă să fie completă. O copie veche deținută de root (instalată de
    /// actualizarea automată) sau un /Applications fără drept de scriere cer
    /// parola de administrator.
    private static func install(_ source: URL) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".GDC Firewall.app.new")
        let quarantine = quarantineWithoutTranslocation(at: source)
        let existingWritable = !fm.fileExists(atPath: destination.path) || fm.isWritableFile(atPath: destination.path)
        if existingWritable, fm.isWritableFile(atPath: "/Applications") {
            try? fm.removeItem(at: staging)
            try fm.copyItem(at: source, to: staging)
            if let quarantine { try writeQuarantine(quarantine, to: staging) }
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staging, to: destination)
            return
        }
        log.info("Instalarea în /Applications cere drepturi de administrator")
        var steps = ["rm -rf \(shellQuote(staging.path))", "/usr/bin/ditto \(shellQuote(source.path)) \(shellQuote(staging.path))"]
        if let quarantine { steps.append("/usr/bin/xattr -w \(quarantineKey) \(shellQuote(quarantine)) \(shellQuote(staging.path))") }
        steps += ["rm -rf \(shellQuote(destination.path))", "mv \(shellQuote(staging.path)) \(shellQuote(destination.path))"]
        try runAsAdmin(steps.joined(separator: " && "))
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

    // MARK: - Locație

    private static func isRunningFromDevelopmentBuild(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/DerivedData/") || path.contains("/.build/") || path.contains("/Build/engine/")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Același fișier pe disc (nu doar același text de cale): prinde și
    /// `/System/Volumes/Data/Applications/…` sau o cale cu link simbolic.
    private static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let idA = try? a.resourceValues(forKeys: key).fileResourceIdentifier,
           let idB = try? b.resourceValues(forKeys: key).fileResourceIdentifier {
            return idA.isEqual(idB)
        }
        return a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Sub App Translocation, originalul (cel de mutat și de dus la Coș) se află
    /// prin Security.framework — API fără header public, același folosit de LetsMove.
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

    // MARK: - Carantină

    private static func readQuarantine(_ url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { path -> String? in
            guard let path else { return nil }
            let size = getxattr(path, quarantineKey, nil, 0, 0, XATTR_NOFOLLOW)
            guard size > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: size)
            guard getxattr(path, quarantineKey, &buffer, size, 0, XATTR_NOFOLLOW) == size else { return nil }
            return String(decoding: buffer, as: UTF8.self)
        }
    }

    private static func quarantineFlags(_ url: URL) -> UInt32? {
        readQuarantine(url).flatMap { $0.split(separator: ";").first }.flatMap { UInt32($0, radix: 16) }
    }

    /// Atributul fără bitul de izolare; nil dacă nu e carantină sau bitul lipsește.
    private static func quarantineWithoutTranslocation(at url: URL) -> String? {
        guard let value = readQuarantine(url), let flags = quarantineFlags(url), flags & translocateFlag != 0 else { return nil }
        let rest = value.split(separator: ";", omittingEmptySubsequences: false).dropFirst()
        return ([String(format: "%04x", flags & ~translocateFlag)] + rest.map(String.init)).joined(separator: ";")
    }

    private static func writeQuarantine(_ value: String, to url: URL) throws {
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            let bytes = Array(value.utf8)
            return setxattr(path, quarantineKey, bytes, bytes.count, 0, XATTR_NOFOLLOW)
        }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM) }
    }

    // MARK: - Administrator

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAsAdmin(_ shell: String) throws {
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
}
