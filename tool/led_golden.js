// Dumps the reference layout (tool/led_reference.js, copied unchanged from the
// design handoff) as dot lists, for test/led_layout_test.dart.
//   node tool/led_golden.js > test/fixtures/led_golden.json
const fs = require('fs');
const path = require('path');
const ref = require('./led_reference.js');

// The JSON font shipped in assets/ must be the reference font.
const font = JSON.parse(fs.readFileSync(path.join(__dirname, '../assets/led_font.json'), 'utf8'));
for (const ch of 'ABCDEFGHIJKLMNOPQRSTUVWXYZĐ0123456789 -.:/ČĆŠŽ') {
  const g = ref.glyph(ch);
  let rows;
  if (font.composed[ch]) {
    const [base, acc] = font.composed[ch];
    rows = [...font.accents[acc], ...font.glyphs[base]];
  } else {
    const b = font.glyphs[ch];
    rows = ['.'.repeat(b[0].length), '.'.repeat(b[0].length), ...b];
  }
  if (JSON.stringify(rows) !== JSON.stringify(g.rows)) {
    throw new Error(`font mismatch for ${ch}`);
  }
}

const cases = [
  // README §6
  { line: '6', dest: 'Črnomerec', cols: 176, time: 'STIŽE' },
  { line: '220', dest: 'Dugave', cols: 150 },
  { line: '234', dest: 'Glavni kolodvor - Kajzerica - Lanište', cols: 150 },
  { line: '132', dest: 'Savski most - Goli breg - Brezovica', cols: 118 },
  // „Pravila natpisa“ and settings preview
  { line: '12', dest: 'Dubrava', cols: 150 },
  { line: '6', dest: 'Sopot', cols: 110 },
  { line: '6', dest: 'Sopot', cols: 64 },
  // Variant 1b rows
  { line: '234', dest: 'Glavni kolodvor - Kajzerica - Lanište', cols: 176, time: '3 MIN' },
  { line: '13', dest: 'Kvaternikov trg', cols: 176, time: '4 MIN' },
  { line: '268', dest: 'Velika Gorica', cols: 176, time: '9 MIN' },
  { line: '4', dest: 'Savski most', cols: 176, time: '10:06' },
  { line: '9', dest: 'Ljubljanica', cols: 176, time: '10:09' },
  // Narrow phone, Đ, a lone long word
  { line: '6', dest: 'Črnomerec', cols: 120, time: 'STIŽE' },
  { line: '109', dest: 'Đurđekovec', cols: 140, time: '12 MIN' },
  { line: '311', dest: 'Mihaljevac-Gračansko Dolje', cols: 120, time: '23:59' },
];

const pts = (svg) =>
  [...svg.matchAll(/<circle cx="([\d.]+)" cy="([\d.]+)" r=".4"\/>/g)].map((m) => [
    Math.round(+m[1] - 0.5),
    Math.round(+m[2] - 0.5),
  ]);

const out = cases.map((c) => {
  const p = ref.panel({ ...c, color: '#fff', marquee: false, glow: false });
  const svg = decodeURIComponent(p.src.slice('data:image/svg+xml;utf8,'.length));
  const body = svg.slice(svg.indexOf('</defs>'));
  // Split: static dots, then the time block, then one block per clipped line.
  const clips = [...body.matchAll(/<clipPath id="c\d+"><rect x="(\d+)" y="(\d+)" width="(-?\d+)" height="9"\/><\/clipPath>([\s\S]*?)<\/g><\/g><\/g>/g)];
  let rest = body;
  const marquees = clips.map((m) => {
    rest = rest.replace(m[0], '');
    return { x0: +m[1], y: +m[2], avail: +m[3], dots: pts(m[4]).map(([x, y]) => [x, y]) };
  });
  let timeDots = [];
  if (c.time) {
    const tw = ref.measure(c.time, 'tall');
    const td = [];
    ref.draw(td, c.time, c.cols - tw, 0, 'tall');
    timeDots = td;
  }
  const all = pts(rest);
  const timeSet = new Set(timeDots.map((d) => d.join(',')));
  const fixed = all.filter((d) => !timeSet.has(d.join(',')));
  const sort = (a) => a.sort((p, q) => p[1] - q[1] || p[0] - q[0]);
  return {
    ...c,
    dots: sort(fixed),
    time_dots: sort(timeDots),
    marquees: marquees.map((m) => ({ ...m, dots: sort(m.dots) })),
  };
});
process.stdout.write(JSON.stringify(out) + '\n');
