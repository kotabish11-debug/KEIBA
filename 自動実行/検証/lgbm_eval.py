# lgbm_features.py の表で、LightGBM の1着確率が「オッズだけ」より当たるか・期待値で買うと回収率はどうなるかを確かめる
# 使い方: python lgbm_eval.py <features.pkl> [学習の終わり 2018-12-31] [検証の終わり 2021-12-31] [重要度の出力.tsv]
#  - 学習 2006〜学習の終わり / 検証(早く止める・オッズとの混ぜ方を決める)/ テスト(それ以降。一度も見ていない期間)
#  - A: オッズを使わない LightGBM(馬の力だけ)  B: A とオッズを条件付きロジットで混ぜる(Benter の方法)
#    C: オッズも特徴量に入れた LightGBM(動画の作り方に近い)
#  - 当たり方 = 勝ち馬の確率の対数の平均(高いほど良い)。オッズだけ = 1/オッズ を γ 乗して足して1に直したもの(γ は検証期間で決める)
#  - 回収率は確定オッズで計算する(実際に買う時点のオッズとは違うので、出る数字は良く見えがち)
import sys
import numpy as np, pandas as pd, lightgbm as lgb
from scipy.optimize import minimize

D = pd.read_pickle(sys.argv[1])
TR = pd.Timestamp(sys.argv[2] if len(sys.argv) > 2 else '2018-12-31'); VA = pd.Timestamp(sys.argv[3] if len(sys.argv) > 3 else '2021-12-31')
IMP = sys.argv[4] if len(sys.argv) > 4 else None
D = D[(D['date'] >= '2006-01-01')]
# オッズが全頭そろったレースだけ
ok = D.groupby('id')['odds'].transform(lambda s: s.notna().all() and (s >= 1).all())
D = D[ok & (D.groupby('id')['win'].transform('sum') == 1)].reset_index(drop=True)
for c in ['place', 'surf', 'going', 'weather', 'cls', 'sex', 'kinType']: D[c] = D[c].astype('category')
for c in D.columns[D.dtypes == bool]: D[c] = D[c].astype(int)
D['q'] = 1 / D['odds']; D['q'] = D['q'] / D.groupby('id')['q'].transform('sum')
D['logq'] = np.log(D['q']); D['pop'] = D.groupby('id')['odds'].rank(method='min')

DROP = {'id', 'date', 'horseId', 'jockey', 'trainer', 'rank', 'time', 'f3', 'pos1', 'pos4', 'win', 'top3', 'tdiff', 'f3rank', 'pos4r', 'pos1r',
        'rankr', 'spd', 'stdT', 'variant', 'odds', 'q', 'logq', 'pop', 'prevDate', 'sire', 'bms', 'birth', 'grade', 'pace', 'going2', 'distBand', 'bw_x'}
FA = [c for c in D.columns if c not in DROP and D[c].dtype != object]
FC = FA + ['logq', 'pop']
# M: オッズとレースの条件だけ(馬の情報なし)。C の上乗せが「オッズのクセの直し」だけかを切り分ける
FM = ['logq', 'pop', 'heads', 'surf', 'dist', 'cls', 'place', 'going', 'month', 'umaban', 'fillies', 'kinType', 'rno']
print('特徴量', len(FA), file=sys.stderr)
tr, va, te = D['date'] <= TR, (D['date'] > TR) & (D['date'] <= VA), D['date'] > VA
P = dict(objective='binary', learning_rate=0.03, num_leaves=63, min_data_in_leaf=200, feature_fraction=0.7, bagging_fraction=0.8, bagging_freq=1,
         lambda_l2=10, verbose=-1, seed=1)

def fit(F):
    dt = lgb.Dataset(D.loc[tr, F], D.loc[tr, 'win']); dv = lgb.Dataset(D.loc[va, F], D.loc[va, 'win'])
    m = lgb.train(P, dt, 3000, valid_sets=[dv], callbacks=[lgb.early_stopping(100, verbose=False)])
    s = m.predict(D[F], raw_score=True)
    return m, s

def norm(s, ids=None):   # レースの中で足して1に(条件付きロジット)
    ids = D['id'].values if ids is None else ids; s = pd.Series(np.asarray(s, float))
    e = np.exp(s - s.groupby(ids).transform('max')); return (e / e.groupby(ids).transform('sum')).values

