#!/usr/bin/env python3
"""jra_odds.py の出力を DB から保存したレース文書(馬名一致)に重ねて、update 用 JSON を作る。
使い方: python3 jra_merge.py <jra出力> <dbフォルダ(races/*.json)> <更新出力> 
更新出力/manifest.tsv に doc_id と file を出す(version は DB から get して付ける)。
JRAの出馬表(オッズ)に載っていない登録馬は scratched: true。"""
import sys, os, json, glob, time
jra, db, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
pl = {'04': '新潟', '05': '東京', '08': '京都'}
idx = {}
for f in glob.glob(db + '/races/*.json'):
    d = json.load(open(f)); idx[(d.get('date'), d.get('place'), d.get('no'))] = d
now = time.strftime('%Y-%m-%dT%H:%M:%S+09:00', time.gmtime(time.time() + 32400))
hm = now[11:16]
norm = lambda s: s.replace('.', '').replace(' ', '')
n = 0
for f in sorted(glob.glob(jra + '/*.json')):
    b = os.path.basename(f)[:-5]
    k = (f"{b[1:5]}-{b[5:7]}-{b[7:9]}", pl[b[9:11]], int(b[11:13]))
    d = idx.get(k)
    if not d: continue
    rows = {r['name']: r for r in json.load(open(f))['horses']}
    hs = d['horses']
    for h in hs:
        r = rows.get(h['name'])
        if not r:
            h['scratched'] = True; continue
        h.pop('scratched', None)
        h['umaban'] = r['umaban']
        if 'waku' in r: h['waku'] = r['waku']
        if 'odds' in r: h['odds'] = r['odds']; h['oddsKari'] = False
        for key in ('fukuMin', 'fukuMax', 'weight', 'weightDiff'):
            if key in r: h[key] = r[key]
        if r.get('scratched'): h['scratched'] = True
        if r['jockey'] and norm(r['jockey']) != norm(h.get('jockey', '')) and not norm(h.get('jockey', '')).startswith(norm(r['jockey'])[:2]):
            print('騎手違い', b, h['name'], h.get('jockey'), '->', r['jockey'])
    u = {'horses': hs, 'updatedAt': now,
         'memo': (d.get('memo', '') + f" / JRA公式 {hm} 反映(オッズ・馬番など)")[-600:]}
    if d.get('grade'): u['stage'] = '枠順確定'
    json.dump(u, open(f"{out}/{d['id']}.json", 'w'), ensure_ascii=False)
    open(out + '/manifest.tsv', 'a').write(f"{d['id']}\t{out}/{d['id']}.json\n")
    n += 1
print('更新', n)
