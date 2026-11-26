import Foundation

/// Pure policy determining which inactive root tabs should shed their retained card grids
/// when tvOS emits a memory warning (critical on 4 GB `.standard` Apple TV models).
public enum TabMemoryEvictionPolicy: Sendable {
    public static let memoryHeavyTabs: Set<MainNavigationTab> = [
        .home, .movies, .series, .library, .search
    ]

    public static func inactiveTabsToUnload(
        activeTab: MainNavigationTab,
        isHighMemoryDevice: Bool = DeviceHardwareCapabilities.isHighMemoryDevice,
        forceOnMemoryWarning: Bool = true
    ) -> Set<MainNavigationTab> {
        guard forceOnMemoryWarning || !isHighMemoryDevice else {
            return []
        }
        return memoryHeavyTabs.subtracting([activeTab])
    }
}
