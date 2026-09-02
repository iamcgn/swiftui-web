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
      const lineCaps = ['butt', 'round', 'square'];
      const lineJoins = ['miter', 'round', 'bevel'];
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
      // Catalog images by file, loaded on first use; the host is told when one arrives so it
      // can paint again. `base` comes from the manifest script (window.__swiftuiwebAssets).
      const images = new Map();
      let pending = 0;
      let onImageLoad = null;
      function image(file) {
        let entry = images.get(file);
        if (entry) return entry.ready ? entry.img : null;
        const img = new Image();
        entry = { img: img, ready: false };
        images.set(file, entry);
        pending++;
        const done = () => { pending--; if (onImageLoad) onImageLoad(file, entry.ready); };
        img.onload = () => { entry.ready = true; done(); };
        img.onerror = () => { console.error('SwiftUIWeb: could not load image ' + file); done(); };
        const base = (window.__swiftuiwebAssets && window.__swiftuiwebAssets.base) || '';
        img.src = base + file;
        return null;
      }
      // Draws `img` (or one part of it) tinted: the image's alpha filled with `tint`.
      function tinted(img, sx, sy, sw, sh, dw, dh, dpr, tint, smoothing) {
        const pw = Math.max(1, Math.round(dw * dpr)), ph = Math.max(1, Math.round(dh * dpr));
        const off = new OffscreenCanvas(pw, ph);
        const octx = off.getContext('2d');
        octx.imageSmoothingEnabled = smoothing;
        octx.drawImage(img, sx, sy, sw, sh, 0, 0, pw, ph);
        octx.globalCompositeOperation = 'source-in';
        octx.fillStyle = tint;
        octx.fillRect(0, 0, pw, ph);
        return off;
      }
      // One part of a draw: source rect in image pixels, destination in points, stretched or tiled.
      function part(ctx, img, sx, sy, sw, sh, dx, dy, dw, dh, tile, scale, dpr, tint, smoothing) {
        if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
        if (tile) {
          const tw = sw / scale, th = sh / scale;
          ctx.save();
          ctx.beginPath(); ctx.rect(dx, dy, dw, dh); ctx.clip();
          for (let y = dy; y < dy + dh; y += th) {
            for (let x = dx; x < dx + dw; x += tw) {
              if (tint) { ctx.drawImage(tinted(img, sx, sy, sw, sh, tw, th, dpr, tint, smoothing), x, y, tw, th); }
              else { ctx.drawImage(img, sx, sy, sw, sh, x, y, tw, th); }
            }
          }
          ctx.restore();
        } else if (tint) {
          ctx.drawImage(tinted(img, sx, sy, sw, sh, dw, dh, dpr, tint, smoothing), dx, dy, dw, dh);
        } else {
          ctx.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh);
        }
      }
      function drawImage(ctx, dpr, file, scale, pw, ph, x, y, w, h, tile, top, leading, bottom, trailing, smoothing, tint) {
        const img = image(file);
        if (!img) return;
        const previous = ctx.imageSmoothingEnabled;
        ctx.imageSmoothingEnabled = smoothing;
        if (top === 0 && leading === 0 && bottom === 0 && trailing === 0) {
          part(ctx, img, 0, 0, pw, ph, x, y, w, h, tile, scale, dpr, tint, smoothing);
        } else {
          // Nine parts: rigid corners, edges stretched (or tiled) along one axis, the centre along both.
          const l = leading * scale, r = trailing * scale, t = top * scale, b = bottom * scale;
          const sxs = [0, l, pw - r], sws = [l, pw - l - r, r];
          const sys = [0, t, ph - b], shs = [t, ph - t - b, b];
          const dxs = [x, x + leading, x + w - trailing], dws = [leading, w - leading - trailing, trailing];
          const dys = [y, y + top, y + h - bottom], dhs = [top, h - top - bottom, bottom];
          for (let i = 0; i < 3; i++) {
            for (let j = 0; j < 3; j++) {
              const rigid = i !== 1 && j !== 1;
              part(ctx, img, sxs[i], sys[j], sws[i], shs[j], dxs[i], dys[j], dws[i], dhs[j], tile && !rigid, scale, dpr, tint, smoothing);
            }
          }
        }
        ctx.imageSmoothingEnabled = previous;
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
            case 5: { i = readPath(ctx, buf, i); ctx.clip(buf[i++] === 1 ? 'evenodd' : 'nonzero'); break; }
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
            case 10: { i = readPath(ctx, buf, i); ctx.fillStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]); ctx.fill(buf[i++] === 1 ? 'evenodd' : 'nonzero'); break; }
            case 11: {
              i = readPath(ctx, buf, i);
              ctx.lineWidth = buf[i++];
              ctx.lineCap = lineCaps[buf[i++]];
              ctx.lineJoin = lineJoins[buf[i++]];
              ctx.miterLimit = buf[i++];
              const dashCount = buf[i++];
              const dashes = [];
              for (let k = 0; k < dashCount; k++) dashes.push(buf[i++]);
              ctx.setLineDash(dashes);
              ctx.lineDashOffset = buf[i++];
              ctx.strokeStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]);
              ctx.stroke();
              break;
            }
            case 12: {
              const text = strings[buf[i++]], font = strings[buf[i++]], x = buf[i++], y = buf[i++];
              ctx.fillStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]);
              ctx.font = font;
              ctx.fillText(text, x, y);
              break;
            }
            case 13: {
              const file = strings[buf[i++]], scale = buf[i++], pw = buf[i++], ph = buf[i++];
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              const tile = buf[i++] === 1, top = buf[i++], leading = buf[i++], bottom = buf[i++], trailing = buf[i++];
              const smoothing = buf[i++] === 1, hasTint = buf[i++] === 1;
              const tint = color(buf[i++], buf[i++], buf[i++], buf[i++]);
              drawImage(ctx, dpr, file, scale, pw, ph, x, y, rw, rh, tile, top, leading, bottom, trailing, smoothing, hasTint ? tint : null);
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
      window.__swiftuiweb = {
        paint: paint, measure: measure, version: 3,
        setImageLoadHandler: function (handler) { onImageLoad = handler; },
        pendingImages: function () { return pending; },
      };
    })();
    """#
}
