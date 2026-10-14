#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

_Static_assert(sizeof(void*)==8 && sizeof(BOOLEAN)==1 && sizeof(ULONG)==4, "x64 ABI");
_Static_assert(sizeof(OBJECT_ATTRIBUTES)==48 && offsetof(OBJECT_ATTRIBUTES,ObjectName)==16,"object ABI");
typedef NTSTATUS (NTAPI *OpenDirectory)(PHANDLE,ACCESS_MASK,POBJECT_ATTRIBUTES);
typedef NTSTATUS (NTAPI *QueryDirectory)(HANDLE,PVOID,ULONG,BOOLEAN,BOOLEAN,PULONG,PULONG);
extern NTSTATUS call_raw_query(QueryDirectory,HANDLE,PVOID,ULONG,ULONG,ULONG,PULONG,PULONG);
typedef struct {UNICODE_STRING name,type;} Entry;
typedef struct {
    QueryDirectory function;HANDLE directory;PVOID buffer;
    ULONG single,restart,context,needed;NTSTATUS status;
} Job;
static DWORD WINAPI invoke(LPVOID pointer) {
    Job *j=pointer;
    j->status=call_raw_query(j->function,j->directory,j->buffer,1024,j->single,j->restart,&j->context,&j->needed);
    return 0;
}
static DWORD WINAPI watchdog(LPVOID unused) {
    (void)unused;Sleep(15000);fprintf(stderr,"overall TIMEOUT\n");fflush(NULL);
    TerminateProcess(GetCurrentProcess(),124);return 124;
}
static uint32_t fingerprint(Entry *e) {
    uint32_t hash=2166136261u;
    /* Read only this diagnostic's own returned object-name bytes. No registry,
       Steam, login data or process memory is read. */
    for (unsigned i=0;i<e->name.Length/sizeof(WCHAR);i++) {hash^=e->name.Buffer[i];hash*=16777619u;}
    return hash;
}
int main(int argc, char **argv) {
    int require_normalized=argc>1 && !strcmp(argv[1],"--expect-normalized");
    int regression_failed=0;
    HANDLE guard=CreateThread(NULL,0,watchdog,NULL,0,NULL);if(!guard)return 2;CloseHandle(guard);
    HMODULE nt=GetModuleHandleW(L"ntdll.dll");
    OpenDirectory open=(OpenDirectory)(void*)GetProcAddress(nt,"NtOpenDirectoryObject");
    QueryDirectory query=(QueryDirectory)(void*)GetProcAddress(nt,"NtQueryDirectoryObject");
    if(!open||!query)return 2;
    WCHAR name[]=L"\\BaseNamedObjects";
    UNICODE_STRING us={sizeof(name)-sizeof(WCHAR),sizeof(name),name};
    OBJECT_ATTRIBUTES oa;memset(&oa,0,sizeof(oa));oa.Length=sizeof(oa);oa.ObjectName=&us;oa.Attributes=0x40;
    HANDLE directory=NULL;NTSTATUS status=open(&directory,1,&oa);
    printf("open=%08lx\n",(unsigned long)status);if(status<0)return 3;
    HANDLE event=CreateEventW(NULL,FALSE,FALSE,L"Global\\OpenGameBooleanABIProbe");
    printf("temporary event=%s\n",event?"created":"unavailable");
    _Alignas(16) unsigned char buffer[1024];
    for(unsigned mode=0;mode<3;mode++) {
        ULONG context=0;
        int ended=0;
        for(unsigned iteration=0;iteration<8;iteration++) {
            ULONG before=context;
            ULONG single=mode==2?(iteration?0x7ff33401u:0x06f92c01u):1;
            ULONG restart=iteration==0?1:(mode?0x00140000u:0);
            memset(buffer,0,sizeof(buffer));
            Job job={query,directory,buffer,single,restart,context,0,0};
            HANDLE thread=CreateThread(NULL,0,invoke,&job,0,NULL);if(!thread)return 2;
            if(WaitForSingleObject(thread,1500)!=WAIT_OBJECT_0) {
                fprintf(stderr,"per-call TIMEOUT\n");fflush(NULL);TerminateProcess(GetCurrentProcess(),124);return 124;
            }
            CloseHandle(thread);context=job.context;
            printf("mode=%u iter=%u single=%08lx restart=%08lx status=%08lx ctx=%lu->%lu bytes=%lu hash=%08lx\n",
                   mode,iteration,(unsigned long)single,(unsigned long)restart,(unsigned long)job.status,
                   (unsigned long)before,(unsigned long)context,(unsigned long)job.needed,
                   (unsigned long)(job.status>=0?fingerprint((Entry*)buffer):0));fflush(stdout);
            if((ULONG)job.status==0x8000001au) {ended=1;break;}
            if(job.status<0 || context!=before+1)regression_failed=1;
            if(job.status<0)break;
        }
        if(!ended)regression_failed=1;
    }
    if(event)CloseHandle(event);
    CloseHandle(directory);
    if(require_normalized)printf("BOOLEAN_NORMALIZATION=%s\n",regression_failed?"FAIL":"PASS");
    return require_normalized && regression_failed ? 1 : 0;
}
