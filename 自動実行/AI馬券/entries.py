# JRA-VAN の出馬表(全データ/RACE/<年>.txt の RA・SE レコード。木・金曜から入る)から、まだ走っていないレースを
# JRA詳細.jsonl と同じ形(着順なし)にする。lgbm_features.py --extra に渡す
# 使い方: python entries.py <日付 YYYYMMDD>[,<日付>...] <出力.jsonl> [--check]
#   --check: 終わった日を指定すると、作った値を JRA詳細.jsonl(JRA公式の結果)と突き合わせて違いを数える(項目の位置の確かめ)
#   出力の1行 = 1レース。post = 発走時刻(HHMM)。騎手・調教師の名前は、JRA-VAN の略称ではなく JRA詳細 と同じ正式名にする
#   (過去2年の SE と JRA詳細 を馬番で突き合わせて、騎手コード・調教師コード → 名前 の表を作る)
import sys, os, glob, json
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
RACE = os.path.join(ROOT, '馬情報', 'JRA-VAN', '全データ', 'RACE'); HIST = os.path.join(ROOT, '馬情報', '過去レースデータ', '全期間')
DAYS = sys.argv[1].split(','); OUT = sys.argv[2]; CHECK = '--check' in sys.argv
d = lambda b: b.decode('cp932', 'replace').strip('　 ')
def num(b, default=0):
    t = d(b); return int(t) if t.isdigit() else default
KIN = {'1': 'ハンデ', '2': '別定', '3': '馬齢', '4': '定量'}
CLS = {'701': '新馬', '702': '新馬', '703': '未勝利', '005': '1勝クラス', '010': '2勝クラス', '016': '3勝クラス', '999': 'オープン'}
OUTER = {12, 13, 14, 16, 18, 19, 20, 22, 26}   # 外回りを含むトラックコード

years = sorted({x[:4] for x in DAYS} | {str(int(DAYS[0][:4]) - 1)})
ra, se, past = {}, {}, []
for y in years:
    p = os.path.join(RACE, y + '.txt')
    if not os.path.exists(p): continue
    for l in open(p, 'rb'):
        t = l[:2]
        if t not in (b'RA', b'SE'): continue
        day = l[11:19].decode(); rid = day + d(l[19:21]) + d(l[25:27])
        if t == b'SE' and l[2:3] == b'7': past.append((rid, int(d(l[28:30])), d(l[296:301]), d(l[85:90])))
        if day not in DAYS: continue
        key = (l[3:11], l[2:3])   # 作成日・データ区分。新しいものを残す
        if t == b'RA':
            if rid not in ra or key >= ra[rid][0]: ra[rid] = (key, l)
        else:
            u = int(d(l[28:30]))
            if (rid, u) not in se or key >= se[(rid, u)][0]: se[(rid, u)] = (key, l)

# 騎手・調教師のコード → 正式名(JRA詳細)
jk, tr = {}, {}
want = {r for r, _, _, _ in past}
for y in years:
    p = os.path.join(HIST, y, 'JRA詳細.jsonl')
    if not os.path.exists(p): continue
    for l in open(p, encoding='utf-8'):
        x = json.loads(l)
        if x['id'] not in want: continue
        for h in x['horses']: jk[(x['id'], h['umaban'])] = (h.get('jockey') or '', h.get('trainer') or '')
JN, TN = {}, {}
for rid, u, jc, tc in past:
    if (rid, u) in jk:
        if jk[(rid, u)][0]: JN[jc] = jk[(rid, u)][0]
        if jk[(rid, u)][1]: TN[tc] = jk[(rid, u)][1]

out = []
for rid, (_, r) in sorted(ra.items()):
    track = num(r[705:707])
    if track >= 51 or track == 0: continue   # 障害
    surf = '芝' if track <= 22 else 'ダ'
    H = []
    for (rr, u), (_, s) in sorted(se.items()):
        if rr != rid: continue
        if d(s[331:332]) not in ('0', ''): continue   # 取消・除外など
        sex = {'1': '牡', '2': '牝', '3': 'せん'}.get(d(s[78:79]), '')
        bw = d(s[324:327]); sg = d(s[327:328]); df = d(s[328:331])
        jc, tc = d(s[296:301]), d(s[85:90])
        H.append({'horseId': d(s[30:40]), 'name': d(s[40:76]), 'umaban': u, 'waku': num(s[27:28]),
                  'sexAge': sex + str(num(s[82:84])), 'kin': (num(s[288:291], None) or 0) / 10 or None, 'blinker': d(s[294:295]) == '1',
                  'jockey': JN.get(jc, d(s[306:314])), 'trainer': TN.get(tc, d(s[90:98])),
                  'bw': int(bw) if bw.isdigit() and int(bw) > 0 else None,
                  'bwDiff': (int(df) * (-1 if sg == '-' else 1)) if df.isdigit() and bw.isdigit() and int(bw) > 0 else None,
                  'rank': None})
    if len(H) < 2: continue
    fillies = all(h['sexAge'].startswith('牝') for h in H)
    out.append({'id': rid, 'date': f'{rid[:4]}-{rid[4:6]}-{rid[6:8]}', 'post': d(r[873:877]), 'cond': '牝' if fillies else '',
                'race': {'surface': surf, 'course': ('芝' if surf == '芝' else 'ダート') + (' 外' if track in OUTER else ''), 'dist': num(r[697:701]),
                         'cls': CLS.get(d(r[634:637]), 'オープン'), 'kinType': KIN.get(d(r[621:622]), ''), 'going': '', 'weather': ''},
                'horses': H})
with open(OUT, 'w', encoding='utf-8') as f:
    for x in out: f.write(json.dumps(x, ensure_ascii=False) + '\n')
print(f'{len(out)} レース・{sum(len(x["horses"]) for x in out)} 頭(騎手の名前 {len(JN)}・調教師 {len(TN)})', file=sys.stderr)

if CHECK:   # 終わった日: JRA詳細 と項目ごとに突き合わせる
    J = {}
    for y in {x[:4] for x in DAYS}:
        for l in open(os.path.join(HIST, y, 'JRA詳細.jsonl'), encoding='utf-8'):
            x = json.loads(l); J[x['id']] = x
    bad = {}; n = 0
    for x in out:
        j = J.get(x['id'])
        if not j: bad['レースなし'] = bad.get('レースなし', 0) + 1; continue
        for k in ['dist', 'cls', 'kinType']:
            if x['race'][k] != j['race'].get(k): bad['race.' + k] = bad.get('race.' + k, 0) + 1
        if x['race']['surface'] != ('ダ' if (j['race'].get('surface') or '').startswith('ダ') else '芝'): bad['surface'] = bad.get('surface', 0) + 1
        jh = {h['umaban']: h for h in j['horses']}
        for h in x['horses']:
            g = jh.get(h['umaban']); n += 1
            if not g: bad['馬なし'] = bad.get('馬なし', 0) + 1; continue
            for k in ['horseId', 'waku', 'sexAge', 'kin', 'jockey', 'trainer', 'bw', 'bwDiff']:
                a, b = h[k], g.get(k)
                if k == 'jockey': b = (b or '').lstrip('▲△☆◇★')
                if k == 'sexAge' and a != b and bad.get('例', 0) < 3: print('性齢', a, b, file=sys.stderr); bad['例'] = bad.get('例', 0) + 1
                if a != b and not (k == 'kin' and b is not None and abs(a - b) < 0.01): bad[k] = bad.get(k, 0) + 1
    print('突き合わせ:', n, '頭', bad, file=sys.stderr)
