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
    if args.contains("--wait") {exit(try core.wait(p))}
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
