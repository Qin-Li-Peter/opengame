import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class AppModel: ObservableObject {
    let core=OpenGameCore()
    @Published var library=Library(bottles:[],games:[])
    @Published var status="单击选中游戏，双击启动；已运行的游戏会尝试显示原窗口。"
    @Published var error:String?
    @Published var busy=false
    @Published var isQuitting=false
    @Published var runtimeStatus="正在检查运行核心…"
    private var processes:[Process]=[]
    private var launching=Set<String>()
    init(){core.resumeLaunches();reload()}
    func reload(){do{try core.ensureCatalog();library=try core.load();runtimeStatus=core.runtimeStatus()}catch{self.error=error.localizedDescription}}
    func perform(_ action:()throws->Void){do{try action();reload()}catch{self.error=error.localizedDescription}}
    func start(_ spec:LaunchSpec,game:Game?=nil){guard !isQuitting else{return};do{
        let p=try core.start(spec);processes.removeAll{!$0.isRunning};processes.append(p)
        status=game.map{"\($0.title) 正在启动…"} ?? (spec.arguments.first.map{URL(fileURLWithPath:$0).lastPathComponent.lowercased()=="steam.exe"} == true ? "Steam 正在启动，首次可能需要约 30 秒；请在弹出的窗口登录。" : "启动请求已发出；可在日志中查看运行结果。")
        p.terminationHandler={ [weak self] process in
            guard process.terminationStatus != 0 && process.terminationStatus != 42 else{return}
            guard let self else{return}
            if let game {
                DispatchQueue.global(qos:.userInitiated).async{
                    // Steam can return a nonzero launcher code while it keeps
                    // completing the game handshake in the background. Treat
                    // the real game process as authoritative and keep the UI in
                    // its startup state for one cold-start window.
                    let deadline=Date().addingTimeInterval(60)
                    var running:String?
                    repeat {
                        running=try? self.core.nativeRunningGameStatus(game)
                        if running == nil {Thread.sleep(forTimeInterval:0.5)}
                    } while running == nil && Date()<deadline
                    DispatchQueue.main.async{guard !self.isQuitting else{return};self.status=running ?? "程序已退出，返回码 \(process.terminationStatus)。请查看 \(spec.log.lastPathComponent)。"}
                }
            } else {
                DispatchQueue.main.async{guard !self.isQuitting else{return};self.status="程序已退出，返回码 \(process.terminationStatus)。请查看 \(spec.log.lastPathComponent)。"}
            }
        }
    }catch{self.error=error.localizedDescription}}
    func launch(_ game:Game){
        guard !isQuitting && !launching.contains(game.id) else{return}
        launching.insert(game.id);status="正在检查 \(game.title)…"
        let service=core
        DispatchQueue.global(qos:.userInitiated).async{
            let result=Result{() -> (String?,LaunchSpec?) in
                if let existing=try service.runningGameStatus(game){return(existing,nil)}
                try service.prepareGameInput(for:game)
                try service.prepareSteam(for:game)
                return(nil,try service.gameSpec(game))
            }
            DispatchQueue.main.async{
                switch result {
                case .success(let (existing,spec)):
                    if let existing=existing {self.status=existing}
                    else if let spec=spec {self.start(spec,game:game)}
                case .failure(let error):self.error=error.localizedDescription
                }
                DispatchQueue.main.asyncAfter(deadline:.now()+2){self.launching.remove(game.id)}
            }
        }
    }
    func runTool(_ b:Bottle,_ tool:String){do{start(try core.toolSpec(bottle:b,tool:tool))}catch{self.error=error.localizedDescription}}
    func show(_ url:URL){NSWorkspace.shared.open(url)}
    func create(name:String,renderer:Renderer,engineFamily:EngineFamily,done:@escaping(Bool)->Void){
        busy=true;status="正在创建独立容器，首次初始化可能需要一两分钟。"
        let service=core
        DispatchQueue.global(qos:.userInitiated).async{
            let result=Result{try service.createBottle(name:name,renderer:renderer,engineFamily:engineFamily)}
            DispatchQueue.main.async{self.busy=false;switch result{case .success(let b):self.reload();self.status="容器“\(b.name)”已就绪，可以安装或添加游戏。";done(true)
                case .failure(let error):self.error=error.localizedDescription;done(false)}}
        }
    }
    func scan(_ b:Bottle){busy=true
        let service=core
        DispatchQueue.global(qos:.userInitiated).async{
            let result=Result{try service.scanSteam(bottle:b)}
            DispatchQueue.main.async{self.busy=false;switch result{case .success(let n):self.reload();self.status="Steam 扫描完成，新增 \(n) 个游戏。";case .failure(let e):self.error=e.localizedDescription}}
        }
    }
    func copy(_ b:Bottle,name:String,done:@escaping(Bool)->Void){
        busy=true;status="正在复制容器，游戏文件较多时可能需要稍候。";let service=core
        DispatchQueue.global(qos:.userInitiated).async{
            let result=Result{try service.copyBottle(b,name:name)}
            DispatchQueue.main.async{self.busy=false;switch result{case .success(let copied):self.reload();self.status="容器“\(copied.name)”已复制。";done(true);case .failure(let e):self.error=e.localizedDescription;done(false)}}
        }
    }
    func exportBottle(_ bottle:Bottle,to url:URL){
        busy=true;status="正在归档容器“\(bottle.name)”…";let service=core
        DispatchQueue.global(qos:.userInitiated).async{
            let result=Result{try service.exportBottle(bottle,to:url)}
            DispatchQueue.main.async{self.busy=false;switch result{case .success:self.status="容器已归档到 \(url.lastPathComponent)。";case .failure(let error):self.error=error.localizedDescription}}
        }
    }
    func importBottle(from url:URL){
        busy=true;status="正在验证并恢复容器归档…";let service=core
        DispatchQueue.global(qos:.userInitiated).async{
            let result=Result{try service.importBottle(from:url)}
            DispatchQueue.main.async{self.busy=false;switch result{case .success(let bottle):self.reload();self.status="容器“\(bottle.name)”已恢复。";case .failure(let error):self.error=error.localizedDescription}}
        }
    }
    func installRecipe(_ recipe:InstallRecipe,in bottle:Bottle,done:@escaping(Bool)->Void){
        busy=true;status="正在准备 \(recipe.name)…";let service=core
        DispatchQueue.global(qos:.userInitiated).async{
            let result=Result{try service.installRecipe(recipe,in:bottle){message in DispatchQueue.main.async{self.status=message}}}
            DispatchQueue.main.async{self.busy=false;switch result{case .success:self.status="\(recipe.name) 已安装到“\(bottle.name)”。";done(true);case .failure(let error):self.error=error.localizedDescription;done(false)}}
        }
    }
    func requestQuit(_ reply:@escaping(Bool)->Void) {
        isQuitting=true
        status=busy ? "正在等待容器操作完成，然后退出…" : "正在关闭游戏与 Steam…"
        waitForOperationsThenQuit(reply)
    }
    private func waitForOperationsThenQuit(_ reply:@escaping(Bool)->Void) {
        if busy {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.1){self.waitForOperationsThenQuit(reply)}
        } else {finishQuit(force:false,reply:reply)}
    }
    private func finishQuit(force:Bool,reply:@escaping(Bool)->Void) {
        status=force ? "正在关闭 OpenGame 的运行环境…" : "正在关闭游戏与 Steam…"
        let service=core
        DispatchQueue.global(qos:.userInitiated).async {
            let result=Result{
                if force {try service.shutdown(force:true)}
                else {
                    do {try service.shutdown(force:false,gracePeriod:5)}
                    catch {try service.shutdown(force:true)}
                }
            }
            DispatchQueue.main.async {
                switch result {
                case .success:reply(true)
                case .failure(let error):
                    let alert=NSAlert();alert.alertStyle = .warning
                    alert.messageText="无法关闭 OpenGame 的运行环境"
                    alert.informativeText=error.localizedDescription
                    alert.addButton(withTitle:"确定")
                    _=alert.runModal()
                    self.core.resumeLaunches();self.isQuitting=false;self.status="退出失败，请查看 shutdown.log。";reply(false)
                }
            }
        }
    }

}

