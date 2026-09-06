import Foundation
@main struct CatalogTests {
    static func main() throws {
        let fm=FileManager.default
        let root=fm.temporaryDirectory.appendingPathComponent("OpenGame-Test-"+UUID().uuidString)
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
        var current=old.bottles[0];current.engineFamily = .foss;current.renderer = .dxmt
        // A source-only test root has no complete DXMT engine, so routing
        // safely falls back to the base core.
        precondition(core.runtime(current).path.hasSuffix("WineFOSS11/bin/wine"))
        let completeDXMT=root.appendingPathComponent("Engines/WineFOSS11-DXMT/bin/wine")
        try fm.createDirectory(at:completeDXMT.deletingLastPathComponent(),withIntermediateDirectories:true)
        try "#!/bin/sh\nexit 0\n".write(to:completeDXMT,atomically:true,encoding:.utf8)
        try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:completeDXMT.path)
        precondition(core.runtime(current).path.hasSuffix("WineFOSS11-DXMT/bin/wine"))
        let env=try core.environment(current)
        precondition(env["WINEMSYNC"]=="1")
        try core.mutate { $0.bottles.append(current) }
        let reloaded=try core.load()
        precondition(reloaded.bottles.count==2)
        let steamBottle=Bottle(id:"steam",name:"Steam",directory:"Prefixes/Steam",renderer:.dxmt,engineFamily:.foss)
        let prefix=try core.prefix(steamBottle)
        try fm.createDirectory(at:prefix,withIntermediateDirectories:true)
        try Data().write(to:prefix.appendingPathComponent("system.reg"))
        let pack=root.appendingPathComponent("RendererPacks/dxmt")
        for (arch,folder) in [("x86_64-windows","system32"),("i386-windows","syswow64")] {
            for name in ["d3d10core.dll","d3d11.dll","dxgi.dll"] {
                let source=pack.appendingPathComponent("\(arch)/\(name)")
                let target=prefix.appendingPathComponent("drive_c/windows/\(folder)/\(name)")
                try fm.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
                try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try Data("dxmt-\(arch)-\(name)".utf8).write(to:source)
                try Data("stale-wine".utf8).write(to:target)
            }
            let bridge=root.appendingPathComponent("Engines/WineFOSS11-DXMT/lib/wine/\(arch)/winemetal.dll")
            try fm.createDirectory(at:bridge.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data("bridge".utf8).write(to:bridge)
        }
        try "dxmt\n".write(to:prefix.appendingPathComponent(".opengame-renderer"),atomically:true,encoding:.utf8)
        let gameFile=prefix.appendingPathComponent("drive_c/Game/game.exe")
        try fm.createDirectory(at:gameFile.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data().write(to:gameFile)
        let game=Game(id:"game",title:"Game",bottleID:steamBottle.id,executable:gameFile.path,arguments:[],workingDirectory:gameFile.deletingLastPathComponent().path,steamID:"4001890",note:"")
        try core.mutate{$0.bottles=[steamBottle];$0.games=[game]}
        let gameLaunch=try core.gameSpec(game)
        precondition(gameLaunch.executable.path.hasSuffix("WineFOSS11-DXMT/bin/wine"))
        precondition(gameLaunch.environment["SteamNoOverlayUI"]=="1")
        precondition(gameLaunch.environment["SteamNoOverlayUIDrawing"]=="1")
        let repairedD3D11=try Data(contentsOf:prefix.appendingPathComponent("drive_c/windows/system32/d3d11.dll"))
        precondition(repairedD3D11 == Data("dxmt-x86_64-windows-d3d11.dll".utf8),"A stale renderer stamp must not suppress repair")
        let steamFile=prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
        try fm.createDirectory(at:steamFile.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data().write(to:steamFile)
        let steamLaunch=try core.spec(bottle:steamBottle,arguments:[steamFile.path],directory:steamFile.deletingLastPathComponent(),logID:"steam")
        precondition(steamLaunch.executable.path.hasSuffix("WineFOSS11-DXMT/bin/wine"),"Steam and the game must share one Wine core")
        precondition(steamLaunch.environment["WINEDLLOVERRIDES"]=="winemenubuilder.exe=", "Steam UI should keep Wine rendering on the selected core")
        precondition(steamLaunch.arguments.contains("-noverifyfiles") && steamLaunch.arguments.contains("-cef-disable-gpu"))
        print("PASS: catalog preservation, runtime routing, Steam overlay isolation and stable bootstrap flags")
    }
}
