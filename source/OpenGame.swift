import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class AppModel: ObservableObject {
    let core=OpenGameCore()
    @Published var library=Library(bottles:[],games:[])
    @Published var status="点击游戏图标或“运行”启动游戏；已运行的游戏会尝试显示原窗口。"
    @Published var error:String?
    @Published var busy=false
    private var processes:[Process]=[]
    private var launching=Set<String>()
    init(){reload()}
    func reload(){do{try core.ensureCatalog();library=try core.load()}catch{self.error=error.localizedDescription}}
    func perform(_ action:()throws->Void){do{try action();reload()}catch{self.error=error.localizedDescription}}
    func start(_ spec:LaunchSpec){do{
        let p=try core.start(spec);processes.removeAll{!$0.isRunning};processes.append(p)
        status=spec.arguments.first.map{URL(fileURLWithPath:$0).lastPathComponent.lowercased()=="steam.exe"} == true ? "Steam 正在启动，首次可能需要约 30 秒；请在弹出的窗口登录。" : "启动请求已发出；可在日志中查看运行结果。"
        p.terminationHandler={ [weak self] process in
            guard process.terminationStatus != 0 && process.terminationStatus != 42 else{return}
            DispatchQueue.main.async{self?.status="程序已退出，返回码 \(process.terminationStatus)。请查看 \(spec.log.lastPathComponent)。"}
        }
    }catch{self.error=error.localizedDescription}}
    func launch(_ game:Game){
        guard !launching.contains(game.id) else{return}
        launching.insert(game.id);status="正在检查 \(game.title)…"
        let service=core
        DispatchQueue.global(qos:.userInitiated).async{
            let result=Result{try service.runningGameStatus(game)}
            DispatchQueue.main.async{
                switch result {
                case .success(let existing):
                    if let existing=existing {self.status=existing}
                    else {do{self.start(try service.gameSpec(game))}catch{self.error=error.localizedDescription}}
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

@main struct OpenGameApp:App {
    @StateObject private var model=AppModel()
    var body:some Scene{
        WindowGroup("OpenGame") {ContentView().environmentObject(model).frame(minWidth:940,minHeight:650)}
        .defaultSize(width:1040,height:710)
        .commands{CommandGroup(after:.newItem){Button("刷新游戏库"){model.reload()}.keyboardShortcut("r")}}
    }
}

struct ContentView:View{
    @EnvironmentObject var model:AppModel
    @State private var selectedBottle="all"
    @State private var selectedGame:String?
    @State private var search=""
    @State private var showImport=false
    @State private var showInstall=false
    @State private var showCreate=false
    @State private var editGame:Game?
    @State private var editBottle:Bottle?
    @State private var copySource:Bottle?
    var games:[Game]{model.library.games.filter{(selectedBottle=="all" || $0.bottleID==selectedBottle) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))}}
    var current:Game?{games.first{$0.id==selectedGame}}
    var title:String{model.library.bottles.first{$0.id==selectedBottle}?.name ?? "所有游戏"}
    var preferredBottle:String{selectedBottle=="all" ? (model.library.bottles.first?.id ?? "") : selectedBottle}
    func openSteam(){
        let available=model.library.bottles.filter{b in (try? model.core.prefix(b).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")).map{FileManager.default.fileExists(atPath:$0.path)} ?? false}
        guard let b=available.first(where:{$0.id==selectedBottle}) ?? available.first else{model.error="尚未找到 Steam。请先在一个容器中运行 Steam 安装程序。";return}
        do{let file=try model.core.prefix(b).appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe");model.start(try model.core.spec(bottle:b,arguments:[file.path],directory:file.deletingLastPathComponent(),logID:"steam-\(b.id)"))}catch{model.error=error.localizedDescription}
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
                    Text("OpenGame 0.4.1\n独立 Wine 游戏管理器").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
            }
        }detail:{
            VStack(alignment:.leading,spacing:0){
                HStack(alignment:.center){
                    VStack(alignment:.leading,spacing:4){Text(title).font(.largeTitle.bold());Text("\(games.count) 个游戏").foregroundStyle(.secondary)}
                    Spacer()
                    Button("添加游戏",systemImage:"plus.app"){showImport=true}.controlSize(.large)
                    Button("运行安装程序",systemImage:"square.and.arrow.down"){showInstall=true}.controlSize(.large)
                }.padding(24)
                HStack{
                    TextField("搜索游戏",text:$search).textFieldStyle(.roundedBorder).frame(maxWidth:300)
                    Spacer()
                    Menu("容器工具"){
                        ForEach(model.library.bottles){b in
                            Menu(b.name){
                                Button("容器设置与图形后端"){editBottle=b}
                                Button("复制容器"){copySource=b}.disabled(model.busy)
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
                                Button {selectedGame=game.id;model.launch(game)} label: {
                                VStack(spacing:10){
                                    GameIcon(core:model.core,game:game,size:80)
                                    Text(game.title).font(.headline).lineLimit(2).multilineTextAlignment(.center).frame(height:36)
                                    Text(model.library.bottles.first{$0.id==game.bottleID}?.name ?? "").font(.caption).foregroundStyle(.secondary)
                                    Label("运行",systemImage:"play.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                                }.frame(maxWidth:.infinity).padding(.vertical,16)
                                .background(selectedGame==game.id ? Color.accentColor.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius:12))
                                .overlay(RoundedRectangle(cornerRadius:12).stroke(selectedGame==game.id ? Color.accentColor.opacity(0.45) : .clear))
                                .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("启动 "+game.title)
                                .accessibilityHint("已运行时显示原游戏窗口")
                                .accessibilityIdentifier("launch-"+game.id)
                                .contextMenu{
                                    Button("运行"){model.launch(game)}
                                    Button("游戏设置"){editGame=game}
                                    Button("打开所在文件夹"){model.show(URL(fileURLWithPath:game.workingDirectory))}
                                    Divider()
                                    Button("从列表移除（保留文件）"){model.perform{try model.core.removeGame(game.id)}}
                                }
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
                        Button("运行",systemImage:"play.fill"){model.launch(game)}.buttonStyle(.borderedProminent).controlSize(.large)
                    }.padding(18)
                }else{Text("新游戏的兼容性需要分别验证；不支持的反作弊或图形接口可能阻止运行。").font(.caption).foregroundStyle(.secondary).padding(18)}
                HStack{if model.busy{ProgressView().controlSize(.small)};Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2);Spacer()}.padding(.horizontal,18).padding(.bottom,12)
            }.background(Color(nsColor:.windowBackgroundColor))
        }
        .sheet(isPresented:$showImport){GameEditor(bottleID:preferredBottle)}
        .sheet(item:$editGame){game in GameEditor(bottleID:game.bottleID,existing:game)}
        .sheet(isPresented:$showInstall){InstallerSheet(bottleID:preferredBottle)}
        .sheet(isPresented:$showCreate){CreateBottleSheet()}
        .sheet(item:$editBottle){b in BottleEditor(bottle:b)}
        .sheet(item:$copySource){b in CopyBottleSheet(source:b)}
        .alert("OpenGame",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})){Button("确定",role:.cancel){model.error=nil}}message:{Text(model.error ?? "")}
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)){_ in model.reload()}
        .onChange(of:selectedBottle){selectedGame=nil}
    }
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
            Text("更换核心前请退出此容器的所有程序。性能核心已通过 DXMT 窗口呈现和 MSync 测试，真实游戏仍需逐款验证；部分视频播放尚未兼容。原核心的 DXMT 窗口呈现存在已知故障。").font(.callout).foregroundStyle(.secondary)
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
    @State private var renderer=Renderer.dxvk
    @State private var engineFamily=EngineFamily.winehq
    var body:some View{
        VStack(alignment:.leading,spacing:20){
            Text("新建独立容器").font(.title2.bold())
            TextField("例如：新游戏",text:$name).textFieldStyle(.roundedBorder)
            Picker("运行核心",selection:$engineFamily){ForEach(EngineFamily.allCases,id:\.self){Text($0.label).tag($0)}}
            Picker("图形后端",selection:$renderer){ForEach(Renderer.allCases,id:\.self){Text($0.label).tag($0)}}
            Text("创建 Windows 10 兼容环境，同时支持 32 位和 64 位程序。每个容器有独立的游戏配置与存档。DirectX 12 与内核反作弊不在当前支持范围内。").font(.callout).foregroundStyle(.secondary)
            HStack{if model.busy{ProgressView().controlSize(.small);Text("正在初始化…")};Spacer();Button("取消"){dismiss()}.disabled(model.busy);Button("创建"){model.create(name:name,renderer:renderer,engineFamily:engineFamily){ok in if ok{dismiss()}}}.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.busy)}
        }.padding(26).frame(width:520)
    }
}
