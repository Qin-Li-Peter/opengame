import Foundation
@main struct ShutdownTests {
    static func main() throws {
        let fm=FileManager.default
        let root=fm.temporaryDirectory.appendingPathComponent("OpenGame-Shutdown-"+UUID().uuidString)
        defer{try? fm.removeItem(at:root)}
        let core=OpenGameCore(root:root);try core.ensureCatalog()
        let bin=root.appendingPathComponent("Engines/WineHQ11/bin")
        try fm.createDirectory(at:bin,withIntermediateDirectories:true)
        let wine="""
        #!/bin/sh
        echo "wine:$*" >> "$WINEPREFIX/commands"
        if [ "$1" = tasklist ]; then
          [ ! -f "$WINEPREFIX/veto" ] || printf '"game.exe","123","Console","1","1 K"\n'
          exit 0
        fi
        if [ "$1" = wineboot ]; then
          [ ! -f "$WINEPREFIX/veto" ] || exit 7
          touch "$WINEPREFIX/accepted"
        fi
        exit 0
        """
        let server="""
        #!/bin/sh
        echo "server:$*" >> "$WINEPREFIX/commands"
        case "$1" in
          -k0) test -f "$WINEPREFIX/active" ;;
          -k) rm -f "$WINEPREFIX/active" ;;
          -w) test ! -f "$WINEPREFIX/active" ;;
          *) exit 8 ;;
        esac
        """
        for (name,text) in [("wine",wine),("wineserver",server)] {
            let f=bin.appendingPathComponent(name);try text.write(to:f,atomically:true,encoding:.utf8)
            try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:f.path)
        }
        let b=Bottle(id:"test",name:"Test",directory:"Prefixes/test",renderer:.wine)
        let prefix=try core.prefix(b);try fm.createDirectory(at:prefix,withIntermediateDirectories:true)
        try core.mutate{$0.bottles=[b]}
        func mark(_ name:String)throws{try Data().write(to:prefix.appendingPathComponent(name))}
        func commands()throws->String{try String(contentsOf:prefix.appendingPathComponent("commands"),encoding:.utf8)}
        try core.shutdown(gracePeriod:1)
        let idle=try commands()
        precondition(idle=="server:-k0\n","Idle prefix must never boot Wine")
        let launch=LaunchSpec(executable:bin.appendingPathComponent("wine"),arguments:["game"],directory:prefix,environment:try core.environment(b),log:root.appendingPathComponent("Logs/test.log"))
        do {_ = try core.start(launch);fatalError("Launch raced shutdown")}catch is OGError{}
        core.resumeLaunches();try mark("active");try mark("veto")
        do {try core.shutdown(gracePeriod:1);fatalError("Veto ignored")}catch is OGError{}
        precondition(fm.fileExists(atPath:prefix.appendingPathComponent("active").path))
        let vetoed=try commands()
        precondition(!vetoed.contains("server:-k\n"),"Veto must not kill server")
        core.resumeLaunches();try fm.removeItem(at:prefix.appendingPathComponent("veto"))
        try core.shutdown(gracePeriod:1)
        precondition(fm.fileExists(atPath:prefix.appendingPathComponent("accepted").path))
        precondition(!fm.fileExists(atPath:prefix.appendingPathComponent("active").path))
        core.resumeLaunches();try mark("active");try mark("veto")
        try core.shutdown(force:true,gracePeriod:1)
        precondition(!fm.fileExists(atPath:prefix.appendingPathComponent("active").path))
        core.resumeLaunches()
        let outside=root.appendingPathComponent("Unmanaged")
        try fm.createDirectory(at:outside,withIntermediateDirectories:true)
        try fm.createSymbolicLink(at:root.appendingPathComponent("Prefixes/escape"),withDestinationURL:outside)
        let escaped=Bottle(id:"escape",name:"Other app",directory:"Prefixes/escape",renderer:.wine)
        try core.mutate{$0.bottles=[escaped]}
        do{try core.shutdown(gracePeriod:1);fatalError("Escaping prefix allowed")}catch is OGError{}
        precondition(!fm.fileExists(atPath:outside.appendingPathComponent("commands").path))
        print("PASS: idle probe, launch barrier, veto, clean shutdown, explicit force, unmanaged prefix rejection")
    }
}
