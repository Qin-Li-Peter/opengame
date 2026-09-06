#include <windows.h>
#include <stdio.h>
static HANDLE mutex_handle,gate;static LONG counter=0;
static DWORD WINAPI worker(void *arg){
 (void)arg;if(WaitForSingleObject(gate,10000)!=WAIT_OBJECT_0)return 1;
 for(int i=0;i<1000;i++){if(WaitForSingleObject(mutex_handle,10000)!=WAIT_OBJECT_0)return 2;counter++;if(!ReleaseMutex(mutex_handle))return 3;}return 0;
}
int main(void){
 setvbuf(stdout,NULL,_IONBF,0);mutex_handle=CreateMutexW(NULL,FALSE,NULL);gate=CreateEventW(NULL,TRUE,FALSE,NULL);HANDLE threads[4];BOOL ok=mutex_handle&&gate;
 for(int i=0;i<4;i++){threads[i]=CreateThread(NULL,0,worker,NULL,0,NULL);ok=ok&&threads[i]!=NULL;}
 if(!ok)return 1;SetEvent(gate);DWORD result=WaitForMultipleObjects(4,threads,TRUE,30000);ok=result==WAIT_OBJECT_0&&counter==4000;
 for(int i=0;i<4;i++){DWORD exitcode=999;GetExitCodeThread(threads[i],&exitcode);ok=ok&&exitcode==0;CloseHandle(threads[i]);}
 printf("ARCH_BITS=%d\nTHREAD_MUTEX_EVENT=%s\nCOUNTER=%ld\n",(int)sizeof(void*)*8,ok?"PASS":"FAIL",counter);CloseHandle(gate);CloseHandle(mutex_handle);
 HANDLE sem=CreateSemaphoreW(NULL,0,2,NULL);BOOL semok=sem&&WaitForSingleObject(sem,0)==WAIT_TIMEOUT&&ReleaseSemaphore(sem,2,NULL)&&WaitForSingleObject(sem,1000)==WAIT_OBJECT_0&&WaitForSingleObject(sem,1000)==WAIT_OBJECT_0&&WaitForSingleObject(sem,0)==WAIT_TIMEOUT;if(sem)CloseHandle(sem);
 HANDLE automatic=CreateEventW(NULL,FALSE,FALSE,NULL);BOOL eventok=automatic&&SetEvent(automatic)&&WaitForSingleObject(automatic,1000)==WAIT_OBJECT_0&&WaitForSingleObject(automatic,0)==WAIT_TIMEOUT;if(automatic)CloseHandle(automatic);
 printf("SEMAPHORE=%s\nAUTO_RESET_EVENT=%s\n",semok?"PASS":"FAIL",eventok?"PASS":"FAIL");return ok&&semok&&eventok?0:2;
}
