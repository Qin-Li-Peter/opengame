#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
static BOOL veto;
static void record(const char *s){FILE*f=fopen("quit-events.txt","a");if(f){fprintf(f,"%lu %s\n",GetCurrentProcessId(),s);fclose(f);}}
static LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){
 if(m==WM_QUERYENDSESSION){record(veto?"VETO":"QUERY");return !veto;}
 if(m==WM_ENDSESSION && w){record("ENDED");DestroyWindow(h);return 0;}
 if(m==WM_DESTROY){record("CLOSED");PostQuitMessage(0);return 0;}
 return DefWindowProc(h,m,w,l);
}
int WINAPI wWinMain(HINSTANCE h,HINSTANCE prev,PWSTR cmd,int show){
 (void)prev;(void)show;
 veto=wcsstr(cmd,L"veto")!=NULL;
 if(wcsstr(cmd,L"spawn")){
  wchar_t exe[32768],line[33000];GetModuleFileNameW(NULL,exe,32768);swprintf(line,33000,L"\"%ls\" child%ls",exe,veto?L" veto":L"");
  STARTUPINFOW si={0};PROCESS_INFORMATION pi={0};si.cb=sizeof(si);
  if(!CreateProcessW(NULL,line,NULL,NULL,FALSE,0,NULL,NULL,&si,&pi))return 2;
  CloseHandle(pi.hProcess);CloseHandle(pi.hThread);record("PARENT_EXIT");return 0;
 }
 WNDCLASSW wc={0};wc.hInstance=h;wc.lpfnWndProc=proc;wc.lpszClassName=L"OpenGameQuitFixture";wc.hCursor=LoadCursor(NULL,IDC_ARROW);RegisterClassW(&wc);
 HWND window=CreateWindowW(wc.lpszClassName,L"OpenGame — Exit test",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,460,160,NULL,NULL,h,NULL);ShowWindow(window,SW_SHOW);record("START");
 MSG msg;while(GetMessageW(&msg,NULL,0,0)>0){TranslateMessage(&msg);DispatchMessageW(&msg);}return 0;
}
