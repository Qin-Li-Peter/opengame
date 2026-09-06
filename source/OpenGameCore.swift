import Foundation
import AppKit
import Darwin

enum OGError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum Renderer: String, Codable, CaseIterable { case wine, dxvk, dxmt
    var label: String { switch self {case .wine:return "Wine · 旧游戏 / 2D";case .dxvk:return "DXVK · DirectX 10/11";case .dxmt:return "DXMT · DirectX 10/11 → Metal"} }
}
enum EngineFamily: String, Codable, CaseIterable { case winehq, foss
    var label: String { self == .foss ? "性能核心 · WineFOSS11 + MSync（实验）" : "原核心 · WineHQ11" }
}
struct Bottle: Codable, Identifiable, Hashable {
    var id: String; var name: String; var directory: String; var renderer: Renderer
    var engineFamily: EngineFamily? = nil
}
struct Game: Codable, Identifiable, Hashable {
    var id: String; var title: String; var bottleID: String
    var executable: String; var arguments: [String]; var workingDirectory: String
    var icon: String?; var steamID: String?; var note: String
}
struct Library: Codable {
    var schema = 1; var bottles: [Bottle]; var games: [Game]
}
struct LaunchSpec {
    let executable: URL; let arguments: [String]; let directory: URL; let environment: [String:String]; let log: URL
}
// Immutable service state; catalog writes use an advisory lock and atomic replacement.
final class OpenGameCore: @unchecked Sendable {
    let root: URL
    let fm = FileManager.default
    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenGame")) { self.root = root }
    var catalog: URL { root.appendingPathComponent("library.json") }
    func path(_ part: String) -> URL { root.appendingPathComponent(part) }
    // New installations start empty; existing catalogs are loaded unchanged.
    func initialLibrary() -> Library { Library(bottles:[],games:[]) }
    func load() throws -> Library {
        guard fm.fileExists(atPath:catalog.path) else { return initialLibrary() }
        let lib = try JSONDecoder().decode(Library.self,from:Data(contentsOf:catalog))
        guard lib.schema == 1 else { throw OGError.message("不支持的游戏库版本；原文件已保留。") }
        return lib
    }
    @discardableResult func mutate<T>(_ action: (inout Library) throws -> T) throws -> T {
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let fd = Darwin.open(path("library.lock").path,O_CREAT|O_RDWR,0o600)
        guard fd >= 0 else { throw OGError.message("无法锁定游戏库。") }
        defer { flock(fd,LOCK_UN); Darwin.close(fd) }
        guard flock(fd,LOCK_EX)==0 else { throw OGError.message("游戏库正在被占用。") }
        var lib=try load(); let result=try action(&lib)
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        if fm.fileExists(atPath:catalog.path) { try Data(contentsOf:catalog).write(to:path("library.previous.json"),options:.atomic) }
        try encoder.encode(lib).write(to:catalog,options:.atomic)
        return result
    }
    func ensureCatalog() throws {
        for folder in ["Prefixes", "Logs", "bin", "Engines/SteamCompat"] {
            try fm.createDirectory(at:path(folder),withIntermediateDirectories:true)
        }
        if let resources=Bundle.main.resourceURL {
            for (name,target) in [("OpenGameWindow.exe","bin/OpenGameWindow.exe"),("steamwebhelper.exe","Engines/SteamCompat/steamwebhelper.exe")] {
                let source=resources.appendingPathComponent(name)
                if let data=try? Data(contentsOf:source), (try? Data(contentsOf:path(target))) != data {
                    try data.write(to:path(target),options:.atomic)
                }
            }
        }
        if !fm.fileExists(atPath:catalog.path) { try mutate { _ in } }
    }
    func prefix(_ bottle: Bottle) throws -> URL {
        let url=path(bottle.directory).standardizedFileURL
        let base=root.resolvingSymlinksInPath().path+"/Prefixes/"
        guard url.resolvingSymlinksInPath().path.hasPrefix(base) else { throw OGError.message("容器路径必须位于 OpenGame 的 Prefixes 内。") }
        return url
    }
    func runtime(_ b: Bottle) -> URL {
        let names:[Renderer:String]=[.wine:"WineHQ11",.dxvk:"WineHQ11-DXVK",.dxmt:"WineHQ11-DXMT"]
        let name = b.engineFamily == .foss ? names[b.renderer]!.replacingOccurrences(of:"WineHQ11",with:"WineFOSS11") : names[b.renderer]!
        return path("Engines/"+name+"/bin/wine")
    }
    func environment(_ b: Bottle) throws -> [String:String] {
        var env=ProcessInfo.processInfo.environment
        for k in Array(env.keys) where k.hasPrefix("CX_") || k.hasPrefix("WINE") || k.hasPrefix("DYLD_") || k.hasPrefix("DXVK_") || k.hasPrefix("DXMT_") { env.removeValue(forKey:k) }
        env["WINEPREFIX"]=try prefix(b).path;env["WINEDEBUG"]="-all"
        if b.engineFamily == .foss { env["WINEMSYNC"]="1" }
        env["WINEDLLOVERRIDES"]="winemenubuilder.exe="+(b.renderer == .wine ? "" : ";dxgi,d3d11,d3d10core=b")+(b.renderer == .dxmt ? ";winemetal=b" : "")
        let gst=path("Engines/Support/GStreamer.framework/Versions/1.0")
        env["GST_PLUGIN_PATH"]=gst.appendingPathComponent("lib/gstreamer-1.0").path
        env["GST_PLUGIN_SYSTEM_PATH"]=env["GST_PLUGIN_PATH"]
        env["DYLD_FALLBACK_LIBRARY_PATH"]=gst.appendingPathComponent("lib").path+":"+runtime(b).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib").path+":/usr/lib"
        env["MVK_CONFIG_LOG_LEVEL"]="1";env["DXVK_LOG_PATH"]=path("Logs").path
        env["DXMT_LOG_PATH"]=path("Logs").path
        return env
    }
    // Steam updates restore its helper. After bootstrap, preserve the updated
    // Valve binary and install our parameter-only wrapper before restarting CEF.
    // All process operations use this bottle's WINEPREFIX, never a host-wide kill.
    func watchSteamUI(_ bottle:Bottle) throws {
        let fd=Darwin.open(try prefix(bottle).appendingPathComponent(".opengame-steam-watch.lock").path,O_CREAT|O_RDWR,0o600)
        guard fd>=0 else {throw OGError.message("无法锁定 Steam 界面监控。")}
        defer {flock(fd,LOCK_UN);Darwin.close(fd)}
        guard flock(fd,LOCK_EX|LOCK_NB)==0 else {return}
        let steam=try prefix(bottle).appendingPathComponent("drive_c/Program Files (x86)/Steam")
        let helper=steam.appendingPathComponent("bin/cef/cef.win64/steamwebhelper.exe")
        let wrapper=try Data(contentsOf:path("Engines/SteamCompat/steamwebhelper.exe"))
        guard PEIcon.isExecutable(wrapper) else {throw OGError.message("Steam 界面包装器无效。")}
        var uiBottle=bottle;uiBottle.renderer = .wine
        func command(_ args:[String]) throws -> String {
            let process=Process(),pipe=Pipe()
            process.executableURL=runtime(uiBottle);process.arguments=args
            process.environment=try environment(uiBottle);process.standardInput=FileHandle.nullDevice
            process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
            try process.run()
            _ = try wait(process,timeout:10)
            return String(data:pipe.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
        }
        var previous:Data?
        let deadline=Date().addingTimeInterval(90)
        while Date()<deadline {
            Thread.sleep(forTimeInterval:2)
            guard let current=try? Data(contentsOf:helper),PEIcon.isExecutable(current) else {continue}
            if current==wrapper {previous=nil;continue}
            defer {previous=current}
            guard previous==current else {continue}
            // Only this x64 helper is supported. Leave other architectures alone.
            let offset=(0..<4).reduce(0){$0 | Int(current[60+$1]) << ($1*8)}
            guard current[offset+4]==0x64,current[offset+5]==0x86 else {throw OGError.message("Steam CEF 架构已变化，需要更新兼容组件。")}
            let tasks=try command(["tasklist","/FO","CSV","/NH"])
            guard tasks.lowercased().contains("\"steamwebhelper.exe\"") else {continue}
            let backup=path("Backups/SteamCompat/"+UUID().uuidString)
            try fm.createDirectory(at:backup,withIntermediateDirectories:true)
            try current.write(to:backup.appendingPathComponent("steamwebhelper.exe"),options:.atomic)
            try current.write(to:helper.deletingLastPathComponent().appendingPathComponent("steamwebhelper_real.exe"),options:.atomic)
            try wrapper.write(to:helper,options:.atomic)
            _ = try command(["taskkill","/IM","steamwebhelper.exe","/F"])
            print("Steam CEF 参数包装器已安装；官方文件已备份。")
            return
        }
    }
    func spec(bottle: Bottle, arguments: [String], directory: URL, logID: String, initialized: Bool=true) throws -> LaunchSpec {
        var wine=runtime(bottle)
        guard fm.isExecutableFile(atPath:wine.path) else { throw OGError.message("未找到 Wine 运行库：\(wine.path)") }
        let prefixURL = try prefix(bottle)
        if initialized && !fm.fileExists(atPath:prefixURL.appendingPathComponent("system.reg").path) { throw OGError.message("容器尚未完成初始化。") }
        // Prefixes created before DXMT lack its Wine builtin module placeholder.
        // Register only the missing DXMT bridge; preserve existing game DLLs.
        if initialized && bottle.renderer == .dxmt {
            for (arch,folder) in [("x86_64-windows","system32"),("i386-windows","syswow64")] {
                let target=prefixURL.appendingPathComponent("drive_c/windows/\(folder)/winemetal.dll")
                if !fm.fileExists(atPath:target.path) {
                    let source=runtime(bottle).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine/\(arch)/winemetal.dll")
                    try fm.copyItem(at:source,to:target)
                }
            }
        }
        guard fm.fileExists(atPath:directory.path) else { throw OGError.message("工作文件夹不存在：\(directory.path)") }
        let safeID=logID.replacingOccurrences(of:"/",with:"_")
        var actualArguments=arguments;var env=try environment(bottle)
        if initialized,let first=arguments.first,first.hasPrefix("/"),URL(fileURLWithPath:first).lastPathComponent.lowercased()=="steam.exe" {
            var uiBottle=bottle;uiBottle.renderer = .wine
            wine=runtime(uiBottle);env=try environment(uiBottle)
            env["OPENGAME_STEAM_BOTTLE"]=bottle.id
            if !actualArguments.contains("-cef-disable-gpu") {actualArguments.insert("-cef-disable-gpu",at:1)}
        }
        return LaunchSpec(executable:wine,arguments:actualArguments,directory:directory,environment:env,log:path("Logs/\(safeID).log"))
    }
    func gameSpec(_ game: Game) throws -> LaunchSpec {
        let lib=try load();guard let b=lib.bottles.first(where:{$0.id==game.bottleID}) else { throw OGError.message("游戏对应的容器不存在。") }
        guard fm.fileExists(atPath:game.executable) else { throw OGError.message("游戏文件已移动或不存在：\(game.executable)") }
        let launch=try spec(bottle:b,arguments:[game.executable]+game.arguments,directory:URL(fileURLWithPath:game.workingDirectory),logID:game.id)
        if let appID=game.steamID,URL(fileURLWithPath:game.executable).lastPathComponent.lowercased() != "steam.exe" {
            guard !appID.isEmpty,appID.allSatisfy({$0.isASCII && $0.isNumber}) else {throw OGError.message("Steam 游戏编号无效。")}
            var env=launch.environment;env["SteamAppId"]=appID;env["SteamGameId"]=appID
            return LaunchSpec(executable:launch.executable,arguments:launch.arguments,directory:launch.directory,environment:env,log:launch.log)
        }
        return launch
    }
    func runningGameStatus(_ game:Game) throws -> String? {
        // Steam.exe is a launcher shared by many games, not a game identity.
        guard URL(fileURLWithPath:game.executable).lastPathComponent.lowercased() != "steam.exe" else{return nil}
        guard let bottle=try load().bottles.first(where:{$0.id==game.bottleID}) else{throw OGError.message("游戏对应的容器不存在。")}
        let helper=path("bin/OpenGameWindow.exe")
        guard fm.fileExists(atPath:helper.path) else{throw OGError.message("缺少游戏窗口组件，请重新安装新版 OpenGame。")}
        let drive=try prefix(bottle).appendingPathComponent("drive_c").path+"/"
        let target=game.executable.hasPrefix(drive) ? "C:\\"+String(game.executable.dropFirst(drive.count)).replacingOccurrences(of:"/",with:"\\") : "Z:"+game.executable.replacingOccurrences(of:"/",with:"\\")
        let request=try spec(bottle:bottle,arguments:[helper.path,target],directory:prefix(bottle),logID:"window-"+game.id)
        let code=try wait(start(request),timeout:30)
        switch code {
        case 0:
            _ = try activateNativeGame(game)
            return "\(game.title) 已在运行，已请求显示原游戏窗口。"
        case 2:return nil
        case 3:
            if try activateNativeGame(game) {return "\(game.title) 已在运行，已请求 macOS 显示原游戏窗口。"}
            return "\(game.title) 已在运行；暂时无法置前，请切换到游戏窗口。"
        default:throw OGError.message("检查游戏窗口失败（\(code)），请查看 window-\(game.id).log。")
        }
    }
    private func activateNativeGame(_ game:Game) throws -> Bool {
        // Direct Wine launches retain the absolute game path as their host
        // process name. Match the complete path, never just a common EXE name.
        let process=Process(),output=Pipe()
        process.executableURL=URL(fileURLWithPath:"/bin/ps");process.arguments=["-axo","pid=,comm="]
        process.standardOutput=output;process.standardError=FileHandle.nullDevice
        try process.run()
        let data=output.fileHandleForReading.readDataToEndOfFile()
        guard try wait(process,timeout:3)==0,let text=String(data:data,encoding:.utf8) else{return false}
        for line in text.split(separator:"\n") {
            let fields=line.trimmingCharacters(in:.whitespaces).split(maxSplits:1,whereSeparator:{$0.isWhitespace})
            guard fields.count==2,fields[1]==game.executable,let pid=Int32(fields[0]) else{continue}
            let activate:()->Bool={
                guard let app=NSRunningApplication(processIdentifier:pid) else{return false}
                NSApplication.shared.yieldActivation(to:app)
                return app.activate(from:NSRunningApplication.current,options:[.activateAllWindows])
            }
            return Thread.isMainThread ? activate() : DispatchQueue.main.sync(execute:activate)
        }
        return false
    }
    @discardableResult func start(_ spec: LaunchSpec) throws -> Process {
        try fm.createDirectory(at:spec.log.deletingLastPathComponent(),withIntermediateDirectories:true)
        if !fm.fileExists(atPath:spec.log.path) { fm.createFile(atPath:spec.log.path,contents:nil) }
        let log=try FileHandle(forWritingTo:spec.log);try log.seekToEnd()
        let header="\n[OpenGame \(ISO8601DateFormatter().string(from:Date()))] Runtime: \(spec.executable.path)\n"
        try log.write(contentsOf:Data(header.utf8))
        let p=Process();p.executableURL=spec.executable;p.arguments=spec.arguments;p.environment=spec.environment;p.currentDirectoryURL=spec.directory
        p.standardInput=FileHandle.nullDevice;p.standardOutput=log;p.standardError=log
        do { try p.run() } catch { try? log.close();throw error }
        // Child owns duplicated descriptors after spawn; close the parent's copies.
        if let bottleID=spec.environment["OPENGAME_STEAM_BOTTLE"] {
            let watcher=Process()
            let sibling=URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("OpenGameCLI")
            watcher.executableURL=fm.isExecutableFile(atPath:sibling.path) ? sibling : path("bin/OpenGameCLI")
            watcher.arguments=["steam-watch",bottleID];watcher.standardInput=FileHandle.nullDevice;watcher.standardOutput=log;watcher.standardError=log
            do {try watcher.run()} catch {try? log.write(contentsOf:Data("Steam 界面监控启动失败：\(error.localizedDescription)\n".utf8))}
        }
        try? log.close();return p
    }
    func wait(_ p: Process, timeout: TimeInterval=120) throws -> Int32 {
        let deadline=Date().addingTimeInterval(timeout)
        while p.isRunning && Date()<deadline { Thread.sleep(forTimeInterval:0.1) }
        if p.isRunning { p.terminate();throw OGError.message("操作超时，详情见日志。") }
        return p.terminationStatus
    }
    func createBottle(name: String, renderer: Renderer, engineFamily: EngineFamily = .winehq) throws -> Bottle {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else { throw OGError.message("请输入容器名称。") }
        let id=UUID().uuidString.lowercased();let b=Bottle(id:id,name:name,directory:"Prefixes/\(id)",renderer:renderer,engineFamily:engineFamily)
        let dir=try prefix(b);try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        do {
            let base=try spec(bottle:b,arguments:["wineboot","-u"],directory:dir,logID:"create-\(id)",initialized:false)
            var setupEnv=base.environment;setupEnv["WINEDLLOVERRIDES"]="winemenubuilder.exe=;mscoree,mshtml="
            let p=try start(LaunchSpec(executable:base.executable,arguments:base.arguments,directory:base.directory,environment:setupEnv,log:base.log))
            let code=try wait(p)
            let registry=dir.appendingPathComponent("system.reg")
            let flushDeadline=Date().addingTimeInterval(15)
            while code==0 && !fm.fileExists(atPath:registry.path) && Date()<flushDeadline { Thread.sleep(forTimeInterval:0.1) }
            guard code==0 && fm.fileExists(atPath:dir.appendingPathComponent("system.reg").path) else { throw OGError.message("容器初始化失败（\(code)），日志已保留。") }
            let users=dir.appendingPathComponent("drive_c/users")
            for user in (try? fm.contentsOfDirectory(at:users,includingPropertiesForKeys:nil)) ?? [] {
                for entry in (try? fm.contentsOfDirectory(at:user,includingPropertiesForKeys:[.isSymbolicLinkKey])) ?? [] {
                    if (try? entry.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink)==true {
                        try fm.removeItem(at:entry);try fm.createDirectory(at:entry,withIntermediateDirectories:true)
                    }
                }
            }
            try mutate { lib in lib.bottles.append(b) };return b
        } catch { // Keep failed prefix and log for diagnosis; do not add an unusable catalog entry.
            throw error
        }
    }
    func updateBottle(_ bottle:Bottle) throws {
        guard !bottle.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw OGError.message("请输入容器名称。")}
        guard fm.isExecutableFile(atPath:runtime(bottle).path) else{throw OGError.message("此图形后端尚未安装。")}
        if let existing=try load().bottles.first(where:{$0.id==bottle.id}), (existing.engineFamily ?? .winehq) != (bottle.engineFamily ?? .winehq) {
            let idle=Process();idle.executableURL=runtime(existing).deletingLastPathComponent().appendingPathComponent("wineserver");idle.arguments=["-w"];idle.environment=try environment(existing);idle.standardOutput=FileHandle.nullDevice;idle.standardError=FileHandle.nullDevice
            try idle.run()
            do { guard try wait(idle,timeout:2)==0 else { throw OGError.message("无法确认容器状态。") } }
            catch { throw OGError.message("请先退出此容器的游戏、Steam 和 Wine 工具，再切换运行核心。") }
        }
        try mutate { lib in
            guard let i=lib.bottles.firstIndex(where:{$0.id==bottle.id}),lib.bottles[i].directory==bottle.directory else{throw OGError.message("容器不存在或路径已更改。")}
            lib.bottles[i]=bottle
        }
    }
    func copyBottle(_ source:Bottle,name:String) throws -> Bottle {
        let label=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !label.isEmpty else{throw OGError.message("请输入副本名称。")}
        let from=try prefix(source)
        guard fm.fileExists(atPath:from.appendingPathComponent("system.reg").path) else{throw OGError.message("源容器尚未初始化。")}
        // Wait-only helper: never terminates the user's Wine server or games.
        let idle=Process();idle.executableURL=runtime(source).deletingLastPathComponent().appendingPathComponent("wineserver");idle.arguments=["-w"];idle.environment=try environment(source);idle.standardOutput=FileHandle.nullDevice;idle.standardError=FileHandle.nullDevice
        try idle.run()
        do{guard try wait(idle,timeout:2)==0 else{throw OGError.message("无法确认容器状态。")}}
        catch{throw OGError.message("请先退出此容器内的游戏、Steam 和 Wine 工具，稍后再复制。")}
        let id=UUID().uuidString.lowercased();let copied=Bottle(id:id,name:label,directory:"Prefixes/\(id)",renderer:source.renderer,engineFamily:source.engineFamily)
        let to=try prefix(copied)
        let operation=LaunchSpec(executable:URL(fileURLWithPath:"/bin/cp"),arguments:["-cR",from.path,to.path],directory:root,environment:ProcessInfo.processInfo.environment,log:path("Logs/copy-\(id).log"))
        let p=try start(operation)
        guard try wait(p,timeout:300)==0,fm.fileExists(atPath:to.appendingPathComponent("system.reg").path) else{throw OGError.message("容器复制未完成；源容器保留，详情见日志。")}
        func remap(_ value:String)->String {value == from.path || value.hasPrefix(from.path+"/") ? to.path+value.dropFirst(from.path.count) : value}
        try mutate { lib in
            guard lib.bottles.contains(where:{$0==source}) else{throw OGError.message("源容器配置已变化，请刷新后重试。")}
            let games=lib.games.filter{$0.bottleID==source.id}.map{game -> Game in
                var g=game;g.id=UUID().uuidString.lowercased();g.bottleID=id;g.executable=remap(g.executable);g.workingDirectory=remap(g.workingDirectory);g.note="容器副本 · 待验证兼容性";return g
            }
            lib.bottles.append(copied);lib.games.append(contentsOf:games)
        }
        return copied
    }
    func importGame(executable: URL,title: String,bottleID: String,arguments: [String]=[]) throws -> Game {
        guard executable.pathExtension.lowercased()=="exe",fm.fileExists(atPath:executable.path) else { throw OGError.message("请选择现有的 Windows EXE 游戏文件。") }
        let data=try Data(contentsOf:executable,options:.mappedIfSafe)
        guard PEIcon.isExecutable(data) else { throw OGError.message("此文件不是支持的 Windows PE 可执行文件。") }
        let id=UUID().uuidString.lowercased();var icon:String?
        if let ico=try? PEIcon.extract(data) { try fm.createDirectory(at:path("Icons"),withIntermediateDirectories:true);icon="Icons/\(id).ico";try ico.write(to:path(icon!),options:.atomic) }
        let label=title.trimmingCharacters(in:.whitespacesAndNewlines)
        let game=Game(id:id,title:label.isEmpty ? executable.deletingPathExtension().lastPathComponent : label,bottleID:bottleID,executable:executable.path,arguments:arguments,workingDirectory:executable.deletingLastPathComponent().path,icon:icon,steamID:nil,note:"已添加 · 待验证兼容性")
        try mutate { lib in
            guard lib.bottles.contains(where:{$0.id==bottleID}) else { throw OGError.message("请选择有效的容器。") }
            guard !lib.games.contains(where:{$0.bottleID==bottleID && $0.executable==game.executable && $0.steamID==nil}) else { throw OGError.message("此游戏已添加到该容器。") }
            lib.games.append(game)
        };return game
    }
    func updateGame(_ game: Game) throws {
        try mutate { lib in
            guard let i=lib.games.firstIndex(where:{$0.id==game.id}) else { throw OGError.message("游戏已被移除。") }
            guard lib.bottles.contains(where:{$0.id==game.bottleID}) else { throw OGError.message("容器不存在。") }
            guard !game.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw OGError.message("请输入游戏名称。") }
            var updated=game
            if lib.games[i].executable != game.executable {
                let data=try Data(contentsOf:URL(fileURLWithPath:game.executable),options:.mappedIfSafe)
                guard PEIcon.isExecutable(data) else { throw OGError.message("此文件不是支持的 Windows PE 可执行文件。") }
                updated.icon=nil
                if let ico=try? PEIcon.extract(data) { try fm.createDirectory(at:path("Icons"),withIntermediateDirectories:true);updated.icon="Icons/\(game.id).ico";try ico.write(to:path(updated.icon!),options:.atomic) }
            }
            lib.games[i]=updated
        }
    }
    func removeGame(_ id: String) throws { try mutate { $0.games.removeAll(where:{$0.id==id}) } }
    func installerSpec(file: URL,bottle: Bottle) throws -> LaunchSpec {
        guard ["exe","msi"].contains(file.pathExtension.lowercased()),fm.fileExists(atPath:file.path) else { throw OGError.message("请选择 EXE 或 MSI 安装程序。") }
        let args=file.pathExtension.lowercased()=="msi" ? ["msiexec","/i",file.path] : [file.path]
        return try spec(bottle:bottle,arguments:args,directory:file.deletingLastPathComponent(),logID:"installer-\(bottle.id)")
    }
    func toolSpec(bottle: Bottle,tool: String) throws -> LaunchSpec {
        let tools:[String:[String]]=["winecfg":["winecfg"],"regedit":["regedit"],"taskmgr":["taskmgr"],"controllers":["control","joy.cpl"],"uninstall":["uninstaller"]]
        guard let args=tools[tool] else { throw OGError.message("未知的容器工具。") }
        return try spec(bottle:bottle,arguments:args,directory:prefix(bottle),logID:"tool-\(bottle.id)-\(tool)")
    }
    func scanSteam(bottle: Bottle) throws -> Int {
        let steam=try prefix(bottle).appendingPathComponent("drive_c/Program Files (x86)/Steam")
        let exe=steam.appendingPathComponent("steam.exe")
        guard fm.fileExists(atPath:exe.path) else { throw OGError.message("此容器的默认路径下没有 Steam。可通过“运行安装程序”安装。") }
        let apps=steam.appendingPathComponent("steamapps")
        var found:[Game]=[]
        for file in try fm.contentsOfDirectory(at:apps,includingPropertiesForKeys:nil) where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension=="acf" {
            let text=try String(contentsOf:file,encoding:.utf8)
            func value(_ key:String)->String? {
                let p="\""+NSRegularExpression.escapedPattern(for:key)+"\"\\s+\"([^\"]*)\""
                guard let r=try? NSRegularExpression(pattern:p),let m=r.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(m.range(at:1),in:text) else{return nil};return String(text[range])
            }
            guard let appid=value("appid"),!appid.isEmpty,appid.allSatisfy({$0.isNumber}),let name=value("name"),let install=value("installdir"),value("StateFlags")=="4" else { continue }
            let folder=apps.appendingPathComponent("common").appendingPathComponent(install).standardizedFileURL
            guard folder.path.hasPrefix(apps.appendingPathComponent("common").path+"/"),fm.fileExists(atPath:folder.path) else { continue }
            let id="steam-\(bottle.id)-\(appid)";var icon:String?
            let cache=steam.appendingPathComponent("appcache/librarycache/\(appid)")
            if let files=try? fm.contentsOfDirectory(at:cache,includingPropertiesForKeys:nil) {
                for f in files.sorted(by:{$0.lastPathComponent<$1.lastPathComponent}) where ["jpg","png"].contains(f.pathExtension) {
                    if let image=NSImage(contentsOf:f),image.size.width==image.size.height,image.size.width<=256 {
                        icon="Icons/\(id).\(f.pathExtension)";try fm.createDirectory(at:path("Icons"),withIntermediateDirectories:true);try Data(contentsOf:f).write(to:path(icon!),options:.atomic);break
                    }
                }
            }
            found.append(Game(id:id,title:name,bottleID:bottle.id,executable:exe.path,arguments:["-applaunch",appid],workingDirectory:steam.path,icon:icon,steamID:appid,note:"Steam 已安装 · 待验证兼容性"))
        }
        return try mutate { lib in
            var count=0
            for game in found where !lib.games.contains(where:{$0.bottleID==game.bottleID && $0.steamID==game.steamID}) { lib.games.append(game);count+=1 }
            return count
        }
    }
}