struct GameIcon:View {
    let core:OpenGameCore;let game:Game;var size:CGFloat=76
    var body:some View{
        Group{
            if let icon=game.icon,let image=NSImage(contentsOf:core.path(icon)){
                Image(nsImage:image).resizable().interpolation(.high).scaledToFit()
            }else{
                Image(nsImage:NSWorkspace.shared.icon(forFile:game.executable)).resizable().scaledToFit()
            }
        }.frame(width:size,height:size).accessibilityLabel(game.title+" 原始图标")
    }
}

@MainActor final class OpenGameAppDelegate:NSObject,NSApplicationDelegate {
    weak var model:AppModel?
    private var terminationPending=false
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard let model=model else{return .terminateNow}
        if !terminationPending {
            terminationPending=true
            model.requestQuit { [weak self,weak sender] shouldQuit in
                self?.terminationPending=false
                sender?.reply(toApplicationShouldTerminate:shouldQuit)
            }
        }
        return .terminateLater
    }
}

@main struct OpenGameApp:App {
    @NSApplicationDelegateAdaptor(OpenGameAppDelegate.self) private var appDelegate
    @StateObject private var model=AppModel()
    var body:some Scene{
        WindowGroup("OpenGame") {
            ContentView().environmentObject(model).frame(minWidth:940,minHeight:650)
                .disabled(model.isQuitting)
                .overlay {
                    if model.isQuitting {
                        VStack(spacing:14){ProgressView();Text(model.status).multilineTextAlignment(.center)}
                            .padding(28).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
                    }
                }
                .onAppear{appDelegate.model=model}
        }
        .defaultSize(width:1040,height:710)
        .commands{CommandGroup(after:.newItem){Button("刷新游戏库"){model.reload()}.keyboardShortcut("r").disabled(model.isQuitting)}}
    }
}

