# 「競馬予想で始めるデータ分析」の競馬AI(過去走などの特徴量 → LightGBM で1着の確率 → 期待値 = 確率 × 単勝オッズ)を、
# netkeiba のスクレイピングの代わりに 全期間/<年>/JRA詳細.jsonl(2005年〜)と レース.jsonl(確定単勝オッズ)で作るための特徴量づくり
# 使い方: python lgbm_features.py 馬情報/過去レースデータ/全期間 [馬情報/JRA-VAN/馬DB] <出力.pkl>
#  - 1行 = 1頭の1走。特徴量はすべて「そのレースの前に分かる値」だけ(過去走・騎手・調教師・父の成績は前日までの累計)
#  - 障害は除く。取消・除外は除き、中止は着外として残す
import sys, os, glob, json, re
import numpy as np, pandas as pd

DIR = sys.argv[1]; DB = sys.argv[2] if len(sys.argv) > 3 else None; OUT = sys.argv[-1]
PLACE = {'01': '札幌', '02': '函館', '03': '福島', '04': '新潟', '05': '東京', '06': '中山', '07': '中京', '08': '京都', '09': '阪神', '10': '小倉'}

def tsec(t):
    if not t: return np.nan
    m = re.match(r'^(\d+):(\d+(?:\.\d+)?)$', t)
    if m: return int(m.group(1)) * 60 + float(m.group(2))
    try: return float(t)
    except ValueError: return np.nan

# 1. 読み込み
odds, lab, rows = {}, {}, []
for yd in sorted(glob.glob(os.path.join(DIR, '*'))):
    if not re.search(r'\d{4}$', yd): continue
    p = os.path.join(yd, 'レース.jsonl')
    if os.path.exists(p):
        for l in open(p, encoding='utf-8'):
            try: r = json.loads(l)
            except ValueError: continue
            lab[r['id']] = (r.get('grade') or '', r.get('cond') or '')
            for h in r.get('horses') or []:
                if h.get('umaban') and h.get('odds'): odds[(r['id'], h['umaban'])] = h['odds']
    p = os.path.join(yd, 'JRA詳細.jsonl')
    if not os.path.exists(p): continue
    for l in open(p, encoding='utf-8'):
        try: r = json.loads(l)
        except ValueError: continue
        R = r.get('race') or {}; surf = R.get('surface') or ''; course = R.get('course') or ''
        if '障' in surf or '障' in course or '→' in course: continue
        surf = 'ダ' if surf.startswith('ダ') else '芝'
        hs = [h for h in r.get('horses') or [] if str(h.get('rank')) not in ('取消', '除外')]
        if len(hs) < 2: continue
        laps = r.get('laps') or []
        pace = (sum(laps[:3]) - r['last3f']) if len(laps) >= 6 and r.get('last3f') else np.nan
        g, cond = lab.get(r['id'], ('', ''))
        for h in hs:
            rk = h.get('rank'); rk = int(rk) if str(rk).isdigit() else 99
            ps = [int(x) for x in re.findall(r'\d+', h.get('pass') or '')]
            sa = h.get('sexAge') or ''
            rows.append(dict(id=r['id'], date=r['date'], place=PLACE.get(r['id'][8:10], ''), rno=int(r['id'][10:12]), surf=surf,
                dist=R.get('dist') or 0, going=R.get('going') or '', weather=R.get('weather') or '', cls=R.get('cls') or '',
                inner='外' in course, kinType=R.get('kinType') or '', grade=g, fillies='牝' in cond, pace=pace, heads=len(hs),
                horseId=h.get('horseId'), umaban=h.get('umaban'), waku=h.get('waku'), sex=sa[:1], age=int(sa[1:]) if sa[1:].isdigit() else np.nan,
                kin=h.get('kin'), bw=h.get('bw'), bwDiff=h.get('bwDiff'), blinker=bool(h.get('blinker')),
                jockey=re.sub(r'^[▲△☆◇★]', '', h.get('jockey') or ''), appr=bool(re.match(r'^[▲△☆◇★]', h.get('jockey') or '')),
                trainer=h.get('trainer') or '', rank=rk, time=tsec(h.get('time')), f3=tsec(h.get('f3')),
                pos1=ps[0] if ps else np.nan, pos4=ps[-1] if ps else np.nan))
    print(yd, len(rows), file=sys.stderr)

