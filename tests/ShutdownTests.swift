import Foundation
import Darwin
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
        if [ -f "$WINEPREFIX/hang-server" ]; then
          trap '' TERM
          exec /bin/sleep 30
        fi
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
        // A helper that never closes stdout must hit the timeout, not block in read().
        let hung=bin.appendingPathComponent("hung-query")
        try "#!/bin/sh\ntrap '' TERM\nexec /bin/sleep 30\n".write(to:hung,atomically:true,encoding:.utf8)
        try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:hung.path)
        let queryStart=Date()
        do {_ = try core.capturedOutput(hung,[],timeout:0.2);fatalError("Hung query did not time out")} catch is OGError {}
        precondition(Date().timeIntervalSince(queryStart)<2,"Query timeout must include output collection")

        // Neither a shared executable nor a shared prefix alone establishes ownership.
        let worker=bin.appendingPathComponent("native-worker")
        try fm.copyItem(at:URL(fileURLWithPath:"/bin/sleep"),to:worker)
        // A relocated Apple platform binary must be re-signed before macOS runs it.
        _ = try core.capturedOutput(URL(fileURLWithPath:"/usr/bin/codesign"),["--force","--sign","-",worker.path],timeout:5)
        func spawn(_ executable:URL,_ folder:URL)throws->Process {
            let process=Process();process.executableURL=executable;process.arguments=["120"]
            var env=ProcessInfo.processInfo.environment;env["WINEPREFIX"]=folder.path;process.environment=env
            process.standardInput=FileHandle.nullDevice;process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            try process.run();return process
        }
        let ownedNative=try spawn(worker,prefix)
        let otherPrefix=try spawn(worker,root.appendingPathComponent("Prefixes/unrelated"))
        let otherRuntime=try spawn(URL(fileURLWithPath:"/bin/sleep"),prefix)
        defer {for p in [ownedNative,otherPrefix,otherRuntime] where p.isRunning {Darwin.kill(p.processIdentifier,SIGKILL)}}
        let native=core.nativeSessionProcesses(folder:prefix.resolvingSymlinksInPath().path,spec:launch)
        precondition(native.map{$0.pid}==[ownedNative.processIdentifier],"Only exact prefix plus runtime may be terminated")
        // No Wine server exists, but an untracked detached client still does.
        do {try core.shutdown(gracePeriod:0.2);fatalError("Detached client was ignored")} catch is OGError {}
        core.resumeLaunches();try mark("hang-server")
        let forceStart=Date()
        try core.shutdown(force:true,gracePeriod:0.2)
        precondition(Date().timeIntervalSince(forceStart)<7,"Force shutdown must survive an unresponsive Wine server")
        precondition(!ownedNative.isRunning,"Detached client survived native cleanup")
        precondition(otherPrefix.isRunning && otherRuntime.isRunning,"Unrelated processes were terminated")
        try fm.removeItem(at:prefix.appendingPathComponent("hang-server"))
        core.resumeLaunches()
        let outside=root.appendingPathComponent("Unmanaged")
        try fm.createDirectory(at:outside,withIntermediateDirectories:true)
        try fm.createSymbolicLink(at:root.appendingPathComponent("Prefixes/escape"),withDestinationURL:outside)
        let escaped=Bottle(id:"escape",name:"Other app",directory:"Prefixes/escape",renderer:.wine)
        try core.mutate{$0.bottles=[escaped]}
        do{try core.shutdown(gracePeriod:1);fatalError("Escaping prefix allowed")}catch is OGError{}
        precondition(!fm.fileExists(atPath:outside.appendingPathComponent("commands").path))
        print("PASS: idle probe, launch barrier, veto, clean shutdown, explicit force, hung query timeout, unresponsive server, detached native cleanup, unrelated process isolation, unmanaged prefix rejection")
    }
}
