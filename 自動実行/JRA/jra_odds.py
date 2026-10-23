#!/usr/bin/env python3
"""JRA公式(オッズ・出馬表)から全レースの馬番・枠・騎手・単勝/複勝オッズ・馬体重・取消を取る。
使い方: python3 jra_odds.py <出力フォルダ>   → <出力>/<race_id>.json (race_id = k+日付+場コード+R)
場コード: 04新潟 05東京 08京都。cname を POST してたどる(ページは Shift_JIS)。"""
import re, sys, json, subprocess, os, time
B = 'https://www.jra.go.jp/JRADB/'

def get(page, cname):
    for _ in range(3):
        r = subprocess.run(['curl', '-sL', '-m', '40', '-d', 'cname=' + cname, B + page + '.html'], capture_output=True)
        if r.returncode == 0 and r.stdout:
            return r.stdout.decode('shift_jis', 'replace')
        time.sleep(2)
    return ''

def strip(s): return re.sub(r'<[^>]+>', '', s).strip()

def parse(h):
    rows = []
    for tr in re.findall(r'<tr>(.*?)</tr>', h.split('<tbody>', 1)[-1], re.S):
        m = re.search(r'class="num">(\d+)<', tr)
        if not m: continue
        r = {'umaban': int(m.group(1))}
        w = re.search(r'waku/(\d)\.png', tr)
        if w: r['waku'] = int(w.group(1))
        n = re.search(r'class="horse">(.*?)</td>', tr, re.S)
        r['name'] = strip(n.group(1)) if n else ''
        t = re.search(r'class="odds_tan">(.*?)</td>', tr, re.S)
        t = strip(t.group(1)) if t else ''
        try: r['odds'] = float(t)
        except ValueError: r['oddsRaw'] = t
        f = re.search(r'class="min">([\d.]+)<.*?class="max">([\d.]+)<', tr, re.S)
        if f: r['fukuMin'], r['fukuMax'] = float(f.group(1)), float(f.group(2))
        hw = re.search(r'class="h_weight">(.*?)</td>', tr, re.S)
        hw = strip(hw.group(1)) if hw else ''
        m = re.match(r'(\d+)\(([+-]?\d+)\)', hw.replace(' ', '').replace('\n', ''))
        if m: r['weight'], r['weightDiff'] = int(m.group(1)), int(m.group(2))
        j = re.search(r'class="jockey">(.*?)</td>', tr, re.S)
        r['jockey'] = re.sub(r'^[★☆▲△◇]|\s+', '', strip(j.group(1))) if j else ''
        if re.search(r'取消|除外', strip(tr)): r['scratched'] = True
        rows.append(r)
    return rows

def main(out):
    os.makedirs(out, exist_ok=True)
    top = get('accessO', 'pw15oli00/6D')
    days = sorted(set(re.findall(r"'(pw15orl00\d{2}\d{4}\d{2}\d{2}\d{8}/[0-9A-F]{2})'", top)))
    n = 0
    for dc in days:
        lst = get('accessO', dc)
        for rc in sorted(set(re.findall(r"'(pw151ouS3\d{2}\d{4}\d{4}\d{2}\d{8}Z/[0-9A-F]{2})'", lst))):
            m = re.match(r'pw151ouS3(\d{2})\d{4}\d{4}(\d{2})(\d{8})Z', rc)
            venue, rr, date = m.groups()
            rows = parse(get('accessO', rc))
            if rows:
                json.dump({'horses': rows, 'fetchedAt': time.strftime('%Y-%m-%dT%H:%M:%S+09:00', time.gmtime(time.time() + 32400))},
                          open(f'{out}/k{date}{venue}{rr}.json', 'w'), ensure_ascii=False)
                n += 1
    print('JRAオッズ取得', n, 'レース')

if __name__ == '__main__':
    main(sys.argv[1])
