# 即PAT(www.ipat.jra.go.jp)で単勝を買う。Playwright でブラウザを動かす(「競馬予想で始めるデータ分析」#32 の流れ)
#   ログイン(INET-ID → 加入者番号・暗証番号・P-ARS番号)→ 通常投票 → 場 → レース → 式別「単勝」→ 馬番 → 金額(100円単位)→ セット(繰り返し)
#   → 入力終了(購入予定リスト)→ 合計金額 → 購入する
# 使い方: live.py が buy() を呼ぶ。単体で確かめるとき: python ipat.py --check <場 東京> <R 11> <馬番 1> [--show]
#   --check は購入予定リストに入れて合計金額を入れたところで止め、画面を保存して閉じる。買わない
#   --approve: --check の画面(場・レース・馬番・金額)を確かめたあとに実行する。ipat_ok.txt ができ、live.py が本当に買うようになる
# ログイン情報は %USERPROFILE%\.ipat.env に自分で書く(コードやリポジトリには置かない): INET_ID / KANYUSHA / PIN / PARS
# 各手順の画面: 馬情報/JRA-VAN/AI馬券/ipat/<日時>_<tag>_<番号>_<手順>.png(PCだけ)。ID・番号を入れた画面は撮らない
# 画面の作り(2026-10-31 に購入の手前まで確かめた): ログインのボタンは a[title=...]、メニュー以降は AngularJS の ng-click / ui-sref で探す
#   「購入する」を押した後の画面だけは、まだ一度も確かめていない(最初の本当の購入で画面を見る)
import sys, os, re, time, datetime as dt

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
SHOT = os.path.join(ROOT, '馬情報', 'JRA-VAN', 'AI馬券', 'ipat'); OKF = os.path.join(ROOT, '馬情報', 'JRA-VAN', 'AI馬券', 'ipat_ok.txt')
ENV = os.path.join(os.path.expanduser('~'), '.ipat.env')
WD = '月火水木金土日'

def creds():
    if not os.path.exists(ENV): raise RuntimeError(f'{ENV} が無い(INET_ID・KANYUSHA・PIN・PARS を書く)')
    c = dict(l.strip().split('=', 1) for l in open(ENV, encoding='utf-8') if '=' in l and not l.startswith('#'))
    miss = [k for k in ('INET_ID', 'KANYUSHA', 'PIN', 'PARS') if not c.get(k)]
    if miss: raise RuntimeError(f'{ENV} に {miss} が無い')
    return c

class Step:
    def __init__(self, page, tag): self.page, self.tag, self.n = page, tag, 0
    def shot(self, name):
        os.makedirs(SHOT, exist_ok=True); self.n += 1
        self.page.screenshot(path=os.path.join(SHOT, f'{dt.datetime.now():%Y%m%d_%H%M%S}_{self.tag}_{self.n:02d}_{name}.png'), full_page=True)
    def fail(self, name):   # ID・番号の欄を空にしてから、画面と HTML を残す(次に直すため。PCだけ)
        try: self.page.evaluate("document.querySelectorAll('input[name=inetid],input[name=i],input[name=p],input[name=r]').forEach(e => e.value = '')")
        except Exception: pass
        self.shot(name)
        try: open(os.path.join(SHOT, f'{dt.datetime.now():%Y%m%d_%H%M%S}_{self.tag}_{self.n:02d}_{name}.html'), 'w', encoding='utf-8').write(self.page.content())
        except Exception: pass
    def click(self, sel, name, wait=1.0):
        loc = self.page.locator(sel) if isinstance(sel, str) else sel
        loc.first.wait_for(state='visible'); loc.first.click(); self.page.wait_for_load_state('networkidle'); time.sleep(wait); self.shot(name)

def login(page, st):
    c = creds()
    page.goto('https://www.ipat.jra.go.jp/', wait_until='networkidle')
    if '受付時間外' in page.inner_text('body'): st.shot('受付時間外'); raise RuntimeError('即PATの受付時間外')
    page.locator('input[name="inetid"]').fill(c['INET_ID'])
    st.click('a[title="ログイン"]', '加入者情報の画面')   # 撮るのは次の画面(まだ何も入れていない)
    page.locator('input[name="i"]').fill(c['KANYUSHA']); page.locator('input[name="p"]').fill(c['PIN']); page.locator('input[name="r"]').fill(c['PARS'])
    st.click('a[title="ネット投票メニューへ"]', 'メニュー', wait=2)
    body = page.inner_text('body')
    if '購入限度額' not in body: raise RuntimeError('メニューの画面にならない(ログイン情報が違う・お知らせの画面など)')
    m = re.search(r'購入限度額\s*([\d,]+)円', body)
    return int(m.group(1).replace(',', '')) if m else None

