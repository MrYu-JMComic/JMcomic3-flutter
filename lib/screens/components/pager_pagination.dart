/// 根据总条目数和固定单页容量计算分页总页数。
///
/// 容量可由接口明确提供，或由分页器记录首批条数；尾页条数不改变容量。
int calcMaxPageFromTotal(int total, int pageSize) {
  if (total <= 0 || pageSize <= 0) {
    return 1;
  }
  final wholePages = total ~/ pageSize;
  final hasRemainder = total % pageSize != 0;
  return wholePages + (hasRemainder ? 1 : 0);
}
