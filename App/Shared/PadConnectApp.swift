import PadKit
import SwiftUI

@main
struct PadConnectApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.pad)
                .onAppear { model.requestHealthAccess() }
        }
        #if os(macOS)
        .defaultSize(width: 420, height: 640)
        #endif

        #if os(macOS)
        MenuBarExtra {
            MenuBarControls()
                .environmentObject(model)
                .environmentObject(model.pad)
        } label: {
            MenuBarLabel(pad: model.pad)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
