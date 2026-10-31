import CoreGraphics
import Foundation
// drive drag x1 y1 x2 y2   (global display coords, top-left origin)
// drive swipe x y dx       (two-finger horizontal trackpad gesture over a point)
let a = CommandLine.arguments
func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap); usleep(12_000) }
if a[1] == "drag" {
    let p1 = CGPoint(x: Double(a[2])!, y: Double(a[3])!), p2 = CGPoint(x: Double(a[4])!, y: Double(a[5])!)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p1, mouseButton: .left))
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p1, mouseButton: .left))
    for i in 1...30 {
        let t = Double(i) / 30
        post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: CGPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t), mouseButton: .left))
    }
    usleep(200_000)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p2, mouseButton: .left))
} else if a[1] == "swipe" {
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!), total = Int32(a[4])!
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    let steps: Int32 = 10
    for i in 0...steps + 1 {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: i == 0 || i > steps ? 0 : total / steps, wheel3: 0)
        e?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // NSEvent phase: 1 began, 2 changed, 4 ended
        e?.setIntegerValueField(.scrollWheelEventScrollPhase, value: i == 0 ? 1 : (i > steps ? 4 : 2))
        post(e)
    }
}
if a[1] == "click" {
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left))
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left))
} else if a[1] == "type" {
    for ch in a[2].utf16 {
        var c = ch
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c); post(e)
        }
    }
} else if a[1] == "key" { // key <virtualKey> <flags: c s o>
    var flags: CGEventFlags = []
    if a.count > 3 { for f in a[3] { if f == "c" { flags.insert(.maskCommand) }; if f == "s" { flags.insert(.maskShift) } } }
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(Int(a[2])!), keyDown: down); e?.flags = flags; post(e)
    }
} else if a[1] == "scroll" { // scroll x y dy  (vertical, continuous gesture)
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!), total = Int32(a[4])!
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    for i in 0...11 {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: i == 0 || i > 10 ? 0 : total / 10, wheel2: 0, wheel3: 0)
        e?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e?.setIntegerValueField(.scrollWheelEventScrollPhase, value: i == 0 ? 1 : (i > 10 ? 4 : 2)); post(e)
    }
}
if a[1] == "move" { // move x1 y1 x2 y2 steps
    let p1 = CGPoint(x: Double(a[2])!, y: Double(a[3])!), p2 = CGPoint(x: Double(a[4])!, y: Double(a[5])!), n = Int(a[6])!
    for i in 0...n { let t = Double(i) / Double(n); post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t), mouseButton: .left)) }
}
