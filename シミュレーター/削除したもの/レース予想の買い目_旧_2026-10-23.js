// 2026-10-23 に simulator.html の「レース予想」の買い目から外したコード(推定オッズの期待値で堅実・バランス・高配当の券種を選んでいた版)
// 過去1,868レースの本物の払戻で損をする(1日の予算で回収率34〜56%)と分かったため、1日の予算と同じ人気馬の複勝の方式に置き換えた
  function renderBets(s, m) {
    const mk = marketProbs();
    const cands = buildCandidates(s, mk);
    const { good, ref } = pickBets(cands);
    const budget = Math.max(100, Math.floor(Number(settings.budget) / 100) * 100 || 100);
    const bets = allocate(good, budget);
    const ev = evaluate(bets, s);
    const top = [...Array(s.n).keys()].sort((a, b) => s.win[b] - s.win[a]);
    const st = STYLES_BET[settings.style];
    const kari = horses.some(h => h.oddsKari);

    let v = `本命は<strong>${esc(horses[top[0]].name)}</strong>(勝率${pct(s.win[top[0]], 0)})、対抗は${esc(horses[top[1]].name)}(${pct(s.win[top[1]], 0)})。`;
    if (bets.length) {
      v += `「${st.label}」の買い方では、<strong>${bets.length}点・合計${yen(ev.cost)}</strong>を推奨します。`;
      if (kari) v += `<span class="muted">(仮オッズでの計算)</span>`;
    } else {
      v += `<span class="skip">期待値${settings.evMin}以上の馬券が見つからないため、このレースは見送りを推奨します。</span>参考として、条件に近い馬券を薄字で示します。`;
    }
    const gapHint = oddsGapHint(s);
    if (gapHint) v += `<br><span class="muted small">オッズの断層: ${gapHint}${kari ? "(仮オッズ)" : ""}</span>`;
    const trio = trioHint(s);
    if (trio) v += `<br><span class="muted small">3連複の向き: ${trio}</span>`;
    const ax = axisHint(s);
    if (ax) v += `<br><span class="muted small">軸の減点(1〜3番人気): ${ax}</span>`;
    const at = axisTypeHint(s, mk);
    if (at) v += `<br><span class="muted small">軸の型: ${at}${kari ? "(仮オッズ)" : ""}</span>`;
    const wh = wideHint(s, mk);
    if (wh) v += `<br><span class="muted small">ワイドの形: ${wh}${kari ? "(仮オッズ)" : ""}</span>`;
    const tk = tenkaiHint();
    if (tk) v += `<br><span class="muted small">展開と隊列: ${tk}</span>`;
    const g1 = g1Hint(s);
    if (g1) v += `<br><span class="muted small">G1の荒れ方: ${g1}</span>`;
    const sf = smallFieldHint(s);
    if (sf) v += `<br><span class="muted small">少頭数の荒れ方: ${sf}</span>`;
    const ls = longshotHint(s, mk);
    if (ls) v += `<br><span class="muted small">一見堅いレースの逆張り: ${ls}${kari ? "(仮オッズ)" : ""}</span>`;
    const fh = favHoleHint(s);
    if (fh) v += `<br><span class="muted small">1番人気軸の穴流し: ${fh}${kari ? "(仮オッズ)" : ""}</span>`;
    const g1j = g1JockeyHint();
    if (g1j) v += `<br><span class="muted small">G1の騎手: ${g1j}</span>`;
    const conv = convHint(ev, bets, s);
    if (conv) v += `<br><span class="muted small">収束と上振れ: ${conv}</span>`;
    const syn = synthHint(bets);
    if (syn) v += `<br><span class="muted small">合成オッズ(どれが当たっても同じ額が戻る配分): ${syn}</span>`;
    $("verdict").innerHTML = v;

    const statItems = ev ? [
      ["合計金額", yen(ev.cost), ""],
      ["どれかが当たる確率", pct(ev.hit, 0), ""],
      ["期待回収率", pct(ev.rate, 0), ev.rate >= 1 ? "good" : "bad"],
      ["プラス収支になる確率", pct(ev.profit, 0), ""]
    ] : [["合計金額", "0円", ""], ["どれかが当たる確率", "－", ""], ["期待回収率", "－", ""], ["プラス収支になる確率", "－", ""]];
    $("stats").innerHTML = statItems.map(([k, val, cls]) => `<div class="stat"><span class="k">${k}</span><span class="v ${cls}">${val}</span></div>`).join("");

    // 的中したときに戻ってくる金額(払戻の合計)
    if (ev) {
      const pred = predPay(bets, top);
      const order = top.slice(0, 3).map(i => esc(horses[i].name)).join(" → ");
      const diff = v => { const d = Math.floor(v / 10) * 10 - ev.cost; return `<small class="${d >= 0 ? "plus" : "minus"}">収支 ${d >= 0 ? "+" : "−"}${yen(Math.abs(d))}</small>`; };
      $("payBox").innerHTML = `
        <div class="pay-h">予算${yen(ev.cost)}で買って当たったら、全部でいくら戻るか</div>
        <div class="pay-grid">
          <div class="pay-main"><span class="k">予想どおりに決まったとき</span><span class="v">${pred ? yen10(pred) : "0円"}</span>${pred ? diff(pred) : '<small class="minus">この買い目では当たりません</small>'}<span class="ord">${order}</span></div>
          <div class="stat"><span class="k">当たったときの平均</span><span class="v">${yen10(ev.hitAvg)}</span>${diff(ev.hitAvg)}</div>
          <div class="stat"><span class="k">いちばん多く戻るとき</span><span class="v">${yen10(ev.max)}</span>${diff(ev.max)}</div>
        </div>`;
      $("payBox").hidden = false;
    } else {
      $("payBox").hidden = true;
    }

    const rows = (bets.length ? bets : ref).map(b => `
      <tr class="${bets.length ? "" : "ref"}">
        <td><span class="type-pill" title="${BET_DESC[b.type] || ""}">${b.type}</span>${b.cover ? ' <small class="muted" title="同じ組のワイドに添える少額のおさえ">おさえ</small>' : ""}</td>
        <td>${comboHtml(b)}</td>
        <td class="r num">${b.amount ? yen(b.amount) : "－"}</td>
        <td class="r num">${pct(b.p)}</td>
        <td class="r num">${b.odds.toFixed(1)}倍</td>
        <td class="r num ${b.ev >= 1 ? "ev-good" : "ev-bad"}">${b.ev.toFixed(2)}</td>
        <td class="r num">${b.amount ? yen(Math.floor(b.amount * b.odds / 10) * 10) : "－"}</td>
      </tr>`).join("");
    $("betTable").tBodies[0].innerHTML = rows || `<tr><td colspan="7" class="muted">候補がありません。買い方か期待値の条件を緩めてください。</td></tr>`;
  }


