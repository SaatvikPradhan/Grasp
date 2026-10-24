import GraspKit
import SwiftUI

@main
struct GraspPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Placeholder until gate G2, when this becomes the camera that streams to the Mac.
struct ContentView: View {
    private let pitch = LoanTerms.demoContract

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye")
                .font(.system(size: 56, weight: .semibold))
            Text("Grasp")
                .font(.largeTitle.bold())
            Text("The camera link to the Mac arrives at gate G2.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("GraspKit check: \(pitch.monthlyPayment, format: .currency(code: "USD")) a month for \(pitch.termMonths) months")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

#Preview {
    ContentView()
}
