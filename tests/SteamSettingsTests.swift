import Foundation
@main struct SteamSettingsTests {
 static func main() throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("OpenGame-Steam-"+UUID().uuidString)
  defer{try? fm.removeItem(at:root)}
  let core=OpenGameCore(root:root);try core.ensureCatalog()
  var b=Bottle(id:"test",name:"Test",directory:"Prefixes/test",renderer:.wine,engineFamily:.foss)
  let prefix=try core.prefix(b),bin=root.appendingPathComponent("Engines/WineFOSS11/bin")
  try fm.createDirectory(at:bin,withIntermediateDirectories:true)
  for name in ["wine","wineserver"] {
   let f=bin.appendingPathComponent(name);try "#!/bin/sh\nexit 0\n".write(to:f,atomically:true,encoding:.utf8);try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:f.path)
  }
  let steam=prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam")
  try fm.createDirectory(at:steam.appendingPathComponent("bin/cef/cef.win64"),withIntermediateDirectories:true)
  try Data().write(to:prefix.appendingPathComponent("system.reg"))
  let exe=steam.appendingPathComponent("steam.exe");try Data().write(to:exe)
  func pe(_ text:String)->Data {
   var data=Data(repeating:0,count:128);data[0]=0x4d;data[1]=0x5a;data[0x3c]=64;data[64]=0x50;data[65]=0x45;data[68]=0x64;data[69]=0x86;data[88]=0x0b;data[89]=2
   data.append(text.data(using:.utf16LittleEndian)!);return data
  }
  let official=pe("official helper"),wrapper=pe("steamwebhelper_real.exe"),reporter=pe("official reporter"),stub=pe("stub")
  let helper=steam.appendingPathComponent("bin/cef/cef.win64/steamwebhelper.exe"),real=helper.deletingLastPathComponent().appendingPathComponent("steamwebhelper_real.exe"),report=steam.appendingPathComponent("steamerrorreporter64.exe")
  try wrapper.write(to:helper);try official.write(to:real);try stub.write(to:report)
  try wrapper.write(to:core.path("Engines/SteamCompat/steamwebhelper.exe"));try stub.write(to:core.path("Engines/SteamCompat/steamerrorreporter64.exe"))
  try core.mutate{$0.bottles=[b]}
  precondition(b.effectiveSteamMode == .compatibility)
  let compatibility=try core.spec(bottle:b,arguments:[exe.path],directory:steam,logID:"steam")
  precondition(!compatibility.arguments.contains("-noverifyfiles"),"First installation must verify and download the full client")
  try official.write(to:steam.appendingPathComponent("steamclient.dll"))
  let installed=try core.spec(bottle:b,arguments:[exe.path],directory:steam,logID:"installed")
  precondition(installed.arguments.contains("-noverifyfiles"))
  let legacyDir=steam.appendingPathComponent("bin/cef/cef.win7x64")
  try fm.createDirectory(at:legacyDir,withIntermediateDirectories:true)
  let legacyHelper=legacyDir.appendingPathComponent("steamwebhelper.exe"),legacyReal=legacyDir.appendingPathComponent("steamwebhelper_real.exe")
  try official.write(to:legacyHelper)
  try core.prepareSteamLaunchFiles(b)
  let wrappedLegacy=try Data(contentsOf:legacyHelper);precondition(wrappedLegacy==wrapper,"Windows 7 CEF must receive the same compatibility wrapper")
  let originalLegacy=try Data(contentsOf:legacyReal);precondition(originalLegacy==official,"Each CEF variant must preserve its own original")
  b.steamMode = .standard;b.steamOverlayEnabled=true
  do {try core.prepareSteamLaunchFiles(b);fatalError("Unowned reporter restore accepted")}catch is OGError{}
  let stillWrapped=try Data(contentsOf:helper);precondition(stillWrapped==wrapper,"Validation must occur before either restoration")
  let backup=steam.appendingPathComponent(".opengame-original");try fm.createDirectory(at:backup,withIntermediateDirectories:true);try reporter.write(to:backup.appendingPathComponent("steamerrorreporter64.exe"))
  try core.prepareSteamLaunchFiles(b)
  let restored=try Data(contentsOf:helper),restoredReporter=try Data(contentsOf:report)
  let restoredLegacy=try Data(contentsOf:legacyHelper);precondition(restored==official && restoredReporter==reporter && restoredLegacy==official)
  setenv("SteamNoOverlayUI","1",1);defer{unsetenv("SteamNoOverlayUI")}
  let standard=try core.spec(bottle:b,arguments:[exe.path],directory:steam,logID:"standard")
  precondition(!standard.arguments.contains("-noverifyfiles") && !standard.arguments.contains("-cef-disable-gpu"))
  precondition(standard.environment["SteamNoOverlayUI"]==nil && standard.environment["OPENGAME_STEAM_MODE"]=="standard")
  try core.watchSteamUI(b)
  try core.prepareSteamLaunchFiles(b)
  let originalAgain=try Data(contentsOf:helper);precondition(originalAgain==official)
  b.highResolution=true;try core.updateBottle(b)
  let registry=try String(contentsOf:prefix.appendingPathComponent(".opengame-display.reg"),encoding:.utf16)
  precondition(registry.contains("\"RetinaMode\"=\"Y\""))
  var unsupported=b;unsupported.renderer = .d3dmetal
  do {_ = try core.environment(unsupported);fatalError("Unavailable backend accepted")}catch is OGError{}
  precondition(!core.supportsRenderer(.d3dmetal,b))
  let logs=steam.appendingPathComponent("logs");try fm.createDirectory(at:logs,withIntermediateDirectories:true)
  let connection=logs.appendingPathComponent("connection_log.txt")
  var large=Data(repeating:0x61,count:2*1024*1024);large.append(Data("[Logged On, 4, 7] current\n".utf8));try large.write(to:connection)
  precondition(core.steamIsLoggedOn(steam))
  precondition(!core.steamIsLoggedOn(steam,since:Date().addingTimeInterval(60)),"Old log cannot prove a cold client logged on")
  let key="Software\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink",fallback="STHeiti Medium.ttc,Heiti SC"
  let fontRegistry="["+key.replacingOccurrences(of:"\\",with:"\\\\")+"] 1\n\"Tahoma\"=str(7):\"custom.ttf,Custom Font\\0SIMSUN.TTC,SimSun\\0\"\n\"Segoe UI\"=hex(7):00,00\n"
  let links=OpenGameCore.cjkFontLinks(registry:fontRegistry,key:key,fallback:fallback)
  precondition(links["Tahoma"]==["custom.ttf,Custom Font","SIMSUN.TTC,SimSun",fallback],"Preserve all existing fallback entries")
  precondition(links["Segoe UI"]==nil,"Never overwrite an unrecognized/custom encoding")
  precondition(links["Liberation Sans"]==[fallback],"Arial substitutes need their own CJK fallback")
  let alreadyLinked="["+key.replacingOccurrences(of:"\\",with:"\\\\")+"] 1\n\"Tahoma\"=str(7):\""+fallback+"\\0\"\n"
  precondition(OpenGameCore.cjkFontLinks(registry:alreadyLinked,key:key,fallback:fallback)["Tahoma"]==nil,"Fallback registration is idempotent")
  precondition(!OpenGameCore.steamUpdateCompleted(log:"[1] Found pending update\n[2] 正在安装更新..."))
  precondition(OpenGameCore.steamUpdateCompleted(log:"[1] Found pending update\n[2] 更新完成，正在启动 Steam...\n[3] Shutdown\n"))
  precondition(!OpenGameCore.steamUpdateCompleted(log:"[1] Found pending update\n[2] Shutdown\n[3] Startup - Steam Client launched\n"),"Do not recover stale updates")
  print("PASS: legacy Steam mode, prefix-local all-or-nothing restore, official arguments, overlay option, no watcher, high-resolution registry, unsupported backend")
 }
}
