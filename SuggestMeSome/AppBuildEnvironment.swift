import Foundation

enum AppBuildEnvironment {
    static var isLocalDevicePersonalTeam: Bool {
        #if LOCAL_DEVICE_PERSONAL_TEAM
        true
        #else
        false
        #endif
    }
}
