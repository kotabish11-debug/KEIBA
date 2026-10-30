# AI馬券の当日の判断(と購入)。各レースの発走 leadMin 分前に JRA公式の単勝オッズ・馬体重を取り、AIの勝率 × 単勝オッズ が evMin 以上の馬を買う
# 使い方: python live.py <当日の特徴量.pkl(morning.sh)> <entries.jsonl> [--date YYYY-MM-DD] [--replay 分]
#   --replay N: 終わった日を確かめる用。待たずに全レースを回し、オッズは JRA-VAN の時系列オッズ(締切 N 分前)、馬体重は entries の値を使う。買わない
#   設定は config.json(mode: dry = 記録だけ / browser = 即PATで購入の手前まで / live = 本当に買う)
#   記録: 馬情報/AI馬券/記録.csv(買い目と結果。settle.py が結果を埋める)、馬情報/JRA-VAN/AI馬券/予想_<日付>.jsonl(全馬の勝率。PCだけ)
import sys, os, json, re, time, csv, subprocess, urllib.request, urllib.parse, datetime as dt
import numpy as np, pandas as pd, lightgbm as lgb

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, '自動実行', '検証')); from lgbm_rel import rel
CFG = json.load(open(os.path.join(HERE, 'config.json'), encoding='utf-8'))
MD = os.path.join(ROOT, '馬情報', 'JRA-VAN', 'AIモデル'); META = json.load(open(os.path.join(MD, 'meta.json'), encoding='utf-8'))
MODEL = lgb.Booster(model_str=open(os.path.join(MD, 'win.txt'), encoding='utf-8').read())   # 日本語のパスは直接読めない
REC = os.path.join(ROOT, '馬情報', 'AI馬券', '記録.csv'); PRED = os.path.join(ROOT, '馬情報', 'JRA-VAN', 'AI馬券')
os.makedirs(os.path.dirname(REC), exist_ok=True); os.makedirs(PRED, exist_ok=True)
COLS = ['date', 'raceId', 'place', 'R', 'post', 'decidedAt', 'umaban', 'horse', 'p', 'tan', 'ev', 'stake', 'mode', 'status', 'rank', 'payout']
PLACE = {'01': '札幌', '02': '函館', '03': '福島', '04': '新潟', '05': '東京', '06': '中山', '07': '中京', '08': '京都', '09': '阪神', '10': '小倉'}
PERL = next((p for p in [r'C:\Program Files\Git\usr\bin\perl.exe', 'perl'] if p == 'perl' or os.path.exists(p)))
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

args = sys.argv[1:]
def opt(name, default=None):
    return args[args.index(name) + 1] if name in args else default
T = pd.read_pickle(args[0]); ENT = [json.loads(l) for l in open(args[1], encoding='utf-8')]
DAY = opt('--date', dt.date.today().isoformat()); REPLAY = opt('--replay')
ENT = [e for e in ENT if e['date'] == DAY]
if REPLAY: REC = os.path.join(PRED, 'replay_記録.csv')   # 確かめの記録は本番の記録に混ぜない
PF = os.path.join(PRED, ('replay_' if REPLAY else '') + f'予想_{DAY}.jsonl')
T = T[T['date'] == DAY]
def log(*a): print(dt.datetime.now().strftime('%H:%M:%S'), *a, flush=True)

# --- JRA公式のオッズのページ(run.sh の jpage O と同じたどり方) ---
def jpost(acc, cname):
    req = urllib.request.Request('https://www.jra.go.jp/JRADB/' + acc, data=urllib.parse.urlencode({'cname': cname}).encode(), headers={'User-Agent': UA})
    b = urllib.request.urlopen(req, timeout=30).read(); time.sleep(0.5); return b
def link(html, pat):
    for c in re.findall(r'pw[0-9a-zA-Z]+/[0-9A-F]{2}', html.decode('cp932', 'replace')):
        if re.fullmatch(pat, c): return c
