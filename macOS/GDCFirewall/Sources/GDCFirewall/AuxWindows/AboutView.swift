import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("GDC Firewall")
                .font(.title2.weight(.semibold))

            Text(L("Versiunea %@", version))
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text("© 2026 Cristi Gordaș / GDC")
                    .font(.caption)
                // Atribuirea Objective-See e o obligație a licenței GPL-3.0
                // sub care e publicat motorul — nu se scoate niciodată din
                // acest ecran, indiferent de redesign.
                Text(L("Motor de filtrare: LuLu © Objective-See\nDistribuit sub licența GPL-3.0"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Link("gordas.dev/gdc-firewall", destination: URL(string: "https://gordas.dev/gdc-firewall")!)
                .font(.caption)
        }
        .padding(28)
        .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity)
    }
}
