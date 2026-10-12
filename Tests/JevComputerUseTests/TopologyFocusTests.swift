import AppKit
import XCTest
@testable import JevComputerUse

final class TopologyFocusTests:XCTestCase {
    private func state(_ facts:[RunPresentationEvent.Fact]) -> RunPresentationState {
        var state = RunPresentationState(); let id = UUID()
        for (sequence,fact) in ([.request("owned")]+facts).enumerated() { state.apply(.init(runID:id,sequence:sequence,fact:fact)) }
        return state
    }
    func testCompletedIterationsFoldAndKeepFullEvidenceWhenExpanded() {
        let evidence = String(repeating:"근거 👨‍👩‍👧‍👦 e\u{301}\n",count:900)
        let state = state([.cycle(1),.observation("owned"),.action("read"),.source(evidence,"original"),.verification("checked"),.cycleEnd(1),.cycle(2),.observation("next")])
        var focus = TopologyFocus(); let live = focus.projection(state)
        XCTAssertEqual(live.summaries.map(\.expanded),[false,true]); XCTAssertEqual(live.shownCycle,2)
        XCTAssertEqual(live.summaries[0].recordIDs.count,4)
        focus.inspect(1); let inspected = focus.projection(state)
        XCTAssertEqual(inspected.shownCycle,1); XCTAssertFalse(focus.followsCurrent)
        XCTAssertEqual(inspected.records.first(where: { $0.kind == .source })?.text,evidence)
        XCTAssertNil(inspected.currentRecordID)
        XCTAssertEqual(inspected.records.map(\.id),live.summaries[0].recordIDs)
        focus.inspect(1); XCTAssertTrue(focus.followsCurrent); XCTAssertEqual(focus.projection(state).shownCycle,2)
    }
    func testNewEventsDoNotStealAnInspectedIterationAndFollowReturnsToLatest() {
        let initial = state([.cycle(1),.observation("old"),.cycleEnd(1),.cycle(2),.observation("current")])
        var focus = TopologyFocus(); focus.inspect(1)
        var next = initial
        next.apply(.init(runID:initial.runID!,sequence:initial.sequence+1,fact:.cycleEnd(2)))
        next.apply(.init(runID:initial.runID!,sequence:initial.sequence+2,fact:.cycle(3)))
        next.apply(.init(runID:initial.runID!,sequence:initial.sequence+3,fact:.action("latest action")))
        XCTAssertEqual(focus.projection(next).shownCycle,1)
        focus.follow(); XCTAssertEqual(focus.projection(next).shownCycle,3)
        XCTAssertEqual(focus.projection(next).records.last?.text,"latest action")
    }
    func testManualPanPinsCurrentIterationAcrossCompletion() {
        var focus = TopologyFocus(); focus.manual(1)
        let state = state([.cycle(1),.observation("old"),.cycleEnd(1),.cycle(2),.observation("new")])
        XCTAssertEqual(focus.projection(state).shownCycle,1)
        XCTAssertFalse(focus.followsCurrent)
    }
    func testFailureOutcomeClosesButDoesNotClaimSuccessfulIterations() {
        let state = state([.cycle(1),.observation("owned"),.recovery("rejected"),.outcome("cancelled")])
        let projection = TopologyFocus().projection(state)
        XCTAssertNil(projection.currentCycle); XCTAssertFalse(projection.summaries[0].expanded)
        XCTAssertTrue(projection.summaries[0].closed)
        XCTAssertEqual(projection.summaries[0].subtitle,"2단계 · 복구 근거 있음")
        XCTAssertEqual(projection.records.map(\.kind),[.outcome])
    }
    func testCameraAutoFitsZoomsAndFreezesExactly() {
        let viewport = CGRect(x:200,y:16,width:720,height:480)
        var camera = TopologyCamera()
        camera.fit(CGRect(x:0,y:0,width:218,height:144),in:viewport,snap:true)
        let closeScale = camera.scale
        camera.fit(CGRect(x:0,y:0,width:718,height:332),in:viewport)
        camera.frozen = true; let frozen = camera
        for _ in 0..<240 { camera.advance(1.0/60,reducedMotion:false) }
        XCTAssertEqual(camera,frozen)
        camera.frozen = false
        for _ in 0..<240 { camera.advance(1.0/60,reducedMotion:false) }
        XCTAssertFalse(camera.isMoving); XCTAssertLessThan(camera.scale,closeScale)
        XCTAssertEqual(camera.center.x,359,accuracy:0.001)
        XCTAssertTrue(viewport.contains(camera.screen(CGRect(x:0,y:0,width:718,height:332),in:viewport)))
        camera.fit(CGRect(x:750,y:376,width:218,height:144),in:viewport)
        camera.advance(0.016,reducedMotion:true)
        XCTAssertEqual(camera.center,CGPoint(x:859,y:448)); XCTAssertEqual(camera.scale,closeScale)
    }
    func testZoomKeepsPointerAnchorAndCoordinateRoundTrip() {
        let viewport = CGRect(x:200,y:16,width:520,height:380),point = CGPoint(x:530,y:240)
        var camera = TopologyCamera(); camera.fit(CGRect(x:400,y:200,width:468,height:332),in:viewport,snap:true)
        let anchored = camera.world(point,in:viewport)
        camera.zoom(1.4,at:point,in:viewport)
        XCTAssertEqual(camera.world(point,in:viewport).x,anchored.x,accuracy:0.0001)
        XCTAssertEqual(camera.world(point,in:viewport).y,anchored.y,accuracy:0.0001)
        XCTAssertEqual(camera.screen(anchored,in:viewport).x,point.x,accuracy:0.0001)
        camera.pan(CGPoint(x:50,y:-20)); XCTAssertFalse(camera.isMoving)
    }
    func testLongCurrentIterationFocusesRecentStagesWithoutShrinkingBelowReadingScale() {
        let viewport = CGRect(x:200,y:16,width:500,height:380)
        let frames = TopologyStageLayout.frames(count:24,viewport:viewport.size)
        let focus = TopologyStageLayout.focusBounds(frames,whole:false,viewport:viewport)
        XCTAssertEqual(focus,frames.suffix(2).reduce(CGRect.null) { $0.union($1) })
        var camera = TopologyCamera(); camera.fit(focus,in:viewport,snap:true)
        XCTAssertGreaterThanOrEqual(camera.scale,0.8)
        XCTAssertTrue(viewport.contains(camera.screen(frames.last!,in:viewport)))
    }
    @MainActor func testMetalGPUEncoderDrawsCardsConnectionsAndKoreanGlyphs() throws {
        let view = MetalTopologyView(); view.frame = CGRect(x:0,y:0,width:960,height:540)
        XCTAssertNil(view.rendererFailure)
        let first = CGRect(x:0,y:0,width:218,height:144),second = first.offsetBy(dx:250,dy:0)
        view.cards = [
            .init(id:.cycle(1),frame:CGRect(x:8,y:16,width:178,height:84),title:"반복 1",badge:"4단계 · 종료",text:"owned evidence",footnote:"접힘 · 선택해 펼치기",isRail:true),
            .init(id:.record(4),frame:first,title:"관찰",badge:"단계 4 · 반복 2",text:"한글 근거 🐸\n전체 원문은 별도로 보존",footnote:"단계 전문과 근거 확인"),
            .init(id:.record(5),frame:second,title:"실행",badge:"단계 5 · 반복 2",text:"실제로 수신한 이벤트",footnote:"단계 전문과 근거 확인",current:true)
        ]
        let accessibleCards = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(accessibleCards.count,3)
        XCTAssertTrue(accessibleCards.allSatisfy { $0.isAccessibilityEnabled() },"Metal cards must expose enabled inspection actions")
        view.camera.fit(first.union(second),in:view.mainViewport,snap:true)
        let output = try view.renderOffscreen()
        XCTAssertEqual(output.bytes.count,output.width*output.height*4)
        let screen = view.camera.screen(first,in:view.mainViewport)
        func rgb(_ x:Int,_ y:Int) -> [UInt8] { let offset = (y*output.width+x)*4; return Array(output.bytes[offset..<offset+3]) }
        let fill = rgb(Int((screen.minX+4)*2),Int((screen.minY+4)*2))
        var glyphPixels = 0
        for y in Int((screen.minY+12)*2)..<Int((screen.maxY-12)*2) {
            for x in Int((screen.minX+12)*2)..<Int((screen.maxX-12)*2) {
                let pixel = rgb(x,y)
                if zip(pixel,fill).reduce(0,{ $0+abs(Int($1.0)-Int($1.1)) }) > 100 { glyphPixels += 1 }
            }
        }
        XCTAssertGreaterThan(glyphPixels,500,"GPU glyph texture should contain visible Korean text")
        XCTAssertNotEqual(rgb(0,0),fill,"GPU card fill must differ from the background")
        if let path = ProcessInfo.processInfo.environment["JEV_TOPOLOGY_QA_DIR"] {
            try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true)
            let data = Data(output.bytes) as CFData
            let provider = try XCTUnwrap(CGDataProvider(data:data))
            let image = try XCTUnwrap(CGImage(width:output.width,height:output.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:output.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
            let bitmap = NSBitmapImageRep(cgImage:image)
            try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path+"/metal-gpu-render.png"))
        }
    }
}
