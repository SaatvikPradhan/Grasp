import SwiftUI

@main
struct GraspPhoneApp: App {
    @State private var model = PhoneModel()

    var body: some Scene {
        WindowGroup {
            CameraView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}
