# FoundationModels Diagnostics

To troubleshoot "models not installed" or other Apple Intelligence availability issues, use the following steps to capture high-signal diagnostics.

## 1. Enable Verbose Diagnostics in llmHub

1. Open **Settings** (⌘ + , on macOS).
2. Go to the **Diagnostics** section (only visible in DEBUG builds).
3. Toggle **Verbose AFM Logs** to ON.

## 2. Capture Logs in Terminal

Run the following commands in Terminal to capture real-time signals from llmHub and Apple's underlying frameworks.

### Filter llmHub AFM Diagnostics

This captures the `AFM_DIAG` prefixed logs from llmHub.

```bash
log stream --predicate 'subsystem == "com.llmhub" AND category == "AFM"' --style compact
```

### Capture Apple Framework Signals (Broad)

This captures logs related to model asset delivery, cataloging, and Unified Asset Framework (UAF).

```bash
log stream --predicate 'eventMessage CONTAINS[c] "UnifiedAsset" OR eventMessage CONTAINS[c] "MobileAsset" OR eventMessage CONTAINS[c] "modelcatalog" OR eventMessage CONTAINS[c] "UAF"' --style compact
```

## 3. Trigger a Probe

With the Terminal commands running, return to llmHub Settings and:

1. Click **Run AFM Probe**.
2. Click **Run AFM Generate (small)**.

## 4. Analyze Output

- Look for `AFM_DIAG availability=unavailable` and the associated `reason`.
- Check for `MobileAsset` errors (e.g., `404`, `Forbidden`, or `Space exhausted`).
- Verify if `UnifiedAssetFramework` reports any catalog mismatches.
