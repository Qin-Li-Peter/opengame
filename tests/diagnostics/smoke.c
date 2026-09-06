#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <mmsystem.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
int main(void) {
  setvbuf(stdout,NULL,_IONBF,0);
  printf("ARCH_BITS=%d\n",(int)(sizeof(void*)*8));
  WCHAR tmp[MAX_PATH],file[MAX_PATH];GetTempPathW(MAX_PATH,tmp);GetTempFileNameW(tmp,L"OGT",0,file);
  HANDLE h=CreateFileW(file,GENERIC_WRITE|GENERIC_READ,0,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_TEMPORARY,NULL);
  const char value[]="OpenGame filesystem smoke";char got[64]={0};DWORD n=0;BOOL fs=FALSE;
  if(h!=INVALID_HANDLE_VALUE){WriteFile(h,value,sizeof(value),&n,NULL);SetFilePointer(h,0,NULL,FILE_BEGIN);ReadFile(h,got,sizeof(got),&n,NULL);fs=!strcmp(value,got);CloseHandle(h);}DeleteFileW(file);
  printf("FILESYSTEM=%s\n",fs?"PASS":"FAIL");
  HKEY key;DWORD v=0x12345678,out=0,sz=sizeof(out);LONG rr=RegCreateKeyExW(HKEY_CURRENT_USER,L"Software\\OpenGameSmoke",0,NULL,0,KEY_ALL_ACCESS,NULL,&key,NULL);
  if(!rr){RegSetValueExW(key,L"Probe",0,REG_DWORD,(BYTE*)&v,sizeof(v));RegQueryValueExW(key,L"Probe",0,NULL,(BYTE*)&out,&sz);RegDeleteValueW(key,L"Probe");RegCloseKey(key);RegDeleteKeyW(HKEY_CURRENT_USER,L"Software\\OpenGameSmoke");}
  printf("REGISTRY=%s\n",out==v?"PASS":"FAIL");
  HDC dc=CreateCompatibleDC(NULL);HBITMAP bm=CreateBitmap(8,8,1,32,NULL);HGDIOBJ old=SelectObject(dc,bm);SetPixel(dc,2,2,RGB(10,120,230));COLORREF c=GetPixel(dc,2,2);printf("GDI_PIXEL=%s\n",c==RGB(10,120,230)?"PASS":"FAIL");SelectObject(dc,old);DeleteObject(bm);DeleteDC(dc);
  printf("WAVEOUT_DEVICES=%u\n",waveOutGetNumDevs());printf("JOYSTICK_SLOTS=%u\n",joyGetNumDevs());
  ID3D11Device *dev=NULL;ID3D11DeviceContext *ctx=NULL;D3D_FEATURE_LEVEL level=0;
  HRESULT hr=D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,0,NULL,0,D3D11_SDK_VERSION,&dev,&level,&ctx);
  printf("D3D11_CREATE_HRESULT=0x%08lx\n",(unsigned long)hr);printf("D3D11_FEATURE_LEVEL=0x%x\n",level);
  if(FAILED(hr))return 10;
  IDXGIDevice *dxdev=NULL;IDXGIAdapter *adapter=NULL;DXGI_ADAPTER_DESC ad;
  if(SUCCEEDED(ID3D11Device_QueryInterface(dev,&IID_IDXGIDevice,(void**)&dxdev))){IDXGIDevice_GetAdapter(dxdev,&adapter);if(adapter){IDXGIAdapter_GetDesc(adapter,&ad);char s[256];WideCharToMultiByte(CP_UTF8,0,ad.Description,-1,s,sizeof(s),NULL,NULL);printf("D3D11_ADAPTER=%s\n",s);IDXGIAdapter_Release(adapter);}IDXGIDevice_Release(dxdev);}
  D3D11_TEXTURE2D_DESC desc={0};desc.Width=8;desc.Height=8;desc.MipLevels=1;desc.ArraySize=1;desc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;desc.SampleDesc.Count=1;desc.Usage=D3D11_USAGE_DEFAULT;desc.BindFlags=D3D11_BIND_RENDER_TARGET;
  ID3D11Texture2D *tex=NULL,*stage=NULL;ID3D11RenderTargetView *view=NULL;BOOL rendered=FALSE;
  hr=ID3D11Device_CreateTexture2D(dev,&desc,NULL,&tex);
  if(SUCCEEDED(hr)){hr=ID3D11Device_CreateRenderTargetView(dev,(ID3D11Resource*)tex,NULL,&view);if(SUCCEEDED(hr)){float color[4]={1,0,0,1};ID3D11DeviceContext_ClearRenderTargetView(ctx,view,color);desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;hr=ID3D11Device_CreateTexture2D(dev,&desc,NULL,&stage);if(SUCCEEDED(hr)){ID3D11DeviceContext_CopyResource(ctx,(ID3D11Resource*)stage,(ID3D11Resource*)tex);D3D11_MAPPED_SUBRESOURCE m;hr=ID3D11DeviceContext_Map(ctx,(ID3D11Resource*)stage,0,D3D11_MAP_READ,0,&m);if(SUCCEEDED(hr)){BYTE *p=m.pData;rendered=p[0]==255&&p[1]==0&&p[2]==0&&p[3]==255;ID3D11DeviceContext_Unmap(ctx,(ID3D11Resource*)stage,0);}}}}
  printf("D3D11_RENDER_READBACK=%s\n",rendered?"PASS":"FAIL");
  if(stage)ID3D11Texture2D_Release(stage);if(view)ID3D11RenderTargetView_Release(view);if(tex)ID3D11Texture2D_Release(tex);ID3D11DeviceContext_Release(ctx);ID3D11Device_Release(dev);
  return fs&&out==v&&rendered?0:11;
}
