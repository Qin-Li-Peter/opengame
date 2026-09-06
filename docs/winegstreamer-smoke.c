#include <windows.h>
#include <stdio.h>

int main(void)
{
    HMODULE module = LoadLibraryW(L"winegstreamer.dll");
    if (!module)
    {
        printf("WINEGSTREAMER_LOAD=%08lx\n", GetLastError());
        return 1;
    }
    puts("WINEGSTREAMER_LOAD=OK");
    FreeLibrary(module);
    return 0;
}