def clogit(X, mask):   # P ∝ exp(X·β) を mask の期間で当てはめる
    Xm = X[mask.values]; ids = D.loc[mask, 'id'].values; y = D.loc[mask, 'win'].values
    codes = pd.factorize(ids)[0]
    def nll(b):
        s = Xm @ b; s = s - pd.Series(s).groupby(codes).transform('max').values; e = np.exp(s)
        z = np.bincount(codes, e); return -(s[y == 1].sum() - np.log(z).sum())
    return minimize(nll, np.ones(X.shape[1]), method='BFGS').x

mA, sA = fit(FA); mC, sC = fit(FC); mM, sM = fit(FM)
g = clogit(D[['logq']].values, va)[0]
P0 = norm(g * D['logq'].values)
pA = norm(sA); pC = norm(sC)
bB = clogit(np.c_[D['logq'].values, sA], va); PB = norm(np.c_[D['logq'].values, sA] @ bB)
bC = clogit(np.c_[D['logq'].values, sC], va); PC2 = norm(np.c_[D['logq'].values, sC] @ bC)
bM = clogit(np.c_[D['logq'].values, sM], va); PM2 = norm(np.c_[D['logq'].values, sM] @ bM)
bMC = clogit(np.c_[D['logq'].values, sM, sC], va); PMC = norm(np.c_[D['logq'].values, sM, sC] @ bMC)
print(f'オッズの γ = {g:.3f} / B の係数(オッズ, A)= {bB.round(3)} / C+オッズ = {bC.round(3)} / M+オッズ = {bM.round(3)} / オッズ+M+C = {bMC.round(3)}')
D['yr'] = D['date'].dt.year
models = {'オッズだけ': P0, 'A 馬の力だけ': pA, 'B オッズ+A': PB, 'C オッズ入りLGBM': pC, 'C+オッズ': PC2,
          'M オッズのクセだけ+オッズ': PM2, 'オッズ+M+C': PMC}

def ll(p, mask):
    w = (D['win'] == 1) & mask; return np.log(np.clip(p[w.values], 1e-9, 1)).mean()
print('\n## 当たり方(勝ち馬の確率の対数の平均。オッズだけとの差 ×1000、プラスならオッズより当たる)')
periods = {'検証': va, 'テスト前半': te & (D['yr'] <= 2023), 'テスト後半': te & (D['yr'] >= 2024), 'テスト全体': te}
print('| モデル | ' + ' | '.join(periods) + ' | テストの◎勝率 |'); print('|---' * (len(periods) + 2) + '|')
for k, p in models.items():
    top = pd.Series(p, index=D.index)[te].groupby(D.loc[te, 'id']).idxmax()
    cells = [f'{ll(p, m):.4f} ({(ll(p, m) - ll(P0, m)) * 1000:+.1f})' for m in periods.values()]
    print(f'| {k} | ' + ' | '.join(cells) + f' | {D.loc[top, "win"].mean() * 100:.1f}% |')

print('\n## 期待値(確率×確定オッズ)で単勝を買ったときの回収率(テスト期間。年ごと)')
yrs = sorted(D.loc[te, 'yr'].unique())
print('| モデル | 期待値 | オッズ | 点数 | 的中 | 回収率 | ' + ' | '.join(map(str, yrs)) + ' |'); print('|---' * (6 + len(yrs)) + '|')
for k in ['C オッズ入りLGBM', 'C+オッズ', 'M オッズのクセだけ+オッズ', 'オッズ+M+C']:
    ev = models[k] * D['odds'].values
    for th in [1.0, 1.1, 1.2, 1.5]:
        for cap in [10, 30, 1000]:
            b = te & (ev >= th) & (D['odds'] < cap)
            if b.sum() < 50: continue
            ret = (D['win'] * D['odds'] * 100).where(b, 0)
            yr = [f'{ret[b & (D["yr"] == y)].sum() / max(1, (b & (D["yr"] == y)).sum()):.0f}%' for y in yrs]
            print(f'| {k} | ≥{th} | <{cap} | {b.sum()} | {D.loc[b, "win"].mean() * 100:.1f}% | {ret[b].sum() / b.sum():.1f}% | ' + ' | '.join(yr) + ' |')

# 期待値ごとの実際÷予想(B)
print('\n## B の予想勝率ごとの 実際÷予想(テスト)')
pb = pd.Series(PB, index=D.index)[te]; bins = pd.cut(pb, [0, .02, .05, .1, .2, .3, .5, 1])
t = pd.DataFrame({'p': pb, 'w': D.loc[te, 'win'], 'b': bins}).groupby('b', observed=True).agg(n=('w', 'size'), w=('w', 'sum'), p=('p', 'sum'))
print((t.assign(ratio=(t['w'] / t['p']).round(3))).to_string())