// Resource-only PE parser: never executes the file and checks every offset before reading.
enum PEIcon {
    static func isExecutable(_ d:Data)->Bool {
        guard d.count>=64,d[0]==0x4d,d[1]==0x5a else{return false}
        let pe=(0..<4).reduce(0){$0 | Int(d[0x3c+$1])<<($1*8)}
        guard pe>=64,pe+26<=d.count,d[pe]==0x50,d[pe+1]==0x45,d[pe+2]==0,d[pe+3]==0 else{return false}
        let magic=Int(d[pe+24])|Int(d[pe+25])<<8
        return magic==0x10b || magic==0x20b
    }
    static func extract(_ d: Data) throws -> Data {
        func fail() -> OGError { .message("EXE 中没有可读取的图标资源。") }
        func u16(_ o:Int)throws->Int { guard o>=0,o+2<=d.count else {throw fail()};return Int(d[o])|Int(d[o+1])<<8 }
        func u32(_ o:Int)throws->Int { guard o>=0,o+4<=d.count else {throw fail()};return Int(d[o])|Int(d[o+1])<<8|Int(d[o+2])<<16|Int(d[o+3])<<24 }
        let pe=try u32(0x3c);guard try u32(pe)==0x4550 else {throw fail()}
        let opt=pe+24,magic=try u16(opt),count=try u16(pe+6),optSize=try u16(pe+20)
        guard magic==0x10b || magic==0x20b,count<100 else {throw fail()}
        let directories=opt+(magic==0x20b ? 112 : 96),resourceRVA=try u32(directories+16)
        func offset(_ rva:Int)throws->Int {
            for i in 0..<count {let s=opt+optSize+i*40;let va=try u32(s+12),size=try u32(s+16),raw=try u32(s+20)
                if rva>=va && rva-va<size {let o=raw+rva-va;guard o<d.count else{throw fail()};return o}}
            throw fail()
        }
        let root=try offset(resourceRVA)
        func entries(_ rel:Int)throws->[(Int,Int)] {
            let base=root+rel;let names=try u16(base+12),ids=try u16(base+14)
            guard names+ids<4096 else {throw fail()};var result:[(Int,Int)]=[]
            for i in 0..<(names+ids) {let o=base+16+i*8;let id=try u32(o),dest=try u32(o+4);if id&0x80000000==0 {result.append((id,dest))}}
            return result
        }
        func payload(_ entry:Int)throws->Data {
            var entry=entry
            for _ in 0..<4 {
                if entry&0x80000000==0 {let o=root+entry;let rva=try u32(o),length=try u32(o+4),start=try offset(rva);guard length>0,length<16*1024*1024,start+length<=d.count else{throw fail()};return d.subdata(in:start..<start+length)}
                guard let next=try entries(entry&0x7fffffff).first else{throw fail()};entry=next.1
            };throw fail()
        }
        let top=try entries(0);guard let groups=top.first(where:{$0.0==14}),let icons=top.first(where:{$0.0==3}) else {throw fail()}
        guard let group=try entries(groups.1&0x7fffffff).first else{throw fail()}
        let g=try payload(group.1);guard g.count>=6 else{throw fail()}
        func g16(_ o:Int)throws->Int {guard o+2<=g.count else{throw fail()};return Int(g[o])|Int(g[o+1])<<8}
        let n=try g16(4);guard n>0,n<=256,g.count>=6+n*14 else{throw fail()}
        let imageEntries=try entries(icons.1&0x7fffffff);var header=Data([0,0,1,0,UInt8(n&255),UInt8(n>>8)]),body=Data();var pos=6+n*16
        func le32(_ x:Int)->[UInt8] {(0..<4).map{UInt8((x>>($0*8))&255)}}
        for i in 0..<n {let o=6+i*14,id=try g16(o+12);guard let image=imageEntries.first(where:{$0.0==id}) else{throw fail()};let bytes=try payload(image.1);header.append(g.subdata(in:o..<o+8));header.append(contentsOf:le32(bytes.count));header.append(contentsOf:le32(pos));body.append(bytes);pos+=bytes.count}
        header.append(body);return header
    }
}
