#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
static double ticks(void){LARGE_INTEGER t,f;QueryPerformanceCounter(&t);QueryPerformanceFrequency(&f);return (double)t.QuadPart/f.QuadPart;}
static HANDLE ready,go;
static DWORD WINAPI ping(void*arg){unsigned n=*(unsigned*)arg;for(unsigned i=0;i<n;i++){WaitForSingleObject(ready,INFINITE);SetEvent(go);}return 0;}
static int cmp(const void*a,const void*b){double x=*(const double*)a,y=*(const double*)b;return(x>y)-(x<y);}
static void cpu(void){volatile uint64_t s=17;double begin=ticks();for(unsigned i=0;i<40000000;i++)s=s*6364136223846793005ULL+1442695040888963407ULL;printf("RESULT cpu_ms %.6f CHECKSUM %llu\n",(ticks()-begin)*1000,(unsigned long long)s);unsigned n=10000;ready=CreateEventW(NULL,FALSE,FALSE,NULL);go=CreateEventW(NULL,FALSE,FALSE,NULL);HANDLE thread=CreateThread(NULL,0,ping,&n,0,NULL);begin=ticks();for(unsigned i=0;i<n;i++){SetEvent(ready);WaitForSingleObject(go,INFINITE);}double end=ticks();WaitForSingleObject(thread,INFINITE);CloseHandle(thread);CloseHandle(ready);CloseHandle(go);printf("RESULT event_roundtrip_us %.6f\n",(end-begin)*1000000/n);}