if IMP:
    imp = pd.DataFrame({'特徴量': FC, 'gain': mC.feature_importance('gain')}).sort_values('gain', ascending=False)
    imp['gain'] = (imp['gain'] / imp['gain'].sum() * 100).round(2); imp.to_csv(IMP, sep='\t', index=False)
    print('\n## C の特徴量の重要度(上位25, %)'); print(imp.head(25).to_string(index=False))

# 締切前のオッズで判断して買う(JRA-VAN の時系列オッズ o1_raw.txt。約1年分)。払戻は確定オッズ
O1 = sys.argv[5] if len(sys.argv) > 5 else None
if O1:
    T = {}
    for l in open(O1, encoding='ascii', errors='replace'):
        if not l.startswith(('O11', 'O13')): continue
        rid = l[11:19] + l[19:21] + l[25:27]; t = l[27:35]
        if l[2] == '3': T.setdefault(rid, {'s': []})['close'] = t; continue
        o = {}
        for i in range(28):
            s = l[43 + 8 * i: 51 + 8 * i]; u, v = s[:2], s[2:6]
            if u.isdigit() and int(u) > 0 and v.isdigit() and int(v) > 0: o[int(u)] = int(v) / 10
        if o: T.setdefault(rid, {'s': []})['s'].append((t, o))
    def mins(t): return int(t[:2]) * 44640 + int(t[2:4]) * 1440 + int(t[4:6]) * 60 + int(t[6:8])
    for lag in [1, 6]:
        pre = {}
        for rid, x in T.items():
            if 'close' not in x: continue
            c = mins(x['close']); cand = [o for t, o in x['s'] if mins(t) <= c - lag]
            if cand: pre[rid] = cand[-1]
        E = D[te & D['id'].isin(pre.keys())].copy()
        E['odds0'] = [pre[i].get(int(u), np.nan) for i, u in zip(E['id'], E['umaban'])]
        E = E[E.groupby('id')['odds0'].transform(lambda s: s.notna().all())]
        E['q'] = 1 / E['odds0']; E['q'] = E['q'] / E.groupby('id')['q'].transform('sum'); E['logq'] = np.log(E['q'])
        E['pop'] = E.groupby('id')['odds0'].rank(method='min')
        ids = E['id'].values; sCe = mC.predict(E[FC], raw_score=True); sMe = mM.predict(E[FM], raw_score=True)
        pe = {'オッズだけ': norm(g * E['logq'].values, ids), 'C+オッズ': norm(np.c_[E['logq'].values, sCe] @ bC, ids),
              'オッズ+M+C': norm(np.c_[E['logq'].values, sMe, sCe] @ bMC, ids)}
        w = E['win'].values == 1; half = E['date'] >= '2026-04-01'
        print(f'\n## 締切{lag}分前のオッズで判断(テスト期間のうち時系列オッズのある {E["id"].nunique()} レース。前半 = 2026/3まで)')
        for k, p in pe.items():
            a = np.log(p[w]).mean(); a0 = np.log(pe['オッズだけ'][w]).mean()
            print(f'- {k}: 当たり方 {a:.4f}(オッズだけとの差 ×1000 {(a - a0) * 1000:+.1f})')
        print('| モデル | 期待値 | オッズ | 点数 | 的中 | 回収率 | 前半 | 後半 |'); print('|---' * 8 + '|')
        for k in ['C+オッズ', 'オッズ+M+C']:
            ev = pe[k] * E['odds0'].values
            for th in [1.0, 1.1, 1.2]:
                for cap in [10, 30, 1000]:
                    b = (ev >= th) & (E['odds0'].values < cap)
                    if b.sum() < 20: continue
                    ret = np.where(b & w, E['odds'].values * 100, 0)
                    r1 = ret[b & ~half.values].sum() / max(1, (b & ~half.values).sum()); r2 = ret[b & half.values].sum() / max(1, (b & half.values).sum())
                    print(f'| {k} | ≥{th} | <{cap} | {b.sum()} | {w[b].mean() * 100:.1f}% | {ret[b].sum() / b.sum():.1f}% | {r1:.0f}% | {r2:.0f}% |')
