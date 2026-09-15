import AppKit
import Foundation

/// Verifică `update.json` (găzduit pe gordas.dev, lângă pagina de
/// prezentare) contra versiunii instalate. NU e self-update silențios —
/// deschide link-ul de download, userul instalează manual peste versiunea
/// curentă (Regula 13 din Standardul GDC).
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let updateURL = URL(string: "https://gordas.dev/gdc-firewall/update.json")!
    private let dismissedKey = "GDCFirewall.dismissedUpdateVersion"

    /// Manifestul servit de gordas.dev.
    ///
    /// Produsul are DOUĂ componente care se învechesc independent: interfața
    /// GDC și motorul de filtrare. De aceea manifestul poartă două versiuni,
    /// nu una.
    ///
    /// `version` rămâne în fișier PENTRU TOTDEAUNA, chiar dacă `app_version`
    /// îl înlocuiește (Regula 35): orice client deja publicat care îl
    /// decodează ca obligatoriu ar eșua TĂCUT dacă dispare, și ar rămâne
    /// blocat pe „ești la zi” fără nicio cale de ieșire.
    private struct UpdateInfo: Decodable {
        let version: String?              // moștenit, sinonim cu app_version
        let appVersion: String?
        let engineVersionRequired: String?
        let changes: String?
        let downloadURL: [String: String]
        let mandatory: Bool

        enum CodingKeys: String, CodingKey {
            case version
            case appVersion = "app_version"
            case engineVersionRequired = "engine_version_required"
            case changes
            case downloadURL = "download_url"
            case mandatory
        }

        /// Versiunea interfeței, oricare dintre cele două chei ar purta-o.
        var effectiveAppVersion: String { appVersion ?? version ?? "0.0.0" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(String.self, forKey: .version)
            appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
            engineVersionRequired = try c.decodeIfPresent(String.self, forKey: .engineVersionRequired)
            changes = try c.decodeIfPresent(String.self, forKey: .changes)
            mandatory = try c.decodeIfPresent(Bool.self, forKey: .mandatory) ?? false

            // `download_url` a fost și string simplu, și dicționar per
            // platformă. Decodăm tolerant ambele forme: un manifest scris
            // altfel decât ne așteptam nu trebuie să blocheze actualizările.
            if let dict = try? c.decode([String: String].self, forKey: .downloadURL) {
                downloadURL = dict
            } else if let single = try? c.decode(String.self, forKey: .downloadURL) {
                downloadURL = ["mac": single]
            } else {
                downloadURL = [:]
            }
        }
    }

    /// De ce anume se oferă actualizarea. Determină textul pop-up-ului.
    private enum UpdateReason {
        case newInterface          // A — versiune nouă de interfață
        case engineUnsupported     // B — motorul local nu mai e susținut
    }

    /// BUG REAL găsit 2026-08-26: `fetch` întorcea `nil` la orice eșec
    /// (rețea, timeout, JSON invalid) — `checkManually()` trata `nil`
    /// IDENTIC cu "nu există versiune nouă", deci un simplu hiccup de
    /// rețea (sau propagare încă neterminată pe GitHub Pages/Fastly chiar
    /// după un push) făcea aplicația să mintă userul cu "Ești la zi", deși
    /// era deja live o versiune nouă. Fix: `fetch` întoarce acum
    /// `Result<UpdateInfo, Error>` — eșecul e arătat explicit ca eroare,
    /// niciodată deghizat în "la zi".
    private enum FetchError: Error, LocalizedError {
        case network(Error)
        case badStatus(Int)
        case decode(Error)

        var errorDescription: String? {
            switch self {
            case .network(let e): return e.localizedDescription
            case .badStatus(let code): return "Server a răspuns cu status \(code)."
            case .decode: return "Răspunsul primit nu e un update.json valid."
            }
        }
    }

    /// Actualizarea se oferă în DOUĂ cazuri independente (SAU, nu ȘI):
    ///
    ///   A. interfața locală e mai veche decât `app_version` de pe server;
    ///   B. motorul cu care e construită aplicația e sub
    ///      `engine_version_required` — adică rulează un filtru pe care
    ///      autorii lui nu-l mai susțin.
    ///
    /// Cazul B e cel care justifică toată structura: interfața poate fi
    /// perfect la zi în timp ce motorul de sub ea are o gaură cunoscută, iar
    /// un update checker care se uită doar la versiunea aplicației n-ar
    /// semnala niciodată asta.
    private func reason(for info: UpdateInfo) -> UpdateReason? {
        if let required = info.engineVersionRequired,
           Self.semVerCompare(required, LuLu.engineVersion) > 0 {
            // B are prioritate la afișare: e o problemă de securitate, nu
            // o noutate de interfață.
            return .engineUnsupported
        }
        if isNewer(info.effectiveAppVersion) { return .newInterface }
        return nil
    }

    func checkAtLaunch() {
        fetch { [weak self] result in
            guard let self, case .success(let info) = result else { return }
            guard let reason = self.reason(for: info) else { return }

            // Un motor nesusținut reapare la fiecare lansare, ca `mandatory`:
            // nu se poate închide o dată și uita, fiindcă protecția chiar e
            // degradată până la actualizare.
            if reason == .engineUnsupported || info.mandatory {
                self.presentPopup(info, reason: reason)
                return
            }
            let dismissed = UserDefaults.standard.string(forKey: self.dismissedKey)
            if dismissed != info.effectiveAppVersion {
                self.presentPopup(info, reason: reason)
            }
        }
    }

    func checkManually() {
        fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.presentCheckFailedAlert(error)
            case .success(let info):
                if let reason = self.reason(for: info) {
                    self.presentPopup(info, reason: reason)
                } else {
                    self.presentUpToDateAlert()
                }
            }
        }
    }

    private func fetch(completion: @escaping (Result<UpdateInfo, Error>) -> Void) {
        // Dublu cache-bypass: (1) query param unic per cerere — necesar
        // pentru CDN-urile din față (GitHub Pages/Fastly, Cloudflare) care
        // cache-uiesc pe URL complet; (2) cachePolicy explicit pe
        // URLRequest — necesar ca NICI URLCache-ul local (in-process) să nu
        // servească un răspuns anterior, indiferent de Cache-Control primit.
        var components = URLComponents(url: updateURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]

        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(FetchError.network(error))) }
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                DispatchQueue.main.async { completion(.failure(FetchError.badStatus(http.statusCode))) }
                return
            }
            guard let data else {
                DispatchQueue.main.async { completion(.failure(FetchError.badStatus(-1))) }
                return
            }
            do {
                let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
                DispatchQueue.main.async { completion(.success(info)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(FetchError.decode(error))) }
            }
        }.resume()
    }

    /// Comparare SemVer robustă, component cu component (Major.Minor.Patch)
    /// — înlocuiește `String.compare(_:options:.numeric)`, care se poate
    /// comporta imprevizibil dacă una din cele două valori are un prefix
    /// „v” și cealaltă nu (ex. „v1.5.0” vs „1.4.0”: primul caracter „v” vs
    /// „1” e comparat lexical, ÎNAINTE de orice comparație numerică).
    /// Ignoră explicit un eventual prefix „v”/„V”.
    private func isNewer(_ remote: String) -> Bool {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return Self.semVerCompare(remote, current) > 0
    }

    /// Întoarce 1 dacă `a` > `b`, -1 dacă `a` < `b`, 0 dacă egale.
    /// Componente lipsă/nenumerice se tratează ca 0 — niciodată crash.
    static func semVerCompare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            var s = s
            if s.lowercased().hasPrefix("v") { s.removeFirst() }
            return s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va != vb { return va > vb ? 1 : -1 }
        }
        return 0
    }

    /// BUG FIX 2026-08-27 (CLAUDE.md Partea 1, Regula 20): butonul
    /// "Actualizează acum" deschidea `.pkg`-ul în browser (fișier descărcat,
    /// dar userul tot vedea un tab de download) — acum descarcă+instalează
    /// direct, prin SelfUpdater, fără NICIODATĂ să atingă un browser.
    private func presentPopup(_ info: UpdateInfo, reason: UpdateReason) {
        let alert = NSAlert()

        switch reason {
        case .newInterface:
            alert.messageText = "Versiune nouă disponibilă: \(info.effectiveAppVersion)"
            alert.informativeText = (info.changes ?? "")
                + "\n\nApasă „Actualizează acum” pentru a descărca și instala automat."
        case .engineUnsupported:
            alert.alertStyle = .critical
            alert.messageText = "Actualizare critică de securitate"
            // Mesajul apare în limba sistemului, nu în română forțat: cine
            // rulează un motor de filtrare nesusținut trebuie să înțeleagă
            // avertismentul, chiar dacă nu citește română.
            alert.informativeText = L10n.engineUpdateRequired()
                + "\n\nMotor instalat: \(LuLu.engineVersion)"
                + " · minim susținut: \(info.engineVersionRequired ?? "—")"
        }

        alert.addButton(withTitle: "Actualizează acum")
        // „Mai târziu” dispare la un motor nesusținut și la update obligatoriu:
        // butonul ar sugera că amânarea e o opțiune fără consecințe.
        if !info.mandatory && reason != .engineUnsupported {
            alert.addButton(withTitle: "Mai târziu")
        }

        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let urlString = info.downloadURL["mac"], let url = URL(string: urlString) {
            Task { await SelfUpdater.downloadAndInstall(pkgURL: url, version: info.effectiveAppVersion) }
        } else {
            UserDefaults.standard.set(info.effectiveAppVersion, forKey: dismissedKey)
        }
    }

    private func presentUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "Ești la zi"
        alert.informativeText = "Rulezi cea mai recentă versiune."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Distinct explicit de "Ești la zi" — un eșec de rețea/parsing NU
    /// înseamnă că nu există versiune nouă, doar că n-am putut verifica.
    private func presentCheckFailedAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Nu am putut verifica actualizări"
        alert.informativeText = "\(error.localizedDescription)\n\nVerifică-ți conexiunea la internet și încearcă din nou, sau vizitează direct gordas.dev/gdc-firewall."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