def jra_odds(rid):
    D, V, R = rid[:8], rid[8:10], rid[10:12]
    top = jpost('accessO.html', 'pw15oli00/6D')
    c = link(top, rf'pw15orl00{V}\d{{8}}{D}/..') or (_ for _ in ()).throw(RuntimeError('その日・その場の一覧が無い'))
    c = link(jpost('accessO.html', c), rf'pw151ou[A-Z0-9]*{V}\d{{8}}{R}{D}Z/..') or (_ for _ in ()).throw(RuntimeError('レースのオッズのページが無い'))
    f = os.path.join(PRED, f'odds_{rid}.html'); open(f, 'wb').write(jpost('accessO.html', c))
    r = subprocess.run([PERL, os.path.join(ROOT, '自動実行', '全レース', 'jra.pl'), 'odds', f], capture_output=True)
    os.remove(f)
    if r.returncode != 0: raise RuntimeError('オッズがまだ無い')
    out = {}
    for u, x in json.loads(r.stdout).items():
        bw = re.match(r'(\d{3})(?:\(([+\-]?\d+)\))?', x.get('bw') or '')
        out[int(u)] = {'tan': float(x['tan']) if x.get('tan') else None, 'bw': int(bw.group(1)) if bw else None,
                       'bwDiff': int(bw.group(2)) if bw and bw.group(2) else None}
    return out

# --- 確かめ用: JRA-VAN の時系列オッズ(締切 N 分前) ---
def replay_odds(rids, lag):
    want = {r for r in rids}; T1 = {}
    for l in open(os.path.join(ROOT, '馬情報', 'JRA-VAN', 'o1_raw.txt'), encoding='ascii', errors='replace'):
        if not l.startswith(('O11', 'O13')): continue
        rid = l[11:19] + l[19:21] + l[25:27]
        if rid not in want: continue
        t = l[27:35]; mins = int(t[4:6]) * 60 + int(t[6:8]) + (int(t[2:4]) - int(rid[6:8])) * 1440
        if l[2] == '3': T1.setdefault(rid, {'s': []})['close'] = mins; continue
        o = {}
        for i in range(28):
            s = l[43 + 8 * i: 51 + 8 * i]; u, v = s[:2], s[2:6]
            if u.isdigit() and int(u) > 0 and v.isdigit() and int(v) > 0: o[int(u)] = v
        if o: T1.setdefault(rid, {'s': []})['s'].append((mins, o))
    out = {}
    for rid, x in T1.items():
        cand = [o for m, o in x['s'] if 'close' in x and m <= x['close'] - lag]
        if cand: out[rid] = {u: {'tan': int(v) / 10, 'bw': None, 'bwDiff': None} for u, v in cand[-1].items()}
    return out

# --- AIの勝率 ---
def predict(rid, odds):
    R = T[T['id'] == rid].copy()
    R = R[R['umaban'].map(lambda u: (odds.get(int(u)) or {}).get('tan') is not None)].copy()   # 取消・除外を除く
    if len(R) < 2: return None
    for c in ['bw', 'bwDiff']:
        v = R['umaban'].map(lambda u: odds[int(u)][c]); R[c] = np.where(v.notna(), v, R[c]).astype(float)
    R = rel(R)
    R['odds'] = R['umaban'].map(lambda u: odds[int(u)]['tan']).astype(float)
    R['q'] = 1 / R['odds']; R['q'] /= R['q'].sum(); R['logq'] = np.log(R['q']); R['pop'] = R['odds'].rank(method='min')
    for c in R.columns[R.dtypes == bool]: R[c] = R[c].astype(int)
    for c in META['cat']: R[c] = R[c].astype('category')
    s = MODEL.predict(R[META['features']], raw_score=True)
    z = META['blend'][0] * R['logq'].values + META['blend'][1] * s; e = np.exp(z - z.max())
    R['p'] = e / e.sum(); R['ev'] = R['p'] * R['odds']
    return R

def records():
    if not os.path.exists(REC): return []
    return list(csv.DictReader(open(REC, encoding='utf-8-sig')))
def append(rows):
    new = not os.path.exists(REC)
    with open(REC, 'a', encoding='utf-8-sig' if new else 'utf-8', newline='') as f:
        w = csv.DictWriter(f, COLS)
        if new: w.writeheader()
        for r in rows: w.writerow({k: r.get(k, '') for k in COLS})

def money():
    """(今日の前までの資金, 1点の金額, 今日の上限)。資金 = 始めの資金 + 本当に買った分(bought)の 払戻 − 金額。結果待ちは払戻0として数える"""
    B0 = CFG['bankrollStart'] + sum(int(r['payout'] or 0) - int(r['stake'] or 0) for r in records()
                                    if r['status'] == 'bought' and CFG['startDate'] <= r['date'] < DAY)
    f = lambda pct: max(100, int(B0 * pct / 100 / 100) * 100)   # 100円単位に切り捨て、最低100円
    return B0, f(CFG['stakePct']), f(CFG['dailyPct'])

