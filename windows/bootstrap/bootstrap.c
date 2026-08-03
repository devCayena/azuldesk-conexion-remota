// AzulRemote Bootstrap
// Stub autosuficiente: lleva los .dll y assets embebidos como recursos RCDATA.
// Al ejecutarse extrae SOLO los archivos que faltan o cuyo checksum cambió a
// %LOCALAPPDATA%\AzulRemote y luego lanza el AzulRemote.exe real.
//
// Compilado con MSVC: cl bootstrap.c payload.res /Fe:AzulRemote.exe ...
//   1> rc.exe /fo payload.res payload.rc
//   2> cl.exe /O1 /MT /utf-8 /DUNICODE /D_UNICODE bootstrap.c payload.res /Fe:AzulRemote.exe kernel32.lib user32.lib bcrypt.lib shell32.lib

#include <windows.h>
#include <bcrypt.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef ERROR_SHARING_VIOLATION
#define ERROR_SHARING_VIOLATION 32L
#endif

// El payload se embebe con ids numericos 1..N (1 = manifest).
#define ID_MANIFEST 1

typedef struct {
    int id;                 // id del recurso RCDATA
    WCHAR *rel_path;        // ruta relativa dentro de la instalacion (separador '\')
    uint64_t size;          // tamanio del archivo
    BYTE hash[32];          // sha256
} PayloadEntry;

static PayloadEntry *g_entries = NULL;
static int g_entry_count = 0;

// ---------------------------------------------------------------------------
// utilidades

static void fatal(const WCHAR *msg) {
    MessageBoxW(NULL, msg, L"AzulRemote - Error de instalacion", MB_OK | MB_ICONERROR);
}

static WCHAR *dup_str(const WCHAR *s) {
    size_t n = wcslen(s) + 1;
    WCHAR *p = (WCHAR *)LocalAlloc(LMEM_FIXED, n * sizeof(WCHAR));
    if (p) wcscpy_s(p, n, s);
    return p;
}

static WCHAR *to_backslash(WCHAR *s) {
    for (WCHAR *p = s; *p; p++) if (*p == L'/') *p = L'\\';
    return s;
}

// Separa "rel_path \t id \t size \t sha256hex"
static int parse_manifest_line(const WCHAR *line, PayloadEntry *out) {
    WCHAR tmp[1024];
    wcscpy_s(tmp, 1024, line);
    WCHAR *p = tmp;
    WCHAR *tab;
    // rel_path
    tab = wcschr(p, L'\t');
    if (!tab) return 0;
    *tab = 0;
    out->rel_path = dup_str(to_backslash(p));
    if (!out->rel_path) return 0;
    // id
    p = tab + 1;
    tab = wcschr(p, L'\t');
    if (!tab) return 0;
    *tab = 0;
    out->id = _wtoi(p);
    // size
    p = tab + 1;
    tab = wcschr(p, L'\t');
    if (!tab) return 0;
    *tab = 0;
    out->size = _wcstoui64(p, NULL, 10);
    // hash hex (64 chars)
    p = tab + 1;
    if (wcslen(p) < 64) return 0;
    for (int i = 0; i < 32; i++) {
        unsigned int v;
        swscanf_s(p + i * 2, L"%2x", &v);
        out->hash[i] = (BYTE)v;
    }
    return 1;
}

static int load_manifest(void) {
    HRSRC hrs = FindResourceW(NULL, MAKEINTRESOURCE(ID_MANIFEST), RT_RCDATA);
    if (!hrs) return 0;
    HGLOBAL hg = LoadResource(NULL, hrs);
    if (!hg) return 0;
    DWORD size = SizeofResource(NULL, hrs);
    const char *data = (const char *)LockResource(hg);
    if (!data || size == 0) return 0;

    // convertir a wchar por lineas
    int lines = 0;
    const char *p = data;
    const char *end = data + size;
    while (p < end) {
        if (*p == L'\n') lines++;
        p++;
    }
    lines++;

    g_entries = (PayloadEntry *)LocalAlloc(LMEM_FIXED, sizeof(PayloadEntry) * (lines + 1));
    if (!g_entries) return 0;
    memset(g_entries, 0, sizeof(PayloadEntry) * (lines + 1));

    // reinterpretar el buffer (ya es UTF-8 emitido por el manifest; convertimos)
    WCHAR *wide = (WCHAR *)LocalAlloc(LMEM_FIXED, sizeof(WCHAR) * (size * 4 + 8));
    if (!wide) return 0;
    int wn = MultiByteToWideChar(CP_UTF8, 0, data, (int)size, wide, (int)(size * 4));
    if (wn <= 0) { LocalFree(wide); return 0; }
    wide[wn] = 0;

    int count = 0;
    WCHAR *line = wide;
    WCHAR *nl;
    while ((nl = wcschr(line, L'\n')) != NULL) {
        *nl = 0;
        // recortar \r
        size_t l = wcslen(line);
        if (l && line[l - 1] == L'\r') line[l - 1] = 0;
        if (line[0] && line[0] != L'#') {
            PayloadEntry e;
            if (parse_manifest_line(line, &e)) {
                g_entries[count++] = e;
            }
        }
        line = nl + 1;
    }
    g_entry_count = count;
    LocalFree(wide);
    return count > 0;
}

