import Foundation
@main struct SteamDiscoveryTests {
 static func main() throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("OpenGame-Discovery-"+UUID().uuidString)
  defer {try? fm.removeItem(at:root)}
  let core=OpenGameCore(root:root);try core.ensureCatalog()
  let b=Bottle(id:"one",name:"One",directory:"Prefixes/one",renderer:.wine,engineFamily:.foss)
  let prefix=try core.prefix(b),steam=prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam"),external=root.appendingPathComponent("外部 游戏库")
  func mkdir(_ u:URL)throws{try fm.createDirectory(at:u,withIntermediateDirectories:true)}
  try mkdir(steam.appendingPathComponent("steamapps"));try mkdir(external.appendingPathComponent("steamapps"));try mkdir(prefix.appendingPathComponent("dosdevices"))
  try fm.createSymbolicLink(atPath:prefix.appendingPathComponent("dosdevices/c:").path,withDestinationPath:prefix.appendingPathComponent("drive_c").path)
  try fm.createSymbolicLink(atPath:prefix.appendingPathComponent("dosdevices/d:").path,withDestinationPath:external.path)
  try Data().write(to:steam.appendingPathComponent("steam.exe"));try core.mutate{$0.bottles=[b]}
  try "\"libraryfolders\" { \"0\" { \"path\" \"C:\\\\Program Files (x86)\\\\Steam\" } \"1\" { \"path\" \"D:\\\\\" } }".write(to:steam.appendingPathComponent("steamapps/libraryfolders.vdf"),atomically:true,encoding:.utf8)
  func manifest(_ lib:URL,_ id:String,flags:Int=4,download:Int=10,total:Int=10)throws {
   try mkdir(lib.appendingPathComponent("steamapps/common/Game "+id))
   let text="\"AppState\" { \"appid\" \"\(id)\" \"name\" \"游戏 \(id)\" \"installdir\" \"Game \(id)\" \"StateFlags\" \"\(flags)\" \"BytesDownloaded\" \"\(download)\" \"BytesToDownload\" \"\(total)\" }"
   try text.write(to:lib.appendingPathComponent("steamapps/appmanifest_"+id+".acf"),atomically:true,encoding:.utf8)
  }
  try manifest(steam,"100",flags:12);try manifest(external,"200");try manifest(external,"100",flags:2,download:3,total:10)
  let first=try core.refreshSteamLibrary();precondition(first.added==2)
  var games=try core.load().games;precondition(games.count==2 && games.allSatisfy{$0.steamInstallation?.state == .installed})
  precondition(games.first{$0.steamID=="200"}!.steamInstallation!.library==external.path)
  precondition(!core.steamLibraryWatchPaths([b]).isEmpty)
  let again=try core.refreshSteamLibrary();precondition(again.added==0 && again.updated==0)
  try core.mutate {l in let i=l.games.firstIndex{$0.steamID=="200"}!;l.games[i].title="我的名称";l.games[i].arguments += ["-custom"];l.games[i].note="保留";l.games[i].icon="custom.png"}
  try manifest(external,"200",flags:2,download:2,total:10);_ = try core.refreshSteamLibrary()
  let changed=try core.load().games.first{$0.steamID=="200"}!
  precondition(changed.steamInstallation?.state == .downloading && changed.title=="我的名称" && changed.note=="保留" && changed.icon=="custom.png" && changed.arguments.last=="-custom")
  do {_ = try core.gameSpec(changed);fatalError("Downloading game accepted")} catch is OGError {}
  var invalid=changed;invalid.steamID="200&other"
  do {_ = try core.gameSpec(invalid);fatalError("Invalid AppID accepted")} catch is OGError {}
  let file=external.appendingPathComponent("steamapps/appmanifest_200.acf")
  try "\"AppState\" {".write(to:file,atomically:true,encoding:.utf8)
  let partial=try core.refreshSteamLibrary();precondition(!partial.warnings.isEmpty)
  let preserved=try core.load().games.first{$0.steamID=="200"}!
  precondition(preserved==changed,"Partial writes must preserve the prior entry")
  try fm.removeItem(at:file);_ = try core.refreshSteamLibrary()
  let missing=try core.load().games.first{$0.steamID=="200"}!
  precondition(missing.steamInstallation?.state == .notInstalled)
  try core.removeGame("steam-one-100");_ = try core.refreshSteamLibrary()
  games=try core.load().games;precondition(!games.contains{$0.steamID=="100"},"Removed automatic entries stay hidden")
  let unsafe=try core.steamLibraryURL("D:\\..\\escape",bottle:b);precondition(unsafe==nil)
  do {_ = try SteamKeyValues.parse("\"x\" { \"a\" \"b\"");fatalError("Partial VDF accepted")} catch is OGError {}
  let parsed=try SteamKeyValues.parse("// comment\n\"X\" { \"NAME\" \"中文 空格\" }")
  precondition(parsed["x"]?.object?["name"]?.text=="中文 空格")
  print("PASS: multi-library discovery, bit flags, duplicate AppIDs, incremental reconciliation, custom metadata, partial writes, uninstall and hidden entries, path containment")
 }
}