def run_race(e, odds, mode):
    rid = e['id']; R = predict(rid, odds)
    if R is None: log(rid, '出走馬がそろわない'); return
    names = {h['umaban']: h['name'] for h in e['horses']}
    with open(PF, 'a', encoding='utf-8') as f:
        f.write(json.dumps({'id': rid, 'at': dt.datetime.now().isoformat(timespec='seconds'), 'mode': mode,
                            'horses': [{'umaban': int(u), 'p': round(float(p), 4), 'tan': float(o), 'ev': round(float(v), 3)}
                                       for u, p, o, v in zip(R['umaban'], R['p'], R['odds'], R['ev'])]}, ensure_ascii=False) + '\n')
    B = R[(R['ev'] >= CFG['evMin']) & (R['odds'] < CFG['oddsMax'])].sort_values('ev', ascending=False).head(CFG['maxPerRace'])
    B0, stake, cap = money()
    spent = sum(int(r['stake'] or 0) for r in records() if r['date'] == DAY and r['status'] in ('bought', 'dry', 'browser', 'replay'))
    rows = []
    for _, b in B.iterrows():
        st = 'stopped' if B0 < CFG['stopBelow'] else mode if spent + stake <= cap else 'over'
        spent += stake if st == mode else 0
        rows.append({'date': DAY, 'raceId': rid, 'place': PLACE.get(rid[8:10], ''), 'R': int(rid[10:12]), 'post': e.get('post', ''),
                     'decidedAt': dt.datetime.now().strftime('%H:%M:%S'), 'umaban': int(b['umaban']), 'horse': names.get(int(b['umaban']), ''),
                     'p': round(float(b['p']), 4), 'tan': float(b['odds']), 'ev': round(float(b['ev']), 3),
                     'stake': stake if st == mode else 0, 'mode': mode, 'status': st})
    buy = [r for r in rows if r['status'] in ('browser', 'live')]
    if buy and mode == 'live' and not os.path.exists(os.path.join(PRED, 'ipat_ok.txt')):
        log(rid, '即PATの確かめ(ipat.py --check → --approve)が済んでいないので買わない')
        for r in buy: r['status'] = 'notready'
        buy = []
    if buy:
        import ipat
        try:
            ipat.buy([(r['place'], r['R'], r['umaban'], r['stake']) for r in buy], confirm=(mode == 'live'), tag=rid)
            for r in buy: r['status'] = 'bought' if mode == 'live' else 'browser'
        except Exception as ex:
            log(rid, '即PATで失敗:', ex)
            for r in buy: r['status'] = 'failed'
    append(rows)
    log(rid, f'{len(R)}頭', '買い目なし' if not rows else ' '.join(f"{r['umaban']}番({r['tan']}倍・期待値{r['ev']})" for r in rows))

done = {r['raceId'] for r in records() if r['date'] == DAY}
if os.path.exists(PF):
    done |= {json.loads(l)['id'] for l in open(PF, encoding='utf-8')}
ENT = sorted([e for e in ENT if e['id'] not in done], key=lambda e: e.get('post', ''))
_b, _s, _c = money()
log(f'{DAY}: {len(ENT)} レース(済み {len(done)})・mode={CFG["mode"] if not REPLAY else "replay"}・資金 {_b:,}円・1点 {_s}円・今日の上限 {_c}円' + ('・止める線を割っているので買わない' if _b < CFG['stopBelow'] else ''))
if REPLAY:
    od = replay_odds([e['id'] for e in ENT], int(REPLAY))
    for e in ENT:
        if e['id'] in od:
            o = od[e['id']]
            for h in e['horses']:   # 馬体重は entries(JRA-VAN の SE)の値
                if h['umaban'] in o: o[h['umaban']].update(bw=h.get('bw'), bwDiff=h.get('bwDiff'))
            run_race(e, o, 'replay')
    sys.exit(0)
for e in ENT:
    post = dt.datetime.strptime(DAY + e['post'], '%Y-%m-%d%H%M'); at = post - dt.timedelta(minutes=CFG['leadMin'])
    if dt.datetime.now() > post - dt.timedelta(minutes=2): log(e['id'], '締切を過ぎた'); continue
    while dt.datetime.now() < at: time.sleep(min(30, max(1, (at - dt.datetime.now()).total_seconds())))
    for k in range(3):
        try: run_race(e, jra_odds(e['id']), CFG['mode']); break
        except Exception as ex:
            log(e['id'], 'やり直し:', ex)
            if dt.datetime.now() > post - dt.timedelta(minutes=2, seconds=40): break
            time.sleep(10)
log('終わり')
