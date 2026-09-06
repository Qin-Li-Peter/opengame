#include <windows.h>
#include <winhttp.h>
#include <bcrypt.h>
#include <stdio.h>
int main(){unsigned char data[16];NTSTATUS s=BCryptGenRandom(0,data,sizeof data,BCRYPT_USE_SYSTEM_PREFERRED_RNG);printf("RNG=%08lx\n",(unsigned long)s);HINTERNET a=WinHttpOpen(L"OpenGameRuntimeTest/1.0",WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,0,0,0);if(!a)return 1;WinHttpSetTimeouts(a,10000,10000,10000,10000);HINTERNET c=WinHttpConnect(a,L"store.steampowered.com",443,0);HINTERNET r=WinHttpOpenRequest(c,L"GET",L"/",0,0,0,WINHTTP_FLAG_SECURE);if(!WinHttpSendRequest(r,0,0,0,0,0,0)||!WinHttpReceiveResponse(r,0)){printf("HTTPS_ERROR=%lu\n",GetLastError());return 2;}DWORD status=0,n=sizeof(status);WinHttpQueryHeaders(r,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,0,&status,&n,0);printf("HTTPS_STATUS=%lu\n",status);WinHttpCloseHandle(r);WinHttpCloseHandle(c);WinHttpCloseHandle(a);return s==0&&status==200?0:3;}
