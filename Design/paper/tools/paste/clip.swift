import AppKit
import Foundation

func die(_ m: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write((m + "\n").data(using: .utf8)!)
    exit(code)
}

let args = CommandLine.arguments
guard args.count >= 2 else { die("usage: clip set <file> [--mode both|plain|html] | save <dir> | restore <dir> | info") }
let pb = NSPasteboard.general
let fm = FileManager.default

switch args[1] {
case "set":
    guard args.count >= 3 else { die("clip set <file> [--mode both|plain|html]") }
    var mode = "both"
    if let i = args.firstIndex(of: "--mode") {
        guard i + 1 < args.count else { die("--mode needs a value") }
        mode = args[i + 1]
    }
    guard ["both", "plain", "html"].contains(mode) else { die("bad mode \(mode)") }
    guard let data = fm.contents(atPath: args[2]), let s = String(data: data, encoding: .utf8) else {
        die("cannot read \(args[2]) as UTF-8")
    }
    pb.clearContents()
    var ok = true
    if mode == "both" || mode == "html" { ok = pb.setString(s, forType: .html) && ok }
    if mode == "both" || mode == "plain" { ok = pb.setString(s, forType: .string) && ok }
    if !ok { die("setString failed") }
    print(pb.changeCount)

case "save":
    guard args.count >= 3 else { die("clip save <dir>") }
    let dir = args[2]
    do { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true) } catch { die("mkdir: \(error)") }
    var index: [[[String: String]]] = []
    var n = 0
    for item in pb.pasteboardItems ?? [] {
        var entries: [[String: String]] = []
        for t in item.types {
            guard let d = item.data(forType: t) else { continue }
            let fn = "data-\(n).bin"; n += 1
            do { try d.write(to: URL(fileURLWithPath: dir + "/" + fn)) } catch { die("write: \(error)") }
            entries.append(["type": t.rawValue, "file": fn])
        }
        index.append(entries)
    }
    let obj: [String: Any] = ["changeCount": pb.changeCount, "items": index]
    do {
        let j = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try j.write(to: URL(fileURLWithPath: dir + "/index.json"))
    } catch { die("index: \(error)") }
    print("saved \(index.count) items, \(n) data files")

case "restore":
    guard args.count >= 3 else { die("clip restore <dir>") }
    let dir = args[2]
    guard let j = fm.contents(atPath: dir + "/index.json"),
          let obj = try? JSONSerialization.jsonObject(with: j) as? [String: Any],
          let items = obj["items"] as? [[[String: String]]] else { die("bad index in \(dir)") }
    var out: [NSPasteboardItem] = []
    for entries in items {
        let pi = NSPasteboardItem()
        for e in entries {
            guard let t = e["type"], let f = e["file"], let d = fm.contents(atPath: dir + "/" + f) else { die("missing data \(e)") }
            pi.setData(d, forType: NSPasteboard.PasteboardType(t))
        }
        out.append(pi)
    }
    pb.clearContents()
    if !out.isEmpty && !pb.writeObjects(out) { die("writeObjects failed") }
    print(pb.changeCount)

case "info":
    print("changeCount \(pb.changeCount)")
    for (i, item) in (pb.pasteboardItems ?? []).enumerated() {
        for t in item.types {
            print("item\(i)\t\(t.rawValue)\t\(item.data(forType: t)?.count ?? 0)")
        }
    }

default:
    die("unknown subcommand \(args[1])")
}
