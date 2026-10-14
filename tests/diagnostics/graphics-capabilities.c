/* SPDX-License-Identifier: MIT
 * Capability probe: compare API support and resource creation, not game FPS.
 * Build: x86_64-w64-mingw32-gcc graphics-capabilities.c -O2 -ld3d11 -o probe.exe
 */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
struct Format { const char *name; DXGI_FORMAT format; };
int main(void) {
    setvbuf(stdout,NULL,_IONBF,0);
    ID3D11Device *device=NULL; ID3D11DeviceContext *context=NULL;
    D3D_FEATURE_LEVEL level=0;
    const D3D_FEATURE_LEVEL levels[]={D3D_FEATURE_LEVEL_11_1,D3D_FEATURE_LEVEL_11_0,D3D_FEATURE_LEVEL_10_1,D3D_FEATURE_LEVEL_10_0};
    HRESULT hr=D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,0,levels,4,D3D11_SDK_VERSION,&device,&level,&context);
    if(hr==E_INVALIDARG)hr=D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,0,levels+1,3,D3D11_SDK_VERSION,&device,&level,&context);
    printf("{\"kind\":\"device\",\"hr\":\"%08lx\",\"feature_level\":%u}\n",(unsigned long)hr,(unsigned)level);
    if(FAILED(hr)) return 2;
    const struct Format formats[]={
        {"RGBA8",DXGI_FORMAT_R8G8B8A8_UNORM},{"BGRA8",DXGI_FORMAT_B8G8R8A8_UNORM},
        {"RGBA16F",DXGI_FORMAT_R16G16B16A16_FLOAT},{"RGB32F",DXGI_FORMAT_R32G32B32_FLOAT},
        {"R11G11B10F",DXGI_FORMAT_R11G11B10_FLOAT},{"RGB10A2",DXGI_FORMAT_R10G10B10A2_UNORM},
        {"BC1",DXGI_FORMAT_BC1_UNORM},{"BC3",DXGI_FORMAT_BC3_UNORM},
        {"BC5",DXGI_FORMAT_BC5_UNORM},{"BC6H",DXGI_FORMAT_BC6H_UF16},{"BC7",DXGI_FORMAT_BC7_UNORM},
        {"NV12",DXGI_FORMAT_NV12},{"YUY2",DXGI_FORMAT_YUY2},
        {"D24S8",DXGI_FORMAT_D24_UNORM_S8_UINT},{"D32F",DXGI_FORMAT_D32_FLOAT},
        {"RGBA8_SRGB",DXGI_FORMAT_R8G8B8A8_UNORM_SRGB},{"BGRX8",DXGI_FORMAT_B8G8R8X8_UNORM},
        {"R8",DXGI_FORMAT_R8_UNORM},{"RG8",DXGI_FORMAT_R8G8_UNORM},{"R16",DXGI_FORMAT_R16_UNORM},
        {"RG16F",DXGI_FORMAT_R16G16_FLOAT},{"R32F",DXGI_FORMAT_R32_FLOAT},{"RG32F",DXGI_FORMAT_R32G32_FLOAT},
        {"BC2",DXGI_FORMAT_BC2_UNORM},{"BC4",DXGI_FORMAT_BC4_UNORM}
    };
    for(unsigned i=0;i<sizeof(formats)/sizeof(formats[0]);i++) {
        UINT support=0;HRESULT query=ID3D11Device_CheckFormatSupport(device,formats[i].format,&support);
        D3D11_TEXTURE2D_DESC desc={0};desc.Width=64;desc.Height=64;desc.MipLevels=1;desc.ArraySize=1;
        desc.Format=formats[i].format;desc.SampleDesc.Count=1;desc.Usage=D3D11_USAGE_DEFAULT;
        desc.BindFlags=(formats[i].format==DXGI_FORMAT_D24_UNORM_S8_UINT || formats[i].format==DXGI_FORMAT_D32_FLOAT) ? D3D11_BIND_DEPTH_STENCIL : D3D11_BIND_SHADER_RESOURCE;
        // Planar/video resources need separate plane-view/decoder tests.
        // Query them here without passing an unsuitable generic descriptor.
        if(FAILED(query) || formats[i].format==DXGI_FORMAT_NV12 || formats[i].format==DXGI_FORMAT_YUY2) {
            printf("{\"kind\":\"format\",\"name\":\"%s\",\"query_hr\":\"%08lx\",\"support\":%u,\"texture_hr\":null}\n",formats[i].name,(unsigned long)query,(unsigned)support);
            continue;
        }
        ID3D11Texture2D *texture=NULL;
        HRESULT create=ID3D11Device_CreateTexture2D(device,&desc,NULL,&texture);
        printf("{\"kind\":\"format\",\"name\":\"%s\",\"query_hr\":\"%08lx\",\"support\":%u,\"texture_hr\":\"%08lx\"}\n",formats[i].name,(unsigned long)query,(unsigned)support,(unsigned long)create);
        if(texture) {
            HRESULT view;
            if(desc.BindFlags==D3D11_BIND_DEPTH_STENCIL) {
                ID3D11DepthStencilView *dsv=NULL;
                view=ID3D11Device_CreateDepthStencilView(device,(ID3D11Resource*)texture,NULL,&dsv);
                printf("{\"kind\":\"view\",\"name\":\"%s\",\"usage\":\"DSV\",\"hr\":\"%08lx\"}\n",formats[i].name,(unsigned long)view);
                if(dsv)ID3D11DepthStencilView_Release(dsv);
            } else {
                ID3D11ShaderResourceView *srv=NULL;
                view=ID3D11Device_CreateShaderResourceView(device,(ID3D11Resource*)texture,NULL,&srv);
                printf("{\"kind\":\"view\",\"name\":\"%s\",\"usage\":\"SRV\",\"hr\":\"%08lx\"}\n",formats[i].name,(unsigned long)view);
                if(srv)ID3D11ShaderResourceView_Release(srv);
            }
            ID3D11Texture2D_Release(texture);
        }
    }
    // Verify actual view creation rather than trusting broad advertised masks.
    for(unsigned usage=0;usage<2;usage++) {
        D3D11_TEXTURE2D_DESC desc={0};desc.Width=64;desc.Height=64;desc.MipLevels=1;desc.ArraySize=1;
        desc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;desc.SampleDesc.Count=1;
        desc.BindFlags=usage ? D3D11_BIND_UNORDERED_ACCESS : D3D11_BIND_RENDER_TARGET;
        ID3D11Texture2D *texture=NULL;HRESULT create=ID3D11Device_CreateTexture2D(device,&desc,NULL,&texture),view=create;
        if(texture) {
            if(usage) {ID3D11UnorderedAccessView *uav=NULL;view=ID3D11Device_CreateUnorderedAccessView(device,(ID3D11Resource*)texture,NULL,&uav);if(uav)ID3D11UnorderedAccessView_Release(uav);}
            else {ID3D11RenderTargetView *rtv=NULL;view=ID3D11Device_CreateRenderTargetView(device,(ID3D11Resource*)texture,NULL,&rtv);if(rtv)ID3D11RenderTargetView_Release(rtv);}
            ID3D11Texture2D_Release(texture);
        }
        printf("{\"kind\":\"view\",\"name\":\"RGBA8\",\"usage\":\"%s\",\"hr\":\"%08lx\"}\n",usage?"UAV":"RTV",(unsigned long)view);
    }
    for(unsigned samples=2;samples<=8;samples*=2) {
        UINT quality=0;HRESULT query=ID3D11Device_CheckMultisampleQualityLevels(device,DXGI_FORMAT_R8G8B8A8_UNORM,samples,&quality);
        if(FAILED(query) || quality==0 || quality==0xffffffff) {printf("{\"kind\":\"msaa\",\"samples\":%u,\"quality\":%u,\"create_hr\":null}\n",samples,quality);continue;}
        D3D11_TEXTURE2D_DESC desc={0};desc.Width=64;desc.Height=64;desc.MipLevels=1;desc.ArraySize=1;desc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;desc.SampleDesc.Count=samples;desc.BindFlags=D3D11_BIND_RENDER_TARGET;
        ID3D11Texture2D *texture=NULL;HRESULT create=ID3D11Device_CreateTexture2D(device,&desc,NULL,&texture);
        printf("{\"kind\":\"msaa\",\"samples\":%u,\"quality\":%u,\"create_hr\":\"%08lx\"}\n",samples,quality,(unsigned long)create);
        if(texture)ID3D11Texture2D_Release(texture);
    }
    D3D11_FEATURE_DATA_THREADING threads={0};HRESULT threading=ID3D11Device_CheckFeatureSupport(device,D3D11_FEATURE_THREADING,&threads,sizeof(threads));
    printf("{\"kind\":\"threading\",\"hr\":\"%08lx\",\"concurrent_create\":%d,\"command_lists\":%d}\n",(unsigned long)threading,threads.DriverConcurrentCreates,threads.DriverCommandLists);
    ID3D11DeviceContext_Release(context);ID3D11Device_Release(device);return 0;
}
