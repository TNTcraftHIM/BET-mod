# Releases

**English** | [中文](RELEASES.zh-CN.md)

The full Windows package is published as a GitHub Release asset:

- `BETPlayerCap-v2.19.10-full.zip`

## Verify your download (recommended)

A SHA256 checksum is tracked in this repo at
[`dist/BETPlayerCap-v2.19.10-full.zip.sha256`](dist/BETPlayerCap-v2.19.10-full.zip.sha256)
and is also posted in the release notes.

PowerShell:

```powershell
Get-FileHash .\BETPlayerCap-v2.19.10-full.zip -Algorithm SHA256
```

Compare the printed hash to the value in the `.sha256` file. They must match.

## Rebuilding the package (maintainers)

The zip is built from tracked sources plus a tested local UE4SS install:

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_release.ps1 -GameRoot "F:\Steam\steamapps\common\Backrooms_Escape_Together"
```

This regenerates `dist/BETPlayerCap-v2.19.10-full.zip`. Then refresh the checksum:

```bash
sha256sum dist/BETPlayerCap-v2.19.10-full.zip | sed 's#dist/##' > dist/BETPlayerCap-v2.19.10-full.zip.sha256
```

The zip itself is not tracked in git (`dist/*.zip` is ignored); upload it to the GitHub
Release. The `.sha256` file is tracked.
