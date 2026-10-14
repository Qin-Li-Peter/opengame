/* SPDX-License-Identifier: MIT. D3D12 queue/barrier/RTV/readback correctness smoke test. */
#define COBJMACROS
#define WIDL_C_INLINE_WRAPPERS
#include <windows.h>
#include <d3d12.h>
#include <stdio.h>
int main(void) {
 setvbuf(stdout,NULL,_IONBF,0);ID3D12Device *dev=NULL;
 HRESULT hr=D3D12CreateDevice(NULL,D3D_FEATURE_LEVEL_11_0,&IID_ID3D12Device,(void**)&dev);
 printf("D3D12_DEVICE=%08lx\n",(unsigned long)hr);if(FAILED(hr))return 2;
 ID3D12CommandQueue *queue=NULL;ID3D12CommandAllocator *alloc=NULL;ID3D12GraphicsCommandList *list=NULL;
 D3D12_COMMAND_QUEUE_DESC q={0};q.Type=D3D12_COMMAND_LIST_TYPE_DIRECT;
 if(FAILED(ID3D12Device_CreateCommandQueue(dev,&q,&IID_ID3D12CommandQueue,(void**)&queue)))return 3;
 if(FAILED(ID3D12Device_CreateCommandAllocator(dev,q.Type,&IID_ID3D12CommandAllocator,(void**)&alloc)))return 4;
 if(FAILED(ID3D12Device_CreateCommandList(dev,0,q.Type,alloc,NULL,&IID_ID3D12GraphicsCommandList,(void**)&list)))return 5;
 D3D12_HEAP_PROPERTIES heap={0};heap.Type=D3D12_HEAP_TYPE_DEFAULT;
 D3D12_RESOURCE_DESC desc={0};desc.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;desc.Width=32;desc.Height=32;desc.DepthOrArraySize=1;desc.MipLevels=1;desc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;desc.SampleDesc.Count=1;desc.Flags=D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
 ID3D12Resource *texture=NULL,*readback=NULL;
 if(FAILED(ID3D12Device_CreateCommittedResource(dev,&heap,D3D12_HEAP_FLAG_NONE,&desc,D3D12_RESOURCE_STATE_RENDER_TARGET,NULL,&IID_ID3D12Resource,(void**)&texture)))return 6;
 D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint;UINT64 size=0;ID3D12Device_GetCopyableFootprints(dev,&desc,0,1,0,&footprint,NULL,NULL,&size);
 D3D12_RESOURCE_DESC buffer={0};buffer.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;buffer.Width=size;buffer.Height=1;buffer.DepthOrArraySize=1;buffer.MipLevels=1;buffer.SampleDesc.Count=1;buffer.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
 heap.Type=D3D12_HEAP_TYPE_READBACK;
 if(FAILED(ID3D12Device_CreateCommittedResource(dev,&heap,D3D12_HEAP_FLAG_NONE,&buffer,D3D12_RESOURCE_STATE_COPY_DEST,NULL,&IID_ID3D12Resource,(void**)&readback)))return 7;
 ID3D12DescriptorHeap *rtv=NULL;D3D12_DESCRIPTOR_HEAP_DESC hd={0};hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV;hd.NumDescriptors=1;
 if(FAILED(ID3D12Device_CreateDescriptorHeap(dev,&hd,&IID_ID3D12DescriptorHeap,(void**)&rtv)))return 8;
 D3D12_CPU_DESCRIPTOR_HANDLE handle=ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(rtv);
 ID3D12Device_CreateRenderTargetView(dev,texture,NULL,handle);const float color[4]={0,1,0,1};ID3D12GraphicsCommandList_ClearRenderTargetView(list,handle,color,0,NULL);
 D3D12_RESOURCE_BARRIER barrier={0};barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;barrier.Transition.pResource=texture;barrier.Transition.StateBefore=D3D12_RESOURCE_STATE_RENDER_TARGET;barrier.Transition.StateAfter=D3D12_RESOURCE_STATE_COPY_SOURCE;
 ID3D12GraphicsCommandList_ResourceBarrier(list,1,&barrier);
 D3D12_TEXTURE_COPY_LOCATION source={0},dest={0};source.pResource=texture;source.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;dest.pResource=readback;dest.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;dest.PlacedFootprint=footprint;
 ID3D12GraphicsCommandList_CopyTextureRegion(list,&dest,0,0,0,&source,NULL);
 if(FAILED(ID3D12GraphicsCommandList_Close(list)))return 9;
 ID3D12CommandList *commands=(ID3D12CommandList*)list;ID3D12CommandQueue_ExecuteCommandLists(queue,1,&commands);
 ID3D12Fence *fence=NULL;if(FAILED(ID3D12Device_CreateFence(dev,0,D3D12_FENCE_FLAG_NONE,&IID_ID3D12Fence,(void**)&fence)))return 10;
 HANDLE done=CreateEventW(NULL,FALSE,FALSE,NULL);if(!done)return 11;
 if(FAILED(ID3D12CommandQueue_Signal(queue,fence,1)) || FAILED(ID3D12Fence_SetEventOnCompletion(fence,1,done)) || WaitForSingleObject(done,15000)!=WAIT_OBJECT_0)return 12;
 BYTE *pixels=NULL;D3D12_RANGE range={0,(SIZE_T)size};if(FAILED(ID3D12Resource_Map(readback,0,&range,(void**)&pixels)))return 13;
 BYTE *pixel=pixels+footprint.Offset+16*footprint.Footprint.RowPitch+16*4;BOOL valid=pixel[0]==0 && pixel[1]==255 && pixel[2]==0 && pixel[3]==255;
 printf("D3D12_READBACK=%s RGBA=%u,%u,%u,%u\n",valid?"PASS":"FAIL",pixel[0],pixel[1],pixel[2],pixel[3]);
 D3D12_RANGE written={0,0};ID3D12Resource_Unmap(readback,0,&written);CloseHandle(done);
 ID3D12Fence_Release(fence);ID3D12DescriptorHeap_Release(rtv);ID3D12Resource_Release(readback);ID3D12Resource_Release(texture);ID3D12GraphicsCommandList_Release(list);ID3D12CommandAllocator_Release(alloc);ID3D12CommandQueue_Release(queue);ID3D12Device_Release(dev);
 return valid?0:14;
}
