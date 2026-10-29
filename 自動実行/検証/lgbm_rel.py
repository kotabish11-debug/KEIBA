# レースの中での相対値(z と順位)。学習(lgbm_features.py・lgbm_chokyo.py)と当日の予想(自動実行/AI馬券/live.py)で同じ計算を使う
# 当日は取消・除外で頭数が変わるので、オッズを取った時点で出走する馬だけで計算し直す
import numpy as np

REL = ['spdMax5', 'spdMean5', 'spd_1', 'jkWin', 'trWin', 'kin', 'winRate', 'rankMean5', 'sireSWin']
ASC = ('kin', 'rankMean5')   # 小さいほど上(順位1)

def rel(D, chokyo=True):
    D['heads'] = D.groupby('id')['id'].transform('size')
    for c in REL:
        gr = D.groupby('id')[c]
        D[c + '_z'] = (D[c] - gr.transform('mean')) / gr.transform('std').replace(0, np.nan)
        D[c + '_rk'] = gr.rank(ascending=c in ASC, method='min') / D['heads']
    if chokyo and 'ck4f' in D:
        for c in ['ck4f', 'ck1f']: D[c + '_rk'] = D.groupby('id')[c].rank(method='min') / D['heads']
    return D
