import CloudKit
import SwiftUI
import NXModel

struct TonTonCloudStatus: View {
    @EnvironmentObject var loc: Localizer
    @State private var account: CKAccountStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(loc.t("tonton.icloud"), systemImage: "icloud")
                .font(.headline)
            Text(loc.t(account == .available ? "tonton.icloudReady" : "tonton.icloudChecking"))
            Text(loc.t("tonton.icloudNote")).font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .task {
            guard let name = Bundle.main.object(forInfoDictionaryKey: "DMCloudSaveContainer") as? String else { return }
            account = try? await CKContainer(identifier: name).accountStatus()
        }
    }
}
