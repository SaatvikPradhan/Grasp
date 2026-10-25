import Foundation

/// A short spoken command at the bench, heard by the listener that's always on while lab notes
/// run, so no fist or Space is needed when hands are wet or full. Only how a phrase ends counts,
/// so "I'm not done yet" isn't "done", and Grasp's own "Step 3 of 6…" is never a command.
public enum BenchCommand: Equatable, Sendable {
    case next, back, again, finish

    /// The command a finished phrase ends with, if any.
    public static func ending(_ phrase: String) -> BenchCommand? {
        let words = phrase.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
        guard !words.isEmpty else { return nil }
        let joined = words.joined(separator: " ")
        // Grasp reading a step aloud, heard back through the mic.
        if joined.range(of: #"step \w+ of \w+"#, options: .regularExpression) != nil { return nil }
        let tail = words.suffix(4).joined(separator: " ")
        for (phrase, command) in phrases where tail == phrase || tail.hasSuffix(" " + phrase) {
            // One word on its own ("done", "stop") counts only as a short phrase, and never after a "not".
            if !phrase.contains(" ") {
                guard words.count <= 3, !words.dropLast().contains(where: negations.contains) else { return nil }
            }
            return command
        }
        return nil
    }

    /// What was said since `before` (the recognizer's text at the last pause), or nil when it only
    /// rewrote what it had already heard. New speech adds to the end; a rewrite changes words
    /// earlier on, so the same ending heard again isn't a second command.
    public static func newWords(_ now: String, since before: String) -> String? {
        let old = before.split(separator: " "), new = now.split(separator: " ")
        let key = { (word: Substring) in word.lowercased().filter { $0.isLetter || $0.isNumber } }
        var same = 0
        while same < old.count, same < new.count, key(old[same]) == key(new[same]) { same += 1 }
        guard same < new.count else { return nil }
        if same < old.count, let last = old.last, let newLast = new.last, key(last) == key(newLast) { return nil }
        return new.dropFirst(same).joined(separator: " ")
    }

    /// Longest first, so "we're done" finishes rather than moving on.
    private static let phrases: [(String, BenchCommand)] = [
        ("stop the experiment", .finish), ("finish the experiment", .finish), ("end the experiment", .finish),
        ("stop recording", .finish), ("we're done", .finish), ("we are done", .finish), ("all done", .finish),
        ("say that again", .again), ("repeat that", .again), ("one more time", .again),
        ("previous step", .back), ("go back", .back), ("step back", .back),
        ("next step", .next), ("step done", .next), ("that's done", .next), ("i'm done", .next),
        ("finish", .finish), ("stop", .finish), ("repeat", .again), ("done", .next), ("next", .next),
    ]

    private static let negations: Set<String> = ["not", "isn't", "aren't", "never", "almost", "nearly", "don't", "can't"]
}
