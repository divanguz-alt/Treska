// Referentna implementacija iz prototipa (JS -> SVG). Prenesi logiku u Kotlin; SVG izlaz nije potreban.
// panel({ line, dest, cols, color, pitch, time, blink, marquee, glow }) -> { src, w, h, alt }
const G = {
A:[".###.","#...#","#...#","#####","#...#","#...#","#...#"],B:["####.","#...#","#...#","####.","#...#","#...#","####."],
C:[".###.","#...#","#....","#....","#....","#...#",".###."],D:["####.","#...#","#...#","#...#","#...#","#...#","####."],
E:["#####","#....","#....","####.","#....","#....","#####"],F:["#####","#....","#....","####.","#....","#....","#...."],
G:[".###.","#...#","#....","#.###","#...#","#...#",".####"],H:["#...#","#...#","#...#","#####","#...#","#...#","#...#"],
I:["###",".#.",".#.",".#.",".#.",".#.","###"],J:["..###","...#.","...#.","...#.","...#.","#..#.",".##.."],
K:["#...#","#..#.","#.#..","##...","#.#..","#..#.","#...#"],L:["#....","#....","#....","#....","#....","#....","#####"],
M:["#...#","##.##","#.#.#","#.#.#","#...#","#...#","#...#"],N:["#...#","#...#","##..#","#.#.#","#..##","#...#","#...#"],
O:[".###.","#...#","#...#","#...#","#...#","#...#",".###."],P:["####.","#...#","#...#","####.","#....","#....","#...."],
Q:[".###.","#...#","#...#","#...#","#.#.#","#..#.",".##.#"],R:["####.","#...#","#...#","####.","#.#..","#..#.","#...#"],
S:[".####","#....","#....",".###.","....#","....#","####."],T:["#####","..#..","..#..","..#..","..#..","..#..","..#.."],
U:["#...#","#...#","#...#","#...#","#...#","#...#",".###."],V:["#...#","#...#","#...#","#...#","#...#",".#.#.","..#.."],
W:["#...#","#...#","#...#","#.#.#","#.#.#","#.#.#",".#.#."],X:["#...#","#...#",".#.#.","..#..",".#.#.","#...#","#...#"],
Y:["#...#","#...#",".#.#.","..#..","..#..","..#..","..#.."],Z:["#####","....#","...#.","..#..",".#...","#....","#####"],
'Đ':["####.",".#..#",".#..#","###.#",".#..#",".#..#","####."],
'0':[".###.","#...#","#..##","#.#.#","##..#","#...#",".###."],'1':["..#..",".##..","..#..","..#..","..#..","..#..",".###."],
'2':[".###.","#...#","....#","...#.","..#..",".#...","#####"],'3':["#####","...#.","..#..","...#.","....#","#...#",".###."],
'4':["...#.","..##.",".#.#.","#..#.","#####","...#.","...#."],'5':["#####","#....","####.","....#","....#","#...#",".###."],
'6':["..##.",".#...","#....","####.","#...#","#...#",".###."],'7':["#####","....#","...#.","..#..",".#...",".#...",".#..."],
'8':[".###.","#...#","#...#",".###.","#...#","#...#",".###."],'9':[".###.","#...#","#...#",".####","....#","...#.",".##.."],
' ':["...","...","...","...","...","...","..."],'-':["....","....","....","####","....","....","...."],
'.':[".",".",".",".",".",".","#"],':':[".",".","#",".","#",".","."],'/':["....#","...#.","...#.","..#..",".#...",".#...","#...."]
};
const CAR = [".#.#.","..#.."], ACU = ["...#.","..#.."];
const ACC = { 'Č':['C',CAR], 'Ć':['C',ACU], 'Š':['S',CAR], 'Ž':['Z',CAR] };
const LED = { lime:'#d4ef72', amber:'#ffb52e', orange:'#ff6a26', white:'#eef4ef' };
const ROWS_N = 18;

