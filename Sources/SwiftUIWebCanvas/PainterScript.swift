/// The Canvas2D decoder for `DisplayListEncoder`'s flat format, injected into the page once.
/// Kept as a Swift string so an app needs nothing but its wasm bundle. Opcodes must match
/// `DisplayOp` / `DisplayPathOp` in SwiftUIWebCore.
enum PainterScript {
    static let source = #"""
    (function () {
      if (window.__swiftuiweb) return;
      const colorCache = new Map();
      function color(r, g, b, a) {
        const k = r + ',' + g + ',' + b + ',' + a;
        let s = colorCache.get(k);
        if (!s) { s = 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')'; colorCache.set(k, s); }
        return s;
      }
      function readPath(ctx, buf, i) {
        const count = buf[i++];
        ctx.beginPath();
        for (let k = 0; k < count; k++) {
          const tag = buf[i++];
          switch (tag) {
            case 0: ctx.moveTo(buf[i++], buf[i++]); break;
            case 1: ctx.lineTo(buf[i++], buf[i++]); break;
            case 2: { const x = buf[i++], y = buf[i++], cx = buf[i++], cy = buf[i++]; ctx.quadraticCurveTo(cx, cy, x, y); break; }
            case 3: { const x = buf[i++], y = buf[i++], c1x = buf[i++], c1y = buf[i++], c2x = buf[i++], c2y = buf[i++]; ctx.bezierCurveTo(c1x, c1y, c2x, c2y, x, y); break; }
            case 4: ctx.closePath(); break;
          }
        }
        return i;
      }
      function paint(rootCtx, buf, strings, dpr, w, h) {
        rootCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
        rootCtx.clearRect(0, 0, w, h);
        rootCtx.textBaseline = 'alphabetic';
        let ctx = rootCtx;
        const groups = [];
        let i = 0;
        const n = buf.length;
        while (i < n) {
          const op = buf[i++];
          switch (op) {
            case 1: ctx.save(); break;
            case 2: ctx.restore(); break;
            case 3: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++]; ctx.beginPath(); ctx.rect(x, y, rw, rh); ctx.clip(); break; }
            case 4: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++], r = buf[i++]; ctx.beginPath(); ctx.roundRect(x, y, rw, rh, r); ctx.clip(); break; }
            case 5: { i = readPath(ctx, buf, i); ctx.clip(); break; }
            case 6: {
              const opacity = buf[i++];
              const off = new OffscreenCanvas(Math.max(1, Math.round(w * dpr)), Math.max(1, Math.round(h * dpr)));
              const octx = off.getContext('2d');
              octx.setTransform(dpr, 0, 0, dpr, 0, 0);
              octx.textBaseline = 'alphabetic';
              groups.push({ ctx: ctx, off: off, opacity: opacity });
              ctx = octx;
              break;
            }
            case 7: {
              const g = groups.pop();
              const parent = g.ctx;
              parent.save();
              parent.globalAlpha = g.opacity;
              parent.setTransform(1, 0, 0, 1, 0, 0);
              parent.drawImage(g.off, 0, 0);
              parent.restore();
              ctx = parent;
              break;
            }
            case 8: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++]; ctx.fillStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]); ctx.fillRect(x, y, rw, rh); break; }
            case 9: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++], r = buf[i++]; ctx.fillStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]); ctx.beginPath(); ctx.roundRect(x, y, rw, rh, r); ctx.fill(); break; }
            case 10: { i = readPath(ctx, buf, i); ctx.fillStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]); ctx.fill(); break; }
            case 11: { i = readPath(ctx, buf, i); ctx.lineWidth = buf[i++]; ctx.strokeStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]); ctx.stroke(); break; }
            case 12: {
              const text = strings[buf[i++]], font = strings[buf[i++]], x = buf[i++], y = buf[i++];
              ctx.fillStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]);
              ctx.font = font;
              ctx.fillText(text, x, y);
              break;
            }
            default: throw new Error('SwiftUIWeb: unknown display op ' + op + ' at ' + (i - 1));
          }
        }
      }
      const measureCache = new Map();
      function measure(ctx, font, text) {
        const k = font + ' ' + text;
        let w = measureCache.get(k);
        if (w === undefined) { ctx.font = font; w = ctx.measureText(text).width; measureCache.set(k, w); }
        return w;
      }
      window.__swiftuiweb = { paint: paint, measure: measure, version: 1 };
    })();
    """#
}
