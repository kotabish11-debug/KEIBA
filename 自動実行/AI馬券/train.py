# AI馬券の本番モデルを作る(検証26の「C+オッズ」: オッズも特徴量に入れた LightGBM を、もう一度オッズと条件付きロジットで混ぜる)
# 使い方: python train.py <features.pkl(lgbm_features.py → lgbm_chokyo.py)> [学習の終わり 2023-12-31]
#   学習 2006〜学習の終わり / 検証(早く止める・混ぜ方を決める)= それ以降の全部
#   出力: 馬情報/JRA-VAN/AIモデル/win.txt(LightGBM)と meta.json(特徴量・混ぜ方・検証の成績)。JRA-VAN の調教を使うので PC だけに置く
#   馬場・天候は外す(当日の朝に分からないことがあり、効きも 0.03% 以下だった)
import sys, os, json
import numpy as np, pandas as pd, lightgbm as lgb
from scipy.optimize import minimize

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUTD = os.path.join(ROOT, '馬情報', 'JRA-VAN', 'AIモデル'); os.makedirs(OUTD, exist_ok=True)
D = pd.read_pickle(sys.argv[1]); TR = pd.Timestamp(sys.argv[2] if len(sys.argv) > 2 else '2023-12-31')
if 'upcoming' in D: D = D[D['upcoming'] != 1]
D = D[D['date'] >= '2006-01-01']
ok = D.groupby('id')['odds'].transform(lambda s: s.notna().all() and (s >= 1).all())
D = D[ok & (D.groupby('id')['win'].transform('sum') == 1)].reset_index(drop=True)
CAT = ['place', 'surf', 'cls', 'sex', 'kinType']
for c in CAT: D[c] = D[c].astype('category')
for c in D.columns[D.dtypes == bool]: D[c] = D[c].astype(int)
D['q'] = 1 / D['odds']; D['q'] = D['q'] / D.groupby('id')['q'].transform('sum'); D['logq'] = np.log(D['q'])
D['pop'] = D.groupby('id')['odds'].rank(method='min')

DROP = {'id', 'date', 'horseId', 'jockey', 'trainer', 'rank', 'time', 'f3', 'pos1', 'pos4', 'win', 'top3', 'tdiff', 'f3rank', 'pos4r', 'pos1r',
        'rankr', 'spd', 'stdT', 'variant', 'odds', 'q', 'logq', 'pop', 'prevDate', 'sire', 'bms', 'birth', 'grade', 'pace', 'going2', 'distBand',
        'going', 'weather', 'upcoming'}
F = [c for c in D.columns if c not in DROP and D[c].dtype != object] + ['logq', 'pop']
tr = D['date'] <= TR; va = D['date'] > TR
P = dict(objective='binary', learning_rate=0.03, num_leaves=63, min_data_in_leaf=200, feature_fraction=0.7, bagging_fraction=0.8, bagging_freq=1,
         lambda_l2=10, verbose=-1, seed=1)
m = lgb.train(P, lgb.Dataset(D.loc[tr, F], D.loc[tr, 'win']), 3000, valid_sets=[lgb.Dataset(D.loc[va, F], D.loc[va, 'win'])],
              callbacks=[lgb.early_stopping(100, verbose=False)])
s = m.predict(D.loc[va, F], raw_score=True)
ids = pd.factorize(D.loc[va, 'id'].values)[0]; y = D.loc[va, 'win'].values; lq = D.loc[va, 'logq'].values

def nll(X, b):
    z = X @ b; z = z - pd.Series(z).groupby(ids).transform('max').values; e = np.exp(z)
    return -(z[y == 1].sum() - np.log(np.bincount(ids, e)).sum())
g = minimize(lambda b: nll(lq[:, None], b), [1.0], method='BFGS').x
X = np.c_[lq, s]; b = minimize(lambda b: nll(X, b), [1.0, 1.0], method='BFGS').x
nr = len(set(ids)); ll0 = -nll(lq[:, None], g) / nr; ll1 = -nll(X, b) / nr
print(f'木 {m.best_iteration} 本 / 混ぜ方 オッズ {b[0]:.3f}・LGBM {b[1]:.3f} / 検証 {nr} レース: 当たり方 {ll1:.4f}(オッズだけ {ll0:.4f}、差 ×1000 {(ll1 - ll0) * 1000:+.1f})')
open(os.path.join(OUTD, 'win.txt'), 'w', encoding='utf-8').write(m.model_to_string(num_iteration=m.best_iteration))   # LightGBM は日本語のパスに直接書けない
json.dump({'features': F, 'cat': CAT, 'blend': list(map(float, b)), 'gamma': float(g[0]), 'trainedUntil': str(TR.date()),
           'validFrom': str(D.loc[va, 'date'].min().date()), 'validTo': str(D.loc[va, 'date'].max().date()), 'validRaces': nr,
           'validLL': ll1, 'validLLodds': ll0, 'trees': m.best_iteration},
          open(os.path.join(OUTD, 'meta.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('保存:', OUTD)