struct ContentView:View{
    @EnvironmentObject var model:AppModel
    @State private var selectedBottle="all"
    @State private var selectedGame:String?
    @State private var search=""
    @State private var showImport=false
    @State private var showInstall=false
    @State private var showRecipes=false
    @State private var showCreate=false
    @State private var editGame:Game?
    @State private var editBottle:Bottle?
    @State private var copySource:Bottle?
    var games:[Game]{model.library.games.filter{(selectedBottle=="all" || $0.bottleID==selectedBottle) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))}}
    var current:Game?{games.first{$0.id==selectedGame}}
    var title:String{model.library.bottles.first{$0.id==selectedBottle}?.name ?? "所有游戏"}
    var version:String{Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""}
    var preferredBottle:String{selectedBottle=="all" ? (model.library.bottles.first?.id ?? "") : selectedBottle}
    func openSteam(){
        let available=model.library.bottles.filter{b in (try? model.core.prefix(b).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")).map{FileManager.default.fileExists(atPath:$0.path)} ?? false}
        guard let b=available.first(where:{$0.id==selectedBottle}) ?? available.first else{model.error="尚未找到 Steam。请先在一个容器中运行 Steam 安装程序。";return}
        do{let file=try model.core.prefix(b).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe");model.start(try model.core.spec(bottle:b,arguments:[file.path],directory:file.deletingLastPathComponent(),logID:"steam-\(b.id)"))}catch{model.error=error.localizedDescription}
    }
    func exportBottle(_ bottle:Bottle){
        let panel=NSSavePanel();panel.nameFieldStringValue=bottle.name+".opengamebottle";panel.canCreateDirectories=true
        panel.begin{response in guard response == .OK,var url=panel.url else{return};if url.pathExtension.lowercased() != "opengamebottle"{url.appendPathExtension("opengamebottle")};model.exportBottle(bottle,to:url)}
    }
    func importBottle(){
        let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=false;panel.allowedContentTypes=[UTType(filenameExtension:"opengamebottle") ?? .data]
        panel.begin{response in if response == .OK,let url=panel.url{model.importBottle(from:url)}}
    }
    private func gameCard(_ game:Game)->some View {
        VStack(spacing:10){
            GameIcon(core:model.core,game:game,size:80)
            Text(game.title).font(.headline).lineLimit(2).multilineTextAlignment(.center).frame(height:36)
            Text(model.library.bottles.first{$0.id==game.bottleID}?.name ?? "").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity).padding(.vertical,16)
        .background(selectedGame==game.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius:12))
        .overlay(RoundedRectangle(cornerRadius:12).stroke(selectedGame==game.id ? Color.accentColor.opacity(0.45) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count:2){selectedGame=game.id;model.launch(game)}
        .simultaneousGesture(DragGesture(minimumDistance:0).onChanged{_ in
            if selectedGame != game.id {selectedGame=game.id}
        })
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(game.title)
        .accessibilityHint("单击选中，双击启动；已运行时显示原游戏窗口")
        .accessibilityIdentifier("launch-"+game.id)
        .contextMenu{
            Button("游戏设置"){editGame=game}
            Button("打开所在文件夹"){model.show(URL(fileURLWithPath:game.workingDirectory))}
            Divider()
            Button("从列表移除（保留文件）"){model.perform{try model.core.removeGame(game.id)}}
        }
    }
    var body:some View{
        NavigationSplitView{
            List(selection:$selectedBottle){
                Label("所有游戏",systemImage:"house").tag("all")
                Section("容器"){
                    ForEach(model.library.bottles){b in
                        Label(b.name,systemImage:"shippingbox").tag(b.id)
                    }
                }
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min:180,ideal:210,max:260)
            .safeAreaInset(edge:.bottom){
                VStack(alignment:.leading,spacing:12){
                    Button("新建容器",systemImage:"plus"){showCreate=true}.disabled(model.busy)
                    HStack(spacing:10){Image(nsImage:NSApplication.shared.applicationIconImage).resizable().frame(width:36,height:36);Text("OpenGame \(version)\n独立 Wine 游戏管理器").font(.caption).foregroundStyle(.secondary)}
                }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
            }
        }detail:{
            VStack(alignment:.leading,spacing:0){
                HStack(alignment:.center){
                    VStack(alignment:.leading,spacing:4){Text(title).font(.largeTitle.bold());Text("\(games.count) 个游戏").foregroundStyle(.secondary)}
                    Spacer()
                    Button("添加游戏",systemImage:"plus.app"){showImport=true}.controlSize(.large)
                    Button("运行安装程序",systemImage:"square.and.arrow.down"){showInstall=true}.controlSize(.large)
                    Button("安装组件",systemImage:"shippingbox.and.arrow.backward"){showRecipes=true}.controlSize(.large)
                }.padding(24)
                HStack{
                    TextField("搜索游戏",text:$search).textFieldStyle(.roundedBorder).frame(maxWidth:300)
                    Spacer()
                    Menu("容器工具"){
                        Button("导入容器归档…",systemImage:"square.and.arrow.down.on.square"){importBottle()}.disabled(model.busy)
                        Divider()
                        ForEach(model.library.bottles){b in
                            Menu(b.name){
                                Button("容器设置与图形后端"){editBottle=b}
                                Button("复制容器"){copySource=b}.disabled(model.busy)
                                Button("导出容器归档…"){exportBottle(b)}.disabled(model.busy)
                                Button("打开 C: 盘"){model.perform{model.show(try model.core.prefix(b).appendingPathComponent("drive_c"))}}
                                Button("Wine 配置"){model.runTool(b,"winecfg")}
                                Button("游戏控制器"){model.runTool(b,"controllers")}
                                Button("任务管理器"){model.runTool(b,"taskmgr")}
                                Button("注册表编辑器"){model.runTool(b,"regedit")}
                                Button("卸载 Windows 程序"){model.runTool(b,"uninstall")}
                                Divider()
                                Button("扫描已安装的 Steam 游戏"){model.scan(b)}
                            }
                        }
                    }
                    Button("Steam"){openSteam()}
                    Button("日志",systemImage:"doc.text.magnifyingglass"){model.show(model.core.path("Logs"))}
                }.padding(.horizontal,24).padding(.bottom,16)
                Divider()
                ScrollView{
                    if games.isEmpty{
                        VStack(spacing:14){Image(systemName:"gamecontroller").font(.system(size:42)).foregroundStyle(.secondary);Text("这里还没有游戏").font(.title2);Text("添加已有的 EXE，或先运行安装程序。\nSteam 安装完成后，可以从容器工具中扫描游戏。").multilineTextAlignment(.center).foregroundStyle(.secondary)}.frame(maxWidth:.infinity).padding(.top,70)
                    }else{
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:160,maximum:210),spacing:18)],spacing:20){
                            ForEach(games){game in
                                gameCard(game)
                            }
                        }.padding(24)
                    }
                }
                Divider()
                if let game=current{
                    HStack(spacing:14){
                        GameIcon(core:model.core,game:game,size:42)
                        VStack(alignment:.leading,spacing:4){Text(game.title).font(.headline);Text(game.note).font(.caption).foregroundStyle(.secondary)}
                        Spacer()
                        Button("设置"){editGame=game}
                    }.padding(18)
                }else{Text("新游戏的兼容性需要分别验证；不支持的反作弊或图形接口可能阻止运行。").font(.caption).foregroundStyle(.secondary).padding(18)}
                HStack{if model.busy{ProgressView().controlSize(.small)};VStack(alignment:.leading,spacing:2){Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2);Text(model.runtimeStatus).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)};Spacer()}.padding(.horizontal,18).padding(.bottom,12)
            }.background(Color(nsColor:.windowBackgroundColor))
        }
        .sheet(isPresented:$showImport){GameEditor(bottleID:preferredBottle)}
        .sheet(item:$editGame){game in GameEditor(bottleID:game.bottleID,existing:game)}
        .sheet(isPresented:$showInstall){InstallerSheet(bottleID:preferredBottle)}
        .sheet(isPresented:$showRecipes){RecipeSheet(bottleID:preferredBottle)}
        .sheet(isPresented:$showCreate){CreateBottleSheet()}
        .sheet(item:$editBottle){b in BottleEditor(bottle:b)}
        .sheet(item:$copySource){b in CopyBottleSheet(source:b)}
        .alert("OpenGame",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})){Button("确定",role:.cancel){model.error=nil}}message:{Text(model.error ?? "")}
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)){_ in model.reload()}
        .onChange(of:selectedBottle){selectedGame=nil}
    }
}

