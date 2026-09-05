/**
 * deck-lib.js — biblioteca reutilizável de slides PPTX no padrão visual PX.
 *
 * Uso (o caller passa o pptxgenjs já resolvido do seu node_modules):
 *
 *   const Pptx = require('/abs/path/node_modules/pptxgenjs');
 *   const { makeDeck } = require('/abs/path/.claude/skills/px-deck/assets/deck-lib.js');
 *   const deck = makeDeck(Pptx, { logoPath: '/abs/logo-px.png', title: '...' });
 *   deck.cover({ label:'...', title:'...', subtitle:'...', infoBoxes:[['PARA','...']] });
 *   deck.footer(deck.section('01', 'Seção', 'sub'));   // seção numerada
 *   deck.shot({ title, subtitle, img:'/abs/shot.png', bullets:[...] });
 *   await deck.save('/abs/out.pptx');
 *
 * REGRA DURA: todo texto de prosa em Português BR com acentuação correta
 * (á é í ó ú ã õ ç â ê ô à). NÃO usar travessão (—): dois-pontos, vírgula ou parênteses.
 * Blocos de comando de terminal podem ficar sem acento (mimicam input real).
 */

const THEMES = {
  px: {
    navy: '1E3A5F', navyDark: '15293F', navyCard: '243B57', amber: 'F0A500',
    white: 'FFFFFF', gray: '4A5568', lightGray: '94A3B8', muted: 'F5F7FA',
    green: '2E9E5B', red: 'D14343', border: 'E2E8F0', faintNum: '294565',
    coverSub: 'CBD5E1', codeBg: '15293F', codeText: 'D7E3F0',
  },
};

