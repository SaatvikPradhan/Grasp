import Foundation

/// What Grasp keeps in Tiger Data, as SQL: every page read, every answer, checked note and deep
/// dive, lab notebooks, and the probe readings in a TimescaleDB hypertable, so past runs can be
/// queried by time.
public enum TigerRecords {
    /// Creates the tables once; safe to run every launch. The readings table becomes a hypertable
    /// where TimescaleDB is installed (as on Tiger Cloud) and stays a plain table elsewhere.
    public static let setup = """
        SET standard_conforming_strings = on;
        CREATE TABLE IF NOT EXISTS grasp_pages (
            id uuid PRIMARY KEY, read_at timestamptz NOT NULL, kind text, title text, summary text,
            facts jsonb, catches jsonb, mistakes int);
        CREATE TABLE IF NOT EXISTS grasp_answers (
            asked_at timestamptz NOT NULL, page_id uuid, question text, answer text, numbers_checked boolean, sources jsonb);
        CREATE TABLE IF NOT EXISTS grasp_notes (
            written_at timestamptz NOT NULL, page_id uuid, note text, status text, page_says text);
        CREATE TABLE IF NOT EXISTS grasp_deep_dives (
            asked_at timestamptz NOT NULL, page_id uuid, topic text, findings jsonb, bottom_line text, sources jsonb);
        CREATE TABLE IF NOT EXISTS grasp_lab_sessions (
            id uuid PRIMARY KEY, saved_at timestamptz NOT NULL, title text, summary text, minutes double precision, notebook text);
        CREATE TABLE IF NOT EXISTS grasp_readings (
            time timestamptz NOT NULL, run_id uuid NOT NULL, cup text NOT NULL, celsius double precision NOT NULL, simulated boolean);
        DO $$ BEGIN
            PERFORM create_hypertable('grasp_readings', by_range('time'), if_not_exists => TRUE);
        EXCEPTION WHEN undefined_function OR undefined_object THEN NULL;
        END $$;
        """

    public static func page(id: UUID, readAt: Date, reading: PageReading) -> String {
        let facts = reading.facts.map { ["label": $0.label, "value": $0.asPrinted, "quote": $0.quote] }
        let catches = reading.allCatches.map { ["title": $0.title, "explanation": $0.explanation, "quote": $0.quote] }
        return """
            INSERT INTO grasp_pages (id, read_at, kind, title, summary, facts, catches, mistakes) VALUES (\
            \(SQL.uuid(id)), \(SQL.time(readAt)), \(SQL.text(reading.kind)), \(SQL.text(reading.title)), \(SQL.text(reading.summary)), \
            \(SQL.json(facts)), \(SQL.json(catches)), \(reading.mismatches.count)) ON CONFLICT (id) DO NOTHING
            """
    }

    public static func answer(at: Date, pageID: UUID?, question: String, answer: GroundedAnswer, sources: [String]) -> String {
        """
        INSERT INTO grasp_answers (asked_at, page_id, question, answer, numbers_checked, sources) VALUES (\
        \(SQL.time(at)), \(SQL.uuid(pageID)), \(SQL.text(question)), \(SQL.text(answer.answer)), \(answer.numbersChecked), \(SQL.json(sources)))
        """
    }

    public static func notes(at: Date, pageID: UUID, linked: LinkedNotes) -> String? {
        guard !linked.notes.isEmpty else { return nil }
        let rows = linked.notes.map { note in
            "(\(SQL.time(at)), \(SQL.uuid(pageID)), \(SQL.text(note.note)), \(SQL.text(note.status.rawValue)), \(SQL.text(note.paperSays)))"
        }
        return "INSERT INTO grasp_notes (written_at, page_id, note, status, page_says) VALUES " + rows.joined(separator: ", ")
    }

    public static func deepDive(at: Date, pageID: UUID?, topic: String, dive: DeepDive) -> String {
        let findings = dive.findings.map { ["text": $0.text, "sources": $0.sources.map { $0 + 1 }] as [String: Any] }
        let sources = dive.sources.map { ["site": $0.site, "url": $0.url.absoluteString] }
        return """
            INSERT INTO grasp_deep_dives (asked_at, page_id, topic, findings, bottom_line, sources) VALUES (\
            \(SQL.time(at)), \(SQL.uuid(pageID)), \(SQL.text(topic)), \(SQL.json(findings)), \(SQL.text(dive.bottomLine)), \(SQL.json(sources)))
            """
    }

    public static func labSession(id: UUID, at: Date, notebook: LabNotebook, markdown: String) -> String {
        """
        INSERT INTO grasp_lab_sessions (id, saved_at, title, summary, minutes, notebook) VALUES (\
        \(SQL.uuid(id)), \(SQL.time(at)), \(SQL.text(notebook.title)), \(SQL.text(notebook.summary)), \
        \(SQL.number(notebook.duration / 60)), \(SQL.text(markdown))) ON CONFLICT (id) DO NOTHING
        """
    }

    /// One reading of one cup.
    public struct Reading: Equatable, Sendable {
        public var time: Date
        public var cup: Cup
        public var celsius: Double

        public init(time: Date, cup: Cup, celsius: Double) {
            self.time = time
            self.cup = cup
            self.celsius = celsius
        }
    }

    /// Many readings in one insert.
    public static func readings(_ readings: [Reading], run: UUID, simulated: Bool) -> String? {
        guard !readings.isEmpty else { return nil }
        let rows = readings.map { "(\(SQL.time($0.time)), \(SQL.uuid(run)), \(SQL.text($0.cup.rawValue)), \(SQL.number($0.celsius)), \(simulated))" }
        return "INSERT INTO grasp_readings (time, run_id, cup, celsius, simulated) VALUES " + rows.joined(separator: ", ")
    }

    /// Each cup's average per minute over the last hour: the kind of question a hypertable is for.
    public static let lastHourByMinute = """
        SELECT time_bucket('1 minute', time) AS minute, cup, round(avg(celsius)::numeric, 1)
        FROM grasp_readings WHERE time > now() - interval '1 hour' GROUP BY minute, cup ORDER BY minute, cup
        """
}

/// SQL literals, quoted safely for the simple query protocol.
public enum SQL {
    public static func text(_ value: String?) -> String {
        guard let value else { return "NULL" }
        return "'" + value.replacingOccurrences(of: "\0", with: "").replacingOccurrences(of: "'", with: "''") + "'"
    }

    public static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "NULL" }
        return String(value)
    }

    public static func uuid(_ value: UUID?) -> String {
        value.map { "'\($0.uuidString)'::uuid" } ?? "NULL"
    }

    public static func time(_ date: Date) -> String {
        "to_timestamp(\(String(format: "%.3f", date.timeIntervalSince1970)))"
    }

    public static func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else { return "NULL" }
        return text(String(decoding: data, as: UTF8.self)) + "::jsonb"
    }
}
