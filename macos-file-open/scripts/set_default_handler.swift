// Set/verify the default app for a file extension via LaunchServices (no Homebrew/duti needed).
// Usage: swiftc set_default_handler.swift -o /tmp/set-default-handler
//        /tmp/set-default-handler <ext> <bundle-id> [sample-file-path]
// Example: /tmp/set-default-handler md com.apple.TextEdit ~/CanteenMenu/README.md
// Prints "RESULT: SUCCESS" when the sample file's default app matches the bundle id.
import CoreServices
import Foundation
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: set_default_handler <ext> <bundle-id> [sample-file-path]")
    exit(1)
}
let ext = args[1]
let handler = args[2] as CFString
let sample = args.count > 3 ? args[3] : nil

// Candidate UTIs: derived from the extension, plus plain-text fallback for md-like files.
var candidates = Set<String>()
if let ut = UTType(filenameExtension: ext) {
    candidates.insert(ut.identifier)
    if let parent = ut.supertypes.first {
        candidates.insert(parent.identifier)
    }
}
candidates.insert("public.plain-text")
for uti in candidates {
    LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, handler)
    print("set \(uti) -> \(handler)")
}

if let sample {
    let url = URL(fileURLWithPath: sample) as CFURL
    var err: Unmanaged<CFError>?
    if let appURL = LSCopyDefaultApplicationURLForURL(url, .all, &err)?.takeRetainedValue() as URL? {
        print("sample default app: \(appURL.path)")
        print(appURL.path.contains(args[2]) ? "RESULT: SUCCESS" : "RESULT: not applied yet")
    } else {
        print("RESULT: query failed: \(String(describing: err?.takeRetainedValue()))")
    }
}
