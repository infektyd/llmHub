import Foundation

struct WorkspaceItem: Codable {
    let id: UUID
    let filename: String
    let data: Data
    let contentType: String
    let createdAt: Date
    let metadata: [String: String]
}

func test() {
    let fileManager = FileManager.default
    let item = WorkspaceItem(id: UUID(), filename: "test.json", data: Data("Hello, world!".utf8), contentType: "text/plain", createdAt: Date(), metadata: [:])
    let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_benchmark.json")
    let data = try! JSONEncoder().encode(item)
    try! data.write(to: fileURL)

    let start = Date()
    for _ in 0..<10000 {
        let _ = try! Data(contentsOf: fileURL)
    }
    print("Sync: \(Date().timeIntervalSince(start))")

    let start2 = Date()
    let group = DispatchGroup()
    for _ in 0..<10000 {
        group.enter()
        DispatchQueue.global().async {
            let _ = try! Data(contentsOf: fileURL)
            group.leave()
        }
    }
    group.wait()
    print("Async/Concurrent: \(Date().timeIntervalSince(start2))")
}
test()
