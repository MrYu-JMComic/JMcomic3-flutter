/// 下载导入支持的归档类型。
///
/// 这里保留明确的枚举，而不是把后缀判断散落在页面层，避免后续新增导入格式时
/// Android 文件选择器、桌面文件选择器和 Rust 后端调用关系不一致。
enum DownloadImportArchiveKind {
  jmZip,
  jmi,
}

/// 根据用户选择的路径判断导入类型。
///
/// 只接受后端实际支持的 `.jm.zip` 和 `.jmi`：普通 `.zip` 可能来自其他导出工具，
/// 不能直接传给 `import_jm_zip`，否则会在 Rust 侧执行一段无意义的失败解析。
DownloadImportArchiveKind? detectDownloadImportArchiveKind(String path) {
  final lowerPath = path.trim().toLowerCase();
  if (lowerPath.endsWith(".jm.zip")) {
    return DownloadImportArchiveKind.jmZip;
  }
  if (lowerPath.endsWith(".jmi")) {
    return DownloadImportArchiveKind.jmi;
  }
  return null;
}
