import SwiftUI

@main
struct LectureScanApp: App {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CameraScreen(camera: camera)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        camera.start()
                    case .inactive, .background:
                        camera.stop()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
