# 分支、PR 与发布规范

## 分支与 PR

- `main` 保持可构建、可发布；日常工作使用 `codex/<主题>` 或明确用途的短期分支。
- PR 说明具体行为变化、验证结果和已知限制。稳定收尾 PR 同时核对版本、文档、
  固定后端提交和发布文件。
- 本地分析、测试和目标平台构建通过后合并。保留 PR 与提交记录，合并后删除短期分支。
- 未合并提交、未提交修改和旧验证记录先备份再清理。删除 Git 引用前用
  `git bundle create <归档路径> --all` 保存历史，旧检查点不作为正式版本标签。
- 保留 `v<语义版本>+<build number>` 正式发布标签，每次发布递增 build number。

GitHub 中仅保留手动诊断 CI。正式包在固定本地环境生成，再通过 GitHub CLI 上传；
退役的云端发布流程不参与当前版本发布。

## 发布步骤

1. 同步 `main`，确认工作区干净，建立收尾分支。
2. 使用 `scripts/update_version.ps1 -Version 1.7.26+55` 同步 `pubspec.yaml`、
   `lib/assets/version.txt`、`ci/version.code.txt` 和本地 Android 版本；更新
   `ci/version.info.txt`、README 和 CHANGELOG 的实际内容。
3. 固定 `ci/backend.commit.txt`，核对后端检出和锁文件；按 [BUILDING.md](BUILDING.md)
   执行分析、测试、设备回归及 Android / Windows 构建。符号按版本保存在本机归档。
4. 校验 APK / AAB 的版本、架构、签名和 native 内容；核对 Android 签名证书与上一正式版
   一致。Windows 核对 EXE 文件版本、完整目录并测试启动。
5. 创建并合并 PR，在合并后的精确提交上创建版本标签。源码相同的已验证构建可以复用，
   `build-info.json` 同时记录构建提交和发布标签提交。
6. 整理下面的文件，生成 SHA-256 校验和、来源记录和准确的发布说明。
7. 先创建 draft release，上传并核对完整附件及远端 digest，再发布为 latest。
8. 核对 `releases/latest`、标签和附件；清理已合并分支、旧 worktree 和临时产物。

## 附件与来源记录

| 文件名 | 内容 |
| --- | --- |
| `Jmcomic3-arm64-v8a-v<版本>+<编号>.apk` | ARM64 split APK |
| `Jmcomic3-armeabi-v7a-v<版本>+<编号>.apk` | ARM32 split APK |
| `Jmcomic3-android-v<版本>+<编号>.aab` | Android App Bundle |
| `Jmcomic3-windows-x64-v<版本>+<编号>.zip` | 完整 Windows portable 目录与声明 |
| `build-info.json` | 源码与发布 SHA、Rust SHA、工具链、锁文件哈希、证书指纹、验证结果、附件哈希 |
| `SHA256SUMS.txt` | 所有其他附件的 SHA-256 |

`build-info.json` 不记录账号、令牌、keystore 路径或口令。符号、日志和备份保存在
`dist/` 或 `build/`，不混入源码提交。

本地发布命令示例（`$releaseSha` 必须是已验证的合并提交）：

```powershell
$tag = (Get-Content ci/version.code.txt).Trim()
git tag -a $tag $releaseSha -m "JMComic3 $tag"
git push origin $tag
gh release create $tag --verify-tag --draft --title "JMComic3 $tag" --notes-file ci/version.info.txt
gh release upload $tag <本地附件路径>
gh release view $tag --json tagName,isDraft,assets
gh release edit $tag --draft=false --latest
```

旧发布保留以供回退。正式发布标签及附件不通过强制推送或 `--clobber` 覆盖。