struct RecipeSheet:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @State var bottleID:String
    @State private var recipes:[InstallRecipe]=[]
    @State private var selected=""
    @State private var message:String?
    var body:some View{
        VStack(alignment:.leading,spacing:18){
            Text("安装常用组件").font(.title2.bold())
            Picker("安装到容器",selection:$bottleID){ForEach(model.library.bottles){Text($0.name).tag($0.id)}}
            List(recipes,selection:$selected){recipe in VStack(alignment:.leading,spacing:4){Text(recipe.name).font(.headline);Text(recipe.summary).font(.caption).foregroundStyle(.secondary)}.padding(.vertical,5).tag(recipe.id)}.frame(height:220)
            Text("OpenGame 只从配方列出的官方 HTTPS 地址下载，并在运行前校验 SHA-256。若厂商更新文件，旧配方会安全失败，等待 OpenGame 更新校验值。组件许可由对应厂商提供。").font(.callout).foregroundStyle(.secondary)
            if let message=message{Text(message).foregroundStyle(.red)}
            HStack{if model.busy{ProgressView().controlSize(.small)};Spacer();Button("取消"){dismiss()}.disabled(model.busy);Button("下载并安装"){install()}.buttonStyle(.borderedProminent).disabled(selected.isEmpty || model.busy)}
        }.padding(26).frame(width:610)
        .onAppear{do{recipes=try model.core.availableRecipes();selected=recipes.first?.id ?? ""}catch{message=error.localizedDescription}}
    }
    func install(){guard let recipe=recipes.first(where:{$0.id==selected}),let bottle=model.library.bottles.first(where:{$0.id==bottleID}) else{return};model.installRecipe(recipe,in:bottle){ok in if ok{dismiss()}}}
}

