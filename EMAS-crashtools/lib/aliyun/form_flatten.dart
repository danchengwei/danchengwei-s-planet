/// 与 @alicloud/openapi-util 的 flatMap / toForm 行为对齐，用于 RPC formData。
void flattenToStringMap(Map<String, String> target, Object? params, [String prefix = '']) {
  if (params == null) return;
  if (params is Map) {
    final pref = prefix.isEmpty ? '' : '$prefix.';
    params.forEach((dynamic k, dynamic v) {
      final key = k.toString();
      final fullKey = '$pref$key';
      if (v == null) return;
      if (v is Map) {
        flattenToStringMap(target, v, fullKey);
      } else if (v is List) {
        for (var i = 0; i < v.length; i++) {
          final item = v[i];
          final listKey = '$fullKey.${i + 1}';
          if (item == null) continue;
          if (item is Map) {
            flattenToStringMap(target, item, listKey);
          } else if (item is List) {
            _flattenRepeatList(target, item, listKey);
          } else {
            target[listKey] = item.toString();
          }
        }
      } else {
        target[fullKey] = v.toString();
      }
    });
  }
}

void _flattenRepeatList(Map<String, String> target, List list, String prefix) {
  final pref = '$prefix.';
  for (var i = 0; i < list.length; i++) {
    final item = list[i];
    final key = '$pref${i + 1}';
    if (item == null) continue;
    if (item is Map) {
      flattenToStringMap(target, item, key);
    } else if (item is List) {
      _flattenRepeatList(target, item, key);
    } else {
      target[key] = item.toString();
    }
  }
}

String aliyunPercentEncode(String s) {
  return Uri.encodeComponent(s)
      .replaceAll('+', '%20')
      .replaceAll('!', '%21')
      .replaceAll("'", '%27')
      .replaceAll('(', '%28')
      .replaceAll(')', '%29')
      .replaceAll('*', '%2A');
}

/// 扁平化后按 key 排序拼接为 x-www-form-urlencoded。
String toFormString(Map<String, String> flat) {
  final keys = flat.keys.toList()..sort();
  final parts = <String>[];
  for (final k in keys) {
    parts.add('${aliyunPercentEncode(k)}=${aliyunPercentEncode(flat[k]!)}');
  }
  return parts.join('&');
}
