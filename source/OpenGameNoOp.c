/* SPDX-License-Identifier: MIT
 *
 * A quiet replacement for optional Windows telemetry helpers that are known
 * to crash under Wine.  OpenGame only installs this for Steam's 64-bit crash
 * reporter, after preserving Valve's original file in the user's Backups
 * directory.  It deliberately performs no reporting and exits successfully.
 */
#include <windows.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR command_line,
                    int show_command)
{
    (void)instance;
    (void)previous;
    (void)command_line;
    (void)show_command;
    return 0;
}
