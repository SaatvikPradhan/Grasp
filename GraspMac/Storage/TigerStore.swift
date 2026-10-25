import Foundation
import GraspKit
import Observation

/// Keeps what Grasp reads and works out in Tiger Data: every page, answer, checked note, deep dive
/// and lab notebook, and the probe readings every few seconds into a TimescaleDB hypertable.
/// Off without `TIGER_SERVICE` in Config/Secrets.xcconfig; the canvas works the same either way.
@MainActor @Observable
final class TigerStore {
    enum Status: Equatable {
        case off
        case connecting
        case saving(rows: Int)
        case failed(String)
    }

    private(set) var status = Status.off

    @ObservationIgnored private let probes: ProbeHub
    @ObservationIgnored private var connection: PostgresConnection?
    @ObservationIgnored private var pending: [TigerRecords.Reading] = []
    @ObservationIgnored private var lastSaved: [Cup: Double] = [:]
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var rows = 0
    /// Readings from this launch share a run id, so one run can be pulled back out.
    @ObservationIgnored private let run = UUID()

    init(probes: ProbeHub) {
        self.probes = probes
    }

    /// Connects, makes the tables, and starts saving readings.
    func start() async {
        // Snapshot runs are checks: they don't write test pages and simulated readings into your data.
        guard ProcessInfo.processInfo.environment["GRASP_SNAPSHOT"] == nil else { return }
        guard connection == nil, let address = APIKeys.tigerService else { return }
        status = .connecting
        let connection = PostgresConnection(address)
        do {
            try await connection.connect()
            try await connection.query(TigerRecords.setup)
            self.connection = connection
            status = .saving(rows: rows)
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await self?.collectReadings()
                }
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Saving

    func save(page: PageDocument) {
        write(TigerRecords.page(id: page.id, readAt: page.readAt, reading: page.reading))
    }

    func save(answer: AnswerCard, pageID: UUID?) {
        write(TigerRecords.answer(at: Date(), pageID: pageID, question: answer.question, answer: answer.answer,
                                  sources: answer.sources.map(\.quote)))
    }

    func save(_ kind: Card.Kind, pageID: UUID?) {
        switch kind {
        case .answer(let answer):
            save(answer: answer, pageID: pageID)
        case .notes(let notes):
            TigerRecords.notes(at: Date(), pageID: notes.paperID, linked: notes.linked).map(write)
        case .deepDive(let card):
            guard let dive = card.dive else { return }
            write(TigerRecords.deepDive(at: Date(), pageID: card.documentID, topic: card.subject.topic, dive: dive))
        case .notebook(let card):
            write(TigerRecords.labSession(id: UUID(), at: card.date, notebook: card.notebook,
                                          markdown: card.notebook.markdown(date: card.date, frames: card.frames.count, rehearsal: card.isRehearsal)))
        default:
            break
        }
    }

    /// Every new reading, batched: a cup's reading goes in when it's newer than the last one saved.
    private func collectReadings() async {
        let uptime = ProcessInfo.processInfo.systemUptime
        for (cup, reading) in probes.latest where reading.time > (lastSaved[cup] ?? 0) && !probes.isStale(cup) {
            lastSaved[cup] = reading.time
            pending.append(.init(time: Date().addingTimeInterval(reading.time - uptime), cup: cup, celsius: reading.celsius))
        }
        guard pending.count >= 15 else { return }
        let batch = pending
        pending = []
        TigerRecords.readings(batch, run: run, simulated: probes.isSimulated).map { write($0, rows: batch.count) }
    }

    private func write(_ sql: String) { write(sql, rows: 1) }

    private func write(_ sql: String, rows added: Int) {
        guard let connection else { return }
        Task {
            do {
                try await connection.query(sql)
                rows += added
                status = .saving(rows: rows)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}
