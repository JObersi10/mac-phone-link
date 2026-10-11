// PermissionsManager — requests the macOS privacy permissions the client needs
// during onboarding (notifications, local network) and publishes their state.
//
// SPDX-License-Identifier: MIT

import Foundation
import Combine
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(Network)
import Network
#endif

public enum PermissionStatus: Equatable {
    case unknown, requested, granted, denied
}

@MainActor
public final class PermissionsManager: ObservableObject {
    @Published public private(set) var notifications: PermissionStatus = .unknown
    @Published public private(set) var localNetwork: PermissionStatus = .unknown

    #if canImport(Network)
    private var browser: NWBrowser?
    #endif

    public init() {}

    /// Ask for user-notification authorization (alert/sound/badge).
    public func requestNotifications() async {
        #if canImport(UserNotifications)
        notifications = .requested
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notifications = granted ? .granted : .denied
        } catch {
            notifications = .denied
        }
        #else
        notifications = .denied
        #endif
    }

    /// Trigger the macOS local-network prompt by starting a Bonjour browse.
    public func requestLocalNetwork() {
        #if canImport(Network)
        localNetwork = .requested
        let browser = NWBrowser(for: .bonjour(type: "_maclink._tcp", domain: nil),
                                using: NWParameters())
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.localNetwork = .granted
                case .failed, .cancelled: self?.localNetwork = .denied
                default: break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        #else
        localNetwork = .denied
        #endif
    }
}