function makeDeck(Pptx, opts = {}) {
  const C = THEMES[opts.theme || 'px'];
  const FONT = opts.font || 'Arial';
  const MONO = 'Courier New';
  const W = 13.333, H = 7.5;
  const LOGO = opts.logoPath || null;
  const FOOTER = opts.footerText || 'PX Ativos Judiciais';

  const pptx = new Pptx();
  pptx.defineLayout({ name: 'PXW', width: W, height: H });
  pptx.layout = 'PXW';
  if (opts.author) pptx.author = opts.author;
  if (opts.company) pptx.company = opts.company;
  if (opts.title) pptx.title = opts.title;

  let page = 0;
  const S = pptx.ShapeType;

  function logoChip(s, x, y, size) {
    if (!LOGO) return;
    s.addShape(S.roundRect, { x, y, w: size, h: size, rectRadius: 0.09, fill: { color: C.white } });
    const p = size * 0.13;
    s.addImage({ path: LOGO, x: x + p, y: y + p, w: size - 2 * p, h: size - 2 * p });
  }

  function footer(s) {
    page++;
    s.addShape(S.rect, { x: 0, y: H - 0.34, w: W, h: 0.34, fill: { color: C.navy } });
    s.addText(FOOTER, { x: 0.5, y: H - 0.34, w: 9, h: 0.34, fontFace: FONT, fontSize: 9, color: C.white, valign: 'middle', transparency: 25 });
    s.addText(String(page), { x: W - 1.0, y: H - 0.34, w: 0.5, h: 0.34, fontFace: FONT, fontSize: 9, color: C.amber, align: 'right', valign: 'middle', bold: true });
    return s;
  }

  function header(s, title, subtitle) {
    s.addShape(S.rect, { x: 0, y: 0, w: W, h: 0.14, fill: { color: C.navy } });
    if (LOGO) {
      s.addImage({ path: LOGO, x: 0.46, y: 0.4, w: 0.64, h: 0.64 });
      s.addShape(S.rect, { x: 1.26, y: 0.46, w: 0.03, h: 0.62, fill: { color: C.amber } });
      s.addText(title, { x: 1.45, y: 0.42, w: W - 2.4, h: 0.5, fontFace: FONT, fontSize: 25, bold: true, color: C.navy, valign: 'middle' });
      if (subtitle) s.addText(subtitle, { x: 1.45, y: 1.0, w: W - 2.0, h: 0.4, fontFace: FONT, fontSize: 13, color: C.gray, valign: 'middle' });
    } else {
      s.addShape(S.roundRect, { x: 0.5, y: 0.5, w: 0.34, h: 0.34, rectRadius: 0.06, fill: { color: C.amber } });
      s.addText(title, { x: 1.0, y: 0.42, w: W - 2, h: 0.5, fontFace: FONT, fontSize: 25, bold: true, color: C.navy, valign: 'middle' });
      if (subtitle) s.addText(subtitle, { x: 1.0, y: 1.0, w: W - 1.6, h: 0.4, fontFace: FONT, fontSize: 13, color: C.gray, valign: 'middle' });
    }
    return s;
  }

  function bullets(s, arr, x, y, w, h, fs, color) {
    s.addText(arr.map((b) => ({
      text: typeof b === 'string' ? b : b.text,
      options: { bullet: { code: '2022', indent: 14 }, color: color || C.gray, fontSize: fs || 12.5, paraSpaceAfter: 9, fontFace: FONT, bold: typeof b === 'object' && b.bold },
    })), { x, y, w, h, valign: 'top' });
    return s;
  }

  // ---- high-level slide types ----

  function cover({ label, title, subtitle, infoBoxes = [] }) {
    const s = pptx.addSlide(); s.background = { color: C.navy };
    s.addShape(S.rect, { x: 0, y: 0, w: 3.6, h: 0.14, fill: { color: C.amber } });
    if (LOGO) logoChip(s, 0.7, 0.6, 1.15);
    if (label) s.addText(label, { x: 0.7, y: 2.15, w: 11.5, h: 0.4, fontFace: FONT, fontSize: 15, bold: true, color: C.amber, charSpacing: 3 });
    s.addText(title, { x: 0.66, y: 2.55, w: 12, h: 1.4, fontFace: FONT, fontSize: title.length > 22 ? 44 : 60, bold: true, color: C.white });
    s.addShape(S.rect, { x: 0.74, y: 4.05, w: 1.4, h: 0.045, fill: { color: C.amber } });
    if (subtitle) s.addText(subtitle, { x: 0.7, y: 4.25, w: 11.7, h: 0.9, fontFace: FONT, fontSize: 16, color: C.coverSub });
    infoBoxes.slice(0, 3).forEach((b, i) => {
      const x = 0.7 + i * 3.95;
      s.addShape(S.roundRect, { x, y: 5.65, w: 3.7, h: 1.0, rectRadius: 0.06, fill: { color: C.navyCard } });
      s.addText(b[0], { x: x + 0.25, y: 5.8, w: 3.2, h: 0.3, fontFace: FONT, fontSize: 10, bold: true, color: C.amber, charSpacing: 2 });
      s.addText(b[1], { x: x + 0.25, y: 6.12, w: 3.3, h: 0.45, fontFace: FONT, fontSize: 13.5, color: C.white });
    });
    return s;
  }

  function section(num, title, sub) {
    const s = pptx.addSlide(); s.background = { color: C.navy };
    if (LOGO) logoChip(s, 0.7, 0.5, 0.92);
    s.addText(num, { x: 0.7, y: 1.4, w: 6, h: 2.6, fontFace: FONT, fontSize: 140, bold: true, color: C.faintNum });
    s.addText(title, { x: 0.74, y: 4.0, w: 11.8, h: 1.0, fontFace: FONT, fontSize: 40, bold: true, color: C.white });
    s.addShape(S.rect, { x: 0.78, y: 5.0, w: 1.4, h: 0.05, fill: { color: C.amber } });
    if (sub) s.addText(sub, { x: 0.74, y: 5.2, w: 11.7, h: 0.8, fontFace: FONT, fontSize: 16, color: C.coverSub });
    return s;
  }

  // frase de impacto sobre fundo navy
  function statement({ label, big, sub }) {
    const s = pptx.addSlide(); s.background = { color: C.navy };
    s.addShape(S.rect, { x: 0, y: 0, w: 3.6, h: 0.14, fill: { color: C.amber } });
    if (LOGO) logoChip(s, 0.7, 0.55, 0.9);
    if (label) s.addText(label, { x: 0.7, y: 2.0, w: 11.5, h: 0.4, fontFace: FONT, fontSize: 14, bold: true, color: C.amber, charSpacing: 2 });
    s.addText(big, { x: 0.66, y: 2.5, w: 12, h: 2.4, fontFace: FONT, fontSize: 34, bold: true, color: C.white, valign: 'top' });
    if (sub) s.addText(sub, { x: 0.7, y: 5.4, w: 11.7, h: 1.0, fontFace: FONT, fontSize: 16, color: C.coverSub });
    footer(s);
    return s;
  }

  // screenshot grande à esquerda + bullets à direita
  function shot({ title, subtitle, img, bullets: bl = [] }) {
    const s = pptx.addSlide(); s.background = { color: C.white };
    header(s, title, subtitle);
    const iw = 8.55, ih = iw * 900 / 1440, ix = 0.5, iy = 1.55;
    s.addShape(S.rect, { x: ix - 0.04, y: iy - 0.04, w: iw + 0.08, h: ih + 0.08, fill: { color: C.border } });
    s.addImage({ path: img, x: ix, y: iy, w: iw, h: ih, shadow: { type: 'outer', color: '9AA5B1', blur: 6, offset: 3, angle: 90, opacity: 0.4 } });
    const cx = 9.35;
    s.addShape(S.roundRect, { x: cx, y: 1.55, w: 3.45, h: ih + 0.08, rectRadius: 0.06, fill: { color: C.muted }, line: { color: C.border, width: 1 } });
    if (bl.length) bullets(s, bl, cx + 0.25, 1.75, 2.95, ih - 0.2, 12.5);
    footer(s);
    return s;
  }

  // screenshot em destaque, centralizado (sem bullets) — bom p/ board.
  // Dimensiona pela ALTURA disponível (entre header e footer) p/ nunca estourar o slide.
  // aspect = largura/altura natural do print (default 1440/900 = 16:10).
  function showcase({ title, subtitle, img, caption, aspect = 1440 / 900 }) {
    const s = pptx.addSlide(); s.background = { color: C.white };
    header(s, title, subtitle);
    const maxH = caption ? 4.55 : 4.95, maxW = 11.6, iy = 1.62;
    let ih = maxH, iw = ih * aspect;
    if (iw > maxW) { iw = maxW; ih = iw / aspect; }
    const ix = (W - iw) / 2;
    s.addShape(S.rect, { x: ix - 0.04, y: iy - 0.04, w: iw + 0.08, h: ih + 0.08, fill: { color: C.border } });
    s.addImage({ path: img, x: ix, y: iy, w: iw, h: ih, shadow: { type: 'outer', color: '9AA5B1', blur: 7, offset: 3, angle: 90, opacity: 0.4 } });
    if (caption) s.addText(caption, { x: 0.7, y: iy + ih + 0.14, w: 12, h: 0.38, fontFace: FONT, fontSize: 13, italic: true, color: C.navy, align: 'center' });
    footer(s);
    return s;
  }

  // antes/depois: dois painéis (passado cinza > presente navy) com seta entre eles.
  // left/right = { head, sub?, bullets:[...] }
  function beforeAfter({ title, subtitle, left, right, note }) {
    const s = pptx.addSlide(); s.background = { color: C.white };
    header(s, title, subtitle);
    const ly = 1.7, ph = note ? 4.45 : 4.75, pw = 5.5;
    [{ p: left, x: 0.6, hc: '7A8794' }, { p: right, x: 7.23, hc: C.navy }].forEach(({ p, x, hc }) => {
      s.addShape(S.roundRect, { x, y: ly, w: pw, h: ph, rectRadius: 0.08, fill: { color: C.white }, line: { color: C.border, width: 1 } });
      s.addShape(S.rect, { x, y: ly, w: pw, h: 0.66, fill: { color: hc } });
      s.addText(p.head, { x: x + 0.25, y: ly, w: pw - 0.5, h: 0.66, fontFace: FONT, fontSize: 16, bold: true, color: C.white, valign: 'middle' });
      let by = ly + 0.82;
      if (p.sub) { s.addText(p.sub, { x: x + 0.25, y: by, w: pw - 0.5, h: 0.4, fontFace: FONT, fontSize: 12.5, italic: true, color: C.gray }); by += 0.5; }
      bullets(s, p.bullets, x + 0.25, by, pw - 0.5, ly + ph - by - 0.2, 12.5);
    });
    s.addShape(S.rightArrow, { x: 6.2, y: ly + ph / 2 - 0.28, w: 0.86, h: 0.56, fill: { color: C.amber } });
    if (note) s.addText(note, { x: 0.6, y: ly + ph + 0.18, w: 12.13, h: 0.45, fontFace: FONT, fontSize: 12.5, italic: true, color: C.navy, align: 'center' });
    footer(s);
    return s;
  }

  // diagrama (imagem) wide no topo + bullets abaixo, ou side
  function diagram({ title, subtitle, img, natW, natH, bullets: bl = [], layout = 'wide', imgW }) {
    const s = pptx.addSlide(); s.background = { color: C.white };
    header(s, title, subtitle);
    if (layout === 'side') {
      const h = 4.8, w = h * natW / natH, x = 0.7, y = 1.7;
      s.addImage({ path: img, x, y, w, h });
      if (bl.length) bullets(s, bl, x + w + 0.5, 1.9, W - (x + w + 0.5) - 0.6, 4.6, 13);
    } else {
      const w = imgW || 12.0, h = w * natH / natW, x = (W - w) / 2, y = 1.62;
      s.addImage({ path: img, x, y, w, h });
      if (bl.length) bullets(s, bl, 0.7, y + h + 0.25, 12.0, 6.9 - (y + h + 0.25), 13);
    }
    footer(s);
    return s;
  }

  // grid de métricas (cards navy, valor branco grande, label âmbar)
  function metrics({ title, subtitle, items = [], note }) {
    const s = pptx.addSlide(); s.background = { color: C.white };
    header(s, title, subtitle);
    const n = items.length, gap = 0.3, total = 12.13, cw = (total - gap * (n - 1)) / n;
    items.forEach((it, i) => {
      const x = 0.6 + i * (cw + gap);
      s.addShape(S.roundRect, { x, y: 2.0, w: cw, h: 3.0, rectRadius: 0.08, fill: { color: C.navy } });
      s.addText(String(it[0]), { x, y: 2.5, w: cw, h: 1.2, fontFace: FONT, fontSize: 46, bold: true, color: C.white, align: 'center', valign: 'middle' });
      s.addText(it[1], { x: x + 0.2, y: 3.7, w: cw - 0.4, h: 1.1, fontFace: FONT, fontSize: 14, color: C.amber, align: 'center', valign: 'top' });
    });
    if (note) s.addText(note, { x: 0.6, y: 5.5, w: 12.1, h: 0.7, fontFace: FONT, fontSize: 13, italic: true, color: C.navy, align: 'center' });
    footer(s);
    return s;
  }

  // cards (2-4 colunas): cada item [head, body, headColor?]
  function cards({ title, subtitle, items = [], note }) {
    const s = pptx.addSlide(); s.background = { color: C.white };
    header(s, title, subtitle);
    const n = items.length, gap = 0.32, total = 12.13, cw = (total - gap * (n - 1)) / n;
    items.forEach((it, i) => {
      const x = 0.6 + i * (cw + gap);
      const hc = it[2] || C.navy;
      s.addShape(S.rect, { x, y: 1.7, w: cw, h: 0.62, fill: { color: hc } });
      s.addText(it[0], { x: x + 0.22, y: 1.7, w: cw - 0.4, h: 0.62, fontFace: FONT, fontSize: 15, bold: true, color: hc === C.amber ? C.navy : C.white, valign: 'middle' });
      s.addShape(S.rect, { x, y: 2.32, w: cw, h: 4.0, fill: { color: C.muted }, line: { color: C.border, width: 1 } });
      s.addText(it[1], { x: x + 0.24, y: 2.5, w: cw - 0.46, h: 3.7, fontFace: FONT, fontSize: 13, color: C.gray, valign: 'top', lineSpacingMultiple: 1.1 });
    });
    if (note) s.addText(note, { x: 0.6, y: 6.5, w: 12.1, h: 0.35, fontFace: FONT, fontSize: 12, italic: true, color: C.navy });
    footer(s);
    return s;
  }

  // passos numerados (não-técnico): item [num, head, body]
  function steps({ title, subtitle, items = [], note }) {
    const s = pptx.addSlide(); s.background = { color: C.white };
    header(s, title, subtitle);
    const n = items.length, gap = 0.4, total = 12.13, cw = (total - gap * (n - 1)) / n;
    items.forEach((it, i) => {
      const x = 0.6 + i * (cw + gap);
      s.addShape(S.ellipse, { x: x + cw / 2 - 0.45, y: 1.9, w: 0.9, h: 0.9, fill: { color: C.amber } });
      s.addText(String(it[0]), { x: x + cw / 2 - 0.45, y: 1.9, w: 0.9, h: 0.9, fontFace: FONT, fontSize: 30, bold: true, color: C.navy, align: 'center', valign: 'middle' });
      s.addText(it[1], { x, y: 3.0, w: cw, h: 0.6, fontFace: FONT, fontSize: 17, bold: true, color: C.navy, align: 'center' });
      s.addText(it[2], { x: x + 0.1, y: 3.65, w: cw - 0.2, h: 2.2, fontFace: FONT, fontSize: 13, color: C.gray, align: 'center', valign: 'top', lineSpacingMultiple: 1.1 });
      if (i < n - 1) s.addText('>', { x: x + cw + gap / 2 - 0.15, y: 1.95, w: 0.4, h: 0.8, fontFace: FONT, fontSize: 26, bold: true, color: C.lightGray, align: 'center', valign: 'middle' });
    });
    if (note) s.addText(note, { x: 0.6, y: 6.3, w: 12.1, h: 0.5, fontFace: FONT, fontSize: 13, italic: true, color: C.navy, align: 'center' });
    footer(s);
    return s;
  }

  // citação / destaque
  function quote({ title, subtitle, quote: q, author, bullets: bl }) {
    const s = pptx.addSlide(); s.background = { color: C.white };
    header(s, title, subtitle);
    s.addShape(S.rect, { x: 0.6, y: 1.8, w: 0.08, h: 1.7, fill: { color: C.amber } });
    s.addText(q, { x: 0.95, y: 1.8, w: 11.5, h: 1.5, fontFace: FONT, fontSize: 22, italic: true, color: C.navy, valign: 'top' });
    if (author) s.addText(author, { x: 0.95, y: 3.35, w: 11, h: 0.4, fontFace: FONT, fontSize: 13, color: C.gray });
    if (bl && bl.length) bullets(s, bl, 0.95, 4.0, 11.5, 2.6, 14);
    footer(s);
    return s;
  }

  // slide de conteúdo custom: retorna o slide com header; caller adiciona conteúdo e chama deck.footer(s)
  function contentSlide(title, subtitle) {
    const s = pptx.addSlide(); s.background = { color: C.white };
    header(s, title, subtitle);
    return s;
  }

  function closing({ label, title, subtitle, refs = [], note }) {
    const s = pptx.addSlide(); s.background = { color: C.navy };
    s.addShape(S.rect, { x: 0, y: 0, w: 3.6, h: 0.14, fill: { color: C.amber } });
    if (LOGO) logoChip(s, 0.7, 0.55, 0.95);
    if (label) s.addText(label, { x: 0.7, y: 1.9, w: 11.5, h: 0.4, fontFace: FONT, fontSize: 14, bold: true, color: C.amber, charSpacing: 2 });
    s.addText(title, { x: 0.7, y: 2.3, w: 12, h: 1.1, fontFace: FONT, fontSize: title.length > 24 ? 38 : 44, bold: true, color: C.white });
    s.addShape(S.rect, { x: 0.74, y: 3.55, w: 1.4, h: 0.05, fill: { color: C.amber } });
    if (subtitle) s.addText(subtitle, { x: 0.7, y: 3.8, w: 11.4, h: 1.0, fontFace: FONT, fontSize: 16, color: C.coverSub });
    refs.slice(0, 3).forEach((b, i) => {
      const x = 0.7 + i * 3.95;
      s.addShape(S.roundRect, { x, y: 5.1, w: 3.7, h: 1.0, rectRadius: 0.06, fill: { color: C.navyCard } });
      s.addText(b[0], { x: x + 0.25, y: 5.25, w: 3.2, h: 0.3, fontFace: FONT, fontSize: 10, bold: true, color: C.amber, charSpacing: 2 });
      s.addText(b[1], { x: x + 0.25, y: 5.56, w: 3.3, h: 0.5, fontFace: FONT, fontSize: 12, color: C.white });
    });
    if (note) s.addText(note, { x: 0.7, y: 6.5, w: 11, h: 0.4, fontFace: FONT, fontSize: 11, italic: true, color: C.lightGray });
    return s;
  }

  async function save(file) { await pptx.writeFile({ fileName: file }); return { file, slides: page }; }

  return { pptx, C, FONT, MONO, W, H, S, logoChip, footer, header, bullets, cover, section, statement, shot, showcase, beforeAfter, diagram, metrics, cards, steps, quote, contentSlide, closing, save };
}

module.exports = { makeDeck, THEMES };
