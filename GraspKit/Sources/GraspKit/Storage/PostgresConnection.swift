import CommonCrypto
import CryptoKit
import Foundation

/// Where a Postgres database is: Tiger Cloud gives a connection string like
/// `postgres://tsdbadmin:PASSWORD@abc123.tsdb.cloud.timescale.com:34567/tsdb?sslmode=require`.
public struct PostgresAddress: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var database: String
    public var user: String
    public var password: String
    /// Tiger Cloud requires TLS; a local test database may not offer it.
    public var requiresTLS = true

    public init(host: String, port: Int = 5432, database: String, user: String, password: String, requiresTLS: Bool = true) {
        self.host = host
        self.port = port
        self.database = database
        self.user = user
        self.password = password
        self.requiresTLS = requiresTLS
    }

    /// Reads `user:password@host:port/database`, with or without `postgres://` in front and
    /// `?sslmode=…` after. `sslmode=disable` turns TLS off.
    public init?(_ string: String) {
        var rest = string.trimmingCharacters(in: .whitespaces)
        for scheme in ["postgresql://", "postgres://"] where rest.hasPrefix(scheme) { rest.removeFirst(scheme.count) }
        var options = ""
        if let question = rest.firstIndex(of: "?") {
            options = String(rest[rest.index(after: question)...])
            rest = String(rest[..<question])
        }
        guard let at = rest.lastIndex(of: "@") else { return nil }
        let credentials = rest[..<at], location = rest[rest.index(after: at)...]
        guard let colon = credentials.firstIndex(of: ":"), let slash = location.firstIndex(of: "/") else { return nil }
        user = String(credentials[..<colon]).removingPercentEncoding ?? String(credentials[..<colon])
        let secret = String(credentials[credentials.index(after: colon)...])
        password = secret.removingPercentEncoding ?? secret
        let hostPort = location[..<slash]
        database = String(location[location.index(after: slash)...])
        if let portColon = hostPort.lastIndex(of: ":"), let number = Int(hostPort[hostPort.index(after: portColon)...]) {
            host = String(hostPort[..<portColon])
            port = number
        } else {
            host = String(hostPort)
            port = 5432
        }
        requiresTLS = !options.contains("sslmode=disable")
        guard !host.isEmpty, !database.isEmpty, !user.isEmpty else { return nil }
    }
}

/// A small Postgres client: TLS, SCRAM-SHA-256 (or plain password) sign-in, and the simple query
/// protocol, which is all Grasp needs to keep sessions and readings in Tiger Data. No packages.
/// Every call runs on its own serial queue, since the socket blocks.
public final class PostgresConnection: @unchecked Sendable {
    public enum Failure: LocalizedError {
        case connect(String)
        case tlsRefused
        case auth(String)
        case server(String)
        case protocolError(String)

        public var errorDescription: String? {
            switch self {
            case .connect(let message): "Couldn't reach the database: \(message)"
            case .tlsRefused: "The database doesn't accept TLS."
            case .auth(let message): "The database didn't accept the sign-in: \(message)"
            case .server(let message): "Database error: \(message)"
            case .protocolError(let message): "Unexpected reply from the database: \(message)"
            }
        }
    }

    private let address: PostgresAddress
    private let queue = DispatchQueue(label: "grasp.postgres")
    private var input: InputStream?
    private var output: OutputStream?

    public init(_ address: PostgresAddress) {
        self.address = address
    }

    deinit {
        input?.close()
        output?.close()
    }

    /// Connects and signs in.
    public func connect() async throws {
        try await run { try self.open() }
    }

    /// Runs SQL (several statements may be separated by semicolons) and returns the rows of the
    /// last result, each value as text or nil for NULL.
    @discardableResult
    public func query(_ sql: String) async throws -> [[String?]] {
        try await run { try self.simpleQuery(sql) }
    }

    public func close() {
        queue.async {
            try? self.send(Message.terminate)
            self.input?.close()
            self.output?.close()
            self.input = nil
            self.output = nil
        }
    }

    private func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    // MARK: Socket

    private func open() throws {
        var read: Unmanaged<CFReadStream>?
        var write: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, address.host as CFString, UInt32(address.port), &read, &write)
        guard let input = read?.takeRetainedValue() as InputStream?, let output = write?.takeRetainedValue() as OutputStream? else {
            throw Failure.connect("no socket")
        }
        self.input = input
        self.output = output
        input.open()
        output.open()
        try waitUntilOpen()

        if address.requiresTLS {
            try send(Message.sslRequest)
            guard try readBytes(1).first == UInt8(ascii: "S") else { throw Failure.tlsRefused }
            // Start TLS on the open socket, checking the certificate against the host name.
            let settings = [kCFStreamSSLPeerName as String: address.host] as CFDictionary
            input.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
            output.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
            CFReadStreamSetProperty(input as CFReadStream, CFStreamPropertyKey(kCFStreamPropertySSLSettings), settings)
            CFWriteStreamSetProperty(output as CFWriteStream, CFStreamPropertyKey(kCFStreamPropertySSLSettings), settings)
        }

