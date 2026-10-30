# AI馬券の記録(馬情報/AI馬券/記録.csv)に結果を埋め、成績(馬情報/AI馬券/成績.md)を作り直す
# 使い方: python settle.py [記録.csv]
#   結果は JRA-VAN の SE(確定成績、全データ/RACE/<年>.txt): 確定着順と確定単勝オッズ。1着なら 払戻 = 金額 × オッズ
#   取消・除外(着順 00 でオッズなし)は返還(払戻 = 金額)。中止は 0。同着の1着は払戻が分けられるが、ここではオッズのまま(まれなので)
#   dry(記録だけ)の行も、買っていたらいくらになったかを同じように埋める
import sys, os, csv, glob, datetime as dt
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
REC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '馬情報', 'AI馬券', '記録.csv')
if not os.path.exists(REC): sys.exit(0)
rows = list(csv.DictReader(open(REC, encoding='utf-8-sig'))); cols = list(rows[0].keys()) if rows else []
need = {r['raceId'] for r in rows if r['rank'] == ''}
d = lambda b: b.decode('cp932', 'replace').strip()
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from jvfix import fixline   # 2026-10-27 以降の化けたレコードを直す
res = {}
for y in sorted({x[:4] for x in need}):
    p = os.path.join(ROOT, '馬情報', 'JRA-VAN', '全データ', 'RACE', y + '.txt')
    if not os.path.exists(p): continue
    for l in open(p, 'rb'):
        if l[:3] != b'SE7': continue
        l = fixline(l)
        rid = d(l[11:19]) + d(l[19:21]) + d(l[25:27])
        if rid in need: res[(rid, int(d(l[28:30])))] = (d(l[334:336]), d(l[359:363]))
n = 0
for r in rows:
    if r['rank'] != '' or (r['raceId'], int(r['umaban'])) not in res: continue
    rk, od = res[(r['raceId'], int(r['umaban']))]; st = int(r['stake'] or 0) or 100   # 記録だけ(stake 0)も100円として数える
    if rk == '00' and not od.strip('0'): r['rank'], r['payout'] = '返還', st
    else: r['rank'] = str(int(rk)) if rk.isdigit() and int(rk) > 0 else '中止'; r['payout'] = int(round(st * int(od) / 10)) if r['rank'] == '1' else 0
    n += 1
with open(REC, 'w', encoding='utf-8-sig', newline='') as f:
    w = csv.DictWriter(f, cols); w.writeheader(); w.writerows(rows)
print(f'結果を埋めた: {n} 行', file=sys.stderr)

# 成績
done = [r for r in rows if r['rank'] != '']
def summ(rs):
    st = sum(int(r['stake'] or 0) or 100 for r in rs); pay = sum(int(r['payout'] or 0) for r in rs); hit = sum(r['rank'] == '1' for r in rs)
    return f"| {len(rs)} | {hit} | {hit / len(rs) * 100:.1f}% | {st:,} | {pay:,} | {pay / st * 100:.1f}% |" if rs else '| 0 | | | | | |'
L = ['# AI馬券の成績', '', f'更新: {dt.datetime.now():%Y-%m-%d %H:%M}(`自動実行/AI馬券/settle.py`)。買い方は 検証26 の「C+オッズ」で、期待値(AIの勝率 × 発走前の単勝オッズ)1.0以上・30倍未満の単勝。',
     'mode: dry = 記録だけ(買っていない)/ browser = 即PATで購入の手前まで / bought = 本当に買った。記録だけの行も100円買ったとして数える', '',
     '| 区分 | 点数 | 的中 | 的中率 | 金額 | 払戻 | 回収率 |', '|---|---|---|---|---|---|---|']
for k in ['bought', 'dry', 'browser', 'over', 'failed']:
    rs = [r for r in done if r['status'] == k]
    if rs: L.append(f'| {k} ' + summ(rs))
L.append('| 全部 ' + summ(done))
import json
cfg = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'config.json'), encoding='utf-8'))
real = [r for r in rows if r['status'] == 'bought' and r['date'] >= cfg['startDate']]
bank = cfg['bankrollStart'] + sum(int(r['payout'] or 0) - int(r['stake'] or 0) for r in real)
L[4:4] = [f"**資金: {bank:,}円**(始め {cfg['bankrollStart']:,}円・{cfg['startDate']}〜。本当に買った分だけ。結果待ちは払戻0で数える)", '']
L += ['', '## 日ごと', '', '| 日 | 点数 | 的中 | 的中率 | 金額 | 払戻 | 回収率 |', '|---|---|---|---|---|---|---|']
for day in sorted({r['date'] for r in done}, reverse=True): L.append(f'| {day} ' + summ([r for r in done if r['date'] == day]))
L += ['', f'結果待ち: {len(rows) - len(done)} 行']
open(os.path.join(os.path.dirname(REC), '成績.md'), 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print('\n'.join(L[5:9]))