// sha256 de un archivo; devuelve 1 si ok
static int file_sha256(const WCHAR *path, BYTE out[32]) {
    HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;

    BCRYPT_ALG_HANDLE alg = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    int ok = 0;
    do {
        if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, NULL, 0) != 0) break;
        if (BCryptCreateHash(alg, &hash, NULL, 0, NULL, 0, 0) != 0) break;
        BYTE buf[65536];
        DWORD rd = 0;
        BOOL r = ReadFile(h, buf, sizeof(buf), &rd, NULL);
        while (r && rd > 0) {
            if (BCryptHashData(hash, buf, rd, 0) != 0) break;
            r = ReadFile(h, buf, sizeof(buf), &rd, NULL);
        }
        if (r && rd == 0) {
            BCryptFinishHash(hash, out, 32, 0);
            ok = 1;
        }
    } while (0);

    if (hash) BCryptDestroyHash(hash);
    if (alg) BCryptCloseAlgorithmProvider(alg, 0);
    CloseHandle(h);
    return ok;
}

static void create_dirs_for(const WCHAR *full) {
    WCHAR tmp[MAX_PATH];
    wcscpy_s(tmp, MAX_PATH, full);
    for (WCHAR *p = tmp; *p; p++) {
        if (*p == L'\\') {
            *p = 0;
            if (tmp[0]) CreateDirectoryW(tmp, NULL);
            *p = L'\\';
        }
    }
}