D = pd.DataFrame(rows); del rows
D['odds'] = [odds.get((i, u), np.nan) for i, u in zip(D['id'], D['umaban'])]
D['date'] = pd.to_datetime(D['date'])
D = D[D['horseId'].notna()].sort_values(['date', 'id', 'umaban']).reset_index(drop=True)
D['win'] = (D['rank'] == 1).astype(int); D['top3'] = (D['rank'] <= 3).astype(int)
for c in ['dist', 'kin', 'bw', 'bwDiff', 'waku', 'umaban']: D[c] = pd.to_numeric(D[c], errors='coerce')
print('rows', len(D), file=sys.stderr)

# 2. レースの中での値(その走の出来。次のレースの過去走として使う)
g = D.groupby('id')
D['tdiff'] = D['time'] - g['time'].transform('min')                         # 勝ち馬とのタイム差
D['f3rank'] = g['f3'].rank(method='min') / D['heads']                        # 上がり3Fの順位(割合)
D['pos4r'] = D['pos4'] / D['heads']; D['pos1r'] = D['pos1'] / D['heads']    # 4角・最初のコーナーの位置(割合)
D['rankr'] = np.where(D['rank'] < 99, D['rank'] / D['heads'], 1.0)
# スピード指数: コース(場・芝ダ・距離)の基準タイム(2005〜2015年の勝ち時計の中央値)との差を1kmあたりに。斤量1kg=0.1秒/km 程度で補正
w = D[(D['rank'] == 1) & (D['date'] < '2016-01-01')]
std = w.groupby(['place', 'surf', 'dist'])['time'].median().rename('stdT')
D = D.join(std, on=['place', 'surf', 'dist'])
D['spd'] = (D['stdT'] - D['time']) / (D['dist'] / 1000) + (D['kin'] - 55) * 0.1
# その日・その場・芝ダの馬場差(勝ち馬の「指数 − クラスの平均」の平均)を引く
w = D[D['rank'] == 1].copy(); w['ex'] = w['spd'] - w.groupby(['cls', 'surf'])['spd'].transform('mean')
D = D.join(w.groupby(['date', 'place', 'surf'])['ex'].mean().rename('variant'), on=['date', 'place', 'surf'])
D['spd'] = D['spd'] - D['variant'].fillna(0)

# 3. 馬ごとの過去走
D = D.sort_values(['horseId', 'date']).reset_index(drop=True)
gh = D.groupby('horseId', sort=False)
D['nrun'] = gh.cumcount()
D['prevDate'] = gh['date'].shift(1)
D['intv'] = (D['date'] - D['prevDate']).dt.days
for k in range(1, 6):
    for c in ['rankr', 'tdiff', 'f3rank', 'pos4r', 'pos1r', 'spd', 'dist', 'surf', 'pace', 'heads']:
        D[f'{c}_{k}'] = gh[c].shift(k)
    D[f'rank_{k}'] = gh['rank'].shift(k)
D['dchg'] = D['dist'] - D['dist_1']; D['surfChg'] = (D['surf_1'].notna() & (D['surf'] != D['surf_1'])).astype(float)
for k in range(1, 6): D[f'surf_{k}'] = (D[f'surf_{k}'] == D['surf']).astype(float).where(D[f'surf_{k}'].notna())
D['bwPrev'] = gh['bw'].shift(1)
sp = pd.concat([D[f'spd_{k}'] for k in range(1, 6)], axis=1)
D['spdMax5'] = sp.max(axis=1); D['spdMean5'] = sp.mean(axis=1)
D['rankMean5'] = pd.concat([D[f'rankr_{k}'] for k in range(1, 6)], axis=1).mean(axis=1)
D['cumWin'] = gh['win'].cumsum() - D['win']; D['cumTop3'] = gh['top3'].cumsum() - D['top3']
D['winRate'] = D['cumWin'] / D['nrun'].replace(0, np.nan); D['top3Rate'] = D['cumTop3'] / D['nrun'].replace(0, np.nan)
# 1年前の同じ時期(320〜410日前)の最高着順(動画#19「馬の得意な季節」)
prev = D[['horseId', 'date', 'rank']].rename(columns={'date': 'd0', 'rank': 'r0'})
m = D[['horseId', 'date']].reset_index().merge(prev, on='horseId')
m = m[((m['date'] - m['d0']).dt.days >= 320) & ((m['date'] - m['d0']).dt.days <= 410)]
D['rankLastYear'] = m.groupby('index')['r0'].min().reindex(D.index)
# 同じ芝ダ・近い距離(±200m)での過去の勝ち・3着以内(Target Encoding の代わりに、そのまま数える)
m = D[['horseId', 'date', 'surf', 'dist']].reset_index().merge(D[['horseId', 'date', 'surf', 'dist', 'top3', 'win']].rename(columns={'date': 'd0', 'surf': 's0', 'dist': 'x0'}), on='horseId')
m = m[(m['d0'] < m['date']) & (m['s0'] == m['surf']) & ((m['x0'] - m['dist']).abs() <= 200)]
a = m.groupby('index').agg(sameN=('top3', 'size'), sameTop3=('top3', 'sum'), sameWin=('win', 'sum'))
D = D.join(a); D[['sameN', 'sameTop3', 'sameWin']] = D[['sameN', 'sameTop3', 'sameWin']].fillna(0)
del m, a, prev