// --- 画面の部品(HTML) ---
  <!-- 結論・買い目 -->
  <section class="win" aria-labelledby="h-bets">
    <div class="win-h"><h2 id="h-bets">買い目</h2><span class="sub">予算と買い方を選ぶと、券種・馬・金額を出します</span></div>
    <div class="win-b">
      <div class="controls">
        <div class="field"><label for="budget">予算(円)</label><input type="number" id="budget" min="100" step="100" value="3000"></div>
        <div class="field"><span>買い方</span>
          <div class="seg" role="group" aria-label="買い方" id="styleSeg">
            <button type="button" data-style="safe">堅実</button>
            <button type="button" data-style="balance">バランス</button>
            <button type="button" data-style="big">高配当</button>
          </div>
        </div>
        <div class="field"><label for="evMin">期待値がこれ以上の馬券だけ買う</label>
          <select id="evMin">
            <option value="0.9">0.9(参考に広く)</option>
            <option value="1.0">1.0</option>
            <option value="1.1">1.1(推奨)</option>
            <option value="1.3">1.3(厳しめ)</option>
          </select>
        </div>
      </div>
      <p class="verdict" id="verdict"></p>
      <div class="pay" id="payBox" hidden></div>
      <div class="stats" id="stats"></div>
      <div class="tbl-wrap">
        <table class="t" id="betTable">
          <thead><tr><th>券種</th><th>買い目</th><th class="r">金額</th><th class="r">的中率</th><th class="r">推定オッズ</th><th class="r">期待値</th><th class="r">当たれば</th></tr></thead>
          <tbody></tbody>
        </table>
      </div>
      <div class="legend">
        <span>的中率: シミュレーションでその馬券が当たった割合</span>
        <span>期待値: 的中率 × オッズ。1.0を超えると、長く買い続けた場合に理論上プラス</span>
        <span>推定オッズ: 単勝オッズから計算した目安。購入前に実際のオッズを確認</span>
        <span>収束: 単勝・複勝は早く、馬連・ワイドは中期、3連系は長期で成績が落ち着く。長期の買い方ほど外れの連続に耐える資金が要る</span>
      </div>
      <details class="kinds">
        <summary>券種の説明</summary>
        <div class="tbl-wrap">
          <table class="t">
            <thead><tr><th>券種</th><th>当たる条件</th><th>例(16頭立て)</th><th class="c">当たりやすさ</th><th class="c">配当</th><th class="r">払戻率</th></tr></thead>
            <tbody>
              <tr><td><span class="type-pill">単勝</span></td><td>選んだ1頭が<b>1着</b></td><td>組み合わせ16通り</td><td class="c">△</td><td class="c">中</td><td class="r num">80%</td></tr>
              <tr><td><span class="type-pill">複勝</span></td><td>選んだ1頭が<b>3着以内</b>(7頭立て以下は2着以内)</td><td>16通り・当たりは3頭</td><td class="c">◎</td><td class="c">低</td><td class="r num">80%</td></tr>
              <tr><td><span class="type-pill">ワイド</span></td><td>選んだ2頭が<b>どちらも3着以内</b>(着順は問わない)</td><td>120通り・当たりは3組</td><td class="c">○</td><td class="c">低〜中</td><td class="r num">77.5%</td></tr>
              <tr><td><span class="type-pill">馬連</span></td><td>選んだ2頭が<b>1着と2着</b>(どちらが1着でもよい)</td><td>120通り</td><td class="c">△</td><td class="c">中</td><td class="r num">77.5%</td></tr>
              <tr><td><span class="type-pill">馬単</span></td><td>選んだ2頭が<b>1着・2着の順番どおり</b></td><td>240通り</td><td class="c">×</td><td class="c">中〜高</td><td class="r num">75%</td></tr>
              <tr><td><span class="type-pill">3連複</span></td><td>選んだ3頭が<b>1〜3着</b>(着順は問わない)</td><td>560通り</td><td class="c">×</td><td class="c">高</td><td class="r num">75%</td></tr>
              <tr><td><span class="type-pill">3連単</span></td><td>選んだ3頭が<b>1着・2着・3着の順番どおり</b></td><td>3,360通り</td><td class="c">××</td><td class="c">最高</td><td class="r num">72.5%</td></tr>
            </tbody>
          </table>
        </div>
        <ul class="kinds-notes">
          <li>払戻率: 売上のうち、当たった人に戻る割合(JRAの規定)。残りは控除される。払戻率が高い単勝・複勝ほど、長く買ったときに損をしにくい</li>
          <li>買い方ごとの券種: 堅実=単勝・複勝・ワイド・馬連 / バランス=左に加えて馬単・3連複 / 高配当=馬連・馬単・3連複・3連単</li>
          <li>ワイドを買うときは、同じ2頭の馬連を「おさえ」として少額で添えます(期待値1以上のときだけ)。ワイドが当たるとき、その2頭がそのまま1・2着のことも多いためです</li>
          <li>3連単は◎(勝率1位)を1着に固定した組だけを買います。◎が1着のときのボーナスという位置づけで、1着を入れ替えるマルチやボックスは点数が増えるのに配当が見合わないため買いません</li>
          <li>単勝は4〜9.9倍の馬を中心に選びます。3.9倍以下は期待値が条件より0.2以上高いときだけ、10倍以上は買いません(過去1,868レースで、10倍以上の単勝は期待値が高く出るほど外れていたため)</li>
          <li>予算が少ないときは点数を絞ります(1000円までは2点、2000円までは3点)。少ない予算を薄く広げると、当たっても増えにくいためです</li>
          <li>「オッズの断層」は、単勝を人気順に並べて隣同士が2倍以上離れる所から、レースの型を示します(1番人気が抜けて強い=見送り向き/抜けているが不安=逆転候補が狙い目/上位2〜3頭が抜けている=その中で比べる/断層なしの混戦=見送り向き)</li>
          <li>ほかに枠連(同じ枠の馬をまとめて買う馬連)と応援馬券(同じ馬の単勝と複勝のセット)もあるが、このシミュレーターでは使わない</li>
        </ul>
      </details>
    </div>
  </section>
// --- イベント ---
3040:    $("evMin").addEventListener("change", e => setS("evMin", e.target.value));
3055:    $("styleSeg").addEventListener("click", e => {
