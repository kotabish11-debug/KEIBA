// 2026-10-23 に simulator.html の「1日の予算」から外したコード(推定オッズの期待値とケリー基準で全券種に配分していた版)
// 過去1,868レースの本物の払戻で確かめると回収率がバランス56%・高配当34%だったため、本物の複勝オッズを使う買い方に置き換えた(馬情報/的中率を上げるための検証.md の11)
  // ---------------- 1日の予算 ----------------
  // その日の全レースをレース予想と同じ方法で計算し、1日の予算をレースごとに配分する
  const DAY_KEY = "keiba-day-v1";
  const DAY_MIN_UNITS = 3;     // 1レースの最低額(100円単位)
  const DAY_CAP = 0.3;         // 1レースに使う上限(予算に対する割合)
  const DAY_STAR = 1.3;        // ★のレースの重み
  let view = "race";
  const day = { iso: null, budget: 10000, style: "balance", evMin: "1.1", past: false };
  const dayCache = {};         // レースID → { key, info }
  let dayJob = 0;
  let dayTimer = null;
  try { Object.assign(day, JSON.parse(localStorage.getItem(DAY_KEY) || "{}")); } catch (e) {}
  day.iso = null;
  function daySave() {
    try { localStorage.setItem(DAY_KEY, JSON.stringify({ budget: day.budget, style: day.style, evMin: day.evMin, past: day.past })); } catch (e) {}
  }

  // 1レース分を計算する。表示中のレースの状態(race・roster・horses・settings・autoData)を一時的に入れ替えて、同じ関数で計算する
  function analyzeRace(id) {
    const keep = { race, roster, horses, settings, autoData };
    try {
      race = races[id];
      roster = clone(race.horses);
      settings = defaultSettings();
      autoData = docs[id] || null;
      load(); fixRuns(); applyAuto();
      horses = roster.filter(h => !h.scratched);
      if (horses.length < 2) return null;
      const s = simulate();
      const cands = buildCandidates(s, marketProbs());
      return { id, race, horses, total: roster.length, s, cands, kari: horses.some(h => h.oddsKari) };
    } finally {
      ({ race, roster, horses, settings, autoData } = keep);
    }
  }
  function dayCacheKey(id) {
    let st = "";
    try { st = localStorage.getItem("keiba-sim-v2-" + id) || ""; } catch (e) {}
    return JSON.stringify(docs[id] || null) + "|" + st + "|" + JSON.stringify(WEIGHTS);
  }
  function dayDates() {
    const { up, past } = sortedRaces();
    return [...new Set(past.concat(up).map(r => r.iso).filter(Boolean))].sort();
  }
  function dayRaces() {
    const now = new Date();
    return Object.values(races).filter(r => r.iso === day.iso).map(r => {
      const w = saleWindows(r);
      const st = w ? saleStatus(w, now) : { cls: "", text: "" };
      return { r, sale: st, ended: st.cls === "end" || r.stage === "結果確定" };
    }).sort((a, b) => (a.r.time || "").localeCompare(b.r.time || "") || Number(a.r.no) - Number(b.r.no));
  }

  function renderDayDates() {
    const dates = dayDates();
    const today = todayIso();
    if (!day.iso || !dates.includes(day.iso)) day.iso = dates.find(d => d >= today) || dates[dates.length - 1] || null;
    $("dayDate").innerHTML = dates.map(d => `<button type="button" class="chip-btn${d < today ? " done" : ""}" data-date="${esc(d)}" aria-pressed="${d === day.iso}">${esc(dateShort(d))}${d === today ? "<i>今日</i>" : ""}</button>`).join("");
    document.querySelectorAll("#dayStyleSeg button").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.style === day.style)));
    $("dayBudget").value = day.budget;
    $("dayEvMin").value = day.evMin;
    $("dayPast").checked = !!day.past;
  }

  // 計算が済んでいないレースを1つずつ計算する(画面が固まらないように、1レースごとに休む)
  function dayRun() {
    if (view !== "day") return;
    renderDayDates();
    const job = ++dayJob;
    const list = dayRaces().filter(x => day.past || !x.ended);
    const todo = list.filter(x => { const c = dayCache[x.r.id]; return !c || c.key !== dayCacheKey(x.r.id); });
    let done = 0;
    const step = () => {
      if (job !== dayJob) return;
      if (done < todo.length) {
        const id = todo[done].r.id;
        $("dayVerdict").textContent = `計算中… ${done + 1}/${todo.length}レース(${todo[done].r.place}${todo[done].r.no}R)`;
        $("dayProgress").hidden = false;
        $("dayBar").style.width = (done / todo.length * 100).toFixed(0) + "%";
        try { dayCache[id] = { key: dayCacheKey(id), info: analyzeRace(id) }; } catch (e) { dayCache[id] = { key: dayCacheKey(id), info: null }; }
        done++;
        setTimeout(step, 0);
        return;
      }
      $("dayProgress").hidden = true;
      renderDay();
    };
    setTimeout(step, 0);
  }

  // 予算をレースに配分する。重み = そのレースで買う馬券のケリー割合の合計(★は重くする)
  function dayAllocate(items, units) {
    let pool = items.slice();
    const cap = Math.max(DAY_MIN_UNITS, Math.floor(units * DAY_CAP));
    let shares = [];
    for (;;) {
      // 上限を超えた分を、ほかのレースに割合どおり回す
      const tw = pool.reduce((a, x) => a + x.w, 0);
      shares = pool.map(x => ({ x, s: units * x.w / tw }));
      for (let it = 0; it < 20; it++) {
        const over = shares.filter(o => o.s > cap);
        if (!over.length) break;
        over.forEach(o => { o.s = cap; o.fixed = true; });
        const free = shares.filter(o => !o.fixed);
        const rest = units - shares.filter(o => o.fixed).reduce((a, o) => a + o.s, 0);
        const fw = free.reduce((a, o) => a + o.x.w, 0);
        if (!free.length || rest <= 0) break;
        free.forEach(o => { o.s = rest * o.x.w / fw; });
      }
      const small = shares.filter(o => o.s < DAY_MIN_UNITS);
      if (!small.length || pool.length <= 1) break;
      // 最低額に届かないレースは、いちばん重みの小さいものから外す
      const worst = small.reduce((a, b) => (b.x.w < a.x.w ? b : a));
      pool = pool.filter(x => x !== worst.x);
    }
    shares.forEach(o => { o.u = Math.min(cap, Math.floor(o.s)); });
    let used = shares.reduce((a, o) => a + o.u, 0);
    const limit = Math.min(units, shares.reduce((a, o) => a + Math.min(cap, Math.ceil(o.s)), 0));
    const order = shares.slice().sort((a, b) => (b.s - b.u) - (a.s - a.u));
    for (let k = 0; used < limit && k < order.length * 2; k++) {
      const o = order[k % order.length];
      if (o.u < cap && o.u < Math.ceil(o.s)) { o.u++; used++; }
    }
    return shares.filter(o => o.u >= 1 && (o.u >= DAY_MIN_UNITS || units < DAY_MIN_UNITS));
  }

  // 買い目の払戻をシミュレーションの1回ごとに出す(1日の収支の計算に使う)
  function payArray(bets, s) {
    const pays = new Float32Array(s.N);
    for (let r = 0; r < s.N; r++) {
      const a = s.order[r * 3], b = s.order[r * 3 + 1], c = s.order[r * 3 + 2];
      let pay = 0;
      for (const t of bets) if (hits(t, a, b, c)) pay += t.amount * t.odds;
      pays[r] = pay;
    }
    return pays;
  }
  function payStats(pays, cost) {
    let hit = 0, ret = 0, max = 0;
    for (const p of pays) { if (p > 0) hit++; ret += p; if (p > max) max = p; }
    return { cost, hit: hit / pays.length, rate: ret / pays.length / cost, hitAvg: hit ? ret / hit : 0, max };
  }

  function dayChip(info, i) {
    const h = info.horses[i];
    const u = Number(h.umaban);
    const w = wakuOf(u, info.total);
    return `<span class="chip w${w}" title="${w ? w + "枠" : "馬番未確定"}">${w ? u : "－"}</span>`;
  }
  function dayCombo(info, b) {
    const sep = (b.type === "馬単" || b.type === "3連単") ? "→" : "-";
    return `<span class="combo">${b.h.map(i => `${dayChip(info, i)}${nameBtn(info.horses[i].name)}`).join(`<span class="sep">${sep}</span>`)}</span>`;
  }

  function renderDay() {
    if (view !== "day") return;
    const all = dayRaces();
    const units = Math.floor(Math.max(0, Number(day.budget) || 0) / 100);
    const budget = units * 100;
    const items = [], skips = [];
    for (const x of all) {
      if (x.ended && !day.past) { skips.push({ r: x.r, why: "発売終了" }); continue; }
      const c = dayCache[x.r.id];
      const info = c && c.info;
      if (!info) { skips.push({ r: x.r, why: c ? "計算できない" : "計算待ち" }); continue; }
      const { good } = pickBets(info.cands, day.style, day.evMin);
      if (!good.length) { skips.push({ r: x.r, why: `期待値${day.evMin}以上の馬券なし` }); continue; }
      const w = good.reduce((a, b) => a + (b.odds > 1 ? Math.max(0.002, (b.p * b.odds - 1) / (b.odds - 1)) : 0.002), 0) * (x.r.star ? DAY_STAR : 1);
      items.push({ x, info, good, w });
    }
    const shares = units >= 1 ? dayAllocate(items, units) : [];
    const chosen = new Set(shares.map(o => o.x));
    items.filter(it => !chosen.has(it)).forEach(it => skips.push({ r: it.x.r, why: "配分が最低額(300円)に届かない" }));
    const buys = shares.map(o => {
      const bets = allocate(o.x.good, o.u * 100);
      const cost = bets.reduce((a, b) => a + b.amount, 0);
      const pays = payArray(bets, o.x.info.s);
      return Object.assign({}, o.x, { bets, cost, pays, st: payStats(pays, cost) });
    }).filter(b => b.cost > 0);

    // 1日の収支: 各レースのシミュレーション結果を1回ずつ選んで合計する(2万日分)
    const total = buys.reduce((a, b) => a + b.cost, 0);
    let dayHit = 0, dayProfit = 0, dayRet = 0;
    if (buys.length) {
      const rnd = mulberry32(20261019);
      const T = 20000;
      for (let t = 0; t < T; t++) {
        let pay = 0;
        for (const b of buys) pay += b.pays[Math.floor(rnd() * b.pays.length)];
        if (pay > 0) dayHit++;
        if (pay > total) dayProfit++;
        dayRet += pay;
      }
      dayHit /= T; dayProfit /= T; dayRet /= T;
    }

    // 会場ごとにまとめる
    const places = [...new Set(all.map(x => x.r.place))].sort((a, b) => (PLACE_ORDER.indexOf(a) + 99) % 99 - (PLACE_ORDER.indexOf(b) + 99) % 99);
    const byPlace = p => buys.filter(b => b.x.r.place === p);
    const waiting = all.some(x => (day.past || !x.ended) && !dayCache[x.r.id]);
    const kari = buys.some(b => b.info.kari);

    let v;
    if (!all.length) v = "この日のレースがまだありません。";
    else if (!buys.length) v = `<span class="skip">この日は、期待値${esc(day.evMin)}以上で買える馬券が見つかりません。予算は使わずに見送るのがおすすめです。</span>`;
    else {
      const pl = places.filter(p => byPlace(p).length).map(p => `${esc(p)}${byPlace(p).length}レース`).join("・");
      v = `予算${yen(budget)}のうち<strong>${yen(total)}</strong>を、<strong>${pl}</strong>に分けて買います。` +
        (budget - total >= 100 ? `残りの${yen(budget - total)}は、良い馬券がないので使いません。` : "") +
        (kari ? `<span class="muted">(仮オッズのレースを含みます。実際のオッズが出ると変わります)</span>` : "");
    }
    $("dayVerdict").innerHTML = v;
    const stat = (k, val, cls) => `<div class="stat"><span class="k">${k}</span><span class="v ${cls || ""}">${val}</span></div>`;
    $("dayStats").innerHTML = buys.length ? [
      stat("合計金額", yen(total)),
      stat("1日の期待回収率", pct(dayRet / total, 0), dayRet >= total ? "good" : "bad"),
      stat("どれかが当たる確率", pct(dayHit, 0)),
      stat("1日でプラスになる確率", pct(dayProfit, 0))
    ].join("") : "";
    $("dayVenues").innerHTML = places.map(p => {
      const bs = byPlace(p), sum = bs.reduce((a, b) => a + b.cost, 0);
      const n = all.filter(x => x.r.place === p).length;
      return bs.length
        ? `<div class="venue-sum"><span class="k">${esc(p)}</span><span class="v">${yen(sum)}</span><span class="s">${n}レース中 ${bs.length}レースで買う(${bs.map(b => b.x.r.no + "R").join("・")})</span></div>`
        : `<div class="venue-sum none"><span class="k">${esc(p)}</span><span class="v">買わない</span><span class="s">${n}レースすべて見送り</span></div>`;
    }).join("");

    $("dayList").innerHTML = places.filter(p => byPlace(p).length).map(p => {
      const bs = byPlace(p);
      return `<section class="win"><div class="win-b">
        <div class="venue-h"><h3>${esc(p)}</h3><span class="num">${yen(bs.reduce((a, b) => a + b.cost, 0))}</span><span class="muted small">${bs.length}レース</span></div>
        <div class="day-races">${bs.map(b => {
          const r = b.x.r, sale = b.x.sale;
          const rows = b.bets.map(t => `<tr>
            <td><span class="type-pill" title="${BET_DESC[t.type] || ""}">${t.type}</span></td>
            <td>${dayCombo(b.info, t)}</td>
            <td class="r num">${yen(t.amount)}</td>
            <td class="r num">${pct(t.p)}</td>
            <td class="r num">${t.odds.toFixed(1)}倍</td>
            <td class="r num ${t.ev >= 1 ? "ev-good" : "ev-bad"}">${t.ev.toFixed(2)}</td>
            <td class="r num">${yen(Math.floor(t.amount * t.odds / 10) * 10)}</td></tr>`).join("");
          return `<div class="day-race${r.star ? " starred" : ""}">
            <div class="dr-h"><b class="rb-no">${r.star ? "★" : ""}${esc(String(r.no))}R</b>
              <span class="num muted">${esc((r.time || "").replace("発走", ""))}</span>
              <span class="nm2">${esc(r.name)}</span>${gradeBadge(r.grade, true)}
              <span class="muted small">${esc(r.course.replace(/\(.*\)/, ""))}</span>
              ${sale.text ? `<span class="sale-pill ${sale.cls}">${esc(sale.cls === "open" ? "発売中" : sale.cls === "wait" ? "発売前" : "発売終了")}</span>` : ""}
              <span class="amt">${yen(b.cost)}</span>
              <button type="button" class="btn" data-open="${esc(r.id)}">レースを開く</button></div>
            <div class="tbl-wrap"><table class="t">
              <thead><tr><th>券種</th><th>買い目</th><th class="r">金額</th><th class="r">的中率</th><th class="r">推定オッズ</th><th class="r">期待値</th><th class="r">当たれば</th></tr></thead>
              <tbody>${rows}</tbody></table></div>
            <div class="dr-foot"><span>どれかが当たる <b>${pct(b.st.hit, 0)}</b></span><span>期待回収率 <b>${pct(b.st.rate, 0)}</b></span><span>当たったときの平均 <b>${yen10(b.st.hitAvg)}</b></span>${b.info.kari ? '<span class="warn">仮オッズで計算</span>' : ""}${sale.text ? `<span>${esc(sale.text)}</span>` : ""}</div>
          </div>`;
        }).join("")}</div></div></section>`;
    }).join("");

    $("daySkipBox").hidden = !skips.length;
    $("daySkips").innerHTML = places.map(p => {
      const ss = skips.filter(x => x.r.place === p).sort((a, b) => Number(a.r.no) - Number(b.r.no));
      return ss.length ? `<div class="row"><b>${esc(p)}</b>${ss.map(x => `<button type="button" class="skip-chip" data-open="${esc(x.r.id)}" title="${esc(x.r.name + ": " + x.why)}">${esc(String(x.r.no))}R ${esc(x.why)}</button>`).join("")}</div>` : "";
    }).join("");
    if (waiting) $("dayVerdict").innerHTML += `<span class="muted">(計算中のレースがあります)</span>`;
  }