struct BottleEditor:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @State var bottle:Bottle
    @State private var message:String?
    var body:some View{
        VStack(alignment:.leading,spacing:20){
            Text("容器设置").font(.title2.bold())
            TextField("容器名称",text:$bottle.name).textFieldStyle(.roundedBorder)
            Picker("运行核心",selection:Binding(get:{bottle.engineFamily ?? .winehq},set:{bottle.engineFamily=$0})){ForEach(EngineFamily.allCases,id:\.self){Text($0.label).tag($0)}}
            Picker("图形后端",selection:$bottle.renderer){ForEach(Renderer.allCases,id:\.self){Text($0.label).tag($0)}}
            Text("更换核心前请退出此容器的所有程序。推荐核心已通过 DXMT 窗口呈现和 MSync 测试，真实游戏仍需逐款验证；部分视频播放尚未兼容。WineHQ 兼容核心的 DXMT 窗口呈现存在已知故障。").font(.callout).foregroundStyle(.secondary)
            if let message=message{Text(message).foregroundStyle(.red)}
            HStack{Spacer();Button("取消"){dismiss()};Button("保存"){do{try model.core.updateBottle(bottle);model.reload();dismiss()}catch{message=error.localizedDescription}}.buttonStyle(.borderedProminent)}
        }.padding(26).frame(width:550)
    }
}

