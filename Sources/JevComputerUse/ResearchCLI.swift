import Foundation
import EventKit

@MainActor enum ResearchCLI {
    static func run(_ args:[String]) async throws {
        func option(_ name:String) -> String? { guard let i = args.firstIndex(of:name), args.indices.contains(i+1) else { return nil }; return args[i+1] }
        func require(_ name:String) throws -> String { guard let value = option(name) else { throw Failure("Missing \(name)") }; return value }
        let directory = URL(fileURLWithPath:option("--out") ?? FileManager.default.currentDirectoryPath+"/jev-research-"+UUID().uuidString).standardizedFileURL.path
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let control = RunControl(); control.onStatus = { fputs($0+"\n",stderr) }
        switch args[0] {
        case "research":
            let urls = args.indices.filter { args[$0] == "--source" && args.indices.contains($0+1) }.map { args[$0+1] }
            let runner = ResearchRunner(); let goal = try require("--goal")
            try control.recordEvents(in:directory); control.emit(.request(goal))
            let plan = try await runner.prepare(request:goal,calendar:args.contains("--calendar"),directory:directory,model:option("--codex-model"),control:control,urls:urls)
            struct Result:Codable { var status:String; var plan:String; var digest:String; var sourceCount:Int; var eventCount:Int; var unresolved:Int; var summary:String }
            try emit(Result(status:"plan_prepared",plan:directory+"/research-plan.json",digest:plan.digest,sourceCount:plan.sources.count,eventCount:plan.events.count,unresolved:plan.questions.count+plan.events.filter { !$0.clarification.isEmpty }.count,summary:plan.summary))
        case "calendar-list":
            let calendar = ResearchCalendar()
            if args.contains("--request-access") { try await calendar.requestAccess() }
            guard calendar.authorized else { throw Failure("캘린더 전체 접근이 없습니다. calendar-list --request-access로 승인 요청을 열 수 있습니다.") }
            if let name = option("--create-calendar") {
                guard name.hasPrefix("JEV Native Test ") else { throw Failure("검증용 캘린더 이름은 'JEV Native Test '로 시작해야 합니다.") }
                if !calendar.calendars().contains(where:{$0.title == name}) {
                    let created = EKCalendar(for:.event,eventStore:calendar.store); created.title = name
                    guard let source = calendar.store.sources.first(where:{$0.sourceType == .local}) ?? calendar.store.defaultCalendarForNewEvents?.source else { throw Failure("쓰기 가능한 캘린더 소스가 없습니다.") }
                    created.source = source; try calendar.store.saveCalendar(created,commit:true)
                }
            }
            struct Entry:Codable { var id:String; var title:String }
            try emit(calendar.calendars().map { Entry(id:$0.calendarIdentifier,title:$0.title) })
        case "calendar-test-reset":
            let calendar = ResearchCalendar(); guard calendar.authorized else { throw Failure("캘린더 접근이 없습니다.") }
            guard let cal = calendar.calendars().first(where:{$0.calendarIdentifier == (try? require("--calendar-id"))}), cal.title.hasPrefix("JEV Native Test "),
                  let event = calendar.store.event(withIdentifier:try require("--event-id")), event.calendar.calendarIdentifier == cal.calendarIdentifier,
                  (event.notes ?? "").contains("JEV Native event:") else { throw Failure("JEV가 생성한 전용 테스트 캘린더의 일정만 초기화할 수 있습니다.") }
            try calendar.store.remove(event,span:.thisEvent,commit:true)
            struct Result:Codable { var removedOwnedTestEvent:Bool }; try emit(Result(removedOwnedTestEvent:true))
        case "calendar-inspect":
            let calendar = ResearchCalendar(); guard calendar.authorized else { throw Failure("캘린더 접근이 없습니다.") }
            guard let cal = calendar.calendars().first(where:{$0.calendarIdentifier == (try? require("--calendar-id"))}),
                  let start = ISO8601DateFormatter().date(from:try require("--start")), let end = ISO8601DateFormatter().date(from:try require("--end")), end > start else { throw Failure("캘린더 ID와 ISO8601 조회 기간이 필요합니다.") }
            struct Entry:Codable { var identifier:String; var title:String; var start:String; var end:String; var allDay:Bool; var zone:String?; var location:String?; var url:String? }
            let events = calendar.store.events(matching:calendar.store.predicateForEvents(withStart:start,end:end,calendars:[cal]))
            try emit(events.map { Entry(identifier:$0.eventIdentifier,title:$0.title,start:ISO8601DateFormatter().string(from:$0.startDate),end:ISO8601DateFormatter().string(from:$0.endDate),allDay:$0.isAllDay,zone:$0.timeZone?.identifier,location:$0.location,url:$0.url?.absoluteString) })
        case "calendar-commit":
            let plan = try JSONDecoder().decode(ResearchPlan.self,from:Data(contentsOf:URL(fileURLWithPath:require("--plan"))))
            let calendar = ResearchCalendar()
            let receipt = try await calendar.save(plan,approvedDigest:require("--approve"),calendarID:require("--calendar-id"),directory:directory,control:control)
            try emit(receipt)
        default: throw Failure("Unknown research command")
        }
    }
}
