// 過去レースでシミュレーターと同じ計算を動かす(Node)。使い方は run_bt.sh
// node bt.js <sim_core.js> <data.js> <出力 bt.jsonl>
// sim_core.js(extract.pl で simulator.html から抜き出した計算部分)と data.js(make_data.pl)を読み、
// レースごとに「シミュレーターの勝率・3着以内率・馬券の候補(確率と推定オッズ)」を1行1レースのJSONで出す。CPUの数だけ並べて動かす
const fs = require("fs"), vm = require("vm"), os = require("os");
const { Worker, isMainThread, workerData, parentPort } = require("worker_threads");

// 1レースずつ計算する部分。sim_core.js と同じ場所で動かすため、文字にして vm に渡す
function runRange(DATA) {
  const lines = [];
  // race_json.pl と同じ波乱度
  const chaosOf = d => d.surface === "障" ? 12 : (/2歳|新馬/.test(d.cls || "") || /ハンデ/.test(d.cond || "")) ? 20 : 16;
  for (const d of DATA) {
    try {
      const ok = d.horses.map(h => /^\d+$/.test(String(h.rank)) && Number(h.odds) >= 1);
      if (ok.filter(Boolean).length < 5) continue;
      race = raceFromDoc(Object.assign({}, d, { auto: true, chaos: chaosOf(d), going: undefined }), d.id);
      roster = race.horses.map((h, i) => Object.assign(h, { umaban: d.horses[i].umaban, odds: Number(d.horses[i].odds) || 999, oddsKari: false, scratched: !ok[i] }));
      horses = roster.filter(h => !h.scratched);
      settings = defaultSettings();
      const s = simulate();
      const mk = marketProbs();
      const cands = buildCandidates(s, mk);
      const U = horses.map(h => Number(h.umaban));
      const key = c => {
        const u = c.h.map(i => U[i]);
        return (c.type === "馬単" || c.type === "3連単" ? u : u.slice().sort((a, b) => a - b)).join("-");
      };
      const r4 = v => Math.round(v * 1e4) / 1e4;
      // 本物のオッズと組み合わせて確かめるため、馬連・馬単・3連複・ワイドは期待値に関係なく確率0.3%以上を全部出す
      const c = cands.filter(x => x.type === "単勝" || x.type === "複勝" || (x.type !== "3連単" && x.p >= 0.003) || (x.ev >= 0.9 && x.p >= 0.004)).map(x => [x.type, key(x), r4(x.p), x.odds]);
      const picks = {};
      for (const st of ["safe", "balance", "big"]) for (const ev of ["1.0", "1.1", "1.3"]) {
        picks[st + ev] = pickBets(cands, st, ev).good.map(x => [x.type, key(x), r4(x.p), x.odds, x.cover ? 1 : 0]);
      }
      lines.push(JSON.stringify({ id: d.id, date: d.date, place: d.place, cls: d.cls, surface: d.surface, u: U,
        rank: horses.map((h, i) => Number(d.horses[roster.indexOf(h)].rank)), odds: horses.map(h => h.odds),
        win: (s.target || s.win).map(r4), top3: s.top3.map(r4), c, picks }));
    } catch (e) { lines.push(JSON.stringify({ id: d.id, error: String(e) })); }
  }
  return lines;
}

if (isMainThread) {
  const [core, data, out] = process.argv.slice(2);
  const src = fs.readFileSync(data, "utf8");
  const DATA = JSON.parse(src.slice(src.indexOf("=") + 1, src.lastIndexOf(";")));
  const W = Math.max(1, Math.min(os.cpus().length - 1, 8)), n = Math.ceil(DATA.length / W);
  const parts = [];
  for (let w = 0; w < W; w++) {
    parts.push(new Promise((ok, ng) => {
      const t = new Worker(__filename, { workerData: { core, DATA: DATA.slice(w * n, (w + 1) * n) } });
      t.once("message", ok); t.once("error", ng);
    }));
  }
  Promise.all(parts).then(rs => {
    const lines = rs.flat();
    fs.writeFileSync(out, lines.length ? lines.join("\n") + "\n" : "");
  }, e => { console.error(e); process.exit(1); });
} else {
  // ブラウザの画面に関わる名前は、計算に使わない形だけ置いておく
  const prelude = `let race, roster, horses, settings, autoData = null;
    function dateLong() { return ""; }
    function horseProfile() { return {}; }
    function bloodTypes() { return { sire: "", dam: "" }; }`;
  // vm.createContext の別の場所で動かすと関数の呼び出しがとても遅くなるので、このワーカーの中でそのまま動かす
  globalThis.DATA = workerData.DATA;
  parentPort.postMessage(vm.runInThisContext([prelude, fs.readFileSync(workerData.core, "utf8"), runRange.toString(), "runRange(DATA)"].join("\n")));
}
