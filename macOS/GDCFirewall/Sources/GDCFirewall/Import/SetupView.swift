import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Prima configurare: alte firewall-uri găsite pe Mac, importul regulilor lor
/// și locul exact de unde utilizatorul le oprește. Două filtre active cer
/// permisiune de două ori pentru aceeași conexiune.
struct SetupView: View {
    @ObservedObject private var bridge = DaemonBridge.shared
    @State private var firewalls: [ForeignFirewall] = []
    @State private var loading = true
    @State private var results: [String: String] = [:]
    @State private var busy: String?
    @State private var expanded: Set<String> = []
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Configurare inițială"))
                .font(.title2.bold())
            Text(L("Două firewall-uri active pe același Mac îți cer permisiune de două ori pentru aceeași conexiune. Poți prelua regulile lor în GDC Firewall, apoi să le oprești."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if loading {
                        ProgressView(L("Caut alte firewall-uri…"))
                    } else if firewalls.isEmpty {
                        Label(L("Nu am găsit alte firewall-uri pe acest Mac."), systemImage: "checkmark.shield")
                    } else {
                        ForEach(firewalls) { card($0) }
                        Text(L("macOS nu permite unei aplicații să oprească firewall-ul altui producător — pasul acesta îl faci tu, din aplicația lui."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !bridge.isConnected && !firewalls.isEmpty {
                Label(L("Importul devine disponibil după ce motorul GDC e conectat."), systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.footnote)
            }

            HStack {
                Spacer()
                Button(L("Gata"), action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
        .task {
            firewalls = await Task.detached { ForeignFirewalls.detect() }.value
            loading = false
        }
    }

    private func card(_ firewall: ForeignFirewall) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: firewall.isFiltering ? "shield.lefthalf.filled" : "shield")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(firewall.name).font(.headline)
                    Text(firewall.statusText).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(L("Importă regulile")) { importRules(from: firewall) }
                if firewall.kind == .littleSnitch {
                    Button(L("Din fișier…")) { importFromFile(firewall) }
                        .help(L("Un fișier .lsrules sau un export JSON salvat din Little Snitch"))
                }
                if firewall.kind == .littleSnitch || firewall.extensionState != nil {
                    Button(L("Cum îl opresc")) {
                        if expanded.contains(firewall.id) { expanded.remove(firewall.id) } else { expanded.insert(firewall.id) }
                    }
                }
                if busy == firewall.id {
                    ProgressView().controlSize(.small)
                }
            }
            .disabled(busy != nil || !bridge.isConnected)

            if let result = results[firewall.id] {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if expanded.contains(firewall.id) {
                Text(firewall.disableInstructions)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let url = firewall.appURL {
                        Button(L("Deschide %@", firewall.name)) { NSWorkspace.shared.open(url) }
                    }
                    Button(L("Deschide Setări → Rețea")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Acțiuni

    private func importRules(from firewall: ForeignFirewall) {
        let existing = bridge.ruleSignatures
        run(firewall) {
            switch firewall.kind {
            case .lulu:
                return try RuleImporter.importLuLu(existing: existing)
            case .littleSnitch:
                guard let app = firewall.appURL else {
                    throw RuleImporter.ImportError.exportFailed(L("aplicația Little Snitch nu e instalată — folosește „Din fișier…”"))
                }
                let data = try RuleImporter.exportLittleSnitchModel(appURL: app)
                return try RuleImporter.importLittleSnitch(data: data, existing: existing)
            }
        }
    }

    private func importFromFile(_ firewall: ForeignFirewall) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json] + [UTType(filenameExtension: "lsrules")].compactMap { $0 }
        panel.message = L("Alege regulile exportate din Little Snitch (.lsrules sau JSON)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let existing = bridge.ruleSignatures
        run(firewall) {
            try RuleImporter.importLittleSnitch(data: Data(contentsOf: url), existing: existing)
        }
    }

    /// Exportul Little Snitch așteaptă parola de administrator, iar citirea
    /// regulilor LuLu atinge discul — ambele în afara firului principal.
    private func run(_ firewall: ForeignFirewall, _ work: @escaping () throws -> ImportReport) {
        busy = firewall.id
        results[firewall.id] = nil
        Task {
            let outcome = await Task.detached { Result { try work() } }.value
            busy = nil
            switch outcome {
            case .success(let report):
                bridge.addImportedRules(report.rules)
                results[firewall.id] = report.summary
            case .failure(let error):
                results[firewall.id] = error.localizedDescription
            }
        }
    }
}

/// `@MainActor`: `Task {}` pornit de aici revine pe firul principal după
/// `await`, deci fereastra se creează acolo unde AppKit o acceptă.
@MainActor
enum FirstRunSetup {
    static let completedKey = "setupCompleted"

    /// O singură dată, și doar dacă e ceva de configurat: fără alte
    /// firewall-uri, fereastra n-ar avea nimic de spus.
    static func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: FirstRunSetup.completedKey) else { return }
        Task {
            let found = await Task.detached { ForeignFirewalls.detect() }.value
            if found.isEmpty {
                UserDefaults.standard.set(true, forKey: FirstRunSetup.completedKey)
            } else {
                AuxWindowPresenter.showSetup()
            }
        }
    }
}

extension AuxWindowPresenter {
    static func showSetup() {
        present(id: "setup", title: L("Configurare GDC Firewall"), size: NSSize(width: 580, height: 540)) {
            SetupView {
                UserDefaults.standard.set(true, forKey: FirstRunSetup.completedKey)
                close(id: "setup")
            }
        }
    }
}