def buy(bets, confirm=False, tag='', headless=True):
    """bets = [(場 '東京', R 11, 馬番 3, 金額 100), ...]。confirm=False なら購入予定リストに合計金額を入れたところで止めて閉じる(買わない)"""
    from playwright.sync_api import sync_playwright
    if confirm and not os.path.exists(OKF): raise RuntimeError('ipat.py --check の画面を確かめて --approve するまで買わない')
    total = sum(b[3] for b in bets); wd = WD[dt.date.today().weekday()]
    with sync_playwright() as p:
        br = p.chromium.launch(headless=headless); page = br.new_page(locale='ja-JP', viewport={'width': 1280, 'height': 1000})
        page.set_default_timeout(15000); st = Step(page, tag)
        try:
            limit = login(page, st)
            if limit is not None and limit < total: raise RuntimeError(f'購入限度額 {limit}円 が合計 {total}円 より少ない')
            st.click('button[ui-sref="bet.basic"]', '通常投票')
            races = {}
            for b in bets: races.setdefault((b[0], b[1]), []).append(b)
            for (place, R), bs in races.items():
                st.click(page.locator('button', has_text=f'{place}（{wd}）'), f'{place}{wd}')
                st.click(page.locator('button', has_text=re.compile(rf'^\s*{R}R\s*\(')), f'{R}R')
                page.locator('#bet-basic-type').select_option(label='単勝'); time.sleep(0.5)
                for _, _, u, yen in bs:
                    page.locator(f'label[for="no{u}"]').first.click(); time.sleep(0.3)
                    if not page.locator(f'#no{u}').first.is_checked(): raise RuntimeError(f'{u}番にチェックが入らない')
                    page.locator('input[ng-model="vm.nUnit"]:visible').fill(str(yen // 100))   # 金額の欄は100円単位
                    st.click('button[ng-click="vm.onSet()"]:visible', f'{u}番{yen}円セット')
            st.click('button[ng-click="vm.onShowBetList()"]:visible', '購入予定リスト')
            body = page.inner_text('body')
            for place, R, u, yen in bets:   # リストに正しく入ったか
                if not re.search(rf'{place}（{wd}）\s*{R}R\s*単勝', body): raise RuntimeError(f'購入予定リストに {place}{R}R 単勝 が無い')
            if not re.search(rf'合計金額：\s*{total:,}円', body): raise RuntimeError(f'購入予定リストの合計が {total}円 でない')
            page.locator('input[ng-model="vm.cAmountTotal"]:visible').fill(str(total)); time.sleep(0.3); st.shot(f'合計{total}円')
            if not confirm: return 'checked'   # ipat_ok.txt は画面を確かめてから --approve で作る
            page.on('dialog', lambda d: d.accept())   # ブラウザの確認が出たとき
            st.click('button[ng-click="vm.clickPurchase()"]:visible', '購入する', wait=2)
            ok = page.locator('button:visible', has_text=re.compile(r'^\s*OK\s*$'))   # 確認の小さい画面が出たとき
            if ok.count(): ok.first.click(); page.wait_for_load_state('networkidle'); time.sleep(2)
            st.shot('購入後')
            body = page.inner_text('body')
            if not any(k in body for k in ('受付', '受け付け', '完了')): raise RuntimeError('購入の完了が確かめられない(画面を見て、投票履歴で確認)')
            return 'bought'
        except Exception:
            try: st.fail('失敗')
            except Exception: pass
            raise
        finally:
            br.close()

if __name__ == '__main__':
    if sys.argv[1:2] == ['--approve']:
        os.makedirs(os.path.dirname(OKF), exist_ok=True)
        open(OKF, 'w', encoding='utf-8').write(f'{dt.datetime.now().isoformat()} --check の画面を確かめた\n'); print('承認した:', OKF)
    if sys.argv[1:2] == ['--check']:
        place, R, u = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
        print(buy([(place, R, u, 100)], confirm=False, tag='check', headless='--show' not in sys.argv))
        print('画面:', SHOT)
