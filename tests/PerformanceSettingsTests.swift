import Foundation
@main struct PerformanceSettingsTests {
    static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("OpenGame-Performance-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let core=OpenGameCore(root:root)
        try core.ensureCatalog()
        let old=Data("{\"id\":\"test\",\"name\":\"Test\",\"directory\":\"Prefixes/test\",\"renderer\":\"dxmt\",\"engineFamily\":\"foss\"}".utf8)
        var bottle=try JSONDecoder().decode(Bottle.self,from:old)
        precondition(bottle.usesMSync && bottle.effectiveFrameRateLimit==0)
        let defaultEnv=try core.environment(bottle)
        precondition(defaultEnv["WINEMSYNC"]=="1")
        for rate in [0,30,60,120] {
            bottle.frameRateLimit=rate;bottle.msyncEnabled=false
            let env=try core.environment(bottle)
            precondition(env["WINEMSYNC"]=="0")
            precondition(env["DXMT_CONFIG"]==(rate==0 ? nil : "d3d11.preferredMaxFrameRate = \(rate)"))
            try core.mutate{$0.bottles=[bottle]}
            let restored=try core.load().bottles[0]
            precondition(restored.frameRateLimit==rate && restored.msyncEnabled==false)
        }
        bottle.renderer = .wine
        let wineEnv=try core.environment(bottle)
        precondition(wineEnv["DXMT_CONFIG"]==nil)
        bottle.frameRateLimit=59
        do {_ = try core.environment(bottle);fatalError("Invalid frame cap accepted")}catch is OGError{}
        let fm=FileManager.default
        for engine in ["WineFOSS11","WineFOSS11-DXMT"] {
            let bin=root.appendingPathComponent("Engines/\(engine)/bin")
            try fm.createDirectory(at:bin,withIntermediateDirectories:true)
            for (name,body) in [("wine","exit 0"),("wineserver","exec /bin/sleep 30")] {
                let executable=bin.appendingPathComponent(name)
                try "#!/bin/sh\n\(body)\n".write(to:executable,atomically:true,encoding:.utf8)
                try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:executable.path)
            }
        }
        bottle.renderer = .dxmt;bottle.frameRateLimit=0;bottle.msyncEnabled=true
        try core.mutate{$0.bottles=[bottle]}
        var modified=bottle;modified.renderer = .wine
        do {try core.updateBottle(modified);fatalError("Active renderer switch accepted")}catch is OGError{}
        modified=bottle;modified.msyncEnabled=false
        do {try core.updateBottle(modified);fatalError("Active MSync switch accepted")}catch is OGError{}
        let unchanged=try core.load().bottles[0]
        precondition(unchanged.renderer == .dxmt && unchanged.usesMSync)
        print("PASS: legacy defaults, MSync and DXMT frame cap environment, persistence, validation, active-session protection")
    }
}