# 4. 騎手・調教師・父・母父の前日までの成績(ベイズ的に縮める: (勝ち + 全体の勝率×k) ÷ (騎乗 + k))
def prior_rate(keys, name, k=50):
    global D
    a = D.groupby(keys + ['date']).agg(n=('win', 'size'), w=('win', 'sum'), t=('top3', 'sum')).reset_index().sort_values('date')
    gg = a.groupby(keys, sort=False)
    a['N'] = gg['n'].cumsum() - a['n']; a['W'] = gg['w'].cumsum() - a['w']; a['T'] = gg['t'].cumsum() - a['t']
    a[name + 'Win'] = (a['W'] + 0.075 * k) / (a['N'] + k); a[name + 'Top3'] = (a['T'] + 0.22 * k) / (a['N'] + k); a[name + 'N'] = a['N']
    D = D.merge(a[keys + ['date', name + 'Win', name + 'Top3', name + 'N']], on=keys + ['date'], how='left')

if DB:
    ped = []
    for p in glob.glob(os.path.join(DB, '競走馬', '*.tsv')):
        ped.append(pd.read_csv(p, sep='\t', usecols=['id', '父', '母の父', '生年月日'], dtype=str))
    ped = pd.concat(ped).drop_duplicates('id').rename(columns={'id': 'horseId', '父': 'sire', '母の父': 'bms', '生年月日': 'birth'})
    D = D.merge(ped, on='horseId', how='left')
    b = pd.to_datetime(D['birth'], errors='coerce'); D['birthMonth'] = b.dt.month
    D['ageDays'] = (D['date'] - b).dt.days
    print('pedigree', D['sire'].notna().mean(), file=sys.stderr)
else:
    D['sire'] = np.nan; D['bms'] = np.nan
prior_rate(['jockey'], 'jk'); prior_rate(['trainer'], 'tr'); prior_rate(['jockey', 'place', 'surf'], 'jkc')
D['sire'] = D['sire'].fillna(''); D['bms'] = D['bms'].fillna('')
D['going2'] = D['going'].isin(['重', '不良']).astype(int)
prior_rate(['sire', 'surf'], 'sireS'); prior_rate(['sire', 'surf', 'going2'], 'sireG'); prior_rate(['bms', 'surf'], 'bmsS')
D['distBand'] = (D['dist'] // 400).astype(int); prior_rate(['sire', 'surf', 'distBand'], 'sireD')
prior_rate(['place', 'surf', 'dist', 'waku'], 'waku', k=200)   # 枠の有利不利(コースごと)

# 5. 季節・レースの中での相対値
D['month'] = D['date'].dt.month
D['mcos'] = np.cos(2 * np.pi * (D['date'].dt.dayofyear) / 365.25)    # 動画#19: 日付を季節の値に
D['msin'] = np.sin(2 * np.pi * (D['date'].dt.dayofyear) / 365.25)
for c in ['spdMax5', 'spdMean5', 'spd_1', 'jkWin', 'trWin', 'kin', 'winRate', 'rankMean5', 'sireSWin']:
    gr = D.groupby('id')[c]
    D[c + '_z'] = (D[c] - gr.transform('mean')) / gr.transform('std').replace(0, np.nan)
    D[c + '_rk'] = gr.rank(ascending=c in ('kin', 'rankMean5'), method='min') / D['heads']
D = D.sort_values(['date', 'id', 'umaban']).reset_index(drop=True)
D.to_pickle(OUT)
print('saved', OUT, D.shape, file=sys.stderr)
