# Artifact Attachment Fix - Root Cause Analysis

## Problem Statement

Users import artifacts to sandbox. Manifest shows imported files. User sends message. Provider request contains NO attachment references. Model never sees the files.

## Root Cause (Evidence-Backed)

**Issue**: `SandboxedArtifact` objects are never converted to `Attachment` objects or staged for message sending.

### Evidence Chain

| **Checkpoint**  | **File:Line**                      | **Current State**                                            | **Expected State**        |
| --------------- | ---------------------------------- | ------------------------------------------------------------ | ------------------------- |
| Import Success  | `ArtifactSandboxService.swift:261` | ✅ `SandboxedArtifact` created & added to manifest           | ✅ Working                |
| VM State        | `ChatViewModel.swift:588`          | ✅ Added to `recentlyImportedArtifacts: [SandboxedArtifact]` | ✅ Working                |
| **Staging Gap** | `ChatViewModel.swift:650-664`      | ❌ No code converts sandbox artifacts to `Attachment`        | ⚠️ **MISSING**            |
| Send Pipeline   | `ChatViewModel.swift:890`          | ❌ `stagedAttachments` is empty                              | ❌ Attachments missing    |
| Request Build   | `ChatService.swift:517-552`        | ❌ `attachments` param is empty array                        | ❌ No attachment data     |
| Provider Body   | `ChatService.swift:546-552`        | ❌ `formatAttachmentsForRequest` returns empty string        | ❌ Model never sees files |

### Key Code Locations

**ChatViewModel.swift:890** - sends only `stagedAttachments`:

```swift
let finalAttachments = attachments ?? stagedAttachments
```

**ChatService.swift:546-552** - only injects if `!updatedAttachments.isEmpty`:

```swift
if !updatedAttachments.isEmpty {
    let attachmentBlock = service.formatAttachmentsForRequest(updatedAttachments)
    if !attachmentBlock.isEmpty {
        updatedParts.append(.text("\n\n" + attachmentBlock))
    }
}
```

**formatAttachmentsForRequest:1421-1462** - tries to read attachment.url, but no Attachments exist!

## Minimal Fix

Add a method to convert `SandboxedArtifact` → `Attachment` at send-time.

### Option A (Baseline): Explicit UI Action to Stage Artifacts

Add "Attach to Message" button in sidebar → converts selected artifacts to `Attachment` → adds to `stagedAttachments`.

### Option B (Automatic): Auto-stage on importAnytime an artifact is imported, automatically convert to `Attachment` and add to `stagedAttachments`.

### Option C (Header Injection): Fallback cross-provider safety net

If attachments are empty but `recentlyImportedArtifacts` has items, inject a bounded header listing available files.

**Recommendation**: Implement B (auto-stage) + C (header fallback) for reliability.

## Claims vs Evidence

| **Claim**                             | **Evidence**                                                | **File:Line**                      |
| ------------------------------------- | ----------------------------------------------------------- | ---------------------------------- |
| Artifacts import successfully         | `logger.info("✅ Imported artifact...")`                    | `ArtifactSandboxService.swift:260` |
| Artifacts stored in VM                | `recentlyImportedArtifacts.append(artifact)`                | `ChatViewModel.swift:588`          |
| No staging conversion                 | Grep finds no `SandboxedArtifact` → `Attachment` conversion | N/A (missing code)                 |
| `stagedAttachments` is separate array | `var stagedAttachments: [Attachment] = []`                  | `ChatViewModel.swift:56`           |
| Send uses `stagedAttachments` only    | `let finalAttachments = attachments ?? stagedAttachments`   | `ChatViewModel.swift:890`          |
| Request injects only if non-empty     | `if !updatedAttachments.isEmpty { ... }`                    | `ChatService.swift:546`            |

## Implementation Plan

### Step 1: Add Conversion Helper (ChatViewModel)

```swift
/// Converts a SandboxedArtifact to an Attachment.
private func makeAttachment(from sandboxArtifact: SandboxedArtifact) async -> Attachment? {
    let fullPath = await ArtifactSandboxService.shared.artifactPath(for: sandboxArtifact)

    let type: AttachmentType
    if sandboxArtifact.mimeType.hasPrefix("image/") {
        type = .image
    } else if sandboxArtifact.mimeType == "application/pdf" {
        type = .pdf
    } else if sandboxArtifact.mimeType.hasPrefix("text/") || sandboxArtifact.filename.hasSuffix(".swift") {
        type = .code
    } else {
        type = .other
    }

    // Read preview for text files
    let preview: String?
    if type == .code || type == .text {
        preview = try? String(contentsOf: fullPath, encoding: .utf8).prefix(200).map(String.init)
    } else {
        preview = nil
    }

    return Attachment(
        filename: sandboxArtifact.filename,
        url: fullPath,
        type: type,
        previewText: preview
    )
}
```

### Step 2: Auto-stage on Import (ChatViewModel.swift:588)