// --- 画面の部品(HTML) ---
        <div class="controls">
          <div class="field"><label for="dayBudget">1日の予算(円)</label><input type="number" id="dayBudget" min="100" step="100" value="10000"></div>
          <div class="field"><span>買い方</span>
            <div class="seg" role="group" aria-label="買い方" id="dayStyleSeg">
              <button type="button" data-style="safe">堅実</button>
              <button type="button" data-style="balance">バランス</button>
              <button type="button" data-style="big">高配当</button>
            </div>
          </div>
          <div class="field"><label for="dayEvMin">期待値がこれ以上の馬券だけ買う</label>
            <select id="dayEvMin">
              <option value="1.0">1.0</option>
              <option value="1.1">1.1(推奨)</option>
              <option value="1.3">1.3(厳しめ)</option>
            </select>
          </div>
          <label class="day-check"><input type="checkbox" id="dayPast">発売が終わったレースも含める</label>
        </div>
        <div class="progress" id="dayProgress" hidden><i id="dayBar"></i></div>
        <p class="verdict" id="dayVerdict">計算の準備をしています…</p>
        <div class="stats" id="dayStats"></div>
        <div class="venues" id="dayVenues"></div>
      </div>
    </section>
    <div id="dayList" class="view"></div>
    <section class="win" aria-labelledby="h-skip" id="daySkipBox" hidden>
      <div class="win-h"><h2 id="h-skip">見送るレース</h2><span class="sub">期待値の高い馬券が見つからない、または配分が少なすぎるレース。押すとレース予想を開きます</span></div>
      <div class="win-b skips" id="daySkips"></div>
    </section>
    <section class="foot">
      <b>1日の予算の決め方</b>
      <ul>
        <li>その日の全レースを、レース予想と同じ方法(1レース5万回以上のシミュレーション)で計算します。レース予想で手入力した数値やオッズもそのまま使います。</li>
        <li>各レースで期待値が基準以上の馬券を選び、「期待値がどれだけ1を超えているか」と「当たりやすさ」からケリー基準で割合を出し、割合が大きいレースほど多く配分します。★のレースは1.3倍に重くします。</li>
        <li>1レースに使うのは予算の30%まで、1レースの最低額は300円です。それより少なくなるレースは見送ります。良い馬券が少ない日は、予算を使い切らずに残します。</li>
        <li>「1日でプラスになる確率」は、各レースのシミュレーション結果を組み合わせて2万日分の収支を出した割合です。</li>
