import Foundation

func validateAXDiscreteState(_ expected:Node, enabled:Bool?, selected:Bool?, checked:Bool?, focused:Bool?) throws {
    guard (enabled ?? true)==expected.enabled else { throw Failure("AX enabled state changed; reobserve") }
    if let before=expected.selected { guard selected==before else { throw Failure("AX selected state changed; reobserve") } }
    if let before=expected.checked { guard checked==before else { throw Failure("AX checked state changed; reobserve") } }
    if let focused { guard focused==expected.focused else { throw Failure("AX focused state changed; reobserve") } }
}

func validateAXContextLabel(_ expected:Node, role:String, title:String, subrole:String, enabled:Bool?) throws {
    guard role==expected.role, String(title.prefix(300))==expected.title, subrole != "AXSecureTextField", (enabled ?? true)==expected.enabled else { throw Failure("Observed AX ancestor context changed; reobserve") }
}

// Dock application items belong to its application/list tree, not an AXWindow.
// A complete, window-free Dock snapshot and the exact app URL bind this narrow press scope.
func validateDockApplicationTarget(_ expected:Node, observation:Observation, action:Action, currentBundle:String?, currentSubrole:String, currentURL:String?) throws {
    guard action.kind == "press", observation.target?.bundle == "com.apple.dock",
          currentBundle == "com.apple.dock", currentSubrole == "AXApplicationDockItem",
          expected.role == "AXDockItem", expected.subrole == "AXApplicationDockItem",
          expected.actions.contains("AXPress"), expected.ownerPID == observation.target?.pid,
          observation.axOverview?.coverage == .complete, observation.axModalStamps == nil,
          !observation.nodes.contains(where:{ ["AXWindow","AXSheet","AXDialog","AXMenu"].contains($0.role) }),
          let address=expected.applicationURL, address == currentURL,
          let url=URL(string:address), url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
          url.pathExtension == "app", url.query == nil, url.fragment == nil,
          let parentID=expected.parent, let parent=observation.nodes.first(where:{$0.id==parentID}),
          parent.role == "AXList", parent.ownerPID == expected.ownerPID,
          let rootID=parent.parent, let root=observation.nodes.first(where:{$0.id==rootID}),
          root.role == "AXApplication", root.locator == "0", root.parent == nil,
          root.ownerPID == expected.ownerPID else { throw Failure("Dock application context or URL changed; reobserve") }
}
