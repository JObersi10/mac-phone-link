// PhoneLinkApp — the runnable macOS app entry point. Hosts the SwiftUI scene
// from PhoneLinkUI. Kept as its own executable target so the libraries stay
// headless-buildable while this produces the .app binary.
//
// SPDX-License-Identifier: MIT

#if canImport(SwiftUI)
import SwiftUI
import PhoneLinkUI

@main
struct PhoneLinkApp: App {
    @StateObject private var viewModel = ConnectionViewModel()

    var body: some Scene {
        WindowGroup("Phone Link") {
            PhoneLinkRootView(viewModel: viewModel)
                .frame(minWidth: 360, minHeight: 420)
        }
    }
}
#endif
