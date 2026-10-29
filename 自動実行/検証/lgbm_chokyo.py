# lgbm_features.py の表に、JRA-VAN の全調教(坂路 2005〜・ウッド 2021/7〜)の特徴量を足す(jv_chokyo_eval.pl と同じ切り方)
# 使い方: python lgbm_chokyo.py <features.pkl> 馬情報/JRA-VAN <出力.pkl> [--upcoming]
#  - --upcoming: これからのレース(lgbm_features.py の --extra)の行だけを出力する(当日の予想用。自動実行/AI馬券/morning.sh)
#  - n14 / sl14 / wd14 = レース前14日の調教本数(全部・坂路・ウッド)、dn14 = n14 − その馬の前走たちの n14 の平均
#  - 最終の坂路(レース前7日以内で最後の1本): ck4f(4F)・ck1f(終い1F)・ckAcc(終い1F < その前の1F)・ck4fD(4F − その馬のふだん)
import sys, glob
import numpy as np, pandas as pd

D = pd.read_pickle(sys.argv[1]); J = sys.argv[2]; OUT = sys.argv[3]; ONLY = '--upcoming' in sys.argv
need = set(D['horseId'].astype(str))

def read(paths, wood):   # 全データ/SLOP・WOOD/<年>.txt(update.sh が毎回足す)。同じ1本が2度入っていることがあるので、場所・日・時刻・馬で1本にする
    hid, day, tm, t4, l1, l2 = [], [], [], [], [], []
    a, b, c = (79, 97, 100) if wood else (34, 52, 55)
    for path in paths:
        with open(path, 'r', encoding='ascii', errors='replace') as f:
            for l in f:
                h = l[24:34]
                if h not in need: continue
                hid.append(h); day.append(l[12:20]); tm.append(l[11] + l[20:24]); t4.append(l[a:a + 4]); l2.append(l[b:b + 3]); l1.append(l[c:c + 3])
    w = pd.DataFrame({'horseId': hid, 'tm': tm, 'day': pd.to_datetime(day, format='%Y%m%d', errors='coerce'),
                      't4': pd.to_numeric(t4, errors='coerce') / 10, 'l1': pd.to_numeric(l1, errors='coerce') / 10, 'l2': pd.to_numeric(l2, errors='coerce') / 10})
    w = w.drop_duplicates(['horseId', 'day', 'tm'], keep='last'); w['wood'] = wood
    for c in ['t4', 'l1', 'l2']: w.loc[w[c] <= 0, c] = np.nan
    print('坂路' if not wood else 'ウッド', len(w), file=sys.stderr)
    return w.dropna(subset=['day'])

W = pd.concat([read(sorted(glob.glob(J + '/全データ/SLOP/*.txt')), 0), read(sorted(glob.glob(J + '/全データ/WOOD/*.txt')), 1)])
hcode = {h: i for i, h in enumerate(sorted(need))}
W['k'] = W['horseId'].map(hcode).astype(np.int64) * 100000 + (W['day'] - pd.Timestamp('1980-01-01')).dt.days
W = W.sort_values('k')
rk = D['horseId'].astype(str).map(hcode).astype(np.int64) * 100000 + (D['date'] - pd.Timestamp('1980-01-01')).dt.days

def cnt(keys, lo):   # [d-lo, d) の本数
    return np.searchsorted(keys, rk.values, 'left') - np.searchsorted(keys, rk.values - lo, 'left')
ka = W['k'].values; ks = W.loc[W['wood'] == 0, 'k'].values; kw = W.loc[W['wood'] == 1, 'k'].values
D['n14'] = cnt(ka, 14); D['sl14'] = cnt(ks, 14); D['wd14'] = cnt(kw, 14); D['n28'] = cnt(ka, 28)
# 7日以内でいちばん速い坂路(jv_chokyo_eval.pl と同じ。最後の1本だと金・土の軽い調整を拾う)
S = W[W['wood'] == 0].dropna(subset=['t4']); sk = S['k'].values; st4 = S['t4'].values
lo = np.searchsorted(sk, rk.values - 7, 'left'); hi = np.searchsorted(sk, rk.values, 'left')
j = np.array([a + int(np.argmin(st4[a:b])) if b > a else 0 for a, b in zip(lo, hi)]); okk = hi > lo
D['ck4f'] = np.where(okk, S['t4'].values[j], np.nan); D['ck1f'] = np.where(okk, S['l1'].values[j], np.nan)
D['ckAcc'] = np.where(okk & ~np.isnan(S['l2'].values[j]), (S['l1'].values[j] < S['l2'].values[j]).astype(float), np.nan)
# 最終のウッド(7日以内)
S = W[W['wood'] == 1].dropna(subset=['t4']); sk = S['k'].values
i = np.searchsorted(sk, rk.values, 'left') - 1; j = np.clip(i, 0, None)
okk = (i >= 0) & (rk.values - sk[j] <= 7) & (rk.values - sk[j] >= 1)
D['wc1f'] = np.where(okk, S['l1'].values[j], np.nan)
# ふだんとの差(その馬の前走たちの平均)
D = D.sort_values(['horseId', 'date']); g = D.groupby('horseId', sort=False)
for c in ['n14', 'ck4f']:
    m = g[c].transform(lambda s: s.shift(1).expanding().mean())
    D[c.replace('14', '') + 'D' if c == 'n14' else c + 'D'] = D[c] - m
for c in ['ck4f', 'ck1f']:
    gr = D.groupby('id')[c]; D[c + '_rk'] = gr.rank(method='min') / D['heads']
D = D.sort_values(['date', 'id', 'umaban']).reset_index(drop=True)
print(D[['n14', 'nD', 'ck4f', 'ck1f', 'ckAcc', 'ck4fD', 'wc1f']].describe().round(2).to_string(), file=sys.stderr)
if ONLY: D = D[D['upcoming'] == 1].reset_index(drop=True)
D.to_pickle(OUT)