struct CopyBottleSheet:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    let source:Bottle
    @State private var name=""
    var body:some View{
        VStack(alignment:.leading,spacing:20){
            Text("复制容器").font(.title2.bold())
            TextField("副本名称",text:$name).textFieldStyle(.roundedBorder)
            Text("请先退出原容器内的游戏与 Steam。副本会包含容器内的文件、配置、存档和游戏入口；位于容器外的游戏仍引用原文件夹。原容器保留。").font(.callout).foregroundStyle(.secondary)
            HStack{if model.busy{ProgressView().controlSize(.small)};Spacer();Button("取消"){dismiss()}.disabled(model.busy);Button("复制"){model.copy(source,name:name){ok in if ok{dismiss()}}}.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.busy)}
        }.padding(26).frame(width:540).onAppear{name=source.name+" 副本"}
    }
}

struct GameEditor:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @State var bottleID:String
    var existing:Game?=nil
    @State private var name=""
    @State private var executable=""
    @State private var arguments=""
    @State private var message:String?
    @State private var saving=false
    var body:some View{
        VStack(alignment:.leading,spacing:18){
            Text(existing==nil ? "添加已有游戏" : "游戏设置").font(.title2.bold())
            Form{
                TextField("名称",text:$name)
                Picker("运行容器",selection:$bottleID){ForEach(model.library.bottles){Text($0.name).tag($0.id)}}.disabled(existing?.steamID != nil)
                HStack{TextField("Windows EXE",text:$executable).disabled(existing?.steamID != nil);Button("浏览…"){choose()}.disabled(existing?.steamID != nil)}
                Text("启动参数（每行一个参数）").font(.caption).foregroundStyle(.secondary)
                TextEditor(text:$arguments).font(.system(.body,design:.monospaced)).frame(height:72).border(Color.secondary.opacity(0.25))
            }
            Text("直接使用所选文件及其所在文件夹，添加入口不会复制或删除游戏。请保留完整游戏文件夹；需要安装的游戏请先运行安装程序。图标自动从 EXE 中提取。").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if let message=message{Text(message).foregroundStyle(.red).font(.callout)}
            HStack{Spacer();Button("取消"){dismiss()}.disabled(saving);Button(existing==nil ? "添加" : "保存"){save()}.buttonStyle(.borderedProminent).disabled(executable.isEmpty || saving)}
        }.padding(26).frame(width:600)
        .onAppear{if let game=existing{name=game.title;executable=game.executable;arguments=game.arguments.joined(separator:"\n")}}
    }
    func choose(){let p=NSOpenPanel();p.canChooseDirectories=false;p.allowsMultipleSelection=false;p.allowedContentTypes=[UTType(filenameExtension:"exe") ?? .data];p.begin{response in if response == .OK,let url=p.url{executable=url.path;if name.isEmpty{name=url.deletingPathExtension().lastPathComponent}}}}
    func save(){
        saving=true
        let args=arguments.split(separator:"\n",omittingEmptySubsequences:true).map(String.init)
        let file=URL(fileURLWithPath:executable),title=name,bottle=bottleID,old=existing
        let service=model.core
        DispatchQueue.global(qos:.userInitiated).async{
            let result=Result{()throws->Void in
                if var game=old{guard FileManager.default.fileExists(atPath:file.path) else{throw OGError.message("游戏文件不存在。")};game.title=title;game.executable=file.path;game.workingDirectory=file.deletingLastPathComponent().path;game.bottleID=bottle;game.arguments=args;try service.updateGame(game)}
                else{_ = try service.importGame(executable:file,title:title,bottleID:bottle,arguments:args)}
            }
            DispatchQueue.main.async{saving=false;switch result{case .success:model.reload();model.status="游戏入口已保存；可以开始兼容性验证。";dismiss();case .failure(let e):message=e.localizedDescription}}
        }
    }
}
struct InstallerSheet:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @State var bottleID:String
    @State private var filePath=""
    @State private var message:String?
    var body:some View{
        VStack(alignment:.leading,spacing:20){
            Text("运行 Windows 安装程序").font(.title2.bold())
            Picker("安装到容器",selection:$bottleID){ForEach(model.library.bottles){Text($0.name).tag($0.id)}}
            HStack{TextField("EXE 或 MSI 文件路径",text:$filePath).textFieldStyle(.roundedBorder);Button("选择文件…"){let p=NSOpenPanel();p.canChooseDirectories=false;p.allowsMultipleSelection=false;p.allowedContentTypes=[UTType(filenameExtension:"exe") ?? .data,UTType(filenameExtension:"msi") ?? .data];p.begin{response in if response == .OK,let url=p.url{filePath=url.path}}}}
            Text("安装向导将在所选的独立 Windows 环境中运行。请自行完成安装向导；安装结束后，通过“添加游戏”选择容器 C: 盘中的游戏主程序。也可以用此入口安装游戏需要的运行库。").font(.callout).foregroundStyle(.secondary)
            if let message=message{Text(message).foregroundStyle(.red)}
            HStack{Spacer();Button("取消"){dismiss()};Button("运行安装程序"){run()}.buttonStyle(.borderedProminent).disabled(filePath.isEmpty)}
        }.padding(26).frame(width:540)
    }
    func run(){guard let b=model.library.bottles.first(where:{$0.id==bottleID}) else{return};do{model.start(try model.core.installerSpec(file:URL(fileURLWithPath:filePath),bottle:b));dismiss()}catch{message=error.localizedDescription}}
}
struct CreateBottleSheet:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @State private var name=""
    @State private var renderer=Renderer.dxmt
    private let engineFamily=EngineFamily.foss
    var body:some View{
        VStack(alignment:.leading,spacing:20){
            Text("新建独立容器").font(.title2.bold())
            TextField("例如：新游戏",text:$name).textFieldStyle(.roundedBorder)
            LabeledContent("运行核心"){Text(engineFamily.label).foregroundStyle(.secondary)}
            Picker("图形后端",selection:$renderer){ForEach(Renderer.allCases,id:\.self){Text($0.label).tag($0)}}
            Text("默认使用 Wine FOSS 11 + MSync 与 DXMT 创建 Windows 10 兼容环境，同时支持 32 位和 64 位程序。每个容器有独立的游戏配置与存档。DirectX 12 与内核反作弊不在当前支持范围内。").font(.callout).foregroundStyle(.secondary)
            HStack{if model.busy{ProgressView().controlSize(.small);Text("正在初始化…")};Spacer();Button("取消"){dismiss()}.disabled(model.busy);Button("创建"){model.create(name:name,renderer:renderer,engineFamily:engineFamily){ok in if ok{dismiss()}}}.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.busy)}
        }.padding(26).frame(width:520)
    }
}