        try send(Message.startup(user: address.user, database: address.database))
        try signIn()
    }

    private func waitUntilOpen() throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let error = input?.streamError ?? output?.streamError { throw Failure.connect(error.localizedDescription) }
            if input?.streamStatus == .open, output?.streamStatus == .open { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw Failure.connect("timed out")
    }

    private func send(_ data: Data) throws {
        guard let output else { throw Failure.connect("not connected") }
        var sent = 0
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            while sent < data.count {
                let written = output.write(bytes.baseAddress! + sent, maxLength: data.count - sent)
                guard written > 0 else { throw Failure.connect(output.streamError?.localizedDescription ?? "the connection closed") }
                sent += written
            }
        }
    }

    private func readBytes(_ count: Int) throws -> [UInt8] {
        guard let input else { throw Failure.connect("not connected") }
        var bytes = [UInt8](repeating: 0, count: count)
        var got = 0
        while got < count {
            let read = bytes.withUnsafeMutableBufferPointer { input.read($0.baseAddress! + got, maxLength: count - got) }
            guard read > 0 else { throw Failure.connect(input.streamError?.localizedDescription ?? "the connection closed") }
            got += read
        }
        return bytes
    }

    /// One message from the server: its type and body.
    private func receive() throws -> (type: UInt8, body: [UInt8]) {
        let header = try readBytes(5)
        let length = Int(Message.int32(header, at: 1))
        return (header[0], length > 4 ? try readBytes(length - 4) : [])
    }

    // MARK: Sign-in

    private func signIn() throws {
        var scram: SCRAM?
        while true {
            let (type, body) = try receive()
            switch type {
            case UInt8(ascii: "R"):
                switch Message.int32(body, at: 0) {
                case 0:
                    break   // signed in
                case 3:
                    try send(Message.password(address.password))
                case 10:
                    let mechanisms = Message.strings(Array(body.dropFirst(4)))
                    guard mechanisms.contains("SCRAM-SHA-256") else { throw Failure.auth("no SCRAM-SHA-256 offered (\(mechanisms))") }
                    let client = SCRAM(password: address.password)
                    scram = client
                    try send(Message.saslInitial(mechanism: "SCRAM-SHA-256", response: client.clientFirst))
                case 11:
                    guard scram != nil else { throw Failure.protocolError("SASL continue before start") }
                    let final = try scram!.clientFinal(serverFirst: String(decoding: body.dropFirst(4), as: UTF8.self))
                    try send(Message.saslResponse(final))
                case 12:
                    guard let client = scram, client.verify(serverFinal: String(decoding: body.dropFirst(4), as: UTF8.self)) else {
                        throw Failure.auth("the server's signature didn't check out")
                    }
                case let other:
                    throw Failure.auth("unsupported method \(other)")
                }
            case UInt8(ascii: "E"):
                throw Failure.auth(Message.errorText(body))
            case UInt8(ascii: "Z"):
                return
            default:
                continue   // parameter status, backend key, notices
            }
        }
    }

    // MARK: Queries

    private func simpleQuery(_ sql: String) throws -> [[String?]] {
        try send(Message.query(sql))
        var rows: [[String?]] = []
        var failure: String?
        while true {
            let (type, body) = try receive()
            switch type {
            case UInt8(ascii: "T"):
                rows = []   // a new result set
            case UInt8(ascii: "D"):
                rows.append(Message.dataRow(body))
            case UInt8(ascii: "E"):
                failure = Message.errorText(body)
            case UInt8(ascii: "Z"):
                if let failure { throw Failure.server(failure) }
                return rows
            default:
                continue   // command complete, notices, empty query
            }
        }
    }
}

/// Postgres wire messages, built and read as bytes.
enum Message {
    static let sslRequest = int32Bytes(8) + int32Bytes(80_877_103)
    static let terminate = Data([UInt8(ascii: "X")]) + int32Bytes(4)

    static func startup(user: String, database: String) -> Data {
        var body = int32Bytes(196_608)   // protocol 3.0
        for (key, value) in [("user", user), ("database", database), ("application_name", "Grasp")] {
            body += cString(key) + cString(value)
        }
        body.append(0)
        return int32Bytes(Int32(body.count + 4)) + body
    }

    static func password(_ password: String) -> Data { tagged("p", cString(password)) }

    static func saslInitial(mechanism: String, response: String) -> Data {
        let bytes = Data(response.utf8)
        return tagged("p", cString(mechanism) + int32Bytes(Int32(bytes.count)) + bytes)
    }

    static func saslResponse(_ response: String) -> Data { tagged("p", Data(response.utf8)) }

