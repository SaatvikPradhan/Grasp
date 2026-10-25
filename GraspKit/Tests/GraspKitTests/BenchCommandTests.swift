import Testing
@testable import GraspKit

struct BenchCommandTests {
    @Test func hearsShortCommands() {
        #expect(BenchCommand.ending("Done") == .next)
        #expect(BenchCommand.ending("okay, done.") == .next)
        #expect(BenchCommand.ending("Pouring into cup A, next step") == .next)
        #expect(BenchCommand.ending("Go back") == .back)
        #expect(BenchCommand.ending("Can you say that again?") == .again)
        #expect(BenchCommand.ending("Okay, we're done") == .finish)
        #expect(BenchCommand.ending("Stop recording") == .finish)
        #expect(BenchCommand.ending("stop") == .finish)
    }

    @Test func ignoresTalkThatJustHasTheWordInIt() {
        #expect(BenchCommand.ending("I'm not done yet") == nil)
        #expect(BenchCommand.ending("not done") == nil)
        #expect(BenchCommand.ending("the water is almost done cooling") == nil)
        #expect(BenchCommand.ending("we will pour the next one in a minute") == nil)
        #expect(BenchCommand.ending("make sure the kettle doesn't stop") == nil)
        #expect(BenchCommand.ending("") == nil)
    }

    @Test func ignoresGraspReadingAStepAloud() {
        #expect(BenchCommand.ending("Step 3 of 6. Pour the water into cup B and put the lid on. Next") == nil)
    }

    @Test func takesOnlyWhatWasSaidSinceThePause() {
        #expect(BenchCommand.newWords("Done", since: "") == "Done")
        #expect(BenchCommand.newWords("Done itself", since: "Done") == "itself")
        #expect(BenchCommand.newWords("Done. Done", since: "Done") == "Done")
        #expect(BenchCommand.newWords("Done.", since: "Done") == nil)
    }

    @Test func aRewriteOfTheSameEndingIsntSaidTwice() {
        // The recognizer rewrote "it" as "it's" after "go back" had already moved the run back.
        #expect(BenchCommand.newWords("simulating it it's go back", since: "simulating it go back") == nil)
        #expect(BenchCommand.newWords("pour it in done", since: "pour it done") == nil)
        // A rewrite with new words after it still counts.
        #expect(BenchCommand.newWords("pour it in done next step", since: "pour it done") == "in done next step")
    }
}
