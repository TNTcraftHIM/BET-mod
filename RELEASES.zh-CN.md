# 发布版本

[English](RELEASES.md) | **中文**

完整的 Windows 安装包作为 GitHub Release 资源发布：

- `BETPlayerCap-v2.19.11-full.zip`

## 校验你的下载（推荐）

本仓库在
[`dist/BETPlayerCap-v2.19.11-full.zip.sha256`](dist/BETPlayerCap-v2.19.11-full.zip.sha256)
处记录了一个 SHA256 校验和，同时也会在发布说明中给出。

PowerShell：

```powershell
Get-FileHash .\BETPlayerCap-v2.19.11-full.zip -Algorithm SHA256
```

将打印出的哈希值与 `.sha256` 文件中的值进行比对。两者必须一致。

## 重新构建安装包（维护者）

该 zip 由仓库内跟踪的源文件加上一份经过测试的本地 UE4SS 安装构建而成：

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_release.ps1 -GameRoot "F:\Steam\steamapps\common\Backrooms_Escape_Together"
```

这会重新生成 `dist/BETPlayerCap-v2.19.11-full.zip`。然后刷新校验和：

```bash
sha256sum dist/BETPlayerCap-v2.19.11-full.zip | sed 's#dist/##' > dist/BETPlayerCap-v2.19.11-full.zip.sha256
```

该 zip 本身不会被 git 跟踪（`dist/*.zip` 已被忽略）；请将其上传到 GitHub
Release。`.sha256` 文件则会被跟踪。
