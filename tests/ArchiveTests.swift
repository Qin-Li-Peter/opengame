import Foundation
@main struct ArchiveTests {
    static func main() throws {
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("OpenGame-Archive-"+UUID().uuidString)
        defer{try? fm.removeItem(at:root)}
        let core=OpenGameCore(root:root);try core.ensureCatalog()
        let bin=root.appendingPathComponent("Engines/WineFOSS11/bin");try fm.createDirectory(at:bin,withIntermediateDirectories:true)
        for name in ["wine","wineserver"] {let file=bin.appendingPathComponent(name);try "#!/bin/sh\nexit 0\n".write(to:file,atomically:true,encoding:.utf8);try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:file.path)}
        let original=Bottle(id:"original",name:"Archive Test",directory:"Prefixes/original",renderer:.wine,engineFamily:.foss)
        let prefix=try core.prefix(original);try fm.createDirectory(at:prefix.appendingPathComponent("drive_c/Game"),withIntermediateDirectories:true)
        try Data().write(to:prefix.appendingPathComponent("system.reg"));try Data([0x4d,0x5a]).write(to:prefix.appendingPathComponent("drive_c/Game/game.exe"))
        let game=Game(id:"game",title:"Game",bottleID:original.id,executable:prefix.appendingPathComponent("drive_c/Game/game.exe").path,arguments:[],workingDirectory:prefix.appendingPathComponent("drive_c/Game").path,icon:nil,steamID:nil,note:"test")
        try core.mutate{$0.bottles=[original];$0.games=[game]}
        let unsafe=prefix.appendingPathComponent("drive_c/escape")
        try fm.createSymbolicLink(atPath:unsafe.path,withDestinationPath:"/tmp")
        do {
            try core.exportBottle(original,to:root.appendingPathComponent("Unsafe.opengamebottle"))
            preconditionFailure("external symlink should be rejected")
        } catch {}
        try fm.removeItem(at:unsafe)
        let archive=root.appendingPathComponent("Archive.opengamebottle");try core.exportBottle(original,to:archive)
        let restored=try core.importBottle(from:archive,name:"Restored")
        let library=try core.load(),restoredGame=try XCTUnwrap(library.games.first{$0.bottleID==restored.id})
        let restoredPrefix=try core.prefix(restored)
        precondition(restoredGame.executable.hasPrefix(restoredPrefix.path+"/"))
        precondition(fm.fileExists(atPath:restoredGame.executable))
        print("PASS: unsafe symlink rejection, safe bottle export, restore, and internal path migration")
    }
}

func XCTUnwrap<T>(_ value:T?) throws -> T {guard let value=value else{throw OGError.message("Missing restored value")};return value}
