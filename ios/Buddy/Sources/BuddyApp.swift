import SwiftUI

@main
struct BuddyApp: App {
    init() {
        #if DEBUG
        GeistFontCheck.run()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let fixture = ScreenshotHarness.activeFixture {
                let cfg = ScreenshotHarness.makeStore(for: fixture)
                TodayView(store: cfg.store,
                          initialSheet: cfg.sheet,
                          forceMorning: cfg.forceMorning,
                          forceCelebration: cfg.celebrate)
            } else {
                TodayView()
            }
            #else
            TodayView()
            #endif
        }
    }
}