int main(void) {
 setvbuf(stdout,NULL,_IONBF,0);
 cpu();
 ID3D11Device *dev=NULL;ID3D11DeviceContext *ctx=NULL;D3D_FEATURE_LEVEL fl;
 HRESULT h=D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,0,NULL,0,D3D11_SDK_VERSION,&dev,&fl,&ctx);
 if(FAILED(h)){printf("CREATE_DEVICE=0x%lx\n",(unsigned long)h);return 1;}
 char hold[16];if(GetEnvironmentVariableA("OG_BENCH_HOLD",hold,sizeof(hold)))Sleep(15000);
 typedef HRESULT (WINAPI *Compile)(LPCVOID,SIZE_T,LPCSTR,const D3D_SHADER_MACRO*,ID3DInclude*,LPCSTR,LPCSTR,UINT,UINT,ID3DBlob**,ID3DBlob**);
 HMODULE compiler=LoadLibraryA("d3dcompiler_47.dll");
 Compile compile=compiler?(Compile)GetProcAddress(compiler,"D3DCompile"):NULL;
 if(!compile){printf("HLSL_COMPILER_UNAVAILABLE=%lu\n",GetLastError());return 12;}
 const char *vs="float4 main(uint id:SV_VertexID):SV_Position {float2 p=float2((id << 1) & 2,id & 2);return float4(p*float2(2,-2)+float2(-1,1),0,1);}";
 const char *ps="float4 main(float4 p:SV_Position):SV_Target {float x=p.x/1280.0,y=p.y/720.0;[unroll]for(int j=0;j<24;j++){x=sin(x*1.7+y);y=cos(y*1.3+x);}return float4(x*.2+.5,y*.2+.5,.2,1);}";
 ID3DBlob *vb=NULL,*pb=NULL,*err=NULL;
 h=compile(vs,strlen(vs),NULL,NULL,NULL,"main","vs_5_0",0,0,&vb,&err);
 if(FAILED(h)){printf("VERTEX_COMPILE=0x%lx %s\n",(unsigned long)h,err?(char*)ID3D10Blob_GetBufferPointer(err):"");return 2;}
 h=compile(ps,strlen(ps),NULL,NULL,NULL,"main","ps_5_0",0,0,&pb,&err);
 if(FAILED(h)){printf("PIXEL_COMPILE=0x%lx\n",(unsigned long)h);return 3;}
 ID3D11VertexShader *vertex=NULL;ID3D11PixelShader *pixel=NULL;
 h=ID3D11Device_CreateVertexShader(dev,ID3D10Blob_GetBufferPointer(vb),ID3D10Blob_GetBufferSize(vb),NULL,&vertex);if(FAILED(h))return 4;
 h=ID3D11Device_CreatePixelShader(dev,ID3D10Blob_GetBufferPointer(pb),ID3D10Blob_GetBufferSize(pb),NULL,&pixel);if(FAILED(h))return 5;
 D3D11_TEXTURE2D_DESC d={0};d.Width=1280;d.Height=720;d.MipLevels=1;d.ArraySize=1;d.Format=DXGI_FORMAT_R8G8B8A8_UNORM;d.SampleDesc.Count=1;d.BindFlags=D3D11_BIND_RENDER_TARGET;
 ID3D11Texture2D *tex=NULL,*stage=NULL;ID3D11RenderTargetView *rt=NULL;
 if(FAILED(ID3D11Device_CreateTexture2D(dev,&d,NULL,&tex)))return 6;
 if(FAILED(ID3D11Device_CreateRenderTargetView(dev,(ID3D11Resource*)tex,NULL,&rt)))return 7;
 d.BindFlags=0;d.Usage=D3D11_USAGE_STAGING;d.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
 if(FAILED(ID3D11Device_CreateTexture2D(dev,&d,NULL,&stage)))return 8;
 float black[4]={0,0,0,1};D3D11_VIEWPORT vp={0,0,1280,720,0,1};
 ID3D11DeviceContext_ClearRenderTargetView(ctx,rt,black);
 ID3D11DeviceContext_OMSetRenderTargets(ctx,1,&rt,NULL);ID3D11DeviceContext_RSSetViewports(ctx,1,&vp);
 ID3D11DeviceContext_VSSetShader(ctx,vertex,NULL,0);ID3D11DeviceContext_PSSetShader(ctx,pixel,NULL,0);
 ID3D11DeviceContext_IASetPrimitiveTopology(ctx,D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);ID3D11DeviceContext_Draw(ctx,3,0);
 D3D11_QUERY_DESC qd={D3D11_QUERY_EVENT,0};ID3D11Query *done=NULL;
 if(FAILED(ID3D11Device_CreateQuery(dev,&qd,&done)))return 20;
 double durations[80];
 for(int workload=0;workload<2;workload++){
   D3D11_VIEWPORT v={0,0,workload?32:1280,workload?32:720,0,1};
   ID3D11DeviceContext_RSSetViewports(ctx,1,&v);
   int draws=workload?1500:1;
   for(int i=-15;i<80;i++){
     double begin=ticks();
     for(int j=0;j<draws;j++)ID3D11DeviceContext_Draw(ctx,3,0);
     ID3D11DeviceContext_End(ctx,(ID3D11Asynchronous*)done);ID3D11DeviceContext_Flush(ctx);
     HRESULT status;
     while((status=ID3D11DeviceContext_GetData(ctx,(ID3D11Asynchronous*)done,NULL,0,0))==S_FALSE){if(ticks()-begin>20)return 21;SwitchToThread();}
     if(FAILED(status))return 22;
     if(i>=0)durations[i]=(ticks()-begin)*1000;
   }
   qsort(durations,80,sizeof(double),cmp);
   printf("RESULT %s_median_ms %.6f P95 %.6f\n",workload?"draw1500":"shader1280",(durations[39]+durations[40])/2,durations[75]);
 }
 ID3D11Query_Release(done);
 ID3D11DeviceContext_CopyResource(ctx,(ID3D11Resource*)stage,(ID3D11Resource*)tex);
 D3D11_MAPPED_SUBRESOURCE m;h=ID3D11DeviceContext_Map(ctx,(ID3D11Resource*)stage,0,D3D11_MAP_READ,0,&m);if(FAILED(h))return 9;
 BYTE *p=(BYTE*)m.pData+360*m.RowPitch+640*4;BOOL ok=p[3]==255&&p[0]>50&&p[1]>50;
 printf("VALIDATION %s RGBA %u %u %u %u\n",ok?"PASS":"FAIL",p[0],p[1],p[2],p[3]);
 ID3D11DeviceContext_Unmap(ctx,(ID3D11Resource*)stage,0);ID3D11DeviceContext_ClearState(ctx);
 ID3D11Texture2D_Release(stage);ID3D11RenderTargetView_Release(rt);ID3D11Texture2D_Release(tex);ID3D11VertexShader_Release(vertex);ID3D11PixelShader_Release(pixel);ID3D10Blob_Release(vb);ID3D10Blob_Release(pb);ID3D11DeviceContext_Release(ctx);ID3D11Device_Release(dev);return ok?0:10;
}
