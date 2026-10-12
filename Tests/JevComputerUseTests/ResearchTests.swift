import XCTest
@testable import JevComputerUse

final class ResearchTests:XCTestCase {
    private func source() -> WebSource { .init(id:"S1",url:"https://example.org/event",title:"Official event",text:"Test Conference. May 13 - May 19, 2026. Long Beach Convention Center.",fetchedAt:Date(timeIntervalSince1970:1_700_000_000),sha256:"owned") }
    private func event() -> ResearchEvent { .init(title:"Test Conference",start:"2026-05-13",end:"2026-05-20",timeZone:"America/Los_Angeles",allDay:true,location:"Long Beach Convention Center",sourceID:"S1",quotes:["Test Conference.","May 13 - May 19, 2026.","Long Beach Convention Center."],clarification:"") }
    private func plan() -> ResearchPlan { .init(request:"owned test",summary:"Found [S1]",sources:[source()],events:[event()],questions:[],calendarRequested:true) }
    func testPublicSourcesRejectLocalCredentialedAndNonWebURLs() throws {
        for value in ["file:///etc/passwd","http://localhost/","http://127.0.0.1/","http://169.254.169.254/","http://[::1]/","http://machine.local/","https://user:secret@example.org/","https://example.org:22/"] { XCTAssertThrowsError(try ResearchValidation.publicURL(value),value) }
        XCTAssertEqual(try ResearchValidation.publicURL("https://us.pycon.org/2026/").host,"us.pycon.org")
    }
    func testHTMLExcludesScriptsAndRetainsStructuredEventEvidence() {
        let html = "<style>hidden style</style><script>malicious instructions</script><script type='application/ld+json'>{\"startDate\":\"2026-05-13\"}</script><p>Event &amp; place</p>"
        let text = PublicWeb.plain(html)
        XCTAssertFalse(text.contains("malicious")); XCTAssertFalse(text.contains("hidden style")); XCTAssertTrue(text.contains("2026-05-13")); XCTAssertTrue(text.contains("Event & place"))
    }
    func testFetchedTextLimitDoesNotSplitSwiftCharacters() { XCTAssertLessThanOrEqual(PublicWeb.plain(String(repeating:"🐸",count:30000)).count,24000) }
    func testPlanDigestSurvivesSerializationAndDetectsEveryMutation() throws {
        let first = plan(); let data = try jsonData(first); let decoded = try JSONDecoder().decode(ResearchPlan.self,from:data)
        XCTAssertEqual(first.digest,decoded.digest); XCTAssertEqual(first.digest,first.digest)
        var edited = first; edited.events[0].start = "2026-05-14"; XCTAssertNotEqual(first.digest,edited.digest)
        edited = first; edited.sources[0].text += " changed"; XCTAssertNotEqual(first.digest,edited.digest)
    }
    func testNoCalendarWritePlanWithoutEventsOrWithQuestions() {
        var p = plan(); XCTAssertNoThrow(try ResearchValidation.validate(p))
        p.events = []; XCTAssertThrowsError(try ResearchValidation.validate(p))
        p = plan(); p.questions = ["Which year?"]; XCTAssertThrowsError(try ResearchValidation.validate(p))
        p = plan(); p.calendarRequested = false; XCTAssertThrowsError(try ResearchValidation.validate(p))
    }
    func testUnresolvedDateRequiresUserInput() {
        var e = event(); e.clarification = "Which time?"; XCTAssertNotNil(ResearchValidation.eventIssue(e,sources:[source()]))
        e.clarification = ""; e.start = ""; XCTAssertNotNil(ResearchValidation.eventIssue(e,sources:[source()]))
    }
    func testMissingOrFabricatedSourceQuotesBlockRegistration() {
        var e = event(); e.sourceID = "S99"; XCTAssertNotNil(ResearchValidation.eventIssue(e,sources:[source()]))
        e = event(); e.quotes = ["Invented venue"]; XCTAssertNotNil(ResearchValidation.eventIssue(e,sources:[source()]))
        e = event(); e.quotes = []; XCTAssertNotNil(ResearchValidation.eventIssue(e,sources:[source()]))
    }
    func testUnicodeAndWhitespaceNormalizationPreservesEvidence() {
        XCTAssertEqual(ResearchValidation.normalized("e\u{301}  \n🐸"),"é 🐸")
    }
    func testAllDayDatesRejectInvalidCalendarDaysAndNeedZone() {
        XCTAssertNil(ResearchValidation.date("2026-02-30",allDay:true,zone:"Asia/Seoul"))
        XCTAssertNil(ResearchValidation.date("2026-5-13",allDay:true,zone:"Asia/Seoul"))
        XCTAssertNil(ResearchValidation.date("2026-05-13",allDay:true,zone:"Unknown/Zone"))
        XCTAssertNotNil(ResearchValidation.date("2026-05-13",allDay:true,zone:"Asia/Seoul"))
    }
    func testTimedDatesRequireExplicitOffsetAndPositiveInterval() {
        var e = event(); e.allDay = false; e.start = "2026-05-13T09:00:00+09:00"; e.end = "2026-05-13T10:00:00+09:00"; e.timeZone = "Asia/Seoul"
        XCTAssertNil(ResearchValidation.eventIssue(e,sources:[source()]))
        e.end = e.start; XCTAssertNotNil(ResearchValidation.eventIssue(e,sources:[source()]))
        XCTAssertNil(ResearchValidation.date("2026-05-13T09:00:00",allDay:false,zone:"Asia/Seoul"))
    }
    func testExcessiveAndReversedEventRangesStopBeforeSaving() {
        var e = event(); e.end = "2026-05-12"; XCTAssertNotNil(ResearchValidation.eventIssue(e,sources:[source()]))
        e.end = "2028-05-20"; XCTAssertNotNil(ResearchValidation.eventIssue(e,sources:[source()]))
    }
    func testSetupDoesNotConfuseCredentialConfigurationAndActualConnection() {
        var s = SetupState(); s.codexInstalled = true; s.codexAuthenticated = true; s.permissions = ["accessibility":true,"screenRecording":true,"inputPosting":true]; s.keyConfigured = true
        XCTAssertFalse(s.ready); s.keyVerified = true; XCTAssertTrue(s.ready); s.codexAuthenticated = false; XCTAssertFalse(s.ready)
    }
    @MainActor func testApprovalMismatchFailsBeforeCalendarAccessOrWrite() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        do { _ = try await ResearchCalendar().save(plan(),approvedDigest:"wrong",calendarID:"unrelated",directory:dir,control:RunControl()); XCTFail("Must reject changed/unapproved plan") }
        catch { XCTAssertTrue(String(describing:error).contains("승인한 계획")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath:dir))
    }
    @MainActor func testQuestionCancellationAndPauseUseExistingRunControl() async throws {
        let c = RunControl(); c.stop(); do { try await c.checkpoint(); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    @MainActor func testNativeAllDayEndNormalizesInclusiveSecondWithoutChangingTimedEvents() {
        let exclusive = Date(timeIntervalSince1970:1_779_030_000)
        XCTAssertEqual(ResearchCalendar.exclusiveEnd(exclusive.addingTimeInterval(-1),allDay:true,expected:exclusive),exclusive)
        XCTAssertEqual(ResearchCalendar.exclusiveEnd(exclusive,allDay:true,expected:exclusive),exclusive)
        XCTAssertEqual(ResearchCalendar.exclusiveEnd(exclusive.addingTimeInterval(-1),allDay:false,expected:exclusive),exclusive.addingTimeInterval(-1))
        XCTAssertEqual(ResearchCalendar.exclusiveEnd(exclusive.addingTimeInterval(-86400),allDay:true,expected:exclusive),exclusive.addingTimeInterval(-86400))
    }
    func testLiteSearchUnwrapsAndValidatesOnlyRealResultLinks() {
        let html = "<a href='//duckduckgo.com/l/?uddg=https%3A%2F%2Fus.pycon.org%2F2026%2F&amp;rut=hash' class='result-link'>PyCon &amp; dates</a><a href='file:///etc/passwd' class='result-link'>bad</a>"
        let links = PublicWeb.liteResults(html); XCTAssertEqual(links.count,1); XCTAssertEqual(links[0].1,"https://us.pycon.org/2026/"); XCTAssertEqual(links[0].0,"PyCon & dates")
    }
    func testResearchCountsRemainUnknownUntilRunnerProvidesEvidence() {
        var state = RunPresentationState(); let id = UUID(); state.apply(.init(runID:id,sequence:0,fact:.request("research")))
        XCTAssertNil(state.research)
        state.apply(.init(runID:id,sequence:1,fact:.research(.init(sources:2,found:nil,ready:nil,registered:0))))
        XCTAssertEqual(state.research?.sources,2); XCTAssertNil(state.research?.found); XCTAssertEqual(state.research?.registered,0)
        state.apply(.init(runID:id,sequence:2,fact:.research(.init(sources:2,found:3,ready:2,registered:1))))
        XCTAssertEqual(state.research?.registered,1); XCTAssertEqual(state.research?.ready,2)
    }
    func testCalendarCommandsUseAppEventLoopForSystemConsent() {
        XCTAssertEqual(startupMode(["calendar-list","--request-access"]),.application)
        XCTAssertEqual(startupMode(["calendar-commit"]),.application)
        XCTAssertEqual(startupMode(["research"]),.cli)
    }
}
