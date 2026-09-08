/* SPDX-License-Identifier: MIT
 * Windows UDP loopback regression for Darwin IP_RECVTOS conversion.
 * Build: x86_64-w64-mingw32-clang udp-tos.c -lws2_32 -o udp-tos.exe
 */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <mswsock.h>
#include <stdio.h>

#define REQUIRE(call) do { if (!(call)) { \
    fprintf(stderr, "%s failed: %d\n", #call, WSAGetLastError()); \
    goto cleanup; \
} } while (0)

int main(void)
{
    WSADATA startup;
    SOCKET receiver = INVALID_SOCKET, sender = INVALID_SOCKET;
    int result = 1, enabled = 1, tos = 0xb8, timeout = 2000;
    struct sockaddr_in address = {0};
    int address_size = sizeof(address);
    GUID extension = WSAID_WSARECVMSG;
    LPFN_WSARECVMSG receive_message = NULL;
    DWORD bytes;
    char payload[8], control[256];
    WSABUF buffer = {sizeof(payload), payload};
    WSAMSG message = {0};

    if (WSAStartup(MAKEWORD(2, 2), &startup)) return 1;
    receiver = socket(AF_INET, SOCK_DGRAM, 0);
    sender = socket(AF_INET, SOCK_DGRAM, 0);
    REQUIRE(receiver != INVALID_SOCKET && sender != INVALID_SOCKET);
    REQUIRE(!setsockopt(receiver, IPPROTO_IP, IP_RECVTOS, (char *)&enabled, sizeof(enabled)));
    REQUIRE(!setsockopt(receiver, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout)));
    REQUIRE(!setsockopt(sender, IPPROTO_IP, IP_TOS, (char *)&tos, sizeof(tos)));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    REQUIRE(!bind(receiver, (void *)&address, sizeof(address)));
    REQUIRE(!getsockname(receiver, (void *)&address, &address_size));
    REQUIRE(!WSAIoctl(receiver, SIO_GET_EXTENSION_FUNCTION_POINTER,
                      &extension, sizeof(extension), &receive_message,
                      sizeof(receive_message), &bytes, NULL, NULL));
    REQUIRE(receive_message != NULL);
    REQUIRE(sendto(sender, "T", 1, 0, (void *)&address, sizeof(address)) == 1);
    message.lpBuffers = &buffer;
    message.dwBufferCount = 1;
    message.Control.buf = control;
    message.Control.len = sizeof(control);
    REQUIRE(!receive_message(receiver, &message, &bytes, NULL, NULL));
    REQUIRE(bytes == 1 && payload[0] == 'T' && !(message.dwFlags & MSG_CTRUNC));
    for (WSACMSGHDR *header = WSA_CMSG_FIRSTHDR(&message); header;
         header = WSA_CMSG_NXTHDR(&message, header)) {
        if (header->cmsg_level == IPPROTO_IP && header->cmsg_type == IP_TOS &&
            header->cmsg_len >= WSA_CMSG_LEN(sizeof(int))) {
            int value = *(int *)WSA_CMSG_DATA(header);
            printf("TOS=%02x expected=b8\n", value);
            if (value == tos) result = 0;
        }
    }
    puts(result ? "FAIL: missing or incorrect TOS ancillary data" : "PASS");
cleanup:
    if (sender != INVALID_SOCKET) closesocket(sender);
    if (receiver != INVALID_SOCKET) closesocket(receiver);
    WSACleanup();
    return result;
}
