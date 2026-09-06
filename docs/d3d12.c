#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <d3d12.h>
#include <stdio.h>

int main(void) {
    ID3D12Device *device = NULL;
    HRESULT result = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device);
    printf("D3D12_CREATE_DEVICE=%08lx\n", (unsigned long)result);
    if (SUCCEEDED(result)) ID3D12Device_Release(device);
    return SUCCEEDED(result) ? 0 : 1;
}