// Escribe un recurso a disco (id), con reintentos si el archivo esta bloqueado.
static int extract_resource(int id, const WCHAR *dst) {
    HRSRC hrs = FindResourceW(NULL, MAKEINTRESOURCE(id), RT_RCDATA);
    if (!hrs) return 0;
    HGLOBAL hg = LoadResource(NULL, hrs);
    if (!hg) return 0;
    DWORD size = SizeofResource(NULL, hrs);
    const BYTE *data = (const BYTE *)LockResource(hg);
    if (!data) return 0;

    create_dirs_for(dst);

    int attempts = 0;
    while (attempts < 50) {
        HANDLE h = CreateFileW(dst, GENERIC_WRITE, FILE_SHARE_READ, NULL,
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h == INVALID_HANDLE_VALUE) {
            DWORD err = GetLastError();
            if (err == ERROR_SHARING_VIOLATION || err == 5 /*ACCESS_DENIED*/) {
                attempts++;
                Sleep(200);
                continue;
            }
            return 0;
        }
        DWORD written = 0;
        BOOL ok = WriteFile(h, data, size, &written, NULL);
        CloseHandle(h);
        return ok && written == size;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// instalacion / actualizacion

static WCHAR *get_install_dir(void) {
    // permitir override para testing
    DWORD len = GetEnvironmentVariableW(L"AZULREMOTE_HOME", NULL, 0);
    if (len > 0) {
        WCHAR *env = (WCHAR *)LocalAlloc(LMEM_FIXED, sizeof(WCHAR) * len);
        if (env) {
            GetEnvironmentVariableW(L"AZULREMOTE_HOME", env, len);
            return env;
        }
    }
    WCHAR local[MAX_PATH];
    if (!SHGetFolderPathW(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, local)) {
        PathAppendW(local, L"AzulRemote");
        return dup_str(local);
    }
    return NULL;
}

static int install_payload(const WCHAR *install_dir) {
    int updated = 0;
    for (int i = 0; i < g_entry_count; i++) {
        PayloadEntry *e = &g_entries[i];
        WCHAR full[MAX_PATH];
        swprintf_s(full, MAX_PATH, L"%s\\%s", install_dir, e->rel_path);

        BYTE local_hash[32];
        int needs = 1;
        if (file_sha256(full, local_hash)) {
            WIN32_FILE_ATTRIBUTE_DATA fad;
            if (GetFileAttributesExW(full, GetFileExInfoStandard, &fad)) {
                uint64_t local_size =
                    ((uint64_t)fad.nFileSizeHigh << 32) | fad.nFileSizeLow;
                if (local_size == e->size && memcmp(local_hash, e->hash, 32) == 0) {
                    needs = 0; // ya esta actualizado
                }
            }
        }

        if (needs) {
            // Si el archivo existe, intentar borrarlo primero
            if (GetFileAttributesW(full) != INVALID_FILE_ATTRIBUTES) {
                SetFileAttributesW(full, FILE_ATTRIBUTE_NORMAL);
                if (!DeleteFileW(full)) {
                    WCHAR tmp[MAX_PATH];
                    swprintf_s(tmp, MAX_PATH, L"%s.old", full);
                    DeleteFileW(tmp);
                    MoveFileExW(full, tmp, MOVEFILE_REPLACE_EXISTING);
                    DeleteFileW(tmp);
                }
                Sleep(200);
            }
            if (!extract_resource(e->id, full)) {
                return -1;
            }
            updated++;
        }
    }
    return updated;
}

// ---------------------------------------------------------------------------
// lanzamiento

// Retorna una cadena (allocada) con la linea de comandos despues del exe.
static WCHAR *rest_of_cmdline(void) {
    LPWSTR cmd = GetCommandLineW();
    if (!cmd) return dup_str(L"");
    // saltar el primer token (ruta del exe), respetando comillas
    const WCHAR *p = cmd;
    if (*p == L'"') {
        p++;
        while (*p && *p != L'"') p++;
        if (*p == L'"') p++;
    } else {
        while (*p && *p != L' ') p++;
    }
    while (*p == L' ') p++;
    return dup_str(p);
}

static int launch_app(const WCHAR *install_dir) {
    WCHAR app[MAX_PATH];
    swprintf_s(app, MAX_PATH, L"%s\\AzulRemote.exe", install_dir);

    if (GetFileAttributesW(app) == INVALID_FILE_ATTRIBUTES) {
        fatal(L"No se pudo encontrar AzulRemote.exe instalado.");
        return 1;
    }

    // Si ya hay una instancia corriendo, matarla para que el update aplique
    HWND w = FindWindowW(NULL, L"AzulDesk - Conexion Remota");
    if (w) {
        DWORD pid = 0;
        GetWindowThreadProcessId(w, &pid);
        if (pid) {
            HANDLE hProc = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
            if (hProc) {
                TerminateProcess(hProc, 0);
                CloseHandle(hProc);
                Sleep(1000);
            }
        }
    }

    // si aun hay mutex, esperar y reintentar
    for (int retry = 0; retry < 5; retry++) {
        HANDLE oldMutex = CreateMutexW(NULL, FALSE, L"Local\\AzulRemote_MainInstance");
        if (!oldMutex || GetLastError() != ERROR_ALREADY_EXISTS) {
            if (oldMutex) CloseHandle(oldMutex);
            break;
        }
        CloseHandle(oldMutex);
        Sleep(500);
    }

    WCHAR *args = rest_of_cmdline();
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    memset(&pi, 0, sizeof(pi));
    si.cb = sizeof(si);

    WCHAR cmdline[2048];
    swprintf_s(cmdline, 2048, L"\"%s\" %s", app, args);
    LocalFree(args);

    HANDLE mutex = CreateMutexW(NULL, FALSE, L"Local\\AzulRemote_MainInstance");
    BOOL ok = CreateProcessW(app, cmdline, NULL, NULL, FALSE,
                             CREATE_NEW_PROCESS_GROUP, NULL, install_dir, &si, &pi);
    if (!ok) {
        fatal(L"No se pudo iniciar AzulRemote.exe.");
        if (mutex) CloseHandle(mutex);
        return 1;
    }
    CloseHandle(pi.hThread);
    // esperar para propagar el codigo de salida
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    if (mutex) CloseHandle(mutex);
    return (int)code;
}

// ---------------------------------------------------------------------------

int wmain(void) {
    if (!load_manifest()) {
        fatal(L"AzulRemote instalador corrupto: no se encontro el payload.");
        return 1;
    }

    WCHAR *install_dir = get_install_dir();
    if (!install_dir) {
        fatal(L"No se pudo determinar el directorio de instalacion.");
        return 1;
    }

    int res = install_payload(install_dir);
    if (res < 0) {
        WCHAR msg[512];
        swprintf_s(msg, 512, L"Error instalando AzulRemote.\nDirectorio: %s", install_dir);
        fatal(msg);
        LocalFree(install_dir);
        return 1;
    }

    int code = launch_app(install_dir);

    for (int i = 0; i < g_entry_count; i++) {
        if (g_entries[i].rel_path) LocalFree(g_entries[i].rel_path);
    }
    if (g_entries) LocalFree(g_entries);
    LocalFree(install_dir);
    return code;
}
