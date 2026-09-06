import Foundation
@main struct CatalogTests {
    static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("OpenGame-Test-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let core=OpenGameCore(root:root)
        try core.ensureCatalog()
        let fresh=try core.load()
        precondition(fresh.games.isEmpty && fresh.bottles.isEmpty,"New installations must not inherit personal games")
        let legacy="""
        {"schema":1,"bottles":[{"id":"existing","name":"Existing","directory":"Prefixes/existing","renderer":"dxvk"}],"games":[]}
        """
        try Data(legacy.utf8).write(to:core.catalog)
        try core.ensureCatalog()
        let old=try core.load()
        precondition(old.bottles.count==1 && old.bottles[0].engineFamily==nil)
        precondition(core.runtime(old.bottles[0]).path.hasSuffix("WineHQ11-DXVK/bin/wine"))
        var performance=old.bottles[0];performance.engineFamily = .foss;performance.renderer = .dxmt
        precondition(core.runtime(performance).path.hasSuffix("WineFOSS11-DXMT/bin/wine"))
        let env=try core.environment(performance)
        precondition(env["WINEMSYNC"]=="1")
        try core.mutate { $0.bottles.append(performance) }
        let reloaded=try core.load()
        precondition(reloaded.bottles.count==2)
        print("PASS: empty first-run catalog, existing catalog preservation, runtime family routing")
    }
}
