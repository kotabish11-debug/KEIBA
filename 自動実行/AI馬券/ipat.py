# 即PAT(www.ipat.jra.go.jp)で単勝を買う。Playwright でブラウザを動かす(「競馬予想で始めるデータ分析」#32 の流れ:
#   ログイン → 通常投票 → 場 → レース → 式別 → 馬番 → 金額 → セット(繰り返し)→ 入力終了 → 合計金額 → 購入する)
# 使い方: live.py が buy() を呼ぶ。単体で確かめるとき: python ipat.py --check <場 東京> <R 11> <馬番 1>
#   --check は購入の手前(合計金額を入れたところ)まで進んで止め、画面を保存して閉じる。買わない
#   --approve: --check の画面(選んだ場・レース・馬番・金額が正しいか)を見て確かめたあとに実行する。ipat_ok.txt ができ、live.py が本当に買うようになる
# ログイン情報は %USERPROFILE%\.ipat.env に自分で書く(コードやリポジトリには置かない):
#   INET_ID=xxxxxxxx / KANYUSHA=加入者番号 / PIN=暗証番号 / PARS=P-ARS番号
# 各手順の画面: 馬情報/JRA-VAN/AI馬券/ipat/<日時>_<tag>_<番号>_<手順>.png(PCだけ)
# 注意: 即PATの中の画面は作った時点で確かめていない(ログイン情報が無いため)。--check の画面を確かめて --approve するまで、live.py は本当に買わない(ipat_ok.txt)
import sys, os, time, datetime as dt

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
    def click_text(self, *texts, name=''):
        for t in texts:   # ボタンやリンクの文字で押す。最初に見つかったもの
            loc = self.page.get_by_text(t, exact=False)
            if loc.count():
                loc.first.click(); self.page.wait_for_load_state('networkidle'); self.shot(name or t); return
        self.shot('見つからない_' + (name or texts[0])); raise RuntimeError(f'「{"・".join(texts)}」が見つからない')

def login(page, st):
    c = creds()
    page.goto('https://www.ipat.jra.go.jp/', wait_until='networkidle'); st.shot('ログイン画面')
    if '受付時間外' in page.inner_text('body'): raise RuntimeError('即PATの受付時間外')
    page.locator('input[name="inetid"], input[type="text"]').first.fill(c['INET_ID'])
    st.click_text('ログイン', name='INET-ID')
    page.locator('input[name="i"]').fill(c['KANYUSHA']); page.locator('input[name="p"]').fill(c['PIN']); page.locator('input[name="r"]').fill(c['PARS'])
    st.click_text('ネット投票メニューへ', 'ログイン', name='加入者番号')
    for t in ('OK', '確認'):   # お知らせの画面が出たとき
        if page.get_by_role('button', name=t).count(): page.get_by_role('button', name=t).first.click(); page.wait_for_load_state('networkidle')

def buy(bets, confirm=False, tag='', headless=True):
    """bets = [(場 '東京', R 11, 馬番 3, 金額 100), ...]。confirm=False なら合計金額を入れたところで止めて閉じる(買わない)"""
    from playwright.sync_api import sync_playwright
    if confirm and not os.path.exists(OKF): raise RuntimeError('ipat.py --check の画面を確かめて --approve するまで買わない')
    total = sum(b[3] for b in bets)
    with sync_playwright() as p:
        br = p.chromium.launch(headless=headless); page = br.new_page(locale='ja-JP'); page.set_default_timeout(15000)
        st = Step(page, tag)
        try:
            login(page, st)
            st.click_text('通常投票', name='通常投票')
            races = {}
            for b in bets: races.setdefault((b[0], b[1]), []).append(b)
            for (place, R), bs in races.items():
                st.click_text(f'{place}（{WD[dt.date.today().weekday()]}）', place, name=f'{place}')
                st.click_text(f'{R}R', name=f'{R}R')
                page.get_by_role('combobox').first.select_option(label='単勝'); st.shot('単勝')
                for _, _, u, yen in bs:
                    page.locator(f'label:text-is("{u}")').first.click() if page.locator(f'label:text-is("{u}")').count() else \
                        page.get_by_role('checkbox').nth(u - 1).check()
                    page.get_by_role('textbox').last.fill(str(yen // 100))   # 金額の欄は100円単位
                    st.click_text('セット', name=f'{u}番セット')
            st.click_text('入力終了', name='入力終了')
            page.get_by_role('textbox').last.fill(str(total)); st.shot(f'合計{total}円')
            if not confirm: return 'checked'   # ipat_ok.txt は画面を確かめてから --approve で作る
            page.once('dialog', lambda d: d.accept())   # 「購入しますか」の確認
            st.click_text('購入する', name='購入する')
            for t in ('OK',):
                if page.get_by_role('button', name=t).count(): page.get_by_role('button', name=t).first.click()
            page.wait_for_load_state('networkidle'); time.sleep(1); st.shot('購入後')
            body = page.inner_text('body')
            if '受付' not in body and '完了' not in body: raise RuntimeError('購入の完了の画面が確かめられない(画面を見て確認)')
            return 'bought'
        except Exception:
            try: st.shot('失敗')
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