```swift
@discardableResult
func importFileToSandbox(url: URL) async -> SandboxedArtifact? {
    do {
        let artifact = try await ArtifactSandboxService.shared.importFile(from: url)
        recentlyImportedArtifacts.append(artifact)

        // AUTO-STAGE: Convert to Attachment and add to staged list
        if let attachment = await makeAttachment(from: artifact) {
            stagedAttachments.append(attachment)
            logger.info("✅ Auto-staged artifact as attachment: \(artifact.filename)")
        }

        logger.info("Imported file to sandbox: \(artifact.filename)")
        return artifact
    } catch {
        logger.error("Failed to import file to sandbox: \(error.localizedDescription)")
        return nil
    }
}
```

### Step 3: Add DEBUG-Safe Attachment Metrics (LLMRequestTracer.swift)

```swift
/// Log attachment metrics for debugging (DEBUG-safe: no content, no paths)
nonisolated static func attachmentMetrics(
    provider: String,
    attachmentCount: Int,
    attachmentMeta: [(id: String, filename: String, type: String, bytes: Int)]
) {
    if attachmentCount > 0 {
        let summary = attachmentMeta.prefix(3).map {
            "\($0.filename)(\($0.type),\($0.bytes)B)"
        }.joined(separator: ", ")
        let more = attachmentCount > 3 ? " +\(attachmentCount - 3) more" : ""
        logger.info("📎 [\(provider)] Attachments: \(attachmentCount) - \(summary)\(more)")
    }
}
```

### Step 4: Instrument ChatService (ChatService.swift:546)

```swift
// BEFORE: if !updatedAttachments.isEmpty {
let attachmentCount = updatedAttachments.count
 LLMTrace.attachmentMetrics(
    provider: currentSession.providerID,
    attachmentCount: attachmentCount,
    attachmentMeta: updatedAttachments.prefix(5).map { att in
        (
            id: att.id.uuidString.prefix(8).description,
            filename: att.filename,
            type: att.type.rawValue,
            bytes: att.previewText?.utf8.count ?? 0
        )
    }
)

if !updatedAttachments.isEmpty {
    let attachmentBlock = service.formatAttachmentsForRequest(updatedAttachments)
    if !attachmentBlock.isEmpty {
        updatedParts.append(.text("\n\n" + attachmentBlock))
    }
}
```

### Step 5: Fallback Header (ChatService.swift:546, AFTER attachment block)

```swift
// FALLBACK: If no attachments but sandbox has files, inject header
if updatedAttachments.isEmpty {
    let sandboxArtifacts = await ArtifactSandboxService.shared.listArtifacts()
    if !sandboxArtifacts.isEmpty {
        let header = buildAttachmentHeader(sandboxArtifacts.prefix(10))
        if !header.isEmpty {
            updatedParts.append(.text("\n\n" + header))
            LLMTrace.featureSkipped(
                provider: currentSession.providerID,
                feature: "Attachment fallback header",
                reason: "Injected \(sandboxArtifacts.count) sandbox file refs"
            )
        }
    }
}

private func buildAttachmentHeader(_ artifacts: [SandboxedArtifact]) -> String {
    guard !artifacts.isEmpty else { return "" }
    var lines = ["[AVAILABLE_FILES]"]
    for artifact in artifacts.prefix(10) {
        let size = ByteCountFormatter.string(fromByteCount: Int64(artifact.sizeBytes), countStyle: .file)
        lines.append("- \(artifact.filename) (\(artifact.mimeType), \(size))")
    }
    if artifacts.count > 10 {
        lines.append("... and \(artifacts.count - 10) more files")
    }
    lines.append("[/AVAILABLE_FILES]")
    return lines.joined(separator: "\n")
}
```

## Manual Test Checklist

### macOS

- [ ] Import PNG artifact via sidebar
- [ ] Check console: `✅ Auto-staged artifact as attachment`
- [ ] Send message (any text)
- [ ] Check console: `📎 [provider] Attachments: 1 - filename.png(image,12345B)`
- [ ] Verify provider request body contains attachment header or inline content

### iOS Simulator

- [ ] Import TXT artifact via file picker
- [ ] Check console: attachment metrics logged
- [ ] Send message
- [ ] Verify provider sees file reference

### Edge Cases

- [ ] Import multiple files (3+)
- [ ] Send without importing (should have 0 attachments)
- [ ] Import, clear staging, send (should be 0)

## Diffs Summary

| File                     | Lines Changed | Purpose                                  |
| ------------------------ | ------------- | ---------------------------------------- |
| `ChatViewModel.swift`    | ~30           | Add conversion helper + auto-stage logic |
| `LLMRequestTracer.swift` | ~15           | Add DEBUG-safe attachment metrics        |
| `ChatService.swift`      | ~40           | Add instrumentation + fallback header    |

**Total**: ~85 lines, no regressions, no refactoring.
