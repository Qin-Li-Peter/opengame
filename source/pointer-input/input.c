/* SPDX-License-Identifier: MIT
 * OpenGame Unity input adapter. The current game's UnityPlayer import table
 * is redirected to a local implementation of the missing Wine pointer APIs.
 * No on-disk game instructions or shared Wine libraries are changed.
 */
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <windowsx.h>
#include <stdio.h>
#include <string.h>
static HMODULE versions;
static HHOOK input_hook;
static POINTER_INFO pointer_state;
static BOOL enabled;
static FILE *diagnostic;
static unsigned click_count;
static void record(const char *text) {
    if(diagnostic){fprintf(diagnostic,"%s\n",text);fflush(diagnostic);}
}
static FARPROC version_api(const char *name) {
    if(!versions) versions=LoadLibraryW(L"C:\\windows\\system32\\version.dll");
    return versions ? GetProcAddress(versions,name) : NULL;
}
#define PROXY(ret, name, params, args, failure) \
ret WINAPI OG_##name params { \
    typedef ret (WINAPI *Function) params; \
    union { FARPROC generic; Function typed; } api; \
    api.generic=version_api(#name); \
    return api.typed ? api.typed args : failure; \
}
PROXY(BOOL,GetFileVersionInfoA,(LPCSTR a,DWORD b,DWORD c,LPVOID d),(a,b,c,d),FALSE)
PROXY(BOOL,GetFileVersionInfoW,(LPCWSTR a,DWORD b,DWORD c,LPVOID d),(a,b,c,d),FALSE)
PROXY(DWORD,GetFileVersionInfoSizeA,(LPCSTR a,LPDWORD b),(a,b),0)
PROXY(DWORD,GetFileVersionInfoSizeW,(LPCWSTR a,LPDWORD b),(a,b),0)
PROXY(BOOL,VerQueryValueA,(LPCVOID a,LPCSTR b,LPVOID *c,PUINT d),(a,b,c,d),FALSE)
PROXY(BOOL,VerQueryValueW,(LPCVOID a,LPCWSTR b,LPVOID *c,PUINT d),(a,b,c,d),FALSE)
PROXY(BOOL,GetFileVersionInfoExA,(DWORD a,LPCSTR b,DWORD c,DWORD d,LPVOID e),(a,b,c,d,e),FALSE)
PROXY(BOOL,GetFileVersionInfoExW,(DWORD a,LPCWSTR b,DWORD c,DWORD d,LPVOID e),(a,b,c,d,e),FALSE)
PROXY(DWORD,GetFileVersionInfoSizeExA,(DWORD a,LPCSTR b,LPDWORD c),(a,b,c),0)
PROXY(DWORD,GetFileVersionInfoSizeExW,(DWORD a,LPCWSTR b,LPDWORD c),(a,b,c),0)
PROXY(DWORD,VerLanguageNameA,(DWORD a,LPSTR b,DWORD c),(a,b,c),0)
PROXY(DWORD,VerLanguageNameW,(DWORD a,LPWSTR b,DWORD c),(a,b,c),0)
PROXY(DWORD,VerFindFileA,(DWORD a,LPCSTR b,LPCSTR c,LPCSTR d,LPSTR e,PUINT f,LPSTR g,PUINT h),(a,b,c,d,e,f,g,h),0)
PROXY(DWORD,VerFindFileW,(DWORD a,LPCWSTR b,LPCWSTR c,LPCWSTR d,LPWSTR e,PUINT f,LPWSTR g,PUINT h),(a,b,c,d,e,f,g,h),0)
PROXY(DWORD,VerInstallFileA,(DWORD a,LPCSTR b,LPCSTR c,LPCSTR d,LPCSTR e,LPCSTR f,LPSTR g,PUINT h),(a,b,c,d,e,f,g,h),0)
PROXY(DWORD,VerInstallFileW,(DWORD a,LPCWSTR b,LPCWSTR c,LPCWSTR d,LPCWSTR e,LPCWSTR f,LPWSTR g,PUINT h),(a,b,c,d,e,f,g,h),0)
static BOOL WINAPI pointer_info(UINT32 id, POINTER_INFO *info) {
    if(id!=1 || !info){SetLastError(ERROR_INVALID_PARAMETER);return FALSE;}
    *info=pointer_state;return TRUE;
}
static BOOL WINAPI pointer_type(UINT32 id, POINTER_INPUT_TYPE *type) {
    if(id!=1 || !type){SetLastError(ERROR_INVALID_PARAMETER);return FALSE;}
    *type=PT_MOUSE;return TRUE;
}
static BOOL WINAPI pointer_enabled(void){return enabled;}
static BOOL WINAPI pointer_devices(UINT32 *count, POINTER_DEVICE_INFO *devices) {
    (void)devices;
    if(!count){SetLastError(ERROR_INVALID_PARAMETER);return FALSE;}
    // A mouse is a non-integrated pointer; no pen or touch hardware is exposed.
    *count=0;return TRUE;
}
static void dispatch_pointer(MSG *message) {
    UINT type=WM_POINTERUPDATE;POINTER_BUTTON_CHANGE_TYPE change=POINTER_CHANGE_NONE;
    DWORD flags=POINTER_FLAG_PRIMARY|POINTER_FLAG_INRANGE;
    WORD keys=LOWORD(message->wParam);
    if(keys & MK_LBUTTON) flags|=POINTER_FLAG_FIRSTBUTTON|POINTER_FLAG_INCONTACT;
    if(keys & MK_RBUTTON) flags|=POINTER_FLAG_SECONDBUTTON|POINTER_FLAG_INCONTACT;
    if(keys & MK_MBUTTON) flags|=POINTER_FLAG_THIRDBUTTON|POINTER_FLAG_INCONTACT;
    switch(message->message) {
    case WM_MOUSEMOVE:flags|=POINTER_FLAG_UPDATE;break;
    case WM_LBUTTONDOWN:type=WM_POINTERDOWN;flags|=POINTER_FLAG_DOWN;change=POINTER_CHANGE_FIRSTBUTTON_DOWN;break;
    case WM_LBUTTONUP:type=WM_POINTERUP;flags|=POINTER_FLAG_UP;change=POINTER_CHANGE_FIRSTBUTTON_UP;break;
    case WM_RBUTTONDOWN:type=WM_POINTERDOWN;flags|=POINTER_FLAG_DOWN;change=POINTER_CHANGE_SECONDBUTTON_DOWN;break;
    case WM_RBUTTONUP:type=WM_POINTERUP;flags|=POINTER_FLAG_UP;change=POINTER_CHANGE_SECONDBUTTON_UP;break;
    case WM_MBUTTONDOWN:type=WM_POINTERDOWN;flags|=POINTER_FLAG_DOWN;change=POINTER_CHANGE_THIRDBUTTON_DOWN;break;
    case WM_MBUTTONUP:type=WM_POINTERUP;flags|=POINTER_FLAG_UP;change=POINTER_CHANGE_THIRDBUTTON_UP;break;
    case WM_MOUSEWHEEL:type=WM_POINTERWHEEL;flags|=POINTER_FLAG_WHEEL;break;
    case WM_MOUSEHWHEEL:type=WM_POINTERHWHEEL;flags|=POINTER_FLAG_HWHEEL;break;
    default:return;
    }
    POINT point={GET_X_LPARAM(message->lParam),GET_Y_LPARAM(message->lParam)};
    if(message->message!=WM_MOUSEWHEEL && message->message!=WM_MOUSEHWHEEL) ClientToScreen(message->hwnd,&point);
    BOOL entered=pointer_state.hwndTarget!=message->hwnd;
    pointer_state.pointerType=PT_MOUSE;pointer_state.pointerId=1;
    pointer_state.frameId++;pointer_state.pointerFlags=flags;
    pointer_state.hwndTarget=message->hwnd;pointer_state.sourceDevice=(HANDLE)(ULONG_PTR)1;
    pointer_state.ptPixelLocation=point;pointer_state.ptPixelLocationRaw=point;
    pointer_state.ptHimetricLocation.x=MulDiv(point.x,2540,96);
    pointer_state.ptHimetricLocation.y=MulDiv(point.y,2540,96);
    pointer_state.ptHimetricLocationRaw=pointer_state.ptHimetricLocation;
    pointer_state.dwTime=message->time;pointer_state.historyCount=1;pointer_state.ButtonChangeType=change;
    LARGE_INTEGER counter;QueryPerformanceCounter(&counter);pointer_state.PerformanceCount=counter.QuadPart;
    LPARAM location=MAKELPARAM(point.x,point.y);
    if(entered) SendMessageW(message->hwnd,WM_POINTERENTER,MAKEWPARAM(1,LOWORD(flags|POINTER_FLAG_NEW)),location);
    WPARAM parameters=MAKEWPARAM(1,LOWORD(flags));
    if(type==WM_POINTERWHEEL || type==WM_POINTERHWHEEL) parameters=MAKEWPARAM(1,HIWORD(message->wParam));
    SendMessageW(message->hwnd,type,parameters,location);
    if(type==WM_POINTERDOWN && click_count++<8) record("mouse button forwarded as WM_POINTERDOWN");
}
static LRESULT CALLBACK input_message(int code,WPARAM removed,LPARAM value) {
    if(code>=0 && removed==PM_REMOVE && enabled) dispatch_pointer((MSG*)value);
    return CallNextHookEx(input_hook,code,removed,value);
}
static BOOL WINAPI enable_pointer(BOOL requested) {
    if(requested && !input_hook) input_hook=SetWindowsHookExW(WH_GETMESSAGE,input_message,NULL,GetCurrentThreadId());
    enabled=requested && input_hook!=NULL;
    record(enabled ? "pointer input enabled; thread hook active" : "pointer input disabled or hook failed");
    return !requested || enabled;
}
static void redirect_unity_imports(void) {
    BYTE *module=(BYTE*)GetModuleHandleW(L"UnityPlayer.dll");
    if(!module){record("UnityPlayer not loaded");return;}
    IMAGE_DOS_HEADER *dos=(IMAGE_DOS_HEADER*)module;
    IMAGE_NT_HEADERS64 *nt=(IMAGE_NT_HEADERS64*)(module+dos->e_lfanew);
    DWORD directory=nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    if(!directory)return;
    unsigned replaced=0;
    for(IMAGE_IMPORT_DESCRIPTOR *library=(IMAGE_IMPORT_DESCRIPTOR*)(module+directory);library->Name;library++) {
        if(_stricmp((char*)module+library->Name,"user32.dll") || !library->OriginalFirstThunk) continue;
        IMAGE_THUNK_DATA64 *names=(IMAGE_THUNK_DATA64*)(module+library->OriginalFirstThunk);
        IMAGE_THUNK_DATA64 *addresses=(IMAGE_THUNK_DATA64*)(module+library->FirstThunk);
        for(;names->u1.AddressOfData;names++,addresses++) {
            if(IMAGE_SNAP_BY_ORDINAL64(names->u1.Ordinal))continue;
            const char *name=(char*)((IMAGE_IMPORT_BY_NAME*)(module+names->u1.AddressOfData))->Name;
            void *replacement=NULL;
            if(!strcmp(name,"EnableMouseInPointer"))replacement=enable_pointer;
            else if(!strcmp(name,"IsMouseInPointerEnabled"))replacement=pointer_enabled;
            else if(!strcmp(name,"GetPointerInfo"))replacement=pointer_info;
            else if(!strcmp(name,"GetPointerType"))replacement=pointer_type;
            else if(!strcmp(name,"GetPointerDevices"))replacement=pointer_devices;
            if(replacement){DWORD previous;if(VirtualProtect(&addresses->u1.Function,sizeof(ULONGLONG),PAGE_READWRITE,&previous)) {
                addresses->u1.Function=(ULONGLONG)(ULONG_PTR)replacement;
                VirtualProtect(&addresses->u1.Function,sizeof(ULONGLONG),previous,&previous);replaced++;
            }}
        }
    }
    if(diagnostic){fprintf(diagnostic,"Unity pointer imports redirected: %u\n",replaced);fflush(diagnostic);}
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID reserved) {
    (void)reserved;
    if(reason==DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
        diagnostic=fopen("opengame-input.log","w");
        redirect_unity_imports();
    }
    return TRUE;
}
