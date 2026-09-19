import Cocoa
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let nm = w[kCGWindowName as String] as? String ?? ""; if nm.hasPrefix("CIQ Simulator - ") {
        let b = w[kCGWindowBounds as String] as! [String: Any]
        let id = w[kCGWindowNumber as String] as! Int
        let name = w[kCGWindowName as String] as? String ?? ""
        print("\(id) \(owner) '\(name)' x=\(b["X"]!) y=\(b["Y"]!) w=\(b["Width"]!) h=\(b["Height"]!)")
    }
}
