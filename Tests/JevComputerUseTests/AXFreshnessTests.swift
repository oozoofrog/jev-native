import XCTest
@testable import JevComputerUse

final class AXFreshnessTests:XCTestCase {
    func testCheckboxSelectionChangesDuringDecisionRejectInput()throws {
        let snapshot=Node(id:"owned",role:"AXCheckBox",title:"Include",value:"0",enabled:true,actions:["AXPress"],frame:nil,selected:false,checked:false)
        XCTAssertNoThrow(try validateAXDiscreteState(snapshot,enabled:true,selected:false,checked:false,focused:false))
        XCTAssertThrowsError(try validateAXDiscreteState(snapshot,enabled:true,selected:false,checked:true,focused:false))
        XCTAssertThrowsError(try validateAXDiscreteState(snapshot,enabled:true,selected:true,checked:false,focused:false))
        XCTAssertThrowsError(try validateAXDiscreteState(snapshot,enabled:true,selected:nil,checked:false,focused:false))
        XCTAssertThrowsError(try validateAXDiscreteState(snapshot,enabled:false,selected:false,checked:false,focused:false))
    }
    func testFlattenedNativeParentDoesNotHideTraversalGroupRename()throws {
        let group=Node(id:"group",role:"AXGroup",title:"Right controls",value:"",enabled:true,actions:[],frame:nil)
        XCTAssertNoThrow(try validateAXContextLabel(group,role:"AXGroup",title:"Right controls",subrole:"",enabled:true))
        XCTAssertThrowsError(try validateAXContextLabel(group,role:"AXGroup",title:"Left controls",subrole:"",enabled:true))
        XCTAssertThrowsError(try validateAXContextLabel(group,role:"AXGroup",title:"Right controls",subrole:"AXSecureTextField",enabled:true))
    }

    private func dockObservation() -> Observation {
        let root=Node(id:"root",role:"AXApplication",title:"Dock",value:"",enabled:true,actions:[],frame:nil,locator:"0",ownerPID:750)
        let list=Node(id:"list",role:"AXList",title:"",value:"",enabled:true,actions:[],frame:nil,parent:"root",locator:"0.0",ownerPID:750)
        let item=Node(id:"item",role:"AXDockItem",title:"JevNative",value:"",enabled:true,actions:["AXPress"],frame:nil,subrole:"AXApplicationDockItem",parent:"list",locator:"0.0.1",ownerPID:750,applicationURL:"file:///fixture-workspace/JevNative.app/")
        return Observation(id:"dock",timestamp:Date(),front:nil,apps:[],nodes:[root,list,item],displays:[],truncated:false,axError:nil,elapsedMS:0,target:AppInfo(pid:750,bundle:"com.apple.dock",name:"Dock"),axOverview:AXOverview(revision:"r",coverage:.complete,scanned:3,pending:0,regions:[],roleCounts:[:],metrics:AXMetrics()))
    }
    func testDockPressBindsApplicationURLAndNativeScope() throws {
        let observation=dockObservation(), item=observation.nodes[2], press=Action(kind:"press",target:item.id)
        XCTAssertNoThrow(try validateDockApplicationTarget(item,observation:observation,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:item.applicationURL))
        XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:observation,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:"file:///fixture-workspace/other/JevNative.app/"))
        XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:observation,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:nil))
        XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:observation,action:Action(kind:"secondary",target:item.id,axAction:"AXShowMenu"),currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:item.applicationURL))
        XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:observation,action:press,currentBundle:"other.app",currentSubrole:"AXApplicationDockItem",currentURL:item.applicationURL))
        XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:observation,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXFolderDockItem",currentURL:item.applicationURL))
        var altered=observation
        altered.nodes[2].applicationURL="https://example.test/JevNative.app"
        XCTAssertThrowsError(try validateDockApplicationTarget(altered.nodes[2],observation:altered,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:altered.nodes[2].applicationURL))
        altered=observation; altered.nodes[2].applicationURL="file:///fixture-workspace/a.txt"
        XCTAssertThrowsError(try validateDockApplicationTarget(altered.nodes[2],observation:altered,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:altered.nodes[2].applicationURL))
        altered=observation; altered.nodes[2].subrole="AXFolderDockItem"
        XCTAssertThrowsError(try validateDockApplicationTarget(altered.nodes[2],observation:altered,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:item.applicationURL))
        altered=observation; altered.nodes[1].ownerPID=751
        XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:altered,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:item.applicationURL))
        altered=observation; altered.nodes[1].role="AXGroup"
        XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:altered,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:item.applicationURL))
        altered=observation; altered.target?.bundle="other.app"
        XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:altered,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:item.applicationURL))
    }
    func testIncompleteOrModalDockContextCannotPressApplication() throws {
        let observation=dockObservation(), item=observation.nodes[2], press=Action(kind:"press",target:item.id)
        var altered=observation; altered.axOverview?.coverage = .partial
        XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:altered,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:item.applicationURL))
        altered=observation; altered.axModalStamps=[]
        XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:altered,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:item.applicationURL))
        for role in ["AXMenu","AXWindow","AXSheet","AXDialog"] {
            altered=observation;altered.nodes.append(Node(id:"extra",role:role,title:"",value:"",enabled:true,actions:[],frame:nil))
            XCTAssertThrowsError(try validateDockApplicationTarget(item,observation:altered,action:press,currentBundle:"com.apple.dock",currentSubrole:"AXApplicationDockItem",currentURL:item.applicationURL))
        }
    }
    func testSameTitleDifferentDockApplicationFailsFreshness() {
        let prior=dockObservation();var current=prior
        current.nodes[2].applicationURL="file:///fixture-workspace/other/JevNative.app/"
        XCTAssertFalse(stableTargetState(prior,current,action:Action(kind:"press",target:prior.nodes[2].id)))
        current=prior;current.nodes[2].applicationURL=nil
        XCTAssertFalse(stableTargetState(prior,current,action:Action(kind:"press",target:prior.nodes[2].id)))
    }
}
