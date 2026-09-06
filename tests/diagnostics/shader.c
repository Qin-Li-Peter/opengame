#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <string.h>
int main(void) {
 setvbuf(stdout,NULL,_IONBF,0);
 ID3D11Device *dev=NULL;ID3D11DeviceContext *ctx=NULL;D3D_FEATURE_LEVEL fl;
 HRESULT h=D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,0,NULL,0,D3D11_SDK_VERSION,&dev,&fl,&ctx);
 if(FAILED(h)){printf("CREATE_DEVICE=0x%lx\n",(unsigned long)h);return 1;}
 typedef HRESULT (WINAPI *Compile)(LPCVOID,SIZE_T,LPCSTR,const D3D_SHADER_MACRO*,ID3DInclude*,LPCSTR,LPCSTR,UINT,UINT,ID3DBlob**,ID3DBlob**);
 HMODULE compiler=LoadLibraryA("d3dcompiler_47.dll");
 Compile compile=compiler?(Compile)GetProcAddress(compiler,"D3DCompile"):NULL;
 if(!compile){printf("HLSL_COMPILER_UNAVAILABLE=%lu\n",GetLastError());return 12;}
 const char *vs="float4 main(uint id:SV_VertexID):SV_Position {float2 p=float2((id << 1) & 2,id & 2);return float4(p*float2(2,-2)+float2(-1,1),0,1);}";
 const char *ps="float4 main():SV_Target {return float4(0,1,0,1);}";
 ID3DBlob *vb=NULL,*pb=NULL,*err=NULL;
 h=compile(vs,strlen(vs),NULL,NULL,NULL,"main","vs_5_0",0,0,&vb,&err);
 if(FAILED(h)){printf("VERTEX_COMPILE=0x%lx %s\n",(unsigned long)h,err?(char*)ID3D10Blob_GetBufferPointer(err):"");return 2;}
 h=compile(ps,strlen(ps),NULL,NULL,NULL,"main","ps_5_0",0,0,&pb,&err);
 if(FAILED(h)){printf("PIXEL_COMPILE=0x%lx\n",(unsigned long)h);return 3;}
 ID3D11VertexShader *vertex=NULL;ID3D11PixelShader *pixel=NULL;
 h=ID3D11Device_CreateVertexShader(dev,ID3D10Blob_GetBufferPointer(vb),ID3D10Blob_GetBufferSize(vb),NULL,&vertex);if(FAILED(h))return 4;
 h=ID3D11Device_CreatePixelShader(dev,ID3D10Blob_GetBufferPointer(pb),ID3D10Blob_GetBufferSize(pb),NULL,&pixel);if(FAILED(h))return 5;
 D3D11_TEXTURE2D_DESC d={0};d.Width=32;d.Height=32;d.MipLevels=1;d.ArraySize=1;d.Format=DXGI_FORMAT_R8G8B8A8_UNORM;d.SampleDesc.Count=1;d.BindFlags=D3D11_BIND_RENDER_TARGET;
 ID3D11Texture2D *tex=NULL,*stage=NULL;ID3D11RenderTargetView *rt=NULL;
 if(FAILED(ID3D11Device_CreateTexture2D(dev,&d,NULL,&tex)))return 6;
 if(FAILED(ID3D11Device_CreateRenderTargetView(dev,(ID3D11Resource*)tex,NULL,&rt)))return 7;
 d.BindFlags=0;d.Usage=D3D11_USAGE_STAGING;d.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
 if(FAILED(ID3D11Device_CreateTexture2D(dev,&d,NULL,&stage)))return 8;
 float black[4]={0,0,0,1};D3D11_VIEWPORT vp={0,0,32,32,0,1};
 ID3D11DeviceContext_ClearRenderTargetView(ctx,rt,black);
 ID3D11DeviceContext_OMSetRenderTargets(ctx,1,&rt,NULL);ID3D11DeviceContext_RSSetViewports(ctx,1,&vp);
 ID3D11DeviceContext_VSSetShader(ctx,vertex,NULL,0);ID3D11DeviceContext_PSSetShader(ctx,pixel,NULL,0);
 ID3D11DeviceContext_IASetPrimitiveTopology(ctx,D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);ID3D11DeviceContext_Draw(ctx,3,0);
 ID3D11DeviceContext_CopyResource(ctx,(ID3D11Resource*)stage,(ID3D11Resource*)tex);
 D3D11_MAPPED_SUBRESOURCE m;h=ID3D11DeviceContext_Map(ctx,(ID3D11Resource*)stage,0,D3D11_MAP_READ,0,&m);if(FAILED(h))return 9;
 BYTE *p=(BYTE*)m.pData+16*m.RowPitch+16*4;BOOL ok=p[0]==0&&p[1]==255&&p[2]==0&&p[3]==255;
 printf("ARCH_BITS=%d\nHLSL_COMPILE=PASS\nD3D11_SHADER_DRAW=%s\nRGBA=%u,%u,%u,%u\n",(int)sizeof(void*)*8,ok?"PASS":"FAIL",p[0],p[1],p[2],p[3]);
 ID3D11DeviceContext_Unmap(ctx,(ID3D11Resource*)stage,0);ID3D11DeviceContext_ClearState(ctx);
 ID3D11Texture2D_Release(stage);ID3D11RenderTargetView_Release(rt);ID3D11Texture2D_Release(tex);ID3D11VertexShader_Release(vertex);ID3D11PixelShader_Release(pixel);ID3D10Blob_Release(vb);ID3D10Blob_Release(pb);ID3D11DeviceContext_Release(ctx);ID3D11Device_Release(dev);return ok?0:10;
}
