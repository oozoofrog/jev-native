import Foundation

/// Folding is a projection. The runner's records and full evidence are never modified.
struct TopologyFocus: Equatable {
    private(set) var inspectedCycle: Int?
    private(set) var followsCurrent = true
    private(set) var fitsWholeCycle = false
    mutating func inspect(_ cycle:Int) {
        if inspectedCycle == cycle { inspectedCycle = nil; followsCurrent = true }
        else { inspectedCycle = cycle; followsCurrent = false }
        fitsWholeCycle = true
    }
    mutating func follow() { inspectedCycle = nil; followsCurrent = true; fitsWholeCycle = false }
    mutating func manual(_ cycle:Int? = nil) { if let cycle { inspectedCycle = cycle }; followsCurrent = false }
    mutating func overview() { followsCurrent = false; fitsWholeCycle = true }
    func projection(_ state:RunPresentationState) -> TopologyProjection {
        let cycles = Set(state.topology.map(\.cycle).filter { $0 > 0 }).sorted()
        let current = state.cycle > 0 && !state.completedCycles.contains(state.cycle) && state.outcome == nil ? state.cycle : nil
        let shown = inspectedCycle ?? current
        let records:[TopologyRecord]
        if let shown { records = state.topology.filter { $0.cycle == shown && $0.kind != .outcome } }
        else if state.outcome != nil {
            records = [state.topology.last(where: { $0.kind == .result }),state.topology.last(where: { $0.kind == .outcome })].compactMap { $0 }
        } else { records = state.cycle == 0 ? state.topology.filter { $0.cycle == 0 } : [] }
        let summaries = cycles.map { cycle -> TopologyCycleSummary in
            let entries = state.topology.filter { $0.cycle == cycle && $0.kind != .outcome }
            let closed = state.completedCycles.contains(cycle)
            let recovery = entries.contains { $0.kind == .recovery }
            let last = entries.last
            return TopologyCycleSummary(cycle:cycle,recordIDs:entries.map(\.id),closed:closed,expanded:shown == cycle,
                title:"반복 \(cycle)",subtitle:"\(entries.count)단계 · "+(closed ? (recovery ? "복구 근거 있음" : "종료") : "진행 중"),
                preview:last.map { $0.title+" · "+String($0.text.prefix(62)) } ?? "관찰 대기")
        }
        return TopologyProjection(summaries:summaries,records:records,shownCycle:shown,currentCycle:current,
            currentRecordID:current == shown ? records.last?.id : nil)
    }
}

struct TopologyCycleSummary: Equatable {
    let cycle:Int
    let recordIDs:[Int]
    let closed:Bool
    let expanded:Bool
    let title:String
    let subtitle:String
    let preview:String
}

struct TopologyProjection: Equatable {
    let summaries:[TopologyCycleSummary]
    let records:[TopologyRecord]
    let shownCycle:Int?
    let currentCycle:Int?
    let currentRecordID:Int?
}

/// The camera and hit testing share logical points; drawable pixels are only a renderer concern.
struct TopologyCamera: Equatable {
    var center = CGPoint.zero
    var scale:CGFloat = 1
    private(set) var targetCenter = CGPoint.zero
    private(set) var targetScale:CGFloat = 1
    var frozen = false
    var isMoving:Bool { abs(center.x-targetCenter.x)+abs(center.y-targetCenter.y)>0.05 || abs(scale-targetScale)>0.0001 }
    mutating func fit(_ content:CGRect,in viewport:CGRect,minimumScale:CGFloat = 0.8,maximumScale:CGFloat = 1.15,snap:Bool = false) {
        guard viewport.width > 0,viewport.height > 0,!content.isNull else { return }
        targetCenter = CGPoint(x:content.midX,y:content.midY)
        targetScale = max(minimumScale,min(maximumScale,min(max(1,viewport.width-48)/max(1,content.width),max(1,viewport.height-48)/max(1,content.height))))
        if snap { settle() }
    }
    mutating func settle() { center = targetCenter; scale = targetScale }
    mutating func advance(_ seconds:Double,reducedMotion:Bool) {
        guard !frozen else { return }
        if reducedMotion { settle(); return }
        let fraction = CGFloat(1-exp(-min(0.05,max(0,seconds))*12))
        center.x += (targetCenter.x-center.x)*fraction; center.y += (targetCenter.y-center.y)*fraction
        scale += (targetScale-scale)*fraction
        if !isMoving { settle() }
    }
    func screen(_ world:CGPoint,in viewport:CGRect) -> CGPoint {
        CGPoint(x:viewport.midX+(world.x-center.x)*scale,y:viewport.midY+(world.y-center.y)*scale)
    }
    func world(_ screen:CGPoint,in viewport:CGRect) -> CGPoint {
        CGPoint(x:center.x+(screen.x-viewport.midX)/scale,y:center.y+(screen.y-viewport.midY)/scale)
    }
    func screen(_ world:CGRect,in viewport:CGRect) -> CGRect {
        let origin = screen(world.origin,in:viewport)
        return CGRect(origin:origin,size:CGSize(width:world.width*scale,height:world.height*scale))
    }
    mutating func pan(_ delta:CGPoint) {
        targetCenter.x -= delta.x/scale; targetCenter.y -= delta.y/scale; settle()
    }
    mutating func zoom(_ factor:CGFloat,at point:CGPoint,in viewport:CGRect) {
        let anchored = world(point,in:viewport)
        targetScale = max(0.45,min(1.8,scale*factor)); scale = targetScale
        targetCenter = CGPoint(x:anchored.x-(point.x-viewport.midX)/scale,y:anchored.y-(point.y-viewport.midY)/scale); settle()
    }
}

enum TopologyStageLayout {
    static func frames(count:Int,viewport:CGSize) -> [CGRect] {
        let columns = viewport.width >= 780 ? 3 : viewport.width >= 450 ? 2 : 1
        let width:CGFloat = 218,height:CGFloat = 144,gap:CGFloat = 32
        return (0..<count).map { index in
            let row = index/columns,slot = index%columns,column = row%2 == 0 ? slot : columns-1-slot
            return CGRect(x:CGFloat(column)*(width+gap),y:CGFloat(row)*(height+44),width:width,height:height)
        }
    }
    static func focusBounds(_ frames:[CGRect],whole:Bool,viewport:CGRect) -> CGRect {
        let all = frames.reduce(CGRect.null) { $0.union($1) }
        if whole || all.height*0.8 <= viewport.height-48 { return all }
        return frames.suffix(viewport.width >= 780 ? 3 : 2).reduce(CGRect.null) { $0.union($1) }
    }
}
