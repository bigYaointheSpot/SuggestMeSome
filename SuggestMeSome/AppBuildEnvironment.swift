import Foundation

enum AppBuildEnvironment {
    static var isLocalDevicePersonalTeam: Bool {
        #if LOCAL_DEVICE_PERSONAL_TEAM
        true
        #else
        false
        #endif
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static var isV1LocalAppStoreRelease: Bool {
        !isDebugBuild && !isLocalDevicePersonalTeam
    }

    static var enablesProductionCloudFeatures: Bool {
        !isLocalDevicePersonalTeam && !isV1LocalAppStoreRelease
    }
}
