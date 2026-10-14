import Foundation
import AppKit
import CryptoKit
import Darwin

enum OGError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum Renderer: String, Codable, CaseIterable { case automatic, d3dmetal, dxmt, dxvk, wine
    var label: String { switch self {case .automatic:return "自动";case .d3dmetal:return "D3DMetal";case .dxmt:return "DXMT";case .dxvk:return "DXVK";case .wine:return "Wine"} }
}
enum EngineFamily: String, Codable, CaseIterable { case winehq, foss
    var label: String { self == .foss ? "Wine FOSS 11 + MSync（推荐）" : "WineHQ 11（兼容旧容器）" }
}
enum SteamMode: String, Codable, CaseIterable {
    case standard, compatibility
    var label:String {self == .standard ? "标准模式（实验）" : "兼容模式（CPU 绘制、单进程）"}
}
struct Bottle: Codable, Identifiable, Hashable {
    var id: String; var name: String; var directory: String; var renderer: Renderer
    var engineFamily: EngineFamily? = nil
    // Optional fields preserve schema-1 catalogs and archives.
    var msyncEnabled: Bool? = nil
    var frameRateLimit: Int? = nil
    var highResolution: Bool? = nil
    var dlssEnabled: Bool? = nil
    var steamMode: SteamMode? = nil
    var steamOverlayEnabled: Bool? = nil
    var diagnosticsEnabled: Bool? = nil
    var effectiveSteamMode: SteamMode {steamMode ?? .compatibility}
    var usesSteamOverlay: Bool {steamOverlayEnabled ?? false}
    var usesMSync: Bool { msyncEnabled ?? true }
    var effectiveFrameRateLimit: Int { frameRateLimit ?? 0 }
}
struct Game: Codable, Identifiable, Hashable {
    var id: String; var title: String; var bottleID: String
    var executable: String; var arguments: [String]; var workingDirectory: String
    var icon: String?; var steamID: String?; var note: String
    var steamInstallation:SteamInstallation? = nil
    var steamManaged:Bool? = nil
}
enum SteamInstallState:String,Codable {case installed,downloading,updating,notInstalled,unavailable,failed
    var label:String {switch self {case .installed:return "已安装";case .downloading:return "下载中";case .updating:return "更新中";case .notInstalled:return "未安装";case .unavailable:return "库目录暂不可用";case .failed:return "安装异常"}}
}
struct SteamInstallation:Codable,Hashable {
    var library:String;var directory:String;var manifest:String;var state:SteamInstallState;var buildID:String?
    var downloaded:UInt64;var total:UInt64
    var label:String {state == .downloading && total>0 ? "下载中 \(min(100,Int(Double(downloaded)/Double(total)*100)))%" : state.label}
}
struct SteamScanResult {var added=0;var updated=0;var warnings:[String]=[];var watchPaths:[URL]=[]}
indirect enum SteamKV {
    case text(String),object([String:SteamKV])
    var text:String? {if case .text(let value)=self{return value};return nil}
    var object:[String:SteamKV]? {if case .object(let value)=self{return value};return nil}
}
enum SteamKeyValues {
    // Steam's local files are an observed format, not a stable public API.
    // Reject partial writes and bound size/depth instead of guessing values.
    static func parse(_ text:String) throws -> [String:SteamKV] {
        guard text.utf8.count<=2*1024*1024 else{throw OGError.message("Steam 清单过大。")}
        enum Token {case text(String),open,close}
        let chars=Array(text);var i=0,tokens:[Token]=[]
        while i<chars.count {
            let c=chars[i]
            if c.isWhitespace || c=="\u{feff}" {i+=1;continue}
            if c=="/",i+1<chars.count,chars[i+1]=="/" {while i<chars.count && chars[i] != "\n" {i+=1};continue}
            if c=="{" {tokens.append(.open);i+=1;continue}
            if c=="}" {tokens.append(.close);i+=1;continue}
            var value=""
            if c=="\"" {
                i+=1;var closed=false
                while i<chars.count {
                    let next=chars[i];i+=1
                    if next=="\"" {closed=true;break}
                    if next=="\\",i<chars.count {
                        let escaped=chars[i];i+=1
                        if escaped=="\\" || escaped=="\"" {value.append(escaped)}
                        else {value.append("\\");value.append(escaped)}
                    } else {value.append(next)}
                }
                guard closed else{throw OGError.message("Steam 正在写入清单，请稍后刷新。")}
            } else {
                while i<chars.count && !chars[i].isWhitespace && chars[i] != "{" && chars[i] != "}" {value.append(chars[i]);i+=1}
            }
            guard !value.isEmpty || c=="\"",tokens.count<100000 else{throw OGError.message("Steam 清单格式无效。")}
            tokens.append(.text(value))
        }
        var index=0
        func object(_ depth:Int,_ nested:Bool) throws -> [String:SteamKV] {
            guard depth<=16 else{throw OGError.message("Steam 清单嵌套过深。")}
            var result:[String:SteamKV]=[:]
            while index<tokens.count {
                if case .close=tokens[index] {guard nested else{throw OGError.message("Steam 清单括号无效。")};index+=1;return result}
                guard case .text(let key)=tokens[index] else{throw OGError.message("Steam 清单缺少字段名。")};index+=1
                guard index<tokens.count else{throw OGError.message("Steam 正在写入清单，请稍后刷新。")}
                switch tokens[index] {
                case .text(let value):result[key.lowercased()] = .text(value);index+=1
                case .open:index+=1;result[key.lowercased()] = .object(try object(depth+1,true))
                case .close:throw OGError.message("Steam 清单缺少字段值。")
                }
            }
            guard !nested else{throw OGError.message("Steam 正在写入清单，请稍后刷新。")}
            return result
        }
        return try object(0,false)
    }
}
struct Library: Codable {
    var schema = 1; var bottles: [Bottle]; var games: [Game]
    var hiddenSteamGames:[String]? = nil
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
        for folder in ["Prefixes", "Logs", "bin", "Engines/SteamCompat", "Engines/PointerInput"] {
            try fm.createDirectory(at:path(folder),withIntermediateDirectories:true)
        }
        if let resources=Bundle.main.resourceURL {
            for (name,target) in [("OpenGameWindow.exe","bin/OpenGameWindow.exe"),("OpenGameGraphicsProbe.exe","bin/OpenGameGraphicsProbe.exe"),("OpenGameDLSSProbe.exe","bin/OpenGameDLSSProbe.exe"),("OpenGameD3D12Probe.exe","bin/OpenGameD3D12Probe.exe"),("steamwebhelper.exe","Engines/SteamCompat/steamwebhelper.exe"),("steamerrorreporter64.exe","Engines/SteamCompat/steamerrorreporter64.exe"),("PointerInput/version.dll","Engines/PointerInput/version.dll")] {
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
    func effectiveRenderer(_ b:Bottle) -> Renderer {
        guard b.renderer == .automatic else{return b.renderer}
        if b.engineFamily == .foss,
           fm.isExecutableFile(atPath:activeRuntimeRoot.appendingPathComponent("Engines/WineFOSS11-DXMT/bin/wine").path),rendererPack(.dxmt) != nil {return .dxmt}
        return .wine
    }
    var dxmtExtensions:URL {activeRuntimeRoot.appendingPathComponent("Extensions/dxmt")}
    func supportsDLSS(_ b:Bottle) -> Bool {
        b.engineFamily == .foss && effectiveRenderer(b) == .dxmt &&
        ["nvapi64.dll","nvngx.dll"].allSatisfy{file in
            guard let data=try? Data(contentsOf:dxmtExtensions.appendingPathComponent("x86_64-windows/"+file)) else{return false}
            return PEIcon.isExecutable(data)
        }
    }
    func supportsHighResolution(_ b:Bottle) -> Bool { [.wine,.dxmt].contains(effectiveRenderer(b)) }
    func supportsRenderer(_ renderer:Renderer,_ b:Bottle) -> Bool {
        if renderer == .automatic {return true}
        if renderer == .d3dmetal {return false}
        var candidate=b;candidate.renderer=renderer
        return fm.isExecutableFile(atPath:runtime(candidate).path) && (renderer == .wine || b.engineFamily != .foss || rendererPack(renderer) != nil)
    }
    func runtime(_ b: Bottle) -> URL {
        var b=b;b.renderer=effectiveRenderer(b)
        if b.renderer == .d3dmetal {return path("Engines/Unavailable-D3DMetal/bin/wine")}
        if b.engineFamily == .foss {
            // DXMT includes Wine/Unix-side Metal patches in addition to its PE
            // renderer DLLs. Keep that complete build together instead of
            // mixing it with the base Wine process and wineserver.
            if b.renderer == .dxmt {
                return activeRuntimeRoot.appendingPathComponent("Engines/WineFOSS11-DXMT/bin/wine")
            }
            return activeRuntimeRoot.appendingPathComponent("Engines/WineFOSS11/bin/wine")
        }
        let names:[Renderer:String]=[.wine:"WineHQ11",.dxvk:"WineHQ11-DXVK",.dxmt:"WineHQ11-DXMT"]
        return path("Engines/"+names[b.renderer]!+"/bin/wine")
    }
    func rendererPack(_ renderer:Renderer) -> URL? {
        guard renderer == .dxmt || renderer == .dxvk else{return nil}
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
            var installerBottle=bottle
            if recipe.id == "steam" {installerBottle.renderer = .wine;installerBottle.dlssEnabled=false}
            var request=try spec(bottle:bottle,arguments:[target.path]+step.arguments,directory:downloads,logID:"recipe-\(bottle.id)-\(recipe.id)-\(index)")
            if recipe.id == "steam" {
                var env=try environment(installerBottle,runtimeURL:request.executable)
                env["OPENGAME_STEAM_BOTTLE"]=bottle.id
                env["OPENGAME_STEAM_MODE"]=bottle.effectiveSteamMode.rawValue
                request=LaunchSpec(executable:request.executable,arguments:request.arguments,directory:request.directory,environment:env,log:request.log)
            }
            let code=try wait(start(request),timeout:1800)
            guard code==0 || code==194 else{throw OGError.message("\(recipe.name) 安装程序返回 \(code)，请查看日志。")}
        }
        if recipe.id == "steam" {
            let steam=try prefix(bottle).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
            guard fm.fileExists(atPath:steam.path) else{throw OGError.message("Steam 安装器已退出，但未找到 Steam；请重试安装。")}
            progress("正在配置 Steam 并打开登录窗口…")
            try prepareSteamLaunchFiles(bottle)
            _ = try start(spec(bottle:bottle,arguments:[steam.path],directory:steam.deletingLastPathComponent(),logID:"steam-\(bottle.id)"))
        }
        let stamp=try prefix(bottle).appendingPathComponent(".opengame-dependencies/"+recipe.id+".json")
        try fm.createDirectory(at:stamp.deletingLastPathComponent(),withIntermediateDirectories:true)
        let record=["recipe":recipe.id,"installed_at":ISO8601DateFormatter().string(from:Date())]
        try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]).write(to:stamp,options:.atomic)
    }
    func environment(_ b: Bottle,runtimeURL:URL?=nil) throws -> [String:String] {
        var b=b;b.renderer=effectiveRenderer(b)
        guard b.renderer != .d3dmetal else{throw OGError.message("独立运行核心尚不包含 D3DMetal。")}
        var env=ProcessInfo.processInfo.environment
        for k in Array(env.keys) where k.hasPrefix("CX_") || k.hasPrefix("WINE") || k.hasPrefix("DYLD_") || k.hasPrefix("DXVK_") || k.hasPrefix("DXMT_") { env.removeValue(forKey:k) }
        for key in ["SteamNoOverlayUI","SteamNoOverlayUIDrawing","DISABLE_VK_LAYER_VALVE_steam_overlay_1","OPENGAME_STEAM_BOTTLE","OPENGAME_STEAM_MODE","OPENGAME_RECONFIGURE"] {env.removeValue(forKey:key)}
        env["WINEPREFIX"]=try prefix(b).path;env["WINEDEBUG"]=b.diagnosticsEnabled == true ? "+seh,+loaddll" : "-all"
        if b.engineFamily == .foss { env["WINEMSYNC"]=b.usesMSync ? "1" : "0" }
        guard [0,30,60,120].contains(b.effectiveFrameRateLimit) else {throw OGError.message("帧率上限必须为不限、30、60 或 120。")}
        guard b.highResolution != true || supportsHighResolution(b) else{throw OGError.message("当前图形后端不支持高分辨率模式，请使用 Wine 或 DXMT。")}
        if b.renderer == .dxmt && b.effectiveFrameRateLimit > 0 {
            // DXMT parses this after dxmt.conf, preserving other user options.
            env["DXMT_CONFIG"]="d3d11.preferredMaxFrameRate = \(b.effectiveFrameRateLimit)"
        }
        guard b.dlssEnabled != true || supportsDLSS(b) else{throw OGError.message("当前运行库不支持 DLSS，请安装匹配的 DXMT 扩展组件。")}
        if b.renderer == .dxmt {
            env["DXMT_ENABLE_NVEXT"]=b.dlssEnabled == true ? "1" : "0"
            if b.dlssEnabled == true {env["WINEDLLPATH"]=dxmtExtensions.path}
        }
        env["WINEDLLOVERRIDES"]="winemenubuilder.exe="+(b.renderer == .wine ? "" : ";dxgi,d3d11,d3d10core=b")+(b.renderer == .dxmt ? ";winemetal=b" : "")
        if b.dlssEnabled == true {env["WINEDLLOVERRIDES"]! += ";nvapi64,nvngx=b"}
        let gst=activeRuntimeRoot.appendingPathComponent("Engines/Support/GStreamer.framework/Versions/1.0")
        env["GST_PLUGIN_PATH"]=gst.appendingPathComponent("lib/gstreamer-1.0").path
        env["GST_PLUGIN_SYSTEM_PATH"]=env["GST_PLUGIN_PATH"]
        let selectedRuntime=runtimeURL ?? runtime(b)
        env["DYLD_FALLBACK_LIBRARY_PATH"]=gst.appendingPathComponent("lib").path+":"+selectedRuntime.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib").path+":/usr/lib"
        env["MVK_CONFIG_LOG_LEVEL"]="1";env["DXVK_LOG_PATH"]=path("Logs").path
        env["DXMT_LOG_PATH"]=path("Logs").path
        return env
    }
    private func ensureRendererFiles(_ bottle:Bottle) throws {
        var bottle=bottle;bottle.renderer=effectiveRenderer(bottle)
        guard bottle.engineFamily == .foss else{return}
        if bottle.renderer == .wine {
            let folder=try prefix(bottle),stamp=folder.appendingPathComponent(".opengame-renderer")
            let old=(try? String(contentsOf:stamp,encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines)
            if old=="dxmt" || old=="dxvk" {
                for (arch,targetFolder) in [("x86_64-windows","system32"),("i386-windows","syswow64")] {
                    for name in ["d3d10core.dll","d3d11.dll","dxgi.dll"] {
                        let target=folder.appendingPathComponent("drive_c/windows/\(targetFolder)/\(name)")
                        let backup=folder.appendingPathComponent(".opengame-renderer-backup/\(targetFolder)/\(name)")
                        if let data=try? Data(contentsOf:backup) {try data.write(to:target,options:.atomic)}
                        else if let renderer=Renderer(rawValue:old ?? ""),let pack=rendererPack(renderer),
                            let source=try? Data(contentsOf:pack.appendingPathComponent("\(arch)/\(name)")),
                            (try? Data(contentsOf:target))==source {try fm.removeItem(at:target)}
                    }
                }
                try "wine\n".write(to:stamp,atomically:true,encoding:.utf8)
            }
            return
        }
        guard let pack=rendererPack(bottle.renderer) else{throw OGError.message("尚未安装 \(bottle.renderer.rawValue.uppercased()) 图形增量包。")}
        let prefixURL=try prefix(bottle)
        let stamp=prefixURL.appendingPathComponent(".opengame-renderer")
        let desired=bottle.renderer.rawValue+"\n"
        var rendererMatches=(try? String(contentsOf:stamp,encoding:.utf8))==desired
        if rendererMatches {
            for (arch,folder) in [("x86_64-windows","system32"),("i386-windows","syswow64")] {
                for name in ["d3d10core.dll","d3d11.dll","dxgi.dll"] {
                    let source=pack.appendingPathComponent("\(arch)/\(name)")
                    let target=prefixURL.appendingPathComponent("drive_c/windows/\(folder)/\(name)")
                    guard let expected=try? Data(contentsOf:source),let installed=try? Data(contentsOf:target),expected==installed else{rendererMatches=false;break}
                }
                if !rendererMatches {break}
            }
        }
        if rendererMatches{return}
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
                try Data(contentsOf:source).write(to:target,options:.atomic)
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
    // Link GDI's Latin UI fonts to an installed macOS CJK face. System fonts
    // stay on this Mac: no copying into the app or redistributing Apple fonts.
    static func cjkFontLinks(registry:String,key:String,fallback:String) -> [String:[String]] {
        let names=["Tahoma","Microsoft Sans Serif","Segoe UI","Arial","Liberation Sans","MS Shell Dlg","MS Shell Dlg 2","System"]
        let header="["+key.replacingOccurrences(of:"\\",with:"\\\\")+"]"
        var section=false,existing:[String:String]=[:]
        for line in registry.components(separatedBy:.newlines) {
            if line.hasPrefix("[") {section=line.hasPrefix(header);continue}
            guard section,line.hasPrefix("\""),let end=line.dropFirst().firstIndex(of:"\"") else{continue}
            existing[String(line[line.index(after:line.startIndex)..<end])]=String(line[line.index(after:end)...])
        }
        var result:[String:[String]]=[:]
        for name in names {
            var values:[String]=[]
            if let value=existing[name] {
                // Preserve custom/unrecognized registry encodings untouched.
                guard value.hasPrefix("=str(7):\""),value.hasSuffix("\"") else{continue}
                values=String(value.dropFirst(9).dropLast()).components(separatedBy:"\\0").filter{!$0.isEmpty}
                guard !values.contains(where:{$0.contains("\\\"")}) else{continue}
                values=values.map{$0.replacingOccurrences(of:"\\\\",with:"\\")}
            }
            if !values.contains(fallback) {values.append(fallback);result[name]=values}
        }
        return result
    }
    private func registerHostCJKFonts(_ bottle:Bottle) throws {
        let folder=try prefix(bottle),systemRegistry=folder.appendingPathComponent("system.reg")
        guard let text=try? String(contentsOf:systemRegistry,encoding:.utf8) else{return}
        let candidates=[("/System/Library/Fonts/STHeiti Medium.ttc","Heiti SC","Heiti SC Medium"),
                        ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf","Arial Unicode MS","Arial Unicode MS")]
        // SystemLink needs the family name, not the full face name recorded in
        // the Fonts key (Heiti SC Medium belongs to the Heiti SC family).
        guard let (file,family,_)=candidates.first(where:{fm.fileExists(atPath:$0.0) && text.contains("\""+$0.2+" (TrueType)\"")}) else{return}
        let fallback=URL(fileURLWithPath:file).lastPathComponent+","+family
        let marker=folder.appendingPathComponent(".opengame-cjk-fonts"),desired="host-cjk-link-v2\n"+fallback+"\n"
        guard (try? String(contentsOf:marker,encoding:.utf8)) != desired else{return}
        // Wine shares this key across views. A second Wow6432Node import can
        // reflect back into the first key and replace its preserved entries.
        let keys=["Software\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink"]
        var content="Windows Registry Editor Version 5.00\n",backup=content
        for key in keys {
            let additions=Self.cjkFontLinks(registry:text,key:key,fallback:fallback)
            guard !additions.isEmpty else{continue}
            content += "\n[HKEY_LOCAL_MACHINE\\"+key+"]\n"
            backup += "\n[HKEY_LOCAL_MACHINE\\"+key+"]\n"
            let originalHeader="["+key.replacingOccurrences(of:"\\",with:"\\\\")+"]"
            let section=text.components(separatedBy:originalHeader).dropFirst().first?.components(separatedBy:"\n[").first ?? ""
            for name in additions.keys.sorted() {
                let values=additions[name]!,data=(values.joined(separator:"\0")+"\0\0").data(using:.utf16LittleEndian)!
                content += "\""+name+"\"=hex(7):"+data.map{String(format:"%02x",$0)}.joined(separator:",")+"\n"
                let original=section.components(separatedBy:.newlines).first{$0.hasPrefix("\""+name+"\"=str(7):\"")}
                let old=original == nil ? [] : Array(values.dropLast())
                if original != nil {
                    let bytes=(old.joined(separator:"\0")+"\0\0").data(using:.utf16LittleEndian)!
                    backup += "\""+name+"\"=hex(7):"+bytes.map{String(format:"%02x",$0)}.joined(separator:",")+"\n"
                } else {backup += "\""+name+"\"=-\n"}
            }
        }
        let saved=path("Backups/Fonts/"+bottle.id+"-"+UUID().uuidString+".reg")
        try fm.createDirectory(at:saved.deletingLastPathComponent(),withIntermediateDirectories:true)
        try backup.write(to:saved,atomically:true,encoding:.utf16)
        let registry=folder.appendingPathComponent("opengame-cjk-fonts.reg")
        try content.write(to:registry,atomically:true,encoding:.utf16)
        let process=Process();process.executableURL=runtime(bottle);process.arguments=["regedit","/S",registry.path];process.environment=try environment(bottle)
        process.standardInput=FileHandle.nullDevice;process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        try process.run();guard try wait(process,timeout:30)==0 else{throw OGError.message("中文字体回退注册失败。")}
        try? fm.removeItem(at:registry);try desired.write(to:marker,atomically:true,encoding:.utf8)
    }
    private func isSteamWebHelperWrapper(_ data:Data) -> Bool {
        let marker="steamwebhelper_real.exe".data(using:.utf16LittleEndian)!
        return data.range(of:marker) != nil
    }
    private func officialSteamWebHelperBackup(_ bottle:Bottle) -> Data? {
        guard let folder=try? prefix(bottle) else{return nil}
        let file=folder.appendingPathComponent("drive_c/Program Files (x86)/Steam/.opengame-original/steamwebhelper.exe")
        guard let data=try? Data(contentsOf:file),PEIcon.isExecutable(data),!isSteamWebHelperWrapper(data) else{return nil}
        return data
    }
    func nativeSteamProcessNames(_ bottle:Bottle) throws -> Set<String> {
        let folder=try prefix(bottle)
        let request=LaunchSpec(executable:runtime(bottle),arguments:[],directory:folder,environment:try environment(bottle),log:path("Logs/native-process.log"))
        let owned=Set(nativeSessionProcesses(folder:folder.resolvingSymlinksInPath().path,spec:request).map{$0.pid})
        guard !owned.isEmpty else{return []}
        let data=try capturedOutput(URL(fileURLWithPath:"/bin/ps"),["-axo","pid=,comm="],timeout:3)
        return Set(String(decoding:data,as:UTF8.self).split(separator:"\n").compactMap{line in
            let fields=line.trimmingCharacters(in:.whitespaces).split(maxSplits:1,whereSeparator:{$0.isWhitespace})
            guard fields.count==2,let pid=Int32(fields[0]),owned.contains(pid) else{return nil}
            return fields[1].replacingOccurrences(of:"\\",with:"/").split(separator:"/").last.map{String($0).lowercased()}
        })
    }
    static func steamUpdateCompleted(log:String) -> Bool {
        // These diagnostic markers stay English even when updater UI is Chinese.
        guard let pending=log.range(of:"Found pending update",options:.backwards),
              let shutdown=log.range(of:"] Shutdown",options:.backwards),pending.lowerBound<shutdown.lowerBound else{return false}
        if let startup=log.range(of:"Startup - Steam Client launched",options:.backwards),startup.lowerBound>shutdown.lowerBound {return false}
        return true
    }
    // Steam updates restore its helper. After bootstrap, preserve the updated
    // Valve binary and install our parameter-only wrapper before restarting CEF.
    // All process operations use this bottle's WINEPREFIX, never a host-wide kill.
    func watchSteamUI(_ bottle:Bottle) throws {
        guard !hasClosingMarker(),bottle.effectiveSteamMode == .compatibility else{return}
        let fd=Darwin.open(try prefix(bottle).appendingPathComponent(".opengame-steam-watch.lock").path,O_CREAT|O_RDWR,0o600)
        guard fd>=0 else {throw OGError.message("无法锁定 Steam 界面监控。")}
        defer {flock(fd,LOCK_UN);Darwin.close(fd)}
        guard flock(fd,LOCK_EX|LOCK_NB)==0 else {return}
        let steam=try prefix(bottle).appendingPathComponent("drive_c/Program Files (x86)/Steam")
        let wrapper=try Data(contentsOf:path("Engines/SteamCompat/steamwebhelper.exe"))
        guard PEIcon.isExecutable(wrapper) else {throw OGError.message("Steam 界面包装器无效。")}
        let reporter=steam.appendingPathComponent("steamerrorreporter64.exe")
        let reporterStub=try Data(contentsOf:path("Engines/SteamCompat/steamerrorreporter64.exe"))
        guard PEIcon.isExecutable(reporterStub) else {throw OGError.message("Steam 错误报告兼容组件无效。")}
        let selectedRuntime=runtime(bottle)
        let startedAt=Date(),installed=steam.appendingPathComponent("package/steam_client_win64.installed")
        let initialInstalled=(try? Data(contentsOf:installed)).map{SHA256.hash(data:$0)}
        let bootstrap=steam.appendingPathComponent("logs/bootstrap_log.txt")
        var recoveredUpdate=false
        var uiBottle=bottle;uiBottle.renderer = .wine;uiBottle.dlssEnabled=false
        func command(_ args:[String]) throws -> String {
            guard !hasClosingMarker() else{throw OGError.message("OpenGame 正在退出。") }
            let process=Process(),pipe=Pipe()
            process.executableURL=selectedRuntime;process.arguments=args
            process.environment=try environment(uiBottle,runtimeURL:selectedRuntime);process.standardInput=FileHandle.nullDevice
            process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
            try process.run()
            _ = try wait(process,timeout:10)
            return String(data:pipe.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
        }
        var previous:[String:Data]=[:]
        let deadline=Date().addingTimeInterval(1800)
        while Date()<deadline {
            Thread.sleep(forTimeInterval:2)
            guard !hasClosingMarker(),(try load().bottles.first{$0.id==bottle.id})?.effectiveSteamMode != .standard else{return}
            let processNames=try nativeSteamProcessNames(bottle)
            if !recoveredUpdate,!processNames.contains("steam.exe"),
               let current=try? Data(contentsOf:installed),initialInstalled != SHA256.hash(data:current),
               let modified=try bootstrap.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate,modified>=startedAt,
               let log=try? String(contentsOf:bootstrap,encoding:.utf8),Self.steamUpdateCompleted(log:log) {
                // One bounded recovery only, after a verified official update
                // transaction. Never relaunch an ordinary user-initiated exit.
                recoveredUpdate=true
                try prepareSteamLaunchFiles(bottle)
                let file=steam.appendingPathComponent("steam.exe")
                let request=try spec(bottle:bottle,arguments:[file.path],directory:steam,logID:"steam-"+bottle.id)
                _ = try start(request)
                print("Steam 官方更新已完成，正在恢复更新后的启动。")
                continue
            }
            var changedHelper=false
            let helpers=["cef.win64","cef.win7x64"].map{steam.appendingPathComponent("bin/cef/\($0)/steamwebhelper.exe")}.filter{fm.fileExists(atPath:$0.path)}
            for helper in helpers {
            let realHelper=helper.deletingLastPathComponent().appendingPathComponent("steamwebhelper_real.exe")
            if let current=try? Data(contentsOf:helper),PEIcon.isExecutable(current),current != wrapper {
                if previous[helper.path] == current {
                    guard processNames.contains("steamwebhelper.exe") || processNames.contains("steamwebhelper_real.exe") else {continue}
                    guard !hasClosingMarker() else{return}
                    if isSteamWebHelperWrapper(current) {
                        let real=(try? Data(contentsOf:realHelper)).flatMap{PEIcon.isExecutable($0) && !isSteamWebHelperWrapper($0) ? $0 : nil} ?? officialSteamWebHelperBackup(bottle)
                        guard let real=real else{throw OGError.message("找不到 Steam 官方界面程序备份；请重新安装 Steam。")}
                        try real.write(to:realHelper,options:.atomic)
                    } else {
                        // Only this x64 helper is supported. Leave other architectures alone.
                        let offset=(0..<4).reduce(0){$0 | Int(current[60+$1]) << ($1*8)}
                        guard current[offset+4]==0x64,current[offset+5]==0x86 else {throw OGError.message("Steam CEF 架构已变化，需要更新兼容组件。")}
                        let backup=path("Backups/SteamCompat/"+UUID().uuidString)
                        try fm.createDirectory(at:backup,withIntermediateDirectories:true)
                        try current.write(to:backup.appendingPathComponent("steamwebhelper.exe"),options:.atomic)
                        let local=steam.appendingPathComponent(".opengame-original/"+helper.deletingLastPathComponent().lastPathComponent)
                        try fm.createDirectory(at:local,withIntermediateDirectories:true)
                        try current.write(to:local.appendingPathComponent("steamwebhelper.exe"),options:.atomic)
                        try current.write(to:realHelper,options:.atomic)
                    }
                    try wrapper.write(to:helper,options:.atomic)
                    changedHelper=true
                } else {previous[helper.path]=current}
            } else {previous.removeValue(forKey:helper.path)}
            if let current=try? Data(contentsOf:helper),current==wrapper,
               ((try? Data(contentsOf:realHelper)).map{!PEIcon.isExecutable($0) || isSteamWebHelperWrapper($0)} ?? true),
               let official=officialSteamWebHelperBackup(bottle) {
                try official.write(to:realHelper,options:.atomic)
                changedHelper=true
            }
            }
            if let current=try? Data(contentsOf:reporter),PEIcon.isExecutable(current),current != reporterStub {
                if previous[reporter.path] == current {
                    let backup=path("Backups/SteamCompat/"+UUID().uuidString)
                    try fm.createDirectory(at:backup,withIntermediateDirectories:true)
                    try current.write(to:backup.appendingPathComponent(reporter.lastPathComponent),options:.atomic)
                    let local=steam.appendingPathComponent(".opengame-original")
                    try fm.createDirectory(at:local,withIntermediateDirectories:true)
                    try current.write(to:local.appendingPathComponent("steamerrorreporter64.exe"),options:.atomic)
                    try reporterStub.write(to:reporter,options:.atomic)
                } else {previous[reporter.path]=current}
            } else {previous.removeValue(forKey:reporter.path)}
            let helperReady = !helpers.isEmpty && helpers.allSatisfy{helper in
                let real=helper.deletingLastPathComponent().appendingPathComponent("steamwebhelper_real.exe")
                return (try? Data(contentsOf:helper))==wrapper && ((try? Data(contentsOf:real)).map{PEIcon.isExecutable($0) && !isSteamWebHelperWrapper($0)} ?? false)
            }
            let reporterReady=(try? Data(contentsOf:reporter))==reporterStub
            if changedHelper {_ = try command(["taskkill","/IM","steamwebhelper.exe","/F"])}
            if helperReady && reporterReady && processNames.contains("steam.exe") && processNames.contains("steamwebhelper_real.exe") {
                print("Steam 界面与错误报告兼容组件已就绪；官方文件已备份。")
                return
            }
            if Date().timeIntervalSince(startedAt)>120 && !processNames.contains("steam.exe") && !processNames.contains("steamwebhelper_real.exe") {return}
        }
    }
    func spec(bottle: Bottle, arguments: [String], directory: URL, logID: String, initialized: Bool=true) throws -> LaunchSpec {
        let wine=runtime(bottle)
        guard fm.isExecutableFile(atPath:wine.path) else { throw OGError.message("未找到所选图形后端的完整运行库：\(wine.path)。请重新安装完整包。") }
        let prefixURL = try prefix(bottle)
        if initialized && !fm.fileExists(atPath:prefixURL.appendingPathComponent("system.reg").path) { throw OGError.message("容器尚未完成初始化。") }
        if initialized {try ensureRendererFiles(bottle);try ensureExtensionFiles(bottle);try registerBundledFonts(bottle);try registerHostCJKFonts(bottle)}
        // Prefixes created before DXMT lack its Wine builtin module placeholder.
        // Register only the missing DXMT bridge; preserve existing game DLLs.
        if initialized && effectiveRenderer(bottle) == .dxmt {
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
            var uiBottle=bottle;uiBottle.renderer = .wine;uiBottle.dlssEnabled=false
            // Steam's CEF uses the Wine renderer, but it must share the exact
            // Wine binary, Unix modules and wineserver selected for the game.
            // Mixing the base build with DXMT makes later D3D11 device creation
            // depend on launch order.
            // Steam launches games as children; keep the game frame cap in its
            // environment even though CEF itself uses Wine rendering.
            let gameRenderConfig=env["DXMT_CONFIG"]
            let gameExtension=env["DXMT_ENABLE_NVEXT"],gameDLLPath=env["WINEDLLPATH"]
            env=try environment(uiBottle,runtimeURL:wine)
            env["DXMT_CONFIG"]=gameRenderConfig
            env["DXMT_ENABLE_NVEXT"]=gameExtension;env["WINEDLLPATH"]=gameDLLPath
            if bottle.dlssEnabled == true {env["WINEDLLOVERRIDES"]! += ";nvapi64,nvngx=b"}
            env["OPENGAME_STEAM_BOTTLE"]=bottle.id
            env["OPENGAME_STEAM_MODE"]=bottle.effectiveSteamMode.rawValue
            if !bottle.usesSteamOverlay {
                env["SteamNoOverlayUI"]="1";env["SteamNoOverlayUIDrawing"]="1";env["DISABLE_VK_LAYER_VALVE_steam_overlay_1"]="1"
            }
            if bottle.effectiveSteamMode == .compatibility {
                var flags=["-cef-disable-gpu"]
                // The small official installer contains only the updater.
                // Its first launch must verify and download the full client.
                if fm.fileExists(atPath:URL(fileURLWithPath:first).deletingLastPathComponent().appendingPathComponent("steamclient.dll").path) {flags.append("-noverifyfiles")}
                for flag in flags where !actualArguments.contains(flag) {actualArguments.insert(flag,at:1)}
            }
        }
        return LaunchSpec(executable:wine,arguments:actualArguments,directory:directory,environment:env,log:path("Logs/\(safeID).log"))
    }
    func gameSpec(_ game: Game) throws -> LaunchSpec {
        let lib=try load();guard let b=lib.bottles.first(where:{$0.id==game.bottleID}) else { throw OGError.message("游戏对应的容器不存在。") }
        guard fm.fileExists(atPath:game.executable) else { throw OGError.message("游戏文件已移动或不存在：\(game.executable)") }
        if let appID=game.steamID {
            guard !appID.isEmpty,appID.allSatisfy({$0.isASCII && $0.isNumber}) else {throw OGError.message("Steam 游戏编号无效。")}
            if let installation=game.steamInstallation {
                guard installation.state == .installed else{throw OGError.message("\(game.title)：\(installation.label)。请在 Steam 中完成安装或更新，再刷新游戏库。")}
                guard fm.fileExists(atPath:installation.manifest),fm.fileExists(atPath:installation.directory) else{throw OGError.message("游戏安装已移动或卸载，请刷新游戏库。")}
                guard let app=try steamValues(URL(fileURLWithPath:installation.manifest))["appstate"]?.object,app["appid"]?.text==appID,
                      let flags=app["stateflags"]?.text.flatMap(UInt64.init),flags&4 != 0 else{throw OGError.message("Steam 安装状态已变化，请刷新游戏库。")}
            }
            let steam=try prefix(b).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
            guard fm.fileExists(atPath:steam.path) else{throw OGError.message("未找到 Steam，请先在这个容器中安装 Steam。")}
            var arguments=game.arguments
            if arguments.count>=2,arguments[0]=="-applaunch",arguments[1]==appID {arguments=Array(arguments.dropFirst(2))}
            let launch=try spec(bottle:b,arguments:[steam.path,"-applaunch",appID]+arguments,directory:steam.deletingLastPathComponent(),logID:game.id)
            var env=launch.environment;env["SteamAppId"]=appID;env["SteamGameId"]=appID;env["OPENGAME_STEAM_BOTTLE"]=b.id
            // Steam's injected D3D overlay requests a cross-process swapchain,
            // which DXMT 0.80 cannot create and can crash Unity during startup.
            // Keep the Steam client running for ownership/networking while the
            // game renders without the optional overlay.
            if !b.usesSteamOverlay {
                env["SteamNoOverlayUI"]="1";env["SteamNoOverlayUIDrawing"]="1";env["DISABLE_VK_LAYER_VALVE_steam_overlay_1"]="1"
            }
            return LaunchSpec(executable:launch.executable,arguments:launch.arguments,directory:launch.directory,environment:env,log:launch.log)
        }
        return try spec(bottle:b,arguments:[game.executable]+game.arguments,directory:URL(fileURLWithPath:game.workingDirectory),logID:game.id)
    }
    func prepareSteamLaunchFiles(_ bottle:Bottle) throws {
        if bottle.effectiveSteamMode == .standard {try restoreSteamFiles(bottle);return}
        let steam=try prefix(bottle).appendingPathComponent("drive_c/Program Files (x86)/Steam")
        for variant in ["cef.win64","cef.win7x64"] {
        let helper=steam.appendingPathComponent("bin/cef/\(variant)/steamwebhelper.exe")
        let realHelper=helper.deletingLastPathComponent().appendingPathComponent("steamwebhelper_real.exe")
        let wrapper=try Data(contentsOf:path("Engines/SteamCompat/steamwebhelper.exe"))
        guard PEIcon.isExecutable(wrapper) else {throw OGError.message("Steam 界面包装器无效。")}
        if let current=try? Data(contentsOf:helper),PEIcon.isExecutable(current) {
            if isSteamWebHelperWrapper(current) {
                let validReal=(try? Data(contentsOf:realHelper)).map{PEIcon.isExecutable($0) && !isSteamWebHelperWrapper($0)} ?? false
                if !validReal {
                    guard variant == "cef.win64",let official=officialSteamWebHelperBackup(bottle) else {throw OGError.message("找不到 Steam 官方界面程序备份；请重新安装 Steam。")}
                    try official.write(to:realHelper,options:.atomic)
                }
            } else {
                guard current.count>64 else {throw OGError.message("Steam CEF 程序格式无效。")}
                let offset=(0..<4).reduce(0){$0 | Int(current[60+$1]) << ($1*8)}
                guard current.count>offset+5,current[offset+4]==0x64,current[offset+5]==0x86 else {throw OGError.message("Steam CEF 架构已变化，需要更新兼容组件。")}
                let backup=path("Backups/SteamCompat/"+UUID().uuidString)
                try fm.createDirectory(at:backup,withIntermediateDirectories:true)
                try current.write(to:backup.appendingPathComponent("steamwebhelper.exe"),options:.atomic)
                let local=steam.appendingPathComponent(".opengame-original/"+variant)
                        try fm.createDirectory(at:local,withIntermediateDirectories:true)
                        try current.write(to:local.appendingPathComponent("steamwebhelper.exe"),options:.atomic)
                        try current.write(to:realHelper,options:.atomic)
                try wrapper.write(to:helper,options:.atomic)
            }
        }
        }
        let reporter=steam.appendingPathComponent("steamerrorreporter64.exe")
        let stub=path("Engines/SteamCompat/steamerrorreporter64.exe")
        if let current=try? Data(contentsOf:reporter),let replacement=try? Data(contentsOf:stub),PEIcon.isExecutable(current),PEIcon.isExecutable(replacement),current != replacement {
            let backup=path("Backups/SteamCompat/"+UUID().uuidString)
            try fm.createDirectory(at:backup,withIntermediateDirectories:true)
            try current.write(to:backup.appendingPathComponent(reporter.lastPathComponent),options:.atomic)
            let local=steam.appendingPathComponent(".opengame-original")
            try fm.createDirectory(at:local,withIntermediateDirectories:true)
            try current.write(to:local.appendingPathComponent("steamerrorreporter64.exe"),options:.atomic)
            try replacement.write(to:reporter,options:.atomic)
        }
        // Steam's non-atomic Wine update path can leave byte-identical backups
        // behind, then complain about them on every later start. Remove only
        // verified duplicates; never remove a distinct recovery copy.
        for (name,oldName) in [("steam.exe","steam.exe.old"),("crashhandler64.dll","crashhandler64.dll.old")] {
            let current=steam.appendingPathComponent(name),old=steam.appendingPathComponent(oldName)
            if let a=try? Data(contentsOf:current),let b=try? Data(contentsOf:old),a==b {try? fm.removeItem(at:old)}
        }
    }
    func ensureExtensionFiles(_ bottle:Bottle) throws {
        guard bottle.engineFamily == .foss else{return}
        guard bottle.dlssEnabled != true || supportsDLSS(bottle) else{throw OGError.message("缺少完整、匹配的 DXMT 扩展组件。")}
        let folder=try prefix(bottle),backup=folder.appendingPathComponent(".opengame-extension-backup")
        for name in ["nvapi64.dll","nvngx.dll"] {
            let source=dxmtExtensions.appendingPathComponent("x86_64-windows/"+name)
            let target=folder.appendingPathComponent("drive_c/windows/system32/"+name)
            let marker=backup.appendingPathComponent(name+".installed")
            if bottle.dlssEnabled == true {
                let desired=try Data(contentsOf:source)
                if (try? Data(contentsOf:target))==desired {continue}
                try fm.createDirectory(at:backup,withIntermediateDirectories:true)
                try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                let original=backup.appendingPathComponent(name)
                if let data=try? Data(contentsOf:target),(try? Data(contentsOf:marker)) != data {try data.write(to:original,options:.atomic)}
                try desired.write(to:target,options:.atomic);try desired.write(to:marker,options:.atomic)
            } else if let installed=try? Data(contentsOf:marker),let current=try? Data(contentsOf:target),current==installed {
                let original=backup.appendingPathComponent(name)
                if let data=try? Data(contentsOf:original) {try data.write(to:target,options:.atomic)}
                else {try fm.removeItem(at:target)}
                try fm.removeItem(at:marker)
            }
        }
    }
    func applyHighResolution(_ bottle:Bottle) throws {
        guard supportsHighResolution(bottle) || bottle.highResolution != true else{throw OGError.message("当前图形后端不支持高分辨率模式。")}
        let folder=try prefix(bottle)
        let registry=folder.appendingPathComponent(".opengame-display.reg")
        let value=bottle.highResolution == true ? "Y" : "N"
        let content="Windows Registry Editor Version 5.00\r\n\r\n[HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]\r\n\"RetinaMode\"=\"\(value)\"\r\n"
        try content.write(to:registry,atomically:true,encoding:.utf16)
        let request=try spec(bottle:bottle,arguments:["regedit","/S",registry.path],directory:folder,logID:"display-"+bottle.id)
        let applying=LaunchSpec(executable:request.executable,arguments:request.arguments,directory:request.directory,environment:request.environment.merging(["OPENGAME_RECONFIGURE":"1"]){_,new in new},log:request.log)
        guard try wait(start(applying),timeout:20)==0 else{throw OGError.message("高分辨率设置未成功写入，详情见日志。")}
        let server=runtime(bottle).deletingLastPathComponent().appendingPathComponent("wineserver")
        // updateBottle checks idle before this operation; end only the settings session.
        let p=Process();p.executableURL=server;p.arguments=["-k"];p.environment=request.environment
        p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
        try p.run();guard try wait(p,timeout:5)==0 else{throw OGError.message("显示设置会话尚未结束。")}
    }
    func restoreSteamFiles(_ bottle:Bottle) throws {
        let steam=try prefix(bottle).appendingPathComponent("drive_c/Program Files (x86)/Steam")
        var replacements:[(URL,Data)]=[]
        for variant in ["cef.win64","cef.win7x64"] {
        let helper=steam.appendingPathComponent("bin/cef/\(variant)/steamwebhelper.exe")
        if let current=try? Data(contentsOf:helper),isSteamWebHelperWrapper(current) {
            let real=helper.deletingLastPathComponent().appendingPathComponent("steamwebhelper_real.exe")
            guard let data=try? Data(contentsOf:real),PEIcon.isExecutable(data),!isSteamWebHelperWrapper(data) else{throw OGError.message("缺少此容器的 Steam 官方界面备份，请先修复 Steam 安装。")}
            replacements.append((helper,data))
        }
        }
        let reporter=steam.appendingPathComponent("steamerrorreporter64.exe")
        if let stub=try? Data(contentsOf:path("Engines/SteamCompat/steamerrorreporter64.exe")),let current=try? Data(contentsOf:reporter),current==stub {
            let backup=steam.appendingPathComponent(".opengame-original/steamerrorreporter64.exe")
            guard let data=try? Data(contentsOf:backup),PEIcon.isExecutable(data),data != stub else{throw OGError.message("缺少此容器的 Steam 官方错误报告器备份，请先修复 Steam 安装。")}
            replacements.append((reporter,data))
        }
        // Validate every replacement before restoring either file.
        for (target,data) in replacements {try data.write(to:target,options:.atomic)}
    }
    func prepareGameInput(for game:Game) throws {
        // Only the verified Unity 6 game receives this compatibility profile.
        guard game.steamID=="4001890",URL(fileURLWithPath:game.executable).lastPathComponent=="How to Fish.exe" else{return}
        let library=try load()
        guard let bottle=library.bottles.first(where:{$0.id==game.bottleID}) else{throw OGError.message("游戏对应的容器不存在。")}
        let folder=URL(fileURLWithPath:game.executable).deletingLastPathComponent()
        let adapter=try Data(contentsOf:path("Engines/PointerInput/version.dll"))
        guard PEIcon.isExecutable(adapter) else{throw OGError.message("鼠标兼容组件无效，请重新安装 OpenGame。")}
        let target=folder.appendingPathComponent("version.dll")
        if fm.fileExists(atPath:target.path) {
            let existing=try Data(contentsOf:target)
            let digest=SHA256.hash(data:existing).map{String(format:"%02x",$0)}.joined()
            // Original OpenGame input adapter shipped before reproducible builds.
            let legacy="fc735b5ef3a064768ee29064807bf2ac911234b0a43767b01b16a70f1cdb7671"
            guard existing==adapter || digest==legacy else{throw OGError.message("游戏目录已有不同的 version.dll，未覆盖；请先检查游戏兼容组件。")}
        } else {try adapter.write(to:target,options:.atomic)}
        let args=["reg","add","HKCU\\Software\\Wine\\AppDefaults\\How to Fish.exe\\DllOverrides","/v","version","/t","REG_SZ","/d","native,builtin","/f"]
        let operation=try spec(bottle:bottle,arguments:args,directory:folder,logID:"input-"+game.id)
        let process=try start(operation)
        guard try wait(process,timeout:10)==0 else{throw OGError.message("无法启用游戏鼠标兼容组件，详情见日志。")}
    }
    func prepareSteam(for game:Game) throws {
        guard game.steamID != nil else{return}
        let lib=try load();guard let bottle=lib.bottles.first(where:{$0.id==game.bottleID}) else{throw OGError.message("游戏对应的容器不存在。")}
        let steam=try prefix(bottle).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
        guard fm.fileExists(atPath:steam.path) else{return}
        try prepareSteamLaunchFiles(bottle)
        let request=try spec(bottle:bottle,arguments:[steam.path],directory:steam.deletingLastPathComponent(),logID:"steam-"+bottle.id)
        func tasks() -> Set<String> {
            (try? nativeSteamProcessNames(bottle)) ?? []
        }
        let launchedAt=Date()
        let wasRunning=tasks().contains("steam.exe")
        if !wasRunning {_=try start(request)}
        let deadline=Date().addingTimeInterval(90)
        var readySnapshots=0
        var loggedOnSince:Date?
        while Date()<deadline {
            let current=tasks()
            if current.contains("steam.exe") && (current.contains("steamwebhelper.exe") || current.contains("steamwebhelper_real.exe")) && steamIsLoggedOn(steam.deletingLastPathComponent(),since:wasRunning ? nil : launchedAt) {
                if loggedOnSince == nil {loggedOnSince=Date()}
                readySnapshots += 1
                // A second steam.exe invocation can be lost between account
                // logon and completion of Steam's UI/IPC startup. Existing
                // clients are already stable; a cold client gets a short
                // settling window before -applaunch is forwarded.
                if readySnapshots>=2 && (wasRunning || Date().timeIntervalSince(loggedOnSince!)>=12) {return}
            } else {readySnapshots=0;loggedOnSince=nil}
            Thread.sleep(forTimeInterval:0.5)
        }
        throw OGError.message("Steam 启动超时，请先打开 Steam 后重试。")
    }
    func steamIsLoggedOn(_ steamDirectory:URL,since:Date?=nil) -> Bool {
        let connectionLog=steamDirectory.appendingPathComponent("logs/connection_log.txt")
        if let since {
            guard let date=(try? fm.attributesOfItem(atPath:connectionLog.path))?[.modificationDate] as? Date,date>=since else{return false}
        }
        guard let file=try? FileHandle(forReadingFrom:connectionLog) else{return false}
        defer{try? file.close()}
        guard let size=try? file.seekToEnd(),(try? file.seek(toOffset:size>512*1024 ? size-512*1024 : 0)) != nil,
              let data=try? file.read(upToCount:512*1024) else{return false}
        // The tail can begin in the middle of a multibyte log character. A
        // lossy UTF-8 decode preserves the ASCII connection-state markers.
        let text=String(decoding:data.suffix(512*1024),as:UTF8.self)
        let on=text.range(of:"[Logged On",options:.backwards)?.lowerBound
        let off=text.range(of:"[Logged Off",options:.backwards)?.lowerBound
        guard let on else{return false}
        return off == nil || on > off!
    }
    func runningGameStatus(_ game:Game) throws -> String? {
        if game.steamID != nil,game.steamInstallation != nil {return try nativeRunningGameStatus(game)}
        // Steam.exe is a launcher shared by many games, not a game identity.
        guard URL(fileURLWithPath:game.executable).lastPathComponent.lowercased() != "steam.exe" else{return nil}
        if let native=try nativeRunningGameStatus(game) {return native}
        guard let bottle=try load().bottles.first(where:{$0.id==game.bottleID}) else{throw OGError.message("游戏对应的容器不存在。")}
        let helper=path("bin/OpenGameWindow.exe")
        guard fm.fileExists(atPath:helper.path) else{throw OGError.message("缺少游戏窗口组件，请重新安装新版 OpenGame。")}
        let drive=try prefix(bottle).appendingPathComponent("drive_c").path+"/"
        let target=game.executable.hasPrefix(drive) ? "C:\\"+String(game.executable.dropFirst(drive.count)).replacingOccurrences(of:"/",with:"\\") : "Z:"+game.executable.replacingOccurrences(of:"/",with:"\\")
        let request=try spec(bottle:bottle,arguments:[helper.path,target],directory:prefix(bottle),logID:"window-"+game.id)
        let code=try wait(start(request),timeout:5)
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
    func nativeRunningGameStatus(_ game:Game) throws -> String? {
        guard let pid=try nativeGamePID(game) else{return nil}
        if activateNativeGame(pid) {return "\(game.title) 已在运行，已请求显示原游戏窗口。"}
        return "\(game.title) 已在运行；请切换到游戏窗口。"
    }
    func isGameRunning(_ game:Game) -> Bool {(try? nativeGamePID(game)) != nil}
    private func windowsPath(_ file:String,bottle:Bottle) throws -> String? {
        let drives=try prefix(bottle).appendingPathComponent("dosdevices")
        let mappings=(try? fm.contentsOfDirectory(at:drives,includingPropertiesForKeys:nil)) ?? []
        let candidates=mappings.filter{$0.lastPathComponent.count==2 && $0.lastPathComponent.hasSuffix(":")}.compactMap{drive -> (String,String)? in
            let base=drive.resolvingSymlinksInPath().path
            guard base=="/" || file==base || file.hasPrefix(base+"/") else{return nil}
            let count=min(file.count,base=="/" ? 1 : base.count+1)
            let suffix=String(file.dropFirst(count)).replacingOccurrences(of:"/",with:"\\")
            return (base,drive.lastPathComponent.uppercased()+"\\"+suffix)
        }.sorted{a,b in a.0.count==b.0.count ? a.1<b.1 : a.0.count>b.0.count}
        return candidates.first?.1
    }
    func runningGameIDs(_ games:[Game]) -> Set<String> {Set(((try? nativeGamePIDs(games)) ?? [:]).keys)}
    private func nativeGamePID(_ game:Game) throws -> Int32? {try nativeGamePIDs([game])[game.id]}
    private func nativeGamePIDs(_ games:[Game]) throws -> [String:Int32] {
        guard !games.isEmpty else{return [:]}
        let library=try load(),bottles=Dictionary(uniqueKeysWithValues:library.bottles.map{($0.id,$0)})
        let data=try capturedOutput(URL(fileURLWithPath:"/bin/ps"),["-axo","pid=,comm="],timeout:3)
        let processes:[(Int32,String)]=String(decoding:data,as:UTF8.self).split(separator:"\n").compactMap{line in
            let fields=line.trimmingCharacters(in:.whitespaces).split(maxSplits:1,whereSeparator:{$0.isWhitespace})
            guard fields.count==2,let pid=Int32(fields[0]) else{return nil};return (pid,fields[1].lowercased())
        }
        var owners:[String:Set<Int32>]=[:],result:[String:Int32]=[:]
        for game in games {
            guard let bottle=bottles[game.bottleID] else{continue}
            if owners[bottle.id]==nil {
                let folder=try prefix(bottle),request=LaunchSpec(executable:runtime(bottle),arguments:[],directory:folder,environment:try environment(bottle),log:path("Logs/native-process.log"))
                owners[bottle.id]=Set(nativeSessionProcesses(folder:folder.resolvingSymlinksInPath().path,spec:request).map{$0.pid})
            }
            guard let owned=owners[bottle.id],!owned.isEmpty else{continue}
            var exact=Set([game.executable.lowercased()]),prefixes:[String]=[]
            if game.steamID != nil,URL(fileURLWithPath:game.executable).lastPathComponent.lowercased()=="steam.exe" {
                guard let installation=game.steamInstallation else{continue}
                exact=[];prefixes=[installation.directory.lowercased()+"/"]
                if let windows=try windowsPath(installation.directory,bottle:bottle){prefixes.append(windows.lowercased()+"\\")}
            } else if let windows=try windowsPath(game.executable,bottle:bottle){exact.insert(windows.lowercased())}
            for (pid,name) in processes where owned.contains(pid) {
                let basename=name.replacingOccurrences(of:"\\",with:"/").split(separator:"/").last.map(String.init) ?? ""
                let inInstallation=prefixes.contains(where:{name.hasPrefix($0)}) && name.hasSuffix(".exe") && !["unitycrashhandler64.exe","crashreporter.exe","vcredist.exe","setup.exe","unins000.exe"].contains(basename)
                if exact.contains(name) || inInstallation {result[game.id]=pid;break}
            }
        }
        return result
    }
    private func activateNativeGame(_ game:Game) throws -> Bool {
        guard let pid=try nativeGamePID(game) else{return false}
        return activateNativeGame(pid)
    }
    private func activateNativeGame(_ pid:Int32) -> Bool {
        let activate:()->Bool={
            guard let app=NSRunningApplication(processIdentifier:pid) else{return false}
            NSApplication.shared.yieldActivation(to:app)
            return app.activate(from:NSRunningApplication.current,options:[.activateAllWindows])
        }
        return Thread.isMainThread ? activate() : DispatchQueue.main.sync(execute:activate)
    }
    @discardableResult func start(_ spec: LaunchSpec) throws -> Process {
        processLock.lock();defer{processLock.unlock()}
        guard acceptingLaunches && !hasClosingMarker() else{throw OGError.message("OpenGame 正在退出，暂时不能启动程序。")}
        if let prefix=spec.environment["WINEPREFIX"] {
            let candidate=URL(fileURLWithPath:prefix).resolvingSymlinksInPath().path
            guard candidate.hasPrefix(root.resolvingSymlinksInPath().path+"/Prefixes/") else{throw OGError.message("拒绝管理 OpenGame 之外的容器。")}
            sessionSpecs[candidate]=spec
        }
        var configurationLock:Int32 = -1
        if let folder=spec.environment["WINEPREFIX"],spec.environment["OPENGAME_RECONFIGURE"] != "1" {
            configurationLock=Darwin.open(URL(fileURLWithPath:folder).appendingPathComponent(".opengame-configuration.lock").path,O_CREAT|O_RDWR,0o600)
            guard configurationLock>=0 else{throw OGError.message("无法锁定容器启动。")}
            guard flock(configurationLock,LOCK_SH|LOCK_NB)==0 else{Darwin.close(configurationLock);throw OGError.message("容器正在更改设置，请稍后启动程序。")}
        }
        defer{if configurationLock>=0{flock(configurationLock,LOCK_UN);Darwin.close(configurationLock)}}
        try fm.createDirectory(at:spec.log.deletingLastPathComponent(),withIntermediateDirectories:true)
        if !fm.fileExists(atPath:spec.log.path) { fm.createFile(atPath:spec.log.path,contents:nil) }
        let log=try FileHandle(forWritingTo:spec.log);try log.seekToEnd()
        let diagnosticKeys=["WINEMSYNC","WINEDLLOVERRIDES","WINEDLLPATH","DXMT_CONFIG","DXMT_ENABLE_NVEXT","OPENGAME_STEAM_MODE","SteamNoOverlayUI"]
        let settings=diagnosticKeys.compactMap{key in spec.environment[key].map{"\(key)=\($0)"}}.joined(separator:"\n")
        let header="\n[OpenGame \(ISO8601DateFormatter().string(from:Date()))] Runtime: \(spec.executable.path)\n\(settings)\n"
        try log.write(contentsOf:Data(header.utf8))
        let p=Process();p.executableURL=spec.executable;p.arguments=spec.arguments;p.environment=spec.environment;p.currentDirectoryURL=spec.directory
        p.standardInput=FileHandle.nullDevice;p.standardOutput=log;p.standardError=log
        do { try p.run() } catch { try? log.close();throw error }
        children.removeAll{!$0.isRunning};children.append(p)
        // Child owns duplicated descriptors after spawn; close the parent's copies.
        if let bottleID=spec.environment["OPENGAME_STEAM_BOTTLE"],spec.environment["OPENGAME_STEAM_MODE"] != SteamMode.standard.rawValue {
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
            if p.isRunning {Darwin.kill(p.processIdentifier,SIGKILL)}
            throw error
        }
    }
    // Regular-file capture cannot block on EOF held by a detached Wine child.
    // The timeout covers the process itself, including a stalled Wine server.
    func capturedOutput(_ executable:URL,_ arguments:[String],environment:[String:String]?=nil,timeout:TimeInterval) throws -> Data {
        let file=fm.temporaryDirectory.appendingPathComponent("OpenGame-output-"+UUID().uuidString)
        fm.createFile(atPath:file.path,contents:nil)
        defer {try? fm.removeItem(at:file)}
        let output=try FileHandle(forWritingTo:file)
        defer {try? output.close()}
        let p=Process();p.executableURL=executable;p.arguments=arguments;p.environment=environment
        p.standardInput=FileHandle.nullDevice;p.standardOutput=output;p.standardError=FileHandle.nullDevice
        try p.run()
        guard try wait(p,timeout:timeout)==0 else{throw OGError.message("查询后台进程失败。")}
        return try Data(contentsOf:file)
    }
    private func windowsTaskNames(_ spec:LaunchSpec) throws -> [String] {
        let helper=path("bin/OpenGameWindow.exe")
        let arguments=fm.fileExists(atPath:helper.path) ? [helper.path,"--list"] : ["tasklist","/FO","CSV","/NH"]
        let data=try capturedOutput(spec.executable,arguments,environment:spec.environment,timeout:2)
        let text=String(decoding:data,as:UTF8.self)
        return text.split(separator:"\n").compactMap {line in
            guard line.first=="\"",let end=line.dropFirst().firstIndex(of:"\"") else{return nil}
            return String(line[line.index(after:line.startIndex)..<end]).lowercased()
        }
    }
    private func writeShutdownNote(_ text:String) {
        let destination=path("Logs/shutdown.log")
        if let log=try? FileHandle(forWritingTo:destination) {
            _ = try? log.seekToEnd()
            _ = try? log.write(contentsOf:Data((text+"\n").utf8))
            _ = try? log.close()
        }
    }
    private func nativeWindowsTaskNames(_ spec:LaunchSpec) throws -> [String] {
        guard let folder=spec.environment["WINEPREFIX"] else{return []}
        let owned=Set(nativeSessionProcesses(folder:folder,spec:spec).map{ $0.pid })
        guard !owned.isEmpty else{return []}
        let data=try capturedOutput(URL(fileURLWithPath:"/bin/ps"),["-axo","pid=,comm="],timeout:3)
        return String(decoding:data,as:UTF8.self).split(separator:"\n").compactMap {line in
            let fields=line.trimmingCharacters(in:.whitespaces).split(maxSplits:1,whereSeparator:{$0.isWhitespace})
            guard fields.count==2,let pid=Int32(fields[0]),owned.contains(pid) else{return nil}
            return URL(fileURLWithPath:String(fields[1]).replacingOccurrences(of:"\\",with:"/")).lastPathComponent.lowercased()
        }
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
            currentTasks.formUnion(try nativeWindowsTaskNames(spec))
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
    struct NativeSessionProcess:Hashable {
        let pid:Int32
        let startedSeconds:UInt64
        let startedMicroseconds:UInt64
    }
    private func nativeIdentity(_ pid:Int32) -> NativeSessionProcess? {
        guard pid != getpid() else{return nil}
        var info=proc_bsdinfo()
        guard proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,Int32(MemoryLayout<proc_bsdinfo>.size))==Int32(MemoryLayout<proc_bsdinfo>.size),
              info.pbi_uid==getuid(),info.pbi_status != UInt32(SZOMB) else{return nil}
        return NativeSessionProcess(pid:pid,startedSeconds:info.pbi_start_tvsec,startedMicroseconds:info.pbi_start_tvusec)
    }
    // Read only the local process's prefix; never print or persist its environment.
    private func nativePrefix(_ pid:Int32) -> String? {
        var mib:[Int32]=[CTL_KERN,KERN_PROCARGS2,pid]
        var size=0
        guard sysctl(&mib,3,nil,&size,nil,0)==0,size>4,size<4*1024*1024 else{return nil}
        var bytes=[UInt8](repeating:0,count:size)
        guard sysctl(&mib,3,&bytes,&size,nil,0)==0 else{return nil}
        bytes=Array(bytes.prefix(size))
        let argc=bytes.withUnsafeBytes{$0.loadUnaligned(as:Int32.self)}
        guard argc>=0,argc<100000 else{return nil}
        var offset=4
        func nextString()->String? {
            guard offset<bytes.count,let end=bytes[offset...].firstIndex(of:0) else{return nil}
            let value=String(decoding:bytes[offset..<end],as:UTF8.self);offset=end+1;return value
        }
        guard nextString() != nil else{return nil} // executable path
        while offset<bytes.count && bytes[offset]==0 {offset+=1}
        for _ in 0..<argc {guard nextString() != nil else{return nil}}
        // Wine rewrites argv in place; KERN_PROCARGS2 can contain NUL padding
        // before the surviving environment. Do not mistake it for end-of-data.
        while let entry=nextString() {
            if entry.hasPrefix("WINEPREFIX=/") {
                return URL(fileURLWithPath:String(entry.dropFirst("WINEPREFIX=".count))).resolvingSymlinksInPath().path
            }
        }
        return nil
    }
    func nativeSessionProcesses(folder:String,spec:LaunchSpec) -> [NativeSessionProcess] {
        // Both the actual host executable and exact canonical prefix must match.
        // An EXE basename or a matching Wine binary alone is never sufficient.
        let engine=spec.executable.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath().path+"/"
        let needed=proc_listpids(UInt32(PROC_ALL_PIDS),0,nil,0)
        guard needed>0 else{return []}
        var pids=[Int32](repeating:0,count:Int(needed)/MemoryLayout<Int32>.size+256)
        let count=proc_listpids(UInt32(PROC_ALL_PIDS),0,&pids,Int32(pids.count*MemoryLayout<Int32>.size))
        guard count>0 else{return []}
        return pids.prefix(Int(count)/MemoryLayout<Int32>.size).compactMap {pid in
            guard pid>0,let identity=nativeIdentity(pid) else{return nil}
            var path=[CChar](repeating:0,count:4096)
            guard proc_pidpath(pid,&path,UInt32(path.count))>0 else{return nil}
            let executable=URL(fileURLWithPath:String(cString:path)).resolvingSymlinksInPath().path
            guard executable.hasPrefix(engine),nativePrefix(pid)==folder,nativeIdentity(pid)==identity else{return nil}
            return identity
        }
    }
    private func terminateNativeSession(folder:String,spec:LaunchSpec) throws {
        for (signal,interval):(Int32,TimeInterval) in [(SIGTERM,0.5),(SIGKILL,1.0)] {
            let end=Date().addingTimeInterval(interval)
            repeat {
                let remaining=nativeSessionProcesses(folder:folder,spec:spec)
                if remaining.isEmpty {return}
                for process in remaining where nativeIdentity(process.pid)==process {
                    // Revalidate prefix and executable each pass, including after PID reuse.
                    writeShutdownNote("Native shutdown signal \(signal), PID \(process.pid)")
                    Darwin.kill(process.pid,signal)
                }
                Thread.sleep(forTimeInterval:0.05)
            } while Date()<end
        }
        let remaining=nativeSessionProcesses(folder:folder,spec:spec)
        guard remaining.isEmpty else{throw OGError.message("后台进程尚未退出："+remaining.map{String($0.pid)}.joined(separator:", "))}
    }
    // The Wine server, rather than the original loader PID, owns detached clients.
    // Only validated OpenGame prefixes are considered. Signal 0 probes the server
    // without starting one; clean session end respects WM_QUERYENDSESSION vetoes.
    func shutdown(force:Bool=false,gracePeriod:TimeInterval=15,onlyBottleID:String?=nil) throws {
        let library=try load()
        var selectedPrefix:String?
        if let onlyBottleID {
            guard let b=library.bottles.first(where:{$0.id==onlyBottleID}) else{throw OGError.message("容器不存在。")}
            selectedPrefix=try prefix(b).resolvingSymlinksInPath().path
        }
        processLock.lock()
        acceptingLaunches=false
        do {try fm.createDirectory(at:root,withIntermediateDirectories:true);try String(getpid()).write(to:closingMarker,atomically:true,encoding:.utf8)}
        catch {processLock.unlock();throw error}
        let savedSpecs=sessionSpecs.filter{selectedPrefix == nil || $0.key==selectedPrefix}
        let owned=children.filter{selectedPrefix == nil || $0.environment?["WINEPREFIX"]==selectedPrefix}
        let helpers=watchers.filter{onlyBottleID == nil || $0.arguments?.last==onlyBottleID}
        for p in helpers where p.isRunning {Darwin.kill(p.processIdentifier,SIGTERM)}
        processLock.unlock()
        var targets=savedSpecs
        for b in library.bottles where onlyBottleID == nil || b.id==onlyBottleID {
            let folder=try prefix(b)
            guard fm.fileExists(atPath:folder.path),fm.isExecutableFile(atPath:runtime(b).path) else{continue}
            let key=folder.resolvingSymlinksInPath().path
            if targets[key]==nil {targets[key]=LaunchSpec(executable:runtime(b),arguments:[],directory:folder,environment:try environment(b),log:path("Logs/shutdown.log"))}
        }
        var failures:[String]=[]
        for (folder,spec) in targets.sorted(by:{$0.key<$1.key}) {
            do {
                let server=spec.executable.deletingLastPathComponent().appendingPathComponent("wineserver")
                if force {
                    // Do not depend on IPC with a wedged Wine server for the fallback.
                    do {_ = try shutdownCommand(server,["-k"],spec.environment,timeout:2)}
                    catch {writeShutdownNote("Wine shutdown command failed; checking native processes: "+error.localizedDescription)}
                    try terminateNativeSession(folder:folder,spec:spec)
                    continue
                }
                let active=try shutdownCommand(server,["-k0"],spec.environment,timeout:3)
                if active==1 {
                    guard nativeSessionProcesses(folder:folder,spec:spec).isEmpty else{throw OGError.message("Wine 服务已退出，但仍有游戏进程。")}
                    continue // Never boot Wine just to exit it.
                }
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
                guard nativeSessionProcesses(folder:folder,spec:spec).isEmpty else{throw OGError.message("Wine 会话结束后仍有后台进程。")}
            } catch {failures.append(URL(fileURLWithPath:folder).lastPathComponent+"："+error.localizedDescription)}
        }
        let deadline=Date().addingTimeInterval(3)
        while (owned+helpers).contains(where:{$0.isRunning}) && Date()<deadline {Thread.sleep(forTimeInterval:0.05)}
        for p in owned+helpers where p.isRunning {
            if force {
                Darwin.kill(p.processIdentifier,SIGTERM)
                let end=Date().addingTimeInterval(2)
                while p.isRunning && Date()<end {Thread.sleep(forTimeInterval:0.05)}
                if p.isRunning {Darwin.kill(p.processIdentifier,SIGKILL)}
            } else {failures.append("后台任务尚未退出（PID \(p.processIdentifier)）。")}
        }
        if !failures.isEmpty {throw OGError.message(failures.joined(separator:"\n"))}
        try? fm.removeItem(at:closingMarker)
    }
    func wait(_ p: Process, timeout: TimeInterval=120) throws -> Int32 {
        let deadline=Date().addingTimeInterval(timeout)
        while p.isRunning && Date()<deadline { Thread.sleep(forTimeInterval:0.1) }
        if p.isRunning {
            Darwin.kill(p.processIdentifier,SIGTERM)
            let end=Date().addingTimeInterval(0.25)
            while p.isRunning && Date()<end {Thread.sleep(forTimeInterval:0.02)}
            if p.isRunning {Darwin.kill(p.processIdentifier,SIGKILL)}
            throw OGError.message("操作超时，详情见日志。")
        }
        return p.terminationStatus
    }
    func createBottle(name: String, renderer: Renderer, engineFamily: EngineFamily = .foss) throws -> Bottle {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else { throw OGError.message("请输入容器名称。") }
        let id=UUID().uuidString.lowercased();let b=Bottle(id:id,name:name,directory:"Prefixes/\(id)",renderer:renderer,engineFamily:engineFamily,steamMode:.compatibility)
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
        guard fm.isExecutableFile(atPath:runtime(bottle).path) else{throw OGError.message("此图形后端的完整运行库尚未安装。")}
        guard let known=try load().bottles.first(where:{$0.id==bottle.id}),known.directory==bottle.directory else{throw OGError.message("容器不存在或路径已更改。")}
        let folder=try prefix(bottle)
        let configurationLock=Darwin.open(folder.appendingPathComponent(".opengame-configuration.lock").path,O_CREAT|O_RDWR,0o600)
        guard configurationLock>=0 else{throw OGError.message("无法锁定容器设置。")}
        defer{flock(configurationLock,LOCK_UN);Darwin.close(configurationLock)}
        guard flock(configurationLock,LOCK_EX|LOCK_NB)==0 else{throw OGError.message("容器正在启动或更改设置，请稍后重试。")}
        _ = try environment(bottle)
        if let existing=try load().bottles.first(where:{$0.id==bottle.id}), ((existing.engineFamily ?? .winehq) != (bottle.engineFamily ?? .winehq) || existing.renderer != bottle.renderer || existing.usesMSync != bottle.usesMSync || existing.effectiveFrameRateLimit != bottle.effectiveFrameRateLimit || existing.dlssEnabled != bottle.dlssEnabled || existing.highResolution != bottle.highResolution || existing.effectiveSteamMode != bottle.effectiveSteamMode || existing.usesSteamOverlay != bottle.usesSteamOverlay) {
            let idle=Process();idle.executableURL=runtime(existing).deletingLastPathComponent().appendingPathComponent("wineserver");idle.arguments=["-w"];idle.environment=try environment(existing);idle.standardOutput=FileHandle.nullDevice;idle.standardError=FileHandle.nullDevice
            try idle.run()
            do { guard try wait(idle,timeout:2)==0 else { throw OGError.message("无法确认容器状态。") } }
            catch { throw OGError.message("请先退出此容器的游戏、Steam 和 Wine 工具，再更改运行核心、图形后端或性能设置。") }
        }
        if bottle.effectiveSteamMode == .standard {try restoreSteamFiles(bottle)}
        try ensureExtensionFiles(bottle)
        if known.highResolution != bottle.highResolution {try applyHighResolution(bottle)}
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
        let id=UUID().uuidString.lowercased();var copied=source;copied.id=id;copied.name=label;copied.directory="Prefixes/\(id)"
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
        var restored=manifest.bottle;restored.id=id;restored.name=label;restored.directory="Prefixes/\(id)"
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
                updated.steamManaged=false;updated.steamInstallation=nil
                let data=try Data(contentsOf:URL(fileURLWithPath:game.executable),options:.mappedIfSafe)
                guard PEIcon.isExecutable(data) else { throw OGError.message("此文件不是支持的 Windows PE 可执行文件。") }
                updated.icon=nil
                if let ico=try? PEIcon.extract(data) { try fm.createDirectory(at:path("Icons"),withIntermediateDirectories:true);updated.icon="Icons/\(game.id).ico";try ico.write(to:path(updated.icon!),options:.atomic) }
            }
            lib.games[i]=updated
        }
    }
    func removeGame(_ id: String) throws {
        try mutate { library in
            if let game=library.games.first(where:{$0.id==id}),let appID=game.steamID {
                let key="steam-\(game.bottleID)-\(appID)"
                if !(library.hiddenSteamGames ?? []).contains(key) {library.hiddenSteamGames=(library.hiddenSteamGames ?? [])+[key]}
            }
            library.games.removeAll(where:{$0.id==id})
        }
    }
    func installerSpec(file: URL,bottle: Bottle) throws -> LaunchSpec {
        guard ["exe","msi"].contains(file.pathExtension.lowercased()),fm.fileExists(atPath:file.path) else { throw OGError.message("请选择 EXE 或 MSI 安装程序。") }
        let args=file.pathExtension.lowercased()=="msi" ? ["msiexec","/i",file.path] : [file.path]
        return try spec(bottle:bottle,arguments:args,directory:file.deletingLastPathComponent(),logID:"installer-\(bottle.id)")
    }
    func toolSpec(bottle: Bottle,tool: String) throws -> LaunchSpec {
        if tool=="d3d12-probe" && effectiveRenderer(bottle) != .wine {throw OGError.message("DXMT 和 DXVK 不提供 DirectX 12。请先退出程序，把此容器的图形后端设为 Wine，再进行检测。")}
        if tool=="graphics-probe" || tool=="dlss-probe" || tool=="d3d12-probe" {
            let name=["graphics-probe":"OpenGameGraphicsProbe.exe","dlss-probe":"OpenGameDLSSProbe.exe","d3d12-probe":"OpenGameD3D12Probe.exe"][tool]!
            let exe=path("bin/"+name)
            guard fm.fileExists(atPath:exe.path) else{throw OGError.message("图形诊断组件未随应用提供，请使用完整构建。")}
            return try spec(bottle:bottle,arguments:[exe.path],directory:prefix(bottle),logID:"diagnostics-"+tool+"-"+bottle.id)
        }
        let tools:[String:[String]]=["winecfg":["winecfg"],"regedit":["regedit"],"taskmgr":["taskmgr"],"controllers":["control","joy.cpl"],"uninstall":["uninstaller"],"internet":["control","inetcpl.cpl"],"reboot":["wineboot","-r"]]
        guard let args=tools[tool] else { throw OGError.message("未知的容器工具。") }
        return try spec(bottle:bottle,arguments:args,directory:prefix(bottle),logID:"tool-\(bottle.id)-\(tool)")
    }
    private func steamValues(_ file:URL) throws -> [String:SteamKV] {
        let size=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size<=2*1024*1024 else{throw OGError.message("Steam 清单过大。")}
        return try SteamKeyValues.parse(String(contentsOf:file,encoding:.utf8))
    }
    func steamLibraryURL(_ windowsPath:String,bottle:Bottle) throws -> URL? {
        let normalized=windowsPath.replacingOccurrences(of:"\\",with:"/")
        guard normalized.count>=3 else{return nil}
        let chars=Array(normalized)
        guard chars[1]==":",chars[2]=="/",let letter=String(chars[0]).lowercased().utf8.first,(97...122).contains(letter) else{return nil}
        let relative=String(normalized.dropFirst(3))
        guard !relative.components(separatedBy:"/").contains("..") else{return nil}
        let drive=try prefix(bottle).appendingPathComponent("dosdevices/"+String(chars[0]).lowercased()+":")
        guard fm.fileExists(atPath:drive.path) else{return nil}
        let base=drive.resolvingSymlinksInPath(),target=drive.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard base.path=="/" || target.path==base.path || target.path.hasPrefix(base.path+"/") else{return nil}
        return target
    }
    func steamLibraryLocations(_ bottle:Bottle) throws -> (URL,[URL],[String]) {
        let steam=try prefix(bottle).appendingPathComponent("drive_c/Program Files (x86)/Steam")
        var libraries=[steam.resolvingSymlinksInPath()],warnings:[String]=[]
        let folders=steam.appendingPathComponent("steamapps/libraryfolders.vdf")
        if fm.fileExists(atPath:folders.path) {
            do {
                guard let values=try steamValues(folders)["libraryfolders"]?.object else{throw OGError.message("Steam 库目录清单缺少 libraryfolders。")}
                for key in values.keys.sorted() where key.allSatisfy({$0.isASCII && $0.isNumber}) {
                    guard libraries.count<64 else{warnings.append("Steam 库目录超过 64 个，后续目录未扫描。");break}
                    let value=values[key]!,path=value.object?["path"]?.text ?? value.text
                    guard let path else{continue}
                    if let url=try steamLibraryURL(path,bottle:bottle) {libraries.append(url)}
                    else {warnings.append("容器“\(bottle.name)”的库路径暂不可访问：\(path)")}
                }
            } catch {warnings.append("容器“\(bottle.name)”的库目录清单暂不可读；保留已有入口。")}
        }
        var seen=Set<String>();libraries=libraries.filter{seen.insert($0.path).inserted}
        return (steam,libraries,warnings)
    }
    // Metadata only: never recurse through installed game payloads or start Wine.
    func steamLibraryWatchPaths(_ bottles:[Bottle]) -> [URL] {
        var paths:[URL]=[]
        for bottle in bottles {
            guard let (steam,libraries,_)=try? steamLibraryLocations(bottle) else{continue}
            paths += [steam.deletingLastPathComponent(),steam,steam.appendingPathComponent("steamapps/libraryfolders.vdf")]
            for library in libraries {
                let apps=library.appendingPathComponent("steamapps");paths += [library,apps]
                if let files=try? fm.contentsOfDirectory(at:apps,includingPropertiesForKeys:nil) {
                    paths += files.filter{$0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension=="acf"}.sorted{$0.path<$1.path}.prefix(2048)
                }
            }
        }
        var seen=Set<String>(),unique:[URL]=[]
        for path in paths where seen.insert(path.resolvingSymlinksInPath().path).inserted {
            unique.append(path);if unique.count>=8192 {break}
        }
        return unique
    }
    func steamLibraryFingerprint(_ bottles:[Bottle]) -> String {
        steamLibraryWatchPaths(bottles).sorted{$0.path<$1.path}.map{url in
            let values=try? url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
            return url.path+"|\(values?.fileSize ?? -1)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? -1)"
        }.joined(separator:"\n")
    }
    private func steamArtwork(_ steam:URL,appID:String,id:String) throws -> String? {
        let cache=steam.appendingPathComponent("appcache/librarycache/"+appID)
        var level=[cache],candidates:[URL]=[]
        for _ in 0..<3 {
            var next:[URL]=[]
            for folder in level.prefix(64) {
                guard let files=try? fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isDirectoryKey,.fileSizeKey]) else{continue}
                for file in files.prefix(256) {
                    let values=try? file.resourceValues(forKeys:[.isDirectoryKey,.fileSizeKey])
                    if values?.isDirectory==true {next.append(file)}
                    else if ["jpg","jpeg","png","ico"].contains(file.pathExtension.lowercased()),(values?.fileSize ?? Int.max)<5*1024*1024 {candidates.append(file)}
                }
            }
            level=next
        }
        let chosen=candidates.sorted{a,b in
            func rank(_ p:URL)->Int {let name=p.lastPathComponent.lowercased();return name.contains("icon") ? 0 : name.contains("library_600x900") ? 1 : name.contains("header") ? 2 : 3}
            let ra=rank(a),rb=rank(b);return ra==rb ? a.path<b.path : ra<rb
        }.first{NSImage(contentsOf:$0) != nil}
        guard let chosen else{return nil}
        let icon="Icons/\(id).\(chosen.pathExtension.lowercased())"
        try fm.createDirectory(at:path("Icons"),withIntermediateDirectories:true)
        let data=try Data(contentsOf:chosen)
        if (try? Data(contentsOf:path(icon))) != data {try data.write(to:path(icon),options:.atomic)}
        return icon
    }
    private func isManagedSteamGame(_ game:Game) -> Bool {
        if let managed=game.steamManaged{return managed}
        guard let appID=game.steamID else{return false}
        return game.id=="steam-\(game.bottleID)-\(appID)" && URL(fileURLWithPath:game.executable).lastPathComponent.lowercased()=="steam.exe"
    }
    func refreshSteamLibrary(bottles:[Bottle]?=nil) throws -> SteamScanResult {
        let initial=try load(),bottles=bottles ?? initial.bottles
        var result=SteamScanResult(),found:[String:Game]=[:],listed=Set<String>(),seen=Set<String>()
        for bottle in bottles {
            let (steam,libraries,warnings)=try steamLibraryLocations(bottle);result.warnings += warnings
            let exe=steam.appendingPathComponent("steam.exe")
            for library in libraries {
                let apps=library.appendingPathComponent("steamapps")
                guard let files=try? fm.contentsOfDirectory(at:apps,includingPropertiesForKeys:[.contentModificationDateKey]) else{continue}
                listed.insert(bottle.id+"|"+apps.resolvingSymlinksInPath().path)
                let manifests=files.filter{$0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension=="acf"}.sorted{$0.path<$1.path}
                if manifests.count>2048 {result.warnings.append("容器“\(bottle.name)”超过 2048 份清单，后续未扫描。")}
                for file in manifests.prefix(2048) {
                    let filenameID=String(file.deletingPathExtension().lastPathComponent.dropFirst("appmanifest_".count))
                    let id="steam-\(bottle.id)-\(filenameID)";seen.insert(id)
                    do {
                        guard let app=try steamValues(file)["appstate"]?.object,
                              let appID=app["appid"]?.text,appID==filenameID,!appID.isEmpty,appID.allSatisfy({$0.isASCII && $0.isNumber}),
                              let name=app["name"]?.text,!name.isEmpty,let install=app["installdir"]?.text,!install.isEmpty,
                              let flags=app["stateflags"]?.text.flatMap(UInt64.init) else{throw OGError.message("Steam 游戏清单字段缺失。")}
                        let common=apps.appendingPathComponent("common").resolvingSymlinksInPath(),folder=common.appendingPathComponent(install).standardizedFileURL.resolvingSymlinksInPath()
                        guard folder.path.hasPrefix(common.path+"/"),!install.contains("\\"),!install.components(separatedBy:"/").contains("..") else{throw OGError.message("Steam 安装目录不安全。")}
                        let downloaded=app["bytesdownloaded"]?.text.flatMap(UInt64.init) ?? 0,total=app["bytestodownload"]?.text.flatMap(UInt64.init) ?? 0
                        let staged=app["bytesstaged"]?.text.flatMap(UInt64.init) ?? 0,toStage=app["bytestostage"]?.text.flatMap(UInt64.init) ?? 0
                        let folderExists=(try? folder.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true
                        let downloading=total>downloaded,staging=toStage>staged
                        let state:SteamInstallState
                        if (app["updateresult"]?.text.flatMap(Int.init) ?? 0) != 0 && (downloading || flags&4==0) {state = .failed}
                        else if downloading || staging {state = flags&4 != 0 ? .updating : .downloading}
                        else if flags&4 != 0 && folderExists {state = .installed}
                        else if !folderExists && flags&4 != 0 {state = .notInstalled}
                        else {state = .downloading}
                        var info=SteamInstallation(library:library.path,directory:folder.path,manifest:file.path,state:state,buildID:app["buildid"]?.text,downloaded:downloaded,total:total)
                        if !fm.fileExists(atPath:exe.path) {info.state = .unavailable}
                        if let existing=found[id],existing.steamInstallation?.state == .installed && state != .installed {continue}
                        let icon=try steamArtwork(steam,appID:appID,id:id)
                        found[id]=Game(id:id,title:name,bottleID:bottle.id,executable:exe.path,arguments:["-applaunch",appID],workingDirectory:steam.path,icon:icon,steamID:appID,note:"Steam · 兼容性需实际验证",steamInstallation:info,steamManaged:true)
                    } catch {result.warnings.append("\(file.lastPathComponent) 暂不可读；已有入口保持不变。")}
                }
            }
        }
        let bottleIDs=Set(bottles.map{$0.id})
        func reconcile(_ library:inout Library) -> (Int,Int) {
            var added=0,updated=0
            for i in library.games.indices where bottleIDs.contains(library.games[i].bottleID) && isManagedSteamGame(library.games[i]) {
                let old=library.games[i];guard let appID=old.steamID else{continue}
                let key="steam-\(old.bottleID)-\(appID)"
                if let current=found[key] {
                    library.games[i].steamManaged=true;library.games[i].steamInstallation=current.steamInstallation
                    if library.games[i].icon==nil {library.games[i].icon=current.icon}
                } else if !seen.contains(key),var info=old.steamInstallation {
                    info.state=listed.contains(old.bottleID+"|"+URL(fileURLWithPath:info.manifest).deletingLastPathComponent().resolvingSymlinksInPath().path) ? .notInstalled : .unavailable
                    library.games[i].steamInstallation=info
                }
                if old != library.games[i] {updated+=1}
            }
            let hidden=Set(library.hiddenSteamGames ?? [])
            for game in found.values.sorted(by:{$0.title.localizedStandardCompare($1.title) == .orderedAscending}) where !hidden.contains(game.id) && !library.games.contains(where:{$0.bottleID==game.bottleID && $0.steamID==game.steamID}) {
                library.games.append(game);added+=1
            }
            return (added,updated)
        }
        var preview=initial;let delta=reconcile(&preview)
        if delta.0>0 || delta.1>0 {
            let actual=try mutate{library in reconcile(&library)};result.added=actual.0;result.updated=actual.1
        }
        result.watchPaths=steamLibraryWatchPaths(bottles);return result
    }
    func scanSteam(bottle:Bottle) throws -> Int {try refreshSteamLibrary(bottles:[bottle]).added}

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
