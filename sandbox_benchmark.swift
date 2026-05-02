import Foundation

enum SupportedLanguage: String, CaseIterable {
    case swift
    case python
    case typescript
    case javascript
    case dart

    var fileExtensionValue: String {
        switch self {
        case .swift: return ".swift"
        case .python: return ".py"
        case .typescript: return ".ts"
        case .javascript: return ".js"
        case .dart: return ".dart"
        }
    }
}

let startUnoptimized = Date()
var dummyCount = 0
for _ in 0..<100000 {
    let ext = "png"
    if SupportedLanguage.allCases.map({ $0.fileExtensionValue }).contains(".\(ext)") {
        dummyCount += 1
    }
}
let durationUnoptimized = Date().timeIntervalSince(startUnoptimized)
print("Unoptimized Duration: \(durationUnoptimized) seconds")


let startOptimized = Date()
let supportedExtensions = Set(SupportedLanguage.allCases.map { $0.fileExtensionValue })
for _ in 0..<100000 {
    let ext = "png"
    if supportedExtensions.contains(".\(ext)") {
        dummyCount += 1
    }
}
let durationOptimized = Date().timeIntervalSince(startOptimized)
print("Optimized Duration: \(durationOptimized) seconds")
