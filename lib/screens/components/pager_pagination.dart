/// 根据总条目数和接口提供的单页容量计算分页总页数。
///
/// 收藏接口会单独返回每页容量；其他列表可回退到当前页实际条数。
int calcMaxPageFromTotal(int total, int pageSize) {
  if (total <= 0 || pageSize <= 0) {
    return 1;
  }
  final wholePages = total ~/ pageSize;
  final hasRemainder = total % pageSize != 0;
  return wholePages + (hasRemainder ? 1 : 0);
}
