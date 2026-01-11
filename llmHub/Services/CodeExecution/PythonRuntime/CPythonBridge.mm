#import "CPythonBridge.h"

#if __has_include(<Python/Python.h>)
    #import <Python/Python.h>
#elif __has_include(<Python.h>)
    #import <Python.h>
#else
    // Python headers not available for this build configuration.
#endif

#include <stdlib.h>
#include <string.h>

static bool s_initialized = false;

bool llmhub_python_initialize(const char *pythonHome, const char *pythonPath) {
#if !(__has_include(<Python/Python.h>) || __has_include(<Python.h>))
    (void)pythonHome;
    (void)pythonPath;
    return false;
#else
    if (s_initialized) {
        return true;
    }

    if (pythonHome && pythonHome[0] != '\0') {
        setenv("PYTHONHOME", pythonHome, 1);
    }

    if (pythonPath && pythonPath[0] != '\0') {
        setenv("PYTHONPATH", pythonPath, 1);
    }

    // iOS doesn't allow writing .pyc files into the bundle.
    setenv("PYTHONDONTWRITEBYTECODE", "1", 1);

    Py_Initialize();
    s_initialized = Py_IsInitialized() ? true : false;
    return s_initialized;
#endif
}

int llmhub_python_run_simple_string(const char *code) {
#if !(__has_include(<Python/Python.h>) || __has_include(<Python.h>))
    (void)code;
    return -1;
#else
    if (!s_initialized) {
        return -1;
    }

    if (!code) {
        return -1;
    }

    return PyRun_SimpleString(code);
#endif
}

void llmhub_python_finalize(void) {
#if !(__has_include(<Python/Python.h>) || __has_include(<Python.h>))
    return;
#else
    if (!s_initialized) {
        return;
    }

    Py_Finalize();
    s_initialized = false;
#endif
}

bool llmhub_python_run_and_capture(const char *code, char **outStdout, char **outStderr, int *outExitCode) {
#if !(__has_include(<Python/Python.h>) || __has_include(<Python.h>))
    (void)code;
    if (outStdout) { *outStdout = NULL; }
    if (outStderr) { *outStderr = NULL; }
    if (outExitCode) { *outExitCode = -1; }
    return false;
#else
    if (!s_initialized || !code) {
        if (outStdout) { *outStdout = NULL; }
        if (outStderr) { *outStderr = NULL; }
        if (outExitCode) { *outExitCode = -1; }
        return false;
    }

    // Build a wrapper that captures stdout/stderr into Python strings, then stores them into globals.
    // We then read those globals back via C-API.
    const char *prefix =
        "import sys, io, traceback\n"
        "__llmhub_stdout = io.StringIO()\n"
        "__llmhub_stderr = io.StringIO()\n"
        "__llmhub_old_out, __llmhub_old_err = sys.stdout, sys.stderr\n"
        "sys.stdout, sys.stderr = __llmhub_stdout, __llmhub_stderr\n"
        "__llmhub_exit = 0\n"
        "try:\n";

    const char *suffix =
        "\nexcept SystemExit as e:\n"
        "    try:\n"
        "        __llmhub_exit = int(getattr(e, 'code', 0) or 0)\n"
        "    except Exception:\n"
        "        __llmhub_exit = 1\n"
        "except Exception:\n"
        "    traceback.print_exc()\n"
        "    __llmhub_exit = 1\n"
        "finally:\n"
        "    sys.stdout, sys.stderr = __llmhub_old_out, __llmhub_old_err\n";

    // Indent the user code by 4 spaces for the try: block.
    size_t codeLen = strlen(code);
    // Allocate ~2x worst case for indentation.
    size_t indentedCap = codeLen * 2 + 1;
    char *indented = (char *)malloc(indentedCap);
    if (!indented) {
        if (outExitCode) { *outExitCode = 1; }
        return false;
    }
    size_t j = 0;
    for (size_t i = 0; i < codeLen; i++) {
        if (i == 0 || code[i - 1] == '\n') {
            indented[j++] = ' ';
            indented[j++] = ' ';
            indented[j++] = ' ';
            indented[j++] = ' ';
        }
        indented[j++] = code[i];
        if (j + 8 >= indentedCap) {
            indentedCap *= 2;
            indented = (char *)realloc(indented, indentedCap);
            if (!indented) {
                if (outExitCode) { *outExitCode = 1; }
                return false;
            }
        }
    }
    indented[j] = '\0';

    size_t scriptLen = strlen(prefix) + strlen(indented) + strlen(suffix) + 1;
    char *script = (char *)malloc(scriptLen);
    if (!script) {
        free(indented);
        if (outExitCode) { *outExitCode = 1; }
        return false;
    }

    strcpy(script, prefix);
    strcat(script, indented);
    strcat(script, suffix);

    free(indented);

    int rc = PyRun_SimpleString(script);
    free(script);

    // Extract globals from __main__
    PyObject *mainMod = PyImport_AddModule("__main__");
    PyObject *globals = PyModule_GetDict(mainMod);

    PyObject *pyOut = PyDict_GetItemString(globals, "__llmhub_stdout");
    PyObject *pyErr = PyDict_GetItemString(globals, "__llmhub_stderr");
    PyObject *pyExit = PyDict_GetItemString(globals, "__llmhub_exit");

    const char *outC = "";
    const char *errC = "";

    if (pyOut) {
        PyObject *outStr = PyObject_CallMethod(pyOut, "getvalue", NULL);
        if (outStr) {
            outC = PyUnicode_AsUTF8(outStr);
            Py_DECREF(outStr);
        }
    }

    if (pyErr) {
        PyObject *errStr = PyObject_CallMethod(pyErr, "getvalue", NULL);
        if (errStr) {
            errC = PyUnicode_AsUTF8(errStr);
            Py_DECREF(errStr);
        }
    }

    int exitCode = 0;
    if (pyExit) {
        exitCode = (int)PyLong_AsLong(pyExit);
    }

    if (rc != 0) {
        exitCode = 1;
    }

    if (outStdout) {
        size_t n = outC ? strlen(outC) : 0;
        *outStdout = (char *)malloc(n + 1);
        if (*outStdout) {
            if (n) { memcpy(*outStdout, outC, n); }
            (*outStdout)[n] = '\0';
        }
    }

    if (outStderr) {
        size_t n = errC ? strlen(errC) : 0;
        *outStderr = (char *)malloc(n + 1);
        if (*outStderr) {
            if (n) { memcpy(*outStderr, errC, n); }
            (*outStderr)[n] = '\0';
        }
    }

    if (outExitCode) {
        *outExitCode = exitCode;
    }

    return true;
#endif
}
