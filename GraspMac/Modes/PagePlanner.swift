import GraspKit
import Observation

/// What to do about every page with money on it, worked out as soon as it's read: how it compares
/// with what's typical right now (from the web, with sources), the steps that fix what's wrong with
/// it, and what that comes to. ⌘⇧A or "what should I do about this?" runs it again.
@MainActor @Observable
final class PagePlanner {
    private(set) var isPlanning = false

    @ObservationIgnored private let canvas: CanvasModel

    init(canvas: CanvasModel) {
        self.canvas = canvas
    }

    /// Every page read comes here; pages with money get a plan.
    func pageRead(_ document: PageDocument) {
        guard document.video == nil, ActionPlanner.isWorthPlanning(document.reading) else { return }
        Task { await plan(document) }
    }

    /// Plans the page in focus. Returns a line for the voice bar.
    @discardableResult
    func planFocusedPage() async -> String {
        guard let document = canvas.focusedDocument else { return "Hand Grasp a page first" }
        return await plan(document)
    }

    @discardableResult
    private func plan(_ document: PageDocument) async -> String {
        guard let client = GeminiClient.fromAppKeys else { return GeminiClient.Failure.missingKey.localizedDescription }
        let subject = DeepDiveSubject(topic: document.reading.title, source: document.reading.kind, context: document.reading.summary)
        isPlanning = true
        defer { isPlanning = false }
        do {
            let plan = try await ActionPlanner(client: client).plan(document.reading)
            canvas.showPlan(DeepDiveCard(documentID: document.id, subject: subject, dive: plan, isPlan: true))
            return "\(plan.steps.count) things to do"
        } catch {
            return "Couldn't work out what to do: \(error.localizedDescription)"
        }
    }
}
