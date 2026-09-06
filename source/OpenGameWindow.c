/* SPDX-License-Identifier: MIT
 * OpenGame: locate an existing game by its complete executable path inside
 * the current Wine prefix. Never terminates a process or changes game files.
 * Exit 0: window focused, 2: not running, 3: running but not focused, 4: error.
 */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <tlhelp32.h>
#include <wchar.h>
#include <stdio.h>
static DWORD target_pid;
static HWND target_window;
static BOOL CALLBACK find_window(HWND window, LPARAM unused) {
    (void)unused;
    DWORD pid=0;
    GetWindowThreadProcessId(window,&pid);
    if(pid==target_pid && IsWindowVisible(window) && GetWindow(window,GW_OWNER)==NULL) {
        target_window=window;
        return FALSE;
    }
    return TRUE;
}
int wmain(int argc,wchar_t **argv) {
    if(argc!=2) return 4;
    if(!_wcsicmp(argv[1],L"--list")) {
        HANDLE processes=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
        if(processes==INVALID_HANDLE_VALUE) return 4;
        PROCESSENTRY32W process={0};process.dwSize=sizeof(process);
        if(Process32FirstW(processes,&process)) do {
            wprintf(L"\"%ls\"\n",process.szExeFile);
        } while(Process32NextW(processes,&process));
        CloseHandle(processes);
        return 0;
    }
    wchar_t expected[32768];
    DWORD length=GetFullPathNameW(argv[1],32768,expected,NULL);
    if(!length || length>=32768) return 4;
    HANDLE snapshot=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
    if(snapshot==INVALID_HANDLE_VALUE) return 4;
    PROCESSENTRY32W entry={0};entry.dwSize=sizeof(entry);
    BOOL running=FALSE,focused=FALSE;
    if(Process32FirstW(snapshot,&entry)) do {
        if(entry.th32ProcessID==GetCurrentProcessId()) continue;
        HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,entry.th32ProcessID);
        if(!process) continue;
        wchar_t path[32768];DWORD size=32768;
        BOOL match=QueryFullProcessImageNameW(process,0,path,&size) && !_wcsicmp(path,expected);
        CloseHandle(process);
        if(!match) continue;
        running=TRUE;target_pid=entry.th32ProcessID;target_window=NULL;
        EnumWindows(find_window,0);
        if(target_window) {
            if(IsIconic(target_window)) ShowWindow(target_window,SW_RESTORE);
            BringWindowToTop(target_window);
            SetForegroundWindow(target_window);
            focused=GetForegroundWindow()==target_window;
            printf("EXISTING_GAME_PID=%lu FOCUSED=%d\n",(unsigned long)target_pid,focused);
            break;
        }
    } while(Process32NextW(snapshot,&entry));
    CloseHandle(snapshot);
    return focused ? 0 : running ? 3 : 2;
}
