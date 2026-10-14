/* SPDX-License-Identifier: MIT. API initialization probe; no image-quality claim. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
typedef void *(__cdecl *Query)(unsigned);
typedef int (__cdecl *Init)(void);
typedef unsigned (__cdecl *NGXInit)(unsigned long long,const wchar_t*,ID3D11Device*,const void*,unsigned);
typedef unsigned (__cdecl *Params)(void**);
typedef unsigned (__cdecl *Destroy)(void*);
int main(void) {
 setvbuf(stdout,NULL,_IONBF,0);
 ID3D11Device *dev=NULL;ID3D11DeviceContext *ctx=NULL;D3D_FEATURE_LEVEL level;
 HRESULT hr=D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,0,NULL,0,D3D11_SDK_VERSION,&dev,&level,&ctx);
 if(FAILED(hr)){printf("DEVICE=%08lx\n",(unsigned long)hr);return 2;}
 HMODULE api=LoadLibraryW(L"nvapi64.dll"),ngx=LoadLibraryW(L"nvngx.dll");
 if(!api || !ngx){printf("MODULE_LOAD_FAILED=%lu\n",GetLastError());return 3;}
 union {FARPROC raw;Query typed;} q;q.raw=GetProcAddress(api,"nvapi_QueryInterface");Query query=q.typed;Init init=query?(Init)query(0x0150e828):NULL;
 union {FARPROC raw;NGXInit typed;} n;n.raw=GetProcAddress(ngx,"NVSDK_NGX_D3D11_Init");NGXInit nginit=n.typed;
 union {FARPROC raw;Params typed;} c;c.raw=GetProcAddress(ngx,"NVSDK_NGX_D3D11_GetCapabilityParameters");Params params=c.typed;
 union {FARPROC raw;Destroy typed;} d;d.raw=GetProcAddress(ngx,"NVSDK_NGX_D3D11_DestroyParameters");Destroy destroy=d.typed;
 if(!init || !nginit || !params || !destroy)return 4;
 int status=init();unsigned result=nginit(0,L".",dev,NULL,0x13);void *p=NULL;unsigned cap=params(&p);
 printf("NVAPI_INIT=%d\nNGX_INIT=%08x\nNGX_PARAMETERS=%08x\n",status,result,cap);
 if(p)destroy(p);
 ID3D11DeviceContext_Release(ctx);ID3D11Device_Release(dev);
 return status==0 && result==1 && cap==1 ? 0 : 5;
}
