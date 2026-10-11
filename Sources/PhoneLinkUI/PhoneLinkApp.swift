// PhoneLinkApp — SwiftUI app scene for the macOS client. This lives in the UI
// library without `@main` so the package stays a library (reliable to build in
// CI). To ship a runnable app, add a thin executable target whose only file is:
//
//     import PhoneLinkUI
//     @main struct Main: App { var body: some Scene { PhoneLinkScene(viewModel: ConnectionViewModel()).body } }
//
// (or mark PhoneLinkScene `@main` directly in that target).
//
// SPDX-License-Identifier: MIT

#if canImport(SwiftUI)
import SwiftUI

public struct PhoneLinkScene: Scene {
    @StateObject private var viewModel: ConnectionViewModel

    @MainActor
    public init(viewModel: ConnectionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some Scene {
        WindowGroup("Phone Link") {
            PhoneLinkRootView(viewModel: viewModel)
        }
    }
}
#endif
