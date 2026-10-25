import Foundation
import Testing
@testable import GraspKit

struct PostgresTests {
    /// RFC 7677's example exchange: user "user", password "pencil".
    @Test func scramMatchesTheRFCExample() throws {
        var scram = SCRAM(password: "pencil", user: "user", nonce: "rOprNGfwEbeRWgbNEkqO")
        #expect(scram.clientFirst == "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
        let final = try scram.clientFinal(
            serverFirst: "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096")
        #expect(final == "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=")
        #expect(scram.verify(serverFinal: "v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4="))
        #expect(!scram.verify(serverFinal: "v=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="))
    }

    @Test func scramRefusesAChallengeWithAnotherNonce() {
        var scram = SCRAM(password: "pencil", nonce: "abc")
        #expect(throws: PostgresConnection.Failure.self) { try scram.clientFinal(serverFirst: "r=xyz123,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096") }
    }

    @Test func readsATigerConnectionString() throws {
        let address = try #require(PostgresAddress("postgres://tsdbadmin:p%40ss@abc123.tsdb.cloud.timescale.com:34567/tsdb?sslmode=require"))
        #expect(address.user == "tsdbadmin")
        #expect(address.password == "p@ss")
        #expect(address.host == "abc123.tsdb.cloud.timescale.com")
        #expect(address.port == 34567)
        #expect(address.database == "tsdb")
        #expect(address.requiresTLS)
        #expect(!address.verifiesCertificate)   // Tiger's own authority isn't one macOS trusts
        #expect(PostgresAddress("u:p@db.example.com:5432/app?sslmode=verify-full")?.verifiesCertificate == true)
        // Without the scheme, as Secrets.xcconfig needs it (it reads // as a comment).
        #expect(PostgresAddress("tsdbadmin:secret@abc.example.com:5432/tsdb")?.host == "abc.example.com")
        #expect(PostgresAddress("postgres:pw@localhost:5432/postgres?sslmode=disable")?.requiresTLS == false)
        #expect(PostgresAddress("not a url") == nil)
    }

    @Test func buildsMessagesTheServerExpects() {
        #expect(Message.sslRequest == Data([0, 0, 0, 8, 0x04, 0xD2, 0x16, 0x2F]))
        #expect(Message.query("SELECT 1") == Data([UInt8(ascii: "Q"), 0, 0, 0, 13]) + Data("SELECT 1".utf8) + Data([0]))
        let startup = Message.startup(user: "u", database: "d")
        #expect(Int(Message.int32([UInt8](startup), at: 0)) == startup.count)
    }

    @Test func readsRowsAndErrors() {
        // Two columns: "42" and NULL.
        let row: [UInt8] = [0, 2, 0, 0, 0, 2, UInt8(ascii: "4"), UInt8(ascii: "2"), 0xFF, 0xFF, 0xFF, 0xFF]
        #expect(Message.dataRow(row) == ["42", nil])
        func field(_ code: Character, _ text: String) -> [UInt8] { [code.asciiValue!] + Array(text.utf8) + [0] }
        var error: [UInt8] = field("S", "ERROR")
        error += field("C", "42P01")
        error += field("M", "relation \"x\" does not exist")
        error.append(0)
        #expect(Message.errorText(error) == "relation \"x\" does not exist (42P01)")
    }
}

struct TigerRecordsTests {
    @Test func quotesTextSafely() {
        #expect(SQL.text("Jordan's bill") == "'Jordan''s bill'")
        #expect(SQL.text("'); DROP TABLE grasp_pages; --") == "'''); DROP TABLE grasp_pages; --'")
        #expect(SQL.text(nil) == "NULL")
        #expect(SQL.number(.nan) == "NULL")
    }

    @Test func insertsReadingsInOneStatement() throws {
        let run = UUID()
        let sql = try #require(TigerRecords.readings([
            .init(time: Date(timeIntervalSince1970: 1_000), cup: .a, celsius: 71.5),
            .init(time: Date(timeIntervalSince1970: 1_001), cup: .b, celsius: 70.25),
        ], run: run, simulated: true))
        #expect(sql.hasPrefix("INSERT INTO grasp_readings"))
        #expect(sql.contains("to_timestamp(1000.000)"))
        #expect(sql.contains("'A', 71.5, true"))
        #expect(TigerRecords.readings([], run: run, simulated: false) == nil)
    }

    @Test func makesTheReadingsAHypertableWhenItCan() {
        #expect(TigerRecords.setup.contains("create_hypertable('grasp_readings'"))
        #expect(TigerRecords.setup.contains("EXCEPTION WHEN undefined_function"))
    }
}

/// Runs against a real database when `TIGER_SERVICE` (user:password@host:port/database) is set.
struct LiveTigerTests {
    static let address = ProcessInfo.processInfo.environment["TIGER_SERVICE"].flatMap(PostgresAddress.init)

    @Test(.enabled(if: LiveTigerTests.address != nil)) func storesAndReadsBackReadings() async throws {
        let connection = PostgresConnection(LiveTigerTests.address!)
        try await connection.connect()
        try await connection.query(TigerRecords.setup)
        let run = UUID()
        let now = Date()
        try await connection.query(try #require(TigerRecords.readings([
            .init(time: now, cup: .a, celsius: 80.5), .init(time: now, cup: .b, celsius: 79.25),
        ], run: run, simulated: true)))
        let rows = try await connection.query("SELECT cup, celsius FROM grasp_readings WHERE run_id = \(SQL.uuid(run)) ORDER BY cup")
        #expect(rows == [["A", "80.5"], ["B", "79.25"]])
        let hypertable = try await connection.query("SELECT count(*) FROM timescaledb_information.hypertables WHERE hypertable_name = 'grasp_readings'")
        print("TIGER hypertable rows: \(hypertable)")
        try await connection.query("DELETE FROM grasp_readings WHERE run_id = \(SQL.uuid(run))")
        connection.close()
    }
}
