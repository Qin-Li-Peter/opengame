import Foundation
import AppKit
import CryptoKit
import Darwin

enum OGError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum Renderer: String, Codable, CaseIterable { case wine, dxvk, dxmt
    var label: String { switch self {case .wine:return "Wine · 旧游戏 / 2D";case .dxvk:return "DXVK · DirectX 10/11";case .dxmt:return "DXMT · DirectX 10/11 → Metal"} }
}
enum EngineFamily: String, Codable, CaseIterable { case winehq, foss
    var label: String { self == .foss ? "Wine FOSS 11 + MSync（推荐）" : "WineHQ 11（兼容旧容器）" }
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
struct RecipeStep:Codable {var file:String;var url:String;var sha256:String;var arguments:[String]}
struct InstallRecipe:Codable,Identifiable {var id:String;var name:String;var summary:String;var steps:[RecipeStep]}
struct RecipeCatalog:Codable {var schema:Int;var recipes:[InstallRecipe]}
// Immutable service state; catalog writes use an advisory lock and atomic replacement.
final class OpenGameCore: @unchecked Sendable {
    let root: URL
    let fm = FileManager.default
    private let processLock=NSLock()
    private var acceptingLaunches=true
    private var children:[Process]=[]
    private var watchers:[Process]=[]
    private var sessionSpecs:[String:LaunchSpec]=[:]
    init(root: URL? = nil) {
        if let root=root {self.root=root}
        else if let override=ProcessInfo.processInfo.environment["OPENGAME_ROOT"],override.hasPrefix("/") {self.root=URL(fileURLWithPath:override)}
        else {self.root=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenGame")}
    }
    var catalog: URL { root.appendingPathComponent("library.json") }
    func path(_ part: String) -> URL { root.appendingPathComponent(part) }
    var bundledRuntimeRoot: URL? {
        guard let resources=Bundle.main.resourceURL else{return nil}
        let candidate=resources.appendingPathComponent("Runtime")
        return fm.fileExists(atPath:candidate.appendingPathComponent("Engines/WineFOSS11/bin/wine").path) ? candidate : nil
    }
    var activeRuntimeRoot: URL { bundledRuntimeRoot ?? root }
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
        if b.engineFamily == .foss {
            return activeRuntimeRoot.appendingPathComponent("Engines/WineFOSS11/bin/wine")
        }
        let names:[Renderer:String]=[.wine:"WineHQ11",.dxvk:"WineHQ11-DXVK",.dxmt:"WineHQ11-DXMT"]
        return path("Engines/"+names[b.renderer]!+"/bin/wine")
    }
    func rendererPack(_ renderer:Renderer) -> URL? {
        guard renderer != .wine else{return nil}
        let bundled=activeRuntimeRoot.appendingPathComponent("RendererPacks/"+renderer.rawValue)
        if fm.fileExists(atPath:bundled.path){return bundled}
        let legacy=path("Engines/WineFOSS11-"+renderer.rawValue.uppercased()+"/lib/wine")
        return fm.fileExists(atPath:legacy.path) ? legacy : nil
    }
    func runtimeStatus() -> String {
        let source=bundledRuntimeRoot == nil ? "用户运行目录" : "OpenGame.app"
        let wine=activeRuntimeRoot.appendingPathComponent("Engines/WineFOSS11/bin/wine")
        guard fm.isExecutableFile(atPath:wine.path) else{return "未安装完整 Wine FOSS 运行核心"}
        let renderers=[Renderer.dxmt,Renderer.dxvk].compactMap{rendererPack($0)==nil ? nil : $0.rawValue.uppercased()}.joined(separator:" / ")
        let gst=activeRuntimeRoot.appendingPathComponent("Engines/Support/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0")
        let bridge=activeRuntimeRoot.appendingPathComponent("Engines/WineFOSS11/lib/wine/x86_64-unix/winegstreamer.so")
        let video=fm.fileExists(atPath:gst.path) && fm.fileExists(atPath:bridge.path) ? "Wine 视频桥接已启用" : "不含完整视频组件"
        return "完整核心来自\(source) · \(renderers.isEmpty ? "无图形增量包" : renderers) · \(video)"
    }
    func availableRecipes() throws -> [InstallRecipe] {
        guard let resource=Bundle.main.resourceURL?.appendingPathComponent("Recipes/catalog.json"),fm.fileExists(atPath:resource.path) else{throw OGError.message("安装配方未随应用提供。")}
        let catalog=try JSONDecoder().decode(RecipeCatalog.self,from:Data(contentsOf:resource))
        guard catalog.schema==1 else{throw OGError.message("不支持的安装配方版本。")}
        return catalog.recipes
    }
    func installRecipe(_ recipe:InstallRecipe,in bottle:Bottle,progress:(String)->Void) throws {
        try idleBottle(bottle)
        let allowedHosts=Set(["cdn.akamai.steamstatic.com","aka.ms","download.microsoft.com"])
        let downloads=path("Downloads/"+recipe.id);try fm.createDirectory(at:downloads,withIntermediateDirectories:true)
        for (index,step) in recipe.steps.enumerated() {
            guard let url=URL(string:step.url),url.scheme=="https",let host=url.host,allowedHosts.contains(host),URL(fileURLWithPath:step.file).lastPathComponent==step.file else{throw OGError.message("配方包含未授权的下载地址或文件名。")}
            let target=downloads.appendingPathComponent(step.file)
            progress("正在下载 \(recipe.name)（\(index+1)/\(recipe.steps.count)）…")
            var data:Data
            if let existing=try? Data(contentsOf:target),SHA256.hash(data:existing).map({String(format:"%02x",$0)}).joined()==step.sha256 {data=existing}
            else {
                data=try Data(contentsOf:url,options:.mappedIfSafe)
                let digest=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
                guard digest==step.sha256 else{throw OGError.message("\(step.file) 校验失败；官方文件可能已更新，请先更新 OpenGame 配方。")}
                try data.write(to:target,options:.atomic)
            }
            guard PEIcon.isExecutable(data) else{throw OGError.message("下载的 \(step.file) 不是 Windows 可执行文件。")}
            progress("正在安装 \(recipe.name)（\(index+1)/\(recipe.steps.count)）…")
            let request=try spec(bottle:bottle,arguments:[target.path]+step.arguments,directory:downloads,logID:"recipe-\(bottle.id)-\(recipe.id)-\(index)")
            let code=try wait(start(request),timeout:1800)
            guard code==0 || code==194 else{throw OGError.message("\(recipe.name) 安装程序返回 \(code)，请查看日志。")}
        }
        let stamp=try prefix(bottle).appendingPathComponent(".opengame-dependencies/"+recipe.id+".json")
        try fm.createDirectory(at:stamp.deletingLastPathComponent(),withIntermediateDirectories:true)
        let record=["recipe":recipe.id,"installed_at":ISO8601DateFormatter().string(from:Date())]
        try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]).write(to:stamp,options:.atomic)
    }
    func environment(_ b: Bottle) throws -> [String:String] {
        var env=ProcessInfo.processInfo.environment
        for k in Array(env.keys) where k.hasPrefix("CX_") || k.hasPrefix("WINE") || k.hasPrefix("DYLD_") || k.hasPrefix("DXVK_") || k.hasPrefix("DXMT_") { env.removeValue(forKey:k) }
        env["WINEPREFIX"]=try prefix(b).path;env["WINEDEBUG"]="-all"
        if b.engineFamily == .foss { env["WINEMSYNC"]="1" }
        env["WINEDLLOVERRIDES"]="winemenubuilder.exe="+(b.renderer == .wine ? "" : ";dxgi,d3d11,d3d10core=b")+(b.renderer == .dxmt ? ";winemetal=b" : "")
        let gst=activeRuntimeRoot.appendingPathComponent("Engines/Support/GStreamer.framework/Versions/1.0")
        env["GST_PLUGIN_PATH"]=gst.appendingPathComponent("lib/gstreamer-1.0").path
        env["GST_PLUGIN_SYSTEM_PATH"]=env["GST_PLUGIN_PATH"]
        env["DYLD_FALLBACK_LIBRARY_PATH"]=gst.appendingPathComponent("lib").path+":"+runtime(b).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib").path+":/usr/lib"
        env["MVK_CONFIG_LOG_LEVEL"]="1";env["DXVK_LOG_PATH"]=path("Logs").path
        env["DXMT_LOG_PATH"]=path("Logs").path
        return env
    }
    private func ensureRendererFiles(_ bottle:Bottle) throws {
        guard bottle.engineFamily == .foss,bottle.renderer != .wine else{return}
        guard let pack=rendererPack(bottle.renderer) else{throw OGError.message("尚未安装 \(bottle.renderer.rawValue.uppercased()) 图形增量包。")}
        let prefixURL=try prefix(bottle)
        let stamp=prefixURL.appendingPathComponent(".opengame-renderer")
        let desired=bottle.renderer.rawValue+"\n"
        if (try? String(contentsOf:stamp,encoding:.utf8))==desired{return}
        let backup=prefixURL.appendingPathComponent(".opengame-renderer-backup")
        for (arch,folder) in [("x86_64-windows","system32"),("i386-windows","syswow64")] {
            for name in ["d3d10core.dll","d3d11.dll","dxgi.dll"] {
                let source=pack.appendingPathComponent("\(arch)/\(name)")
                guard fm.fileExists(atPath:source.path) else{throw OGError.message("图形增量包不完整：\(source.lastPathComponent)（\(arch)）")}
                let target=prefixURL.appendingPathComponent("drive_c/windows/\(folder)/\(name)")
                let saved=backup.appendingPathComponent("\(folder)/\(name)")
                if !fm.fileExists(atPath:saved.path),fm.fileExists(atPath:target.path) {
                    try fm.createDirectory(at:saved.deletingLastPathComponent(),withIntermediateDirectories:true)
                    try fm.copyItem(at:target,to:saved)
                }
                try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                let temporary=target.deletingLastPathComponent().appendingPathComponent(".\(name).opengame-\(UUID().uuidString)")
                try fm.copyItem(at:source,to:temporary)
                if fm.fileExists(atPath:target.path){try fm.removeItem(at:target)}
                try fm.moveItem(at:temporary,to:target)
            }
        }
        try desired.write(to:stamp,atomically:true,encoding:.utf8)
    }
    private func prepareBundledFonts(_ bottle:Bottle) throws -> Bool {
        let source=activeRuntimeRoot.appendingPathComponent("Fonts/Liberation")
        guard fm.fileExists(atPath:source.path) else{return false}
        let destination=try prefix(bottle).appendingPathComponent("drive_c/windows/Fonts")
        try fm.createDirectory(at:destination,withIntermediateDirectories:true)
        for file in try fm.contentsOfDirectory(at:source,includingPropertiesForKeys:nil) where file.pathExtension.lowercased()=="ttf" {
            let target=destination.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath:target.path){try fm.copyItem(at:file,to:target)}
        }
        return true
    }
    private func registerBundledFonts(_ bottle:Bottle) throws {
        guard try prepareBundledFonts(bottle) else{return}
        let marker=try prefix(bottle).appendingPathComponent(".opengame-fonts")
        guard !fm.fileExists(atPath:marker.path) else{return}
        let registry=try prefix(bottle).appendingPathComponent("opengame-fonts.reg")
        let content="""
        REGEDIT4

        [HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts]
        "Liberation Sans (TrueType)"="LiberationSans-Regular.ttf"
        "Liberation Serif (TrueType)"="LiberationSerif-Regular.ttf"
        "Liberation Mono (TrueType)"="LiberationMono-Regular.ttf"

        [HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes]
        "Arial"="Liberation Sans"
        "Times New Roman"="Liberation Serif"
        "Courier New"="Liberation Mono"
        """
        try content.write(to:registry,atomically:true,encoding:.utf8)
        let process=Process();process.executableURL=runtime(bottle);process.arguments=["regedit","/S",registry.path];process.environment=try environment(bottle);process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        try process.run();guard try wait(process,timeout:30)==0 else{throw OGError.message("字体注册失败。")}
        try? fm.removeItem(at:registry);try "Liberation 2.1.5\n".write(to:marker,atomically:true,encoding:.utf8)
    }
    // Steam updates restore its helper. After bootstrap, preserve the updated
    // Valve binary and install our parameter-only wrapper before restarting CEF.
    // All process operations use this bottle's WINEPREFIX, never a host-wide kill.
    func watchSteamUI(_ bottle:Bottle) throws {
        guard !hasClosingMarker() else{return}
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
            guard !hasClosingMarker() else{throw OGError.message("OpenGame 正在退出。") }
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
            guard !hasClosingMarker() else{return}
            guard let current=try? Data(contentsOf:helper),PEIcon.isExecutable(current) else {continue}
            if current==wrapper {previous=nil;continue}
            defer {previous=current}
            guard previous==current else {continue}
            // Only this x64 helper is supported. Leave other architectures alone.
            let offset=(0..<4).reduce(0){$0 | Int(current[60+$1]) << ($1*8)}
            guard current[offset+4]==0x64,current[offset+5]==0x86 else {throw OGError.message("Steam CEF 架构已变化，需要更新兼容组件。")}
            let tasks=try command(["tasklist","/FO","CSV","/NH"])
            guard tasks.lowercased().contains("\"steamwebhelper.exe\"") else {continue}
            guard !hasClosingMarker() else{return}
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
        if initialized {try ensureRendererFiles(bottle)}
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
            var env=launch.environment;env["SteamAppId"]=appID;env["SteamGameId"]=appID;env["OPENGAME_STEAM_BOTTLE"]=b.id
            return LaunchSpec(executable:launch.executable,arguments:launch.arguments,directory:launch.directory,environment:env,log:launch.log)
        }
        return launch
    }
    func prepareSteam(for game:Game) throws {
        guard game.steamID != nil,URL(fileURLWithPath:game.executable).lastPathComponent.lowercased() != "steam.exe" else{return}
        let lib=try load();guard let bottle=lib.bottles.first(where:{$0.id==game.bottleID}) else{throw OGError.message("游戏对应的容器不存在。")}
        let steam=try prefix(bottle).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
        guard fm.fileExists(atPath:steam.path) else{return}
        let request=try spec(bottle:bottle,arguments:[steam.path],directory:steam.deletingLastPathComponent(),logID:"steam-"+bottle.id)
        func running() -> Bool {
            ((try? windowsTaskNames(request)) ?? []).contains("steam.exe") || ((try? nativeWindowsTaskNames()) ?? []).contains("steam.exe")
        }
        if running(){return}
        _=try start(request)
        let deadline=Date().addingTimeInterval(35)
        while Date()<deadline {
            if running(){Thread.sleep(forTimeInterval:2);return}
            Thread.sleep(forTimeInterval:0.5)
        }
        throw OGError.message("Steam 启动超时，请先打开 Steam 后重试。")
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
        processLock.lock();defer{processLock.unlock()}
        guard acceptingLaunches && !hasClosingMarker() else{throw OGError.message("OpenGame 正在退出，暂时不能启动程序。")}
        if let prefix=spec.environment["WINEPREFIX"] {
            let candidate=URL(fileURLWithPath:prefix).resolvingSymlinksInPath().path
            guard candidate.hasPrefix(root.resolvingSymlinksInPath().path+"/Prefixes/") else{throw OGError.message("拒绝管理 OpenGame 之外的容器。")}
            sessionSpecs[candidate]=spec
        }
        try fm.createDirectory(at:spec.log.deletingLastPathComponent(),withIntermediateDirectories:true)
        if !fm.fileExists(atPath:spec.log.path) { fm.createFile(atPath:spec.log.path,contents:nil) }
        let log=try FileHandle(forWritingTo:spec.log);try log.seekToEnd()
        let header="\n[OpenGame \(ISO8601DateFormatter().string(from:Date()))] Runtime: \(spec.executable.path)\n"
        try log.write(contentsOf:Data(header.utf8))
        let p=Process();p.executableURL=spec.executable;p.arguments=spec.arguments;p.environment=spec.environment;p.currentDirectoryURL=spec.directory
        p.standardInput=FileHandle.nullDevice;p.standardOutput=log;p.standardError=log
        do { try p.run() } catch { try? log.close();throw error }
        children.removeAll{!$0.isRunning};children.append(p)
        // Child owns duplicated descriptors after spawn; close the parent's copies.
        if let bottleID=spec.environment["OPENGAME_STEAM_BOTTLE"] {
            let watcher=Process()
            let sibling=URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("OpenGameCLI")
            watcher.executableURL=fm.isExecutableFile(atPath:sibling.path) ? sibling : path("bin/OpenGameCLI")
            watcher.arguments=["steam-watch",bottleID];watcher.standardInput=FileHandle.nullDevice;watcher.standardOutput=log;watcher.standardError=log
            do {try watcher.run();watchers.removeAll{!$0.isRunning};watchers.append(watcher)} catch {try? log.write(contentsOf:Data("Steam 界面监控启动失败：\(error.localizedDescription)\n".utf8))}
        }
        try? log.close();return p
    }
    // Cross-process marker also stops helpers launched by an earlier app version.
    private var closingMarker:URL {path(".application-closing")}
    private func hasClosingMarker() -> Bool {
        guard let text=try? String(contentsOf:closingMarker,encoding:.utf8),let pid=Int32(text.trimmingCharacters(in:.whitespacesAndNewlines)) else{return false}
        return Darwin.kill(pid,0)==0 || errno==EPERM
    }
    func resumeLaunches() {
        processLock.lock();defer{processLock.unlock()}
        acceptingLaunches=true
        try? fm.removeItem(at:closingMarker)
    }
    private func shutdownCommand(_ executable:URL,_ arguments:[String],_ environment:[String:String],timeout:TimeInterval) throws -> Int32 {
        try fm.createDirectory(at:path("Logs"),withIntermediateDirectories:true)
        let destination=path("Logs/shutdown.log")
        if !fm.fileExists(atPath:destination.path){fm.createFile(atPath:destination.path,contents:nil)}
        let log=try FileHandle(forWritingTo:destination);defer{try? log.close()};try log.seekToEnd()
        try log.write(contentsOf:Data(("\n["+ISO8601DateFormatter().string(from:Date())+"] "+(environment["WINEPREFIX"] ?? "")+" "+executable.lastPathComponent+" "+arguments.joined(separator:" ")+"\n").utf8))
        let p=Process();p.executableURL=executable;p.arguments=arguments;p.environment=environment
        p.standardInput=FileHandle.nullDevice;p.standardOutput=log;p.standardError=log
        try p.run()
        do {return try wait(p,timeout:timeout)}
        catch {
            // A timed-out shutdown helper must not complete later after Cancel.
            if p.isRunning {Darwin.kill(p.processIdentifier,SIGKILL);p.waitUntilExit()}
            throw error
        }
    }
    private func windowsTaskNames(_ spec:LaunchSpec) throws -> [String] {
        let helper=path("bin/OpenGameWindow.exe")
        var names=Set<String>()
        // Wine's process snapshot can briefly lag a just-detached child. Merge a
        // few bounded snapshots so Command-Q immediately after launch remains safe.
        for attempt in 0..<3 {
            if attempt>0 {Thread.sleep(forTimeInterval:0.2)}
            let p=Process(),output=Pipe()
            p.executableURL=spec.executable
            p.arguments=fm.fileExists(atPath:helper.path) ? [helper.path,"--list"] : ["tasklist","/FO","CSV","/NH"]
            p.environment=spec.environment
            p.standardInput=FileHandle.nullDevice;p.standardOutput=output;p.standardError=FileHandle.nullDevice
            try p.run()
            let data=output.fileHandleForReading.readDataToEndOfFile()
            guard try wait(p,timeout:5)==0,let text=String(data:data,encoding:.utf8) else{continue}
            for line in text.split(separator:"\n") {
                guard line.first=="\"",let end=line.dropFirst().firstIndex(of:"\"") else{continue}
                names.insert(String(line[line.index(after:line.startIndex)..<end]).lowercased())
            }
        }
        return names.sorted()
    }
    private func writeShutdownNote(_ text:String) {
        let destination=path("Logs/shutdown.log")
        if let log=try? FileHandle(forWritingTo:destination) {
            _ = try? log.seekToEnd()
            _ = try? log.write(contentsOf:Data((text+"\n").utf8))
            _ = try? log.close()
        }
    }
    private func nativeWindowsTaskNames() throws -> [String] {
        let p=Process(),output=Pipe()
        p.executableURL=URL(fileURLWithPath:"/bin/ps");p.arguments=["-axo","comm="]
        p.standardInput=FileHandle.nullDevice;p.standardOutput=output;p.standardError=FileHandle.nullDevice
        try p.run()
        let data=output.fileHandleForReading.readDataToEndOfFile()
        guard try wait(p,timeout:3)==0,let text=String(data:data,encoding:.utf8) else{return []}
        let expression=try NSRegularExpression(pattern:"(?i)([a-z0-9_.-]+\\.exe)(?:\\s|$)")
        var names=Set<String>()
        for line in text.split(separator:"\n") {
            let value=String(line),range=NSRange(value.startIndex...,in:value)
            guard let match=expression.firstMatch(in:value,range:range),let capture=Range(match.range(at:1),in:value) else{continue}
            names.insert(String(value[capture]).lowercased())
        }
        return names.sorted()
    }
    private func closeResidualSteamHelpers(_ spec:LaunchSpec,fallback:[String]) throws -> Bool {
        let infrastructure:Set<String>=["services.exe","explorer.exe","rpcss.exe","svchost.exe","winedevice.exe","plugplay.exe","conhost.exe","start.exe","tasklist.exe","wineboot.exe","winedbg.exe","steamservice.exe"]
        let helpers:Set<String>=["steam.exe","steamwebhelper.exe","steamwebhelper_real.exe","steamerrorreporter.exe","steamerrorreporter64.exe","unitycrashhandler64.exe"]
        let current=try windowsTaskNames(spec)
        var currentTasks=Set(current)
        // Steam's CEF crash reporter can outlive its Wine process-table entry.
        // Native process names let us distinguish that known residue from a
        // still-running game after Steam has accepted the end-session request.
        if spec.environment["OPENGAME_STEAM_BOTTLE"] != nil {
            currentTasks.formUnion(try nativeWindowsTaskNames())
        }
        // A crashed helper can disappear from Wine's task table while its host
        // process is still alive. In that state use the pre-shutdown snapshot;
        // it also prevents a game that vetoed shutdown from being misclassified.
        let tasks=currentTasks.subtracting(infrastructure).isEmpty ? Set(fallback) : currentTasks
        writeShutdownNote("Remaining Windows tasks: "+tasks.sorted().joined(separator:", "))
        let blockers=tasks.subtracting(infrastructure).subtracting(helpers)
        // Only use this recovery path when a known Steam helper was observed.
        // An infrastructure-only snapshot is ambiguous: a newly detached game
        // may not have reached Wine's process table yet, and could veto logout.
        guard blockers.isEmpty,!tasks.isDisjoint(with:helpers) else{return false}
        for name in tasks.intersection(helpers) {
            _ = try? shutdownCommand(spec.executable,["taskkill","/IM",name,"/F"],spec.environment,timeout:5)
        }
        return true
    }
    // The Wine server, rather than the original loader PID, owns detached clients.
    // Only validated OpenGame prefixes are considered. Signal 0 probes the server
    // without starting one; clean session end respects WM_QUERYENDSESSION vetoes.
    func shutdown(force:Bool=false,gracePeriod:TimeInterval=15) throws {
        processLock.lock()
        acceptingLaunches=false
        do {try fm.createDirectory(at:root,withIntermediateDirectories:true);try String(getpid()).write(to:closingMarker,atomically:true,encoding:.utf8)}
        catch {processLock.unlock();throw error}
        let savedSpecs=sessionSpecs,owned=children,helpers=watchers
        for p in helpers where p.isRunning {p.terminate()}
        processLock.unlock()
        var targets=savedSpecs
        for b in try load().bottles {
            let folder=try prefix(b)
            guard fm.fileExists(atPath:folder.path),fm.isExecutableFile(atPath:runtime(b).path) else{continue}
            let key=folder.resolvingSymlinksInPath().path
            if targets[key]==nil {targets[key]=LaunchSpec(executable:runtime(b),arguments:[],directory:folder,environment:try environment(b),log:path("Logs/shutdown.log"))}
        }
        var failures:[String]=[]
        for (folder,spec) in targets.sorted(by:{$0.key<$1.key}) {
            do {
                let server=spec.executable.deletingLastPathComponent().appendingPathComponent("wineserver")
                let active=try shutdownCommand(server,["-k0"],spec.environment,timeout:3)
                if active==1 {continue} // No server: do not start Wine just to exit it.
                guard active==0 else{throw OGError.message("无法检查容器状态。")}
                if !force {
                    let tasksBeforeShutdown=try windowsTaskNames(spec)
                    writeShutdownNote("Windows tasks before shutdown: "+tasksBeforeShutdown.sorted().joined(separator:", "))
                    var accepted=false
                    do {
                        let code=try shutdownCommand(spec.executable,["wineboot","--end-session","--kill","--shutdown"],spec.environment,timeout:gracePeriod)
                        accepted=code==0
                    } catch {
                        accepted=try closeResidualSteamHelpers(spec,fallback:tasksBeforeShutdown)
                        if !accepted {throw error}
                    }
                    if !accepted {accepted=try closeResidualSteamHelpers(spec,fallback:tasksBeforeShutdown)}
                    guard accepted else{throw OGError.message("程序取消了退出，或仍有保存提示。")}
                }
                // Windows programs have accepted session end, or the user explicitly
                // chose Force Quit. Stop residual services and wait for server exit.
                _ = try shutdownCommand(server,["-k"],spec.environment,timeout:8)
                guard try shutdownCommand(server,["-w"],spec.environment,timeout:8)==0 else{throw OGError.message("Wine 服务尚未退出。")}
            } catch {failures.append(URL(fileURLWithPath:folder).lastPathComponent+"："+error.localizedDescription)}
        }
        let deadline=Date().addingTimeInterval(3)
        while (owned+helpers).contains(where:{$0.isRunning}) && Date()<deadline {Thread.sleep(forTimeInterval:0.05)}
        for p in owned+helpers where p.isRunning {
            if force {
                p.terminate()
                let end=Date().addingTimeInterval(2)
                while p.isRunning && Date()<end {Thread.sleep(forTimeInterval:0.05)}
                if p.isRunning {Darwin.kill(p.processIdentifier,SIGKILL);p.waitUntilExit()}
            } else {failures.append("后台任务尚未退出（PID \(p.processIdentifier)）。")}
        }
        if !failures.isEmpty {throw OGError.message(failures.joined(separator:"\n"))}
        try? fm.removeItem(at:closingMarker)
    }
    func wait(_ p: Process, timeout: TimeInterval=120) throws -> Int32 {
        let deadline=Date().addingTimeInterval(timeout)
        while p.isRunning && Date()<deadline { Thread.sleep(forTimeInterval:0.1) }
        if p.isRunning { p.terminate();throw OGError.message("操作超时，详情见日志。") }
        return p.terminationStatus
    }
    func createBottle(name: String, renderer: Renderer, engineFamily: EngineFamily = .foss) throws -> Bottle {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else { throw OGError.message("请输入容器名称。") }
        let id=UUID().uuidString.lowercased();let b=Bottle(id:id,name:name,directory:"Prefixes/\(id)",renderer:renderer,engineFamily:engineFamily)
        let dir=try prefix(b);try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        do {
            _ = try prepareBundledFonts(b)
            let base=try spec(bottle:b,arguments:["wineboot","-u"],directory:dir,logID:"create-\(id)",initialized:false)
            var setupEnv=base.environment;setupEnv["WINEDLLOVERRIDES"]="winemenubuilder.exe=;mscoree,mshtml="
            let p=try start(LaunchSpec(executable:base.executable,arguments:base.arguments,directory:base.directory,environment:setupEnv,log:base.log))
            let code=try wait(p)
            let registry=dir.appendingPathComponent("system.reg")
            let flushDeadline=Date().addingTimeInterval(15)
            while code==0 && !fm.fileExists(atPath:registry.path) && Date()<flushDeadline { Thread.sleep(forTimeInterval:0.1) }
            guard code==0 && fm.fileExists(atPath:dir.appendingPathComponent("system.reg").path) else { throw OGError.message("容器初始化失败（\(code)），日志已保留。") }
            try registerBundledFonts(b)
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
        do{guard try wait(idle,timeout:8)==0 else{throw OGError.message("无法确认容器状态。")}}
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
    private func idleBottle(_ bottle:Bottle) throws {
        let idle=Process();idle.executableURL=runtime(bottle).deletingLastPathComponent().appendingPathComponent("wineserver");idle.arguments=["-w"];idle.environment=try environment(bottle);idle.standardOutput=FileHandle.nullDevice;idle.standardError=FileHandle.nullDevice
        try idle.run()
        do{guard try wait(idle,timeout:8)==0 else{throw OGError.message("无法确认容器状态。")}}
        catch{throw OGError.message("请先退出此容器内的游戏、Steam 和 Wine 工具。")}
    }
    struct BottleArchiveManifest:Codable {
        var schema=1;var exportedAt:Date;var originalPrefix:String;var bottle:Bottle;var games:[Game]
    }
    private func validateContainedSymlinks(in directory:URL) throws {
        let base=directory.resolvingSymlinksInPath().standardizedFileURL.path
        guard let entries=fm.enumerator(at:directory,includingPropertiesForKeys:[.isSymbolicLinkKey],options:[]) else{throw OGError.message("无法检查容器文件。")}
        for case let entry as URL in entries {
            guard (try entry.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink==true else{continue}
            let target=try fm.destinationOfSymbolicLink(atPath:entry.path)
            let parts=target.split(separator:"/",omittingEmptySubsequences:false)
            guard !target.hasPrefix("/"),!parts.contains("..") else{throw OGError.message("容器包含指向外部位置的符号链接：\(entry.lastPathComponent)")}
            let resolved=entry.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved==base || resolved.hasPrefix(base+"/") else{throw OGError.message("容器包含越界符号链接：\(entry.lastPathComponent)")}
        }
    }
    func exportBottle(_ bottle:Bottle,to archive:URL) throws {
        guard archive.pathExtension.lowercased()=="opengamebottle" else{throw OGError.message("容器归档必须使用 .opengamebottle 扩展名。")}
        try idleBottle(bottle)
        let source=try prefix(bottle),lib=try load()
        guard fm.fileExists(atPath:source.appendingPathComponent("system.reg").path) else{throw OGError.message("容器尚未初始化。")}
        try validateContainedSymlinks(in:source)
        let temporary=fm.temporaryDirectory.appendingPathComponent("OpenGameExport-"+UUID().uuidString)
        defer{try? fm.removeItem(at:temporary)}
        try fm.createDirectory(at:temporary,withIntermediateDirectories:true)
        let payload=temporary.appendingPathComponent("Prefix")
        let cp=Process();cp.executableURL=URL(fileURLWithPath:"/bin/cp");cp.arguments=["-cR",source.path,payload.path];cp.standardOutput=FileHandle.nullDevice;cp.standardError=FileHandle.nullDevice
        try cp.run();guard try wait(cp,timeout:600)==0 else{throw OGError.message("复制容器内容失败。")}
        let manifest=BottleArchiveManifest(exportedAt:Date(),originalPrefix:source.path,bottle:bottle,games:lib.games.filter{$0.bottleID==bottle.id})
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to:temporary.appendingPathComponent("manifest.json"),options:.atomic)
        let out=archive.deletingLastPathComponent().appendingPathComponent("."+archive.lastPathComponent+".tmp")
        try? fm.removeItem(at:out)
        let ditto=Process();ditto.executableURL=URL(fileURLWithPath:"/usr/bin/ditto");ditto.arguments=["-c","-k","--sequesterRsrc",temporary.path,out.path];ditto.standardOutput=FileHandle.nullDevice;ditto.standardError=FileHandle.nullDevice
        try ditto.run();guard try wait(ditto,timeout:900)==0 else{throw OGError.message("创建容器归档失败。")}
        if fm.fileExists(atPath:archive.path){try fm.removeItem(at:archive)}
        try fm.moveItem(at:out,to:archive)
    }
    func importBottle(from archive:URL,name:String?=nil) throws -> Bottle {
        guard fm.fileExists(atPath:archive.path),archive.pathExtension.lowercased()=="opengamebottle" else{throw OGError.message("请选择有效的 .opengamebottle 文件。")}
        let listingFile=fm.temporaryDirectory.appendingPathComponent("OpenGameListing-"+UUID().uuidString)
        defer{try? fm.removeItem(at:listingFile)}
        fm.createFile(atPath:listingFile.path,contents:nil)
        let listingOutput=try FileHandle(forWritingTo:listingFile)
        let listing=Process();listing.executableURL=URL(fileURLWithPath:"/usr/bin/zipinfo");listing.arguments=["-1",archive.path];listing.standardOutput=listingOutput;listing.standardError=FileHandle.nullDevice
        try listing.run();let listingCode=try wait(listing,timeout:120);try listingOutput.close()
        guard listingCode==0,let entries=String(data:try Data(contentsOf:listingFile),encoding:.utf8) else{throw OGError.message("无法读取容器归档。")}
        for entry in entries.split(separator:"\n").map(String.init) {
            guard !entry.hasPrefix("/"),!entry.split(separator:"/").contains("..") else{throw OGError.message("归档包含不安全路径，已拒绝导入。")}
        }
        let temporary=fm.temporaryDirectory.appendingPathComponent("OpenGameImport-"+UUID().uuidString)
        defer{try? fm.removeItem(at:temporary)}
        try fm.createDirectory(at:temporary,withIntermediateDirectories:true)
        let ditto=Process();ditto.executableURL=URL(fileURLWithPath:"/usr/bin/ditto");ditto.arguments=["-x","-k",archive.path,temporary.path];ditto.standardOutput=FileHandle.nullDevice;ditto.standardError=FileHandle.nullDevice
        try ditto.run();guard try wait(ditto,timeout:900)==0 else{throw OGError.message("解压容器归档失败。")}
        try validateContainedSymlinks(in:temporary)
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        let manifest=try decoder.decode(BottleArchiveManifest.self,from:Data(contentsOf:temporary.appendingPathComponent("manifest.json")))
        guard manifest.schema==1,fm.fileExists(atPath:temporary.appendingPathComponent("Prefix/system.reg").path) else{throw OGError.message("容器归档结构不完整。")}
        let id=UUID().uuidString.lowercased(),label=(name ?? manifest.bottle.name).trimmingCharacters(in:.whitespacesAndNewlines)
        guard !label.isEmpty else{throw OGError.message("请输入容器名称。")}
        let restored=Bottle(id:id,name:label,directory:"Prefixes/\(id)",renderer:manifest.bottle.renderer,engineFamily:manifest.bottle.engineFamily)
        guard fm.isExecutableFile(atPath:runtime(restored).path) else{throw OGError.message("归档所需的运行核心尚未安装。")}
        let destination=try prefix(restored),source=temporary.appendingPathComponent("Prefix")
        let cp=Process();cp.executableURL=URL(fileURLWithPath:"/bin/cp");cp.arguments=["-cR",source.path,destination.path];cp.standardOutput=FileHandle.nullDevice;cp.standardError=FileHandle.nullDevice
        try cp.run();guard try wait(cp,timeout:600)==0 else{throw OGError.message("恢复容器内容失败。")}
        let oldPrefix=manifest.originalPrefix
        func remap(_ value:String)->String {oldPrefix.isEmpty ? value : (value==oldPrefix || value.hasPrefix(oldPrefix+"/") ? destination.path+value.dropFirst(oldPrefix.count) : value)}
        do {
            try mutate{lib in
                lib.bottles.append(restored)
                lib.games.append(contentsOf:manifest.games.map{game in var g=game;g.id=UUID().uuidString.lowercased();g.bottleID=id;g.executable=remap(g.executable);g.workingDirectory=remap(g.workingDirectory);g.note="从容器归档恢复 · 待验证兼容性";return g})
            }
        } catch {try? fm.removeItem(at:destination);throw error}
        return restored
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
