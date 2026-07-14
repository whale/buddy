import SwiftUI

@main
struct BuddyApp: App {
    init() {
        #if DEBUG
        GeistFontCheck.run()
        #endif
        // Must register before the app finishes launching (Apple requirement).
        BackgroundSync.register()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let fixture = ScreenshotHarness.activeFixture {
                let cfg = ScreenshotHarness.makeStore(for: fixture)
                TodayView(store: cfg.store,
                          initialSheet: cfg.sheet,
                          forceMorning: cfg.forceMorning,
                          forceCelebration: cfg.celebrate,
                          initialEditingId: fixture == "editing" ? "m1" : nil)
            } else {
                TodayView()
            }
            #else
            TodayView()
            #endif
        }
    }
}