function glyph(ch) {
  let base = ch, top = null;
  if (ACC[ch]) { base = ACC[ch][0]; top = ACC[ch][1]; }
  const b = G[base] || G[' '];
  const w = b[0].length;
  return { w, rows: [...(top || ['.'.repeat(w), '.'.repeat(w)]), ...b] };
}
const SC = { small:[1,1,0], tall:[1,2,0], big:[2,2,2] }; // sx, sy, first source row
function measure(str, mode) {
  const sx = SC[mode][0]; const cs = [...str];
  return cs.reduce((a, c) => a + glyph(c).w * sx, 0) + Math.max(0, cs.length - 1) * sx;
}
function draw(out, str, x, y, mode) {
  const [sx, sy, r0] = SC[mode];
  for (const c of [...str]) {
    const g = glyph(c);
    for (let r = r0; r < 9; r++) for (let k = 0; k < g.w; k++) if (g.rows[r][k] === '#')
      for (let i = 0; i < sx; i++) for (let j = 0; j < sy; j++) out.push([x + k * sx + i, y + (r - r0) * sy + j]);
    x += (g.w + 1) * sx;
  }
}
const circ = (d) => d.map(([x, y]) => `<circle cx="${x + .5}" cy="${y + .5}" r=".4"/>`).join('');
function splitDest(s) {
  let best = [s], bw = measure(s, 'small');
  [...s].forEach((c, i) => {
    let a, b;
    if (c === ' ') { a = s.slice(0, i); b = s.slice(i + 1); }
    else if (c === '-') { a = s.slice(0, i + 1); b = s.slice(i + 1); }
    else return;
    const w = Math.max(measure(a, 'small'), measure(b, 'small'));
    if (w < bw) { bw = w; best = [a, b]; }
  });
  return best;
}
let uid = 0;
function panel({ line, dest, cols, color, pitch = 2, time = null, blink = false, marquee = true, glow = true }) {
  const lit = [], extra = [];
  const D = dest.toUpperCase();
  let content = cols;
  if (time) {
    const tw = measure(time, 'tall'); content = cols - tw - 6;
    const td = []; draw(td, time, cols - tw, 0, 'tall');
    extra.push(blink ? `<g>${circ(td)}<animate attributeName="opacity" values="1;.12" keyTimes="0;.62" dur="1.2s" calcMode="discrete" repeatCount="indefinite"/></g>` : circ(td));
  }
  const nT = measure(line, 'tall'), dT = measure(D, 'tall');
  if (nT + 6 + dT <= content) {
    draw(lit, line, 0, 0, 'tall');
    draw(lit, D, nT + 6 + Math.floor((content - nT - 6 - dT) / 2), 0, 'tall');
  } else {
    const nB = measure(line, 'big'); draw(lit, line, 0, 2, 'big');
    const x0 = nB + 5, avail = content - x0;
    const lines = splitDest(D.replace(/\s*-\s*/g, '-'));
    lines.forEach((ln, i) => {
      const y = lines.length === 1 ? 4 : i * 9, w = measure(ln, 'small');
      if (w <= avail) { draw(lit, ln, x0 + Math.floor((avail - w) / 2), y, 'small'); return; }
      const id = 'c' + (uid++), gap = 14, L = w + gap, v = 22, p = 1.5;
      const d = []; draw(d, ln, 0, y, 'small'); if (marquee) draw(d, ln, L, y, 'small');
      let anim = '';
      if (marquee) {
        const dur = p + (L + 1) / v, vals = ['0 0'], kt = ['0'];
        for (let k = 0; k <= L; k++) { vals.push(`${-k} 0`); kt.push(((p + k / v) / dur).toFixed(4)); }
        anim = `<animateTransform attributeName="transform" type="translate" calcMode="discrete" values="${vals.join(';')}" keyTimes="${kt.join(';')}" dur="${dur.toFixed(2)}s" repeatCount="indefinite"/>`;
      }
      extra.push(`<clipPath id="${id}"><rect x="${x0}" y="${y}" width="${avail}" height="9"/></clipPath><g clip-path="url(#${id})"><g transform="translate(${x0} 0)"><g>${anim}${circ(d)}</g></g></g>`);
    });
  }
  const W = cols, H = ROWS_N;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W * pitch}" height="${H * pitch}"><defs><pattern id="u" width="1" height="1" patternUnits="userSpaceOnUse"><circle cx=".5" cy=".5" r=".4" fill="${color}" fill-opacity=".09"/></pattern>${glow ? '<filter id="g" x="-5%" y="-20%" width="110%" height="140%"><feGaussianBlur stdDeviation=".55" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>' : ''}</defs><rect width="${W}" height="${H}" fill="url(#u)"/><g fill="${color}"${glow ? ' filter="url(#g)"' : ''}>${circ(lit)}${extra.join('')}</g></svg>`;
  return { src: 'data:image/svg+xml;utf8,' + encodeURIComponent(svg), w: W * pitch, h: H * pitch, alt: `${line} ${dest}` };
}


if (typeof module !== 'undefined') module.exports = { panel, measure, draw, splitDest, glyph, LED };
