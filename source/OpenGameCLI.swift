import Foundation
@main struct OpenGameCLI {
 static func main() {
  let core=OpenGameCore();let args=Array(CommandLine.arguments.dropFirst())
  do {
   try core.ensureCatalog()
   func bottle(_ id:String)throws->Bottle {guard let b=try core.load().bottles.first(where:{$0.id==id}) else {throw OGError.message("找不到容器：\(id)")};return b}
   switch args.first ?? "help" {
   case "list":
    let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];print(String(data:try encoder.encode(core.load()),encoding:.utf8)!)
   case "create":
    guard (args.count==3 || args.count==4),let renderer=Renderer(rawValue:args[2]),let family=EngineFamily(rawValue:args.count==4 ? args[3] : "foss") else{throw OGError.message("create NAME wine|dxvk|dxmt [foss|winehq]")}
    let b=try core.createBottle(name:args[1],renderer:renderer,engineFamily:family);print(b.id)
   case "copy":
    guard args.count==3 else{throw OGError.message("copy BOTTLE_ID NAME")}
    print(try core.copyBottle(bottle(args[1]),name:args[2]).id)
   case "export-bottle":
    guard args.count==3 else{throw OGError.message("export-bottle BOTTLE_ID OUTPUT.opengamebottle")}
    try core.exportBottle(bottle(args[1]),to:URL(fileURLWithPath:args[2]));print(args[2])
   case "import-bottle":
    guard args.count==2 || args.count==3 else{throw OGError.message("import-bottle ARCHIVE.opengamebottle [NAME]")}
    print(try core.importBottle(from:URL(fileURLWithPath:args[1]),name:args.count==3 ? args[2] : nil).id)
   case "runtime-status":
    print(core.runtimeStatus())
   case "recipes":
    for recipe in try core.availableRecipes(){print("\(recipe.id)\t\(recipe.name)\t\(recipe.summary)")}
   case "install-recipe":
    guard args.count==3,let recipe=try core.availableRecipes().first(where:{$0.id==args[2]}) else{throw OGError.message("install-recipe BOTTLE_ID RECIPE_ID")}
    try core.installRecipe(recipe,in:bottle(args[1])){print($0)};print("installed")
   case "stop":
    guard args.count==2 || (args.count==3 && args[2]=="--force") else{throw OGError.message("stop BOTTLE_ID [--force]")}
    defer{core.resumeLaunches()}
    try core.shutdown(force:args.contains("--force"),onlyBottleID:try bottle(args[1]).id);print("Bottle applications stopped")
   case "settings":
    guard args.count>=4,args.count%2==0 else{throw OGError.message("settings BOTTLE_ID OPTION VALUE [OPTION VALUE ...]")}
    var b=try bottle(args[1])
    func flag(_ value:String)throws->Bool {guard value=="on" || value=="off" else{throw OGError.message("开关值必须为 on 或 off。")};return value=="on"}
    for i in stride(from:2,to:args.count,by:2) {
        let value=args[i+1]
        switch args[i] {
        case "msync":b.msyncEnabled=try flag(value)
        case "dlss":b.dlssEnabled=try flag(value)
        case "high-resolution":b.highResolution=try flag(value)
        case "overlay":b.steamOverlayEnabled=try flag(value)
        case "diagnostics":b.diagnosticsEnabled=try flag(value)
        case "frame-limit":guard let rate=Int(value) else{throw OGError.message("帧率上限必须为整数。")};b.frameRateLimit=rate
        case "steam-mode":guard let mode=SteamMode(rawValue:value) else{throw OGError.message("Steam 模式必须为 standard 或 compatibility。")};b.steamMode=mode
        default:throw OGError.message("未知的容器选项：\(args[i])")
        }
    }
    try core.updateBottle(b);print("Settings saved; restart games to apply")
   case "renderer":
    guard args.count==3,let renderer=Renderer(rawValue:args[2]) else{throw OGError.message("renderer BOTTLE_ID wine|dxvk|dxmt")}
    var b=try bottle(args[1]);b.renderer=renderer;try core.updateBottle(b);print(renderer.rawValue)
   case "add":
    guard args.count>=4 else{throw OGError.message("add BOTTLE_ID EXE TITLE [ARG ...]")}
    let game=try core.importGame(executable:URL(fileURLWithPath:args[2]),title:args[3],bottleID:args[1],arguments:Array(args.dropFirst(4)));print(game.id)
   case "remove":
    guard args.count==2 else{throw OGError.message("remove GAME_ID")};try core.removeGame(args[1]);print("Entry removed; game files preserved.")
   case "scan-steam":
    guard args.count==2 else{throw OGError.message("scan-steam BOTTLE_ID")};print(try core.scanSteam(bottle:bottle(args[1])))
   case "run", "describe":
    guard args.count>=2,let game=try core.load().games.first(where:{$0.id==args[1]}) else{throw OGError.message("run GAME_ID [--wait]")}
    let spec=try core.gameSpec(game)
    if args[0]=="describe" {print(spec.executable.path);print(spec.environment["WINEPREFIX"] ?? "");print(spec.arguments);return}
    let p=try core.start(spec);print("PID=\(p.processIdentifier) LOG=\(spec.log.path)")
    if args.contains("--wait") {p.waitUntilExit();exit(p.terminationStatus)}
   case "probe":
    guard args.count==3 else{throw OGError.message("probe BOTTLE_ID TEST_EXE")}
    let b=try bottle(args[1]),file=URL(fileURLWithPath:args[2]);let s=try core.spec(bottle:b,arguments:[file.path],directory:file.deletingLastPathComponent(),logID:"probe-\(b.id)-\(file.lastPathComponent)")
    let p=try core.start(s);let code=try core.wait(p);print("LOG=\(s.log.path) EXIT=\(code)");exit(code)
   case "steam-watch":
    guard args.count==2 else{throw OGError.message("steam-watch BOTTLE_ID")}
    try core.watchSteamUI(bottle(args[1]))
   case "steam":
    let b=try bottle(args.count>1 ? args[1] : "steam")
    let file=try core.prefix(b).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
    guard FileManager.default.fileExists(atPath:file.path) else{throw OGError.message("此容器未安装 Steam。")}
    let entry=Game(id:"steam-"+b.id,title:"Steam",bottleID:b.id,executable:file.path,arguments:[],workingDirectory:file.deletingLastPathComponent().path,icon:nil,steamID:nil,note:"")
    if let status=try core.nativeRunningGameStatus(entry){print(status);return}
    try core.prepareSteamLaunchFiles(b)
    let p=try core.start(core.spec(bottle:b,arguments:[file.path],directory:file.deletingLastPathComponent(),logID:"steam-\(b.id)"));print("PID=\(p.processIdentifier)")
   case "exec":
    guard args.count>=3 else{throw OGError.message("exec BOTTLE_ID WINE_COMMAND [ARG ...]")}
    let b=try bottle(args[1]);let p=try core.start(core.spec(bottle:b,arguments:Array(args.dropFirst(2)),directory:core.prefix(b),logID:"command-\(b.id)"));exit(try core.wait(p))
   case "tool":
    guard args.count==3 else{throw OGError.message("tool BOTTLE_ID winecfg|regedit|taskmgr|controllers|uninstall")}
    let p=try core.start(core.toolSpec(bottle:bottle(args[1]),tool:args[2]));print("PID=\(p.processIdentifier)")
   case "install":
    guard args.count==3 else{throw OGError.message("install BOTTLE_ID INSTALLER.exe|msi")}
    let p=try core.start(core.installerSpec(file:URL(fileURLWithPath:args[2]),bottle:bottle(args[1])));print("PID=\(p.processIdentifier)")
   case "extract-icon":
    guard args.count==3 else{throw OGError.message("extract-icon INPUT.exe OUTPUT.ico")}
    try PEIcon.extract(Data(contentsOf:URL(fileURLWithPath:args[1]))).write(to:URL(fileURLWithPath:args[2]));print("OK")
   default:print("OpenGame CLI: list | create NAME wine|dxvk|dxmt | copy BOTTLE_ID NAME | renderer BOTTLE_ID wine|dxvk|dxmt | add BOTTLE_ID EXE TITLE | remove ID | scan-steam BOTTLE_ID | run ID [--wait] | describe ID | probe BOTTLE_ID EXE | tool BOTTLE_ID TOOL | install BOTTLE_ID FILE | extract-icon EXE ICO")
   }
  } catch {FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1)}
 }
}
