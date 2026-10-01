#ifndef V1_FALLBACK_CACHE_WINDOWS_HELPERS_H
#define V1_FALLBACK_CACHE_WINDOWS_HELPERS_H
#include <windows.h>
#include <stdlib.h>
#include <string.h>

/* Windows ignores mkdir's POSIX mode. Supply a protected DACL at creation
 * instead of inheriting unrelated writable capability/group ACEs. */
static int v1_fallback_create_private_directory(const unsigned short *path) {
    typedef BOOL (WINAPI *open_token_fn)(HANDLE, DWORD, PHANDLE);
    typedef BOOL (WINAPI *token_info_fn)(HANDLE, TOKEN_INFORMATION_CLASS, LPVOID, DWORD, PDWORD);
    typedef DWORD (WINAPI *sid_length_fn)(PSID);
    HMODULE security = GetModuleHandleA("advapi32.dll");
    if (security == NULL) security = LoadLibraryA("advapi32.dll");
    if (security == NULL) return 0;
    open_token_fn open_token = (open_token_fn)GetProcAddress(security, "OpenProcessToken");
    token_info_fn token_info = (token_info_fn)GetProcAddress(security, "GetTokenInformation");
    sid_length_fn sid_length = (sid_length_fn)GetProcAddress(security, "GetLengthSid");
    if (open_token == NULL || token_info == NULL || sid_length == NULL) return 0;
    HANDLE token = NULL;
    void *information = NULL;
    ACL *acl = NULL;
    int result = 0;
    DWORD length = 0;
    if (!open_token(GetCurrentProcess(), TOKEN_QUERY, &token)) goto cleanup;
    token_info(token, TokenUser, NULL, 0, &length);
    if (length == 0) goto cleanup;
    information = malloc(length);
    if (information == NULL || !token_info(token, TokenUser, information, length, &length)) goto cleanup;
    PSID owner = ((TOKEN_USER *)information)->User.Sid;
    if (owner == NULL) goto cleanup;
    DWORD sid_bytes = sid_length(owner);
    if (sid_bytes == 0 || sid_bytes > 128) goto cleanup;
    DWORD ace_bytes = sizeof(ACCESS_ALLOWED_ACE) - sizeof(DWORD) + sid_bytes;
    DWORD acl_bytes = sizeof(ACL) + ace_bytes;
    acl = (ACL *)calloc(1, acl_bytes);
    if (acl == NULL) goto cleanup;
    acl->AclRevision = ACL_REVISION;
    acl->AclSize = (WORD)acl_bytes;
    acl->AceCount = 1;
    ACCESS_ALLOWED_ACE *ace = (ACCESS_ALLOWED_ACE *)((unsigned char *)acl + sizeof(ACL));
    ace->Header.AceType = ACCESS_ALLOWED_ACE_TYPE;
    ace->Header.AceFlags = OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE;
    ace->Header.AceSize = (WORD)ace_bytes;
    ace->Mask = FILE_ALL_ACCESS;
    memcpy(&ace->SidStart, owner, sid_bytes);
    SECURITY_DESCRIPTOR descriptor;
    memset(&descriptor, 0, sizeof(descriptor));
    descriptor.Revision = SECURITY_DESCRIPTOR_REVISION;
    descriptor.Control = SE_DACL_PRESENT | SE_DACL_PROTECTED;
    descriptor.Owner = owner;
    descriptor.Dacl = acl;
    SECURITY_ATTRIBUTES attributes;
    attributes.nLength = sizeof(attributes);
    attributes.lpSecurityDescriptor = &descriptor;
    attributes.bInheritHandle = FALSE;
    result = CreateDirectoryW((LPCWSTR)path, &attributes) != 0;
    if (!result && GetLastError() == ERROR_ALREADY_EXISTS) result = 1;
cleanup:
    free(acl);
    free(information);
    if (token != NULL) CloseHandle(token);
    return result;
}
#endif
