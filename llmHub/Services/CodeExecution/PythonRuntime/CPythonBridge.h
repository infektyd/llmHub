#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialize the embedded CPython runtime.
///
/// The caller provides:
/// - pythonHome: Path to the embedded Python bundle root (e.g. <App>/python)
/// - pythonPath: Additional sys.path entries (colon separated)
///
/// Returns true on success.
bool llmhub_python_initialize(const char *pythonHome, const char *pythonPath);

/// Run Python source code.
///
/// Returns 0 for success; non-zero for failure.
int llmhub_python_run_simple_string(const char *code);

/// Finalize Python (best-effort). Not always recommended to call repeatedly.
void llmhub_python_finalize(void);

/// Run Python code and capture stdout/stderr.
///
/// Returns true if the interpreter was initialized and the call executed.
///
/// The returned strings are allocated with malloc(); the caller must free().
bool llmhub_python_run_and_capture(const char *code, char **outStdout, char **outStderr, int *outExitCode);

#ifdef __cplusplus
}
#endif