    static func query(_ sql: String) -> Data { tagged("Q", cString(sql)) }

    static func tagged(_ type: Character, _ body: Data) -> Data {
        Data([type.asciiValue!]) + int32Bytes(Int32(body.count + 4)) + body
    }

    static func cString(_ string: String) -> Data {
        Data(string.utf8.filter { $0 != 0 }) + Data([0])
    }

    static func int32Bytes(_ value: Int32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    static func int32(_ bytes: [UInt8], at offset: Int) -> Int32 {
        guard bytes.count >= offset + 4 else { return 0 }
        return bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int32($1) }
    }

    static func int16(_ bytes: [UInt8], at offset: Int) -> Int {
        guard bytes.count >= offset + 2 else { return 0 }
        return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    }

    /// Null-terminated strings, as in the list of SASL mechanisms.
    static func strings(_ bytes: [UInt8]) -> [String] {
        bytes.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    }

    static func dataRow(_ body: [UInt8]) -> [String?] {
        let columns = int16(body, at: 0)
        var offset = 2
        var values: [String?] = []
        for _ in 0..<columns {
            let length = Int(int32(body, at: offset))
            offset += 4
            if length < 0 {
                values.append(nil)
            } else {
                values.append(String(decoding: body[offset..<min(offset + length, body.count)], as: UTF8.self))
                offset += length
            }
        }
        return values
    }

    /// An error response's message and SQLSTATE code.
    static func errorText(_ body: [UInt8]) -> String {
        var fields: [UInt8: String] = [:]
        var offset = 0
        while offset < body.count, body[offset] != 0 {
            let code = body[offset]
            let end = body[(offset + 1)...].firstIndex(of: 0) ?? body.count
            fields[code] = String(decoding: body[(offset + 1)..<end], as: UTF8.self)
            offset = end + 1
        }
        return [fields[UInt8(ascii: "M")], fields[UInt8(ascii: "C")].map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
    }
}

/// SCRAM-SHA-256 sign-in (RFC 5802, RFC 7677), without channel binding.
struct SCRAM {
    let password: String
    /// Postgres takes the user name from the startup message, so it's left empty there.
    let user: String
    let clientNonce: String
    private(set) var saltedPassword: [UInt8] = []
    private(set) var authMessage = ""

    init(password: String, user: String = "", nonce: String? = nil) {
        self.password = password
        self.user = user
        clientNonce = nonce ?? Data((0..<18).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
    }

    var clientFirstBare: String { "n=\(user),r=\(clientNonce)" }
    var clientFirst: String { "n,," + clientFirstBare }

    /// Answers the server's challenge with the proof, keeping what `verify` needs.
    mutating func clientFinal(serverFirst: String) throws -> String {
        let fields = Dictionary(serverFirst.split(separator: ",").compactMap { part -> (String, String)? in
            guard let equals = part.firstIndex(of: "=") else { return nil }
            return (String(part[..<equals]), String(part[part.index(after: equals)...]))
        }, uniquingKeysWith: { first, _ in first })
        guard let nonce = fields["r"], nonce.hasPrefix(clientNonce), let saltText = fields["s"],
              let salt = Data(base64Encoded: saltText), let rounds = fields["i"].flatMap(Int.init) else {
            throw PostgresConnection.Failure.auth("bad SCRAM challenge")
        }
        saltedPassword = Self.pbkdf2(password: password, salt: [UInt8](salt), rounds: rounds)
        let withoutProof = "c=biws,r=\(nonce)"
        authMessage = "\(clientFirstBare),\(serverFirst),\(withoutProof)"
        let clientKey = Self.hmac(saltedPassword, "Client Key")
        let storedKey = [UInt8](SHA256.hash(data: clientKey))
        let proof = zip(clientKey, Self.hmac(storedKey, authMessage)).map { $0 ^ $1 }
        return "\(withoutProof),p=\(Data(proof).base64EncodedString())"
    }

    /// Checks the server proved it knows the password too.
    func verify(serverFinal: String) -> Bool {
        guard !saltedPassword.isEmpty, serverFinal.hasPrefix("v="),
              let expected = Data(base64Encoded: String(serverFinal.dropFirst(2))) else { return false }
        return Data(Self.hmac(Self.hmac(saltedPassword, "Server Key"), authMessage)) == expected
    }

    static func hmac(_ key: [UInt8], _ message: String) -> [UInt8] {
        [UInt8](HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key)))
    }

    static func pbkdf2(password: String, salt: [UInt8], rounds: Int) -> [UInt8] {
        var derived = [UInt8](repeating: 0, count: 32)
        let passwordBytes = Array(password.utf8).map { Int8(bitPattern: $0) }
        _ = derived.withUnsafeMutableBytes { output in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes, passwordBytes.count, salt, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
                                 output.bindMemory(to: UInt8.self).baseAddress, 32)
        }
        return derived
    }
}
