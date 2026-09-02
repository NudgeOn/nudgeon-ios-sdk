import Foundation

/// 계약 시나리오 모델 — contract-tests/scenarios/*.json을 동적 파싱(값 타입이 임의라 Codable 대신 수동).
struct Scenario {
    let name: String
    let config: [String: Any]
    let steps: [[String: Any]]
    let expect: [Expectation]

    struct Expectation {
        let path: String
        let asserts: [Assertion]
    }

    struct Assertion {
        enum Kind { case equals(Any), absent, present }
        let pointer: String
        let kind: Kind
    }

    init?(json: [String: Any]) {
        guard let name = json["name"] as? String else { return nil }
        self.name = name
        self.config = json["config"] as? [String: Any] ?? [:]
        self.steps = json["steps"] as? [[String: Any]] ?? []
        self.expect = (json["expect"] as? [[String: Any]] ?? []).compactMap { e in
            guard let path = e["path"] as? String else { return nil }
            let asserts = (e["asserts"] as? [[String: Any]] ?? []).compactMap { a -> Assertion? in
                guard let ptr = a["pointer"] as? String else { return nil }
                if a["absent"] as? Bool == true { return Assertion(pointer: ptr, kind: .absent) }
                if a["present"] as? Bool == true { return Assertion(pointer: ptr, kind: .present) }
                if let v = a["equals"] { return Assertion(pointer: ptr, kind: .equals(v)) }
                return nil
            }
            return Expectation(path: path, asserts: asserts)
        }
    }

    /// 저장소의 공용 시나리오 디렉터리에서 전 시나리오 로드 (#filePath 기준 repo 루트 탐색).
    static func loadAll() -> [Scenario] {
        let here = URL(fileURLWithPath: #filePath)
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = repoRoot.appendingPathComponent("contract-tests/scenarios")
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return Scenario(json: obj)
            }
    }
}

/// JSON 포인터(점 표기 + 배열 인덱스) 해석 및 assert 매칭.
enum JSONMatch {
    /// "batch.0.properties.product_id" → (존재여부, 값).
    static func resolve(_ pointer: String, in root: [String: Any]) -> (found: Bool, value: Any?) {
        var current: Any = root
        for comp in pointer.split(separator: ".") {
            if let dict = current as? [String: Any] {
                guard let v = dict[String(comp)] else { return (false, nil) }
                current = v
            } else if let arr = current as? [Any], let idx = Int(comp), idx >= 0, idx < arr.count {
                current = arr[idx]
            } else {
                return (false, nil)
            }
        }
        return (true, current)
    }

    static func satisfies(_ assertion: Scenario.Assertion, _ body: [String: Any]) -> Bool {
        let (found, value) = resolve(assertion.pointer, in: body)
        switch assertion.kind {
        case .present: return found
        case .absent: return !found
        case .equals(let expected): return found && equal(value, expected)
        }
    }

    static func equal(_ a: Any?, _ b: Any?) -> Bool {
        if let x = a as? String, let y = b as? String { return x == y }
        if let x = a as? NSNumber, let y = b as? NSNumber { return x.isEqual(y) }
        return false
    }

    /// Expectation이 body에 완전히 부합하는지 (경로 일치 + 모든 assert 충족).
    static func matches(_ exp: Scenario.Expectation, _ record: MockIngestServer.Recorded) -> Bool {
        guard record.path == exp.path else { return false }
        return exp.asserts.allSatisfy { satisfies($0, record.body) }
    }
}
