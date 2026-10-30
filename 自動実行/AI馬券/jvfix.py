# JRA-VAN の RACE レコード(RA・SE)の文字化けを読むときに直す
# 2026-10-27 以降に update.sh(PC収集)が足したレコードは、JV-Link が Shift-JIS を cp1252 として文字にし、jvget が Shift-JIS で書き直したため、
# 日本語の1バイト目が「?」になり、レコードの長さもずれている(項目の位置がずれる)。
# 化けたレコードを Shift-JIS で読むと「1文字 = 元の1バイト」になるので、cp1252 に戻すと長さと数字の項目の位置が元に戻る(日本語の名前は戻らない)
LEN = {b'RA': 1271, b'SE': 554}   # 正しいレコードの長さ(改行を含む)

def fixline(l):
    n = LEN.get(l[:2])
    if n is None or len(l) == n: return l
    f = l.rstrip(b'\r\n').decode('cp932', 'replace').encode('cp1252', 'replace') + b'\n'
    return f if len(f) == n else l
