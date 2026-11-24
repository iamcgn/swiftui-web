// An experimental WebGL2 painter for DisplayListEncoder's flat format: the same ops
// PainterScript's Canvas2D decoder paints, drawn on the GPU instead.
//
// It is a shim, so the experiment needs no change to the Swift side and adds nothing to an
// app's wasm: loaded before the app starts, it traps the assignment of `window.__swiftuiweb`
// (PainterScript publishing its bridge) and wraps the bridge's `paint`, so the app's main
// canvas is drawn by WebGL2 while everything else (text measurement, drag previews,
// `rasterize`, AsyncImage state) stays Canvas2D. Without WebGL2 it leaves the bridge alone.
//
// Modes (`?webgl=` in the page URL, or `window.__swiftuiwebGLConfig.mode`):
//   overlay  (default) a WebGL canvas laid over the 2D canvas, which stays clear
//   blit     WebGL draws offscreen and the frame is copied into the 2D canvas (one drawImage)
//   2d       the shim is installed but Canvas2D paints (for like-for-like timing)
//   off      not installed
// `?webglSamples=N` sets the MSAA sample count (default 4; 1 turns multisampling off) and
// `?webglSync` makes both painters wait for their pixels before returning their time.
//
// How it draws:
//   - Rects and rounded rects in an axis-aligned space: a signed-distance quad (analytic edges).
//   - Paths: flattened on the CPU; one convex contour is a triangle fan, anything else goes
//     through the stencil buffer (nonzero or even-odd) and a covering quad. Edges are
//     antialiased by 4x MSAA.
//   - Strokes: a CPU stroker (joins, caps, dashes); a translucent stroke goes through the
//     stencil so its overlaps are painted once. Hairlines are a device pixel wide at reduced alpha.
//   - Clips: device-aligned rects are the scissor; anything else is a stencil level.
//   - Text: each run is rasterised once by Canvas2D into an atlas (so glyphs are the browser's
//     own), then drawn as a textured quad.
//   - Gradients: in the fragment shader, with the stops in a ramp texture.
//   - Groups (opacity, shadow, filter, blend, mask): a multisampled offscreen target each,
//     resolved and composited back; blurs are separable Gaussians, blend modes the W3C formulas.
(function () {
  'use strict';
  if (window.__swiftuiwebGL) return;
  const query = new URLSearchParams(location.search);
  const config = Object.assign({
    mode: query.get('webgl') || 'overlay',
    samples: Number(query.get('webglSamples') || 4),
    sync: query.has('webglSync'),
  }, window.__swiftuiwebGLConfig || {});
  const info = { mode: config.mode, active: false, reason: '', renderer: '', samples: 0, frames: 0, glFrames: 0, fallbacks: 0, lastMs: 0, stats: {}, errors: [], targets: 0, targetBytes: 0 };
  window.__swiftuiwebGL = info;
  if (config.mode === 'off' || config.mode === '0') { info.reason = 'off'; return; }

  // Images the WebGL painter loaded itself, and the host's load handler (so an image that
  // arrives repaints the page, as the Canvas2D painter's do).
  let imageHandler = null;
  let glPending = 0;

  let bridgeValue;
  Object.defineProperty(window, '__swiftuiweb', {
    configurable: true, enumerable: true,
    get() { return bridgeValue; },
    set(v) { bridgeValue = v && typeof v.paint === 'function' && !v.__gl ? wrap(v) : v; },
  });

  function wrap(bridge) {
    const original = bridge.paint;
    let mainCanvas = null, painter = null, unavailable = false, last = null;
    // bench(n): repaints the last frame n times with each painter, waiting for its pixels each
    // time (so the GPU's work counts), and returns the paint times: the same content both ways.
    info.bench = function (n) {
      if (!last) return null;
      const { ctx, buf, strings, dpr, w, h, bitmaps } = last;
      const stat = xs => { const s = xs.slice().sort((a, b) => a - b); return { median: s[Math.floor(s.length / 2)], p90: s[Math.floor(s.length * 0.9)], min: s[0], max: s[s.length - 1], n: s.length }; };
      const times2d = [], timesGL = [];
      const reps = Math.max(1, n | 0 || 30);
      for (let k = 0; k < reps + 3; k++) {
        const t0 = performance.now();
        original.call(bridge, ctx, buf, strings, dpr, w, h, bitmaps);
        ctx.getImageData(0, 0, 1, 1);
        if (k >= 3) times2d.push(performance.now() - t0);
      }
      if (painter) {
        painter.hide();
        for (let k = 0; k < reps + 3; k++) {
          const t0 = performance.now();
          painter.paint(buf, strings, dpr, w, h, bitmaps, true);
          if (k >= 3) timesGL.push(performance.now() - t0);
        }
      }
      return { ops: buf.length, canvas2d: stat(times2d), webgl: timesGL.length ? stat(timesGL) : null, stats: info.stats };
    };
    bridge.__gl = true;
    bridge.paint = function (ctx, buf, strings, dpr, w, h, bitmaps) {
      const canvas = ctx && ctx.canvas;
      if (!mainCanvas && canvas && canvas instanceof HTMLCanvasElement && canvas.isConnected) mainCanvas = canvas;
      const main = canvas === mainCanvas;
      if (main && !unavailable && config.mode !== '2d' && !painter) {
        painter = createPainter(canvas, ctx);
        if (!painter) unavailable = true;
      }
      if (main) last = { ctx, buf: Float64Array.from(buf), strings: strings.slice(), dpr, w, h, bitmaps };
      if (!main || !painter) {
        const t0 = performance.now();
        let ms = original.call(this, ctx, buf, strings, dpr, w, h, bitmaps);
        if (main) {
          if (config.sync) { ctx.getImageData(0, 0, 1, 1); ms = performance.now() - t0; }
          info.frames++; info.lastMs = ms;
        }
        return ms;
      }
      try {
        const ms = painter.paint(buf, strings, dpr, w, h, bitmaps);
        info.frames++; info.glFrames++; info.lastMs = ms;
        return ms;
      } catch (e) {
        // This frame falls back to Canvas2D; the next one tries WebGL again.
        info.fallbacks++;
        if (info.errors.length < 20) info.errors.push(String((e && e.stack) || e));
        console.error('SwiftUIWeb WebGL painter: ' + ((e && e.message) || e));
        painter.hide();
        return original.call(this, ctx, buf, strings, dpr, w, h, bitmaps);
      }
    };
    const setHandler = bridge.setImageLoadHandler;
    bridge.setImageLoadHandler = function (handler) { imageHandler = handler; return setHandler.call(this, handler); };
    const pendingOriginal = bridge.pendingImages;
    bridge.pendingImages = function () { return pendingOriginal.call(this) + glPending; };
    const forget = bridge.forgetMeasurements;
    bridge.forgetMeasurements = function () { if (painter) painter.forgetText(); return forget.apply(this, arguments); };
    return bridge;
  }

  // ---------------------------------------------------------------------------------------
  // Text helpers: the same font-string conventions as PainterScript ('|spacing', '|t<ratio>').
  let tabularSlot = 0;
  const slotCache = new Map();
  function isDigit(ch) { return ch >= '0' && ch <= '9'; }
  function setFont(ctx, font) {
    const parts = font.split('|');
    ctx.font = parts[0];
    if (parts.length > 2 && parts[2][0] === 't') {
      let slot = slotCache.get(font);
      if (slot === undefined) { slot = ctx.measureText('0').width * Number(parts[2].slice(1)); slotCache.set(font, slot); }
      tabularSlot = slot;
    } else {
      tabularSlot = 0;
    }
    const spacing = parts.length > 1 ? Number(parts[1]) : 0;
    if ('letterSpacing' in ctx) { ctx.letterSpacing = spacing + 'px'; return 0; }
    return spacing;
  }
  function fillSpacedText(ctx, text, x, y, spacing) {
    if (!spacing && !tabularSlot) { ctx.fillText(text, x, y); return; }
    let cursor = x;
    const slot = tabularSlot;
    for (const ch of Array.from(text)) {
      const w = ctx.measureText(ch).width;
      if (slot && isDigit(ch)) { ctx.fillText(ch, cursor + (slot - w) / 2, y); cursor += slot + spacing; }
      else { ctx.fillText(ch, cursor, y); cursor += w + spacing; }
    }
  }

  // ---------------------------------------------------------------------------------------
  const VS_MAIN = `#version 300 es
  precision highp float;
  in vec2 a_pos; in vec2 a_tex; in vec2 a_local; in vec4 a_color; in vec4 a_p0; in vec4 a_p1; in float a_kind;
  uniform vec2 u_size;
  out vec2 v_pos; out vec2 v_tex; out vec2 v_local; out vec4 v_color; out vec4 v_p0; out vec4 v_p1; flat out int v_kind;
  void main() {
    v_pos = a_pos; v_tex = a_tex; v_local = a_local; v_color = a_color; v_p0 = a_p0; v_p1 = a_p1; v_kind = int(a_kind + 0.5);
    gl_Position = vec4(a_pos.x / u_size.x * 2.0 - 1.0, 1.0 - a_pos.y / u_size.y * 2.0, 0.0, 1.0);
  }`;
  // Kinds: 0 solid; 1 rounded-rect distance (p0 centre and half size, p1.x radius, device px);
  // 2 premultiplied image × alpha; 3 tint × image alpha; 4 gradient; 5 gradient × image alpha;
  // 6 atlas text (premultiplied); 7 gradient × atlas alpha.
  const FS_MAIN = `#version 300 es
  precision highp float;
  in vec2 v_pos; in vec2 v_tex; in vec2 v_local; in vec4 v_color; in vec4 v_p0; in vec4 v_p1; flat in int v_kind;
  uniform sampler2D u_tex; uniform sampler2D u_ramp; uniform sampler2D u_atlas;
  uniform vec2 u_rampSize;
  out vec4 o;
  const float TAU = 6.283185307179586;
  vec4 gradient() {
    int type = int(v_p1.w + 0.5);
    vec2 p = v_local;
    float t = 0.0;
    if (type == 0) {
      vec2 d = v_p0.zw - v_p0.xy;
      float dd = dot(d, d);
      if (dd <= 0.0) return vec4(0.0);
      t = dot(p - v_p0.xy, d) / dd;
    } else if (type == 1) {
      // Two circles (Canvas2D's createRadialGradient): the largest t whose circle passes through p with r(t) >= 0.
      vec2 c0 = v_p0.xy, c1 = v_p0.zw; float r0 = v_p1.x, r1 = v_p1.y;
      vec2 cd = c1 - c0; float dr = r1 - r0; vec2 pd = p - c0;
      float a = dot(cd, cd) - dr * dr;
      float b = dot(pd, cd) + r0 * dr;
      float c = dot(pd, pd) - r0 * r0;
      if (abs(a) < 1e-6) {
        if (abs(b) < 1e-9) return vec4(0.0);
        t = c / (2.0 * b);
        if (r0 + t * dr < 0.0) return vec4(0.0);
      } else {
        float disc = b * b - a * c;
        if (disc < 0.0) return vec4(0.0);
        float s = sqrt(disc);
        float t1 = (b + s) / a, t2 = (b - s) / a;
        float hi = max(t1, t2), lo = min(t1, t2);
        if (r0 + hi * dr >= 0.0) t = hi; else if (r0 + lo * dr >= 0.0) t = lo; else return vec4(0.0);
      }
    } else if (type == 2) {
      vec2 d = p - v_p0.xy;
      t = fract((atan(d.y, d.x) - v_p0.z) / TAU);
    } else {
      // Elliptical: concentric circles in a space squashed vertically about the centre.
      vec2 q = vec2(p.x - v_p0.x, (p.y - v_p0.y) / v_p1.z);
      float dr = v_p1.y - v_p1.x;
      if (abs(dr) < 1e-9) return vec4(0.0);
      t = (length(q) - v_p1.x) / dr;
    }
    t = clamp(t, 0.0, 1.0);
    vec4 c = texture(u_ramp, vec2((t * (u_rampSize.x - 1.0) + 0.5) / u_rampSize.x, (v_color.r + 0.5) / u_rampSize.y));
    return vec4(c.rgb * c.a, c.a) * v_color.a;
  }
  void main() {
    if (v_kind == 0) { o = v_color; }
    else if (v_kind == 1) {
      vec2 q = abs(v_pos - v_p0.xy) - v_p0.zw + v_p1.x;
      float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - v_p1.x;
      o = v_color * clamp(0.5 - d, 0.0, 1.0);
    }
    else if (v_kind == 2) { o = texture(u_tex, v_tex) * v_color.a; }
    else if (v_kind == 3) { o = v_color * texture(u_tex, v_tex).a; }
    else if (v_kind == 4) { o = gradient(); }
    else if (v_kind == 5) { o = gradient() * texture(u_tex, v_tex).a; }
    else if (v_kind == 6) { o = texture(u_atlas, v_tex) * v_color.a; }
    else { o = gradient() * texture(u_atlas, v_tex).a; }
  }`;
  // Compositing a group's texture back into its parent: device-space quad, the source (and mask,
  // destination, original) read through "views" — a texture covering device pixels from x0
  // rightwards and from y1 upwards (GL rows run bottom up), k device pixels a texel.
  const FS_COMP = `#version 300 es
  precision highp float;
  in vec2 v_pos; in vec2 v_tex; in vec2 v_local; in vec4 v_color; in vec4 v_p0; in vec4 v_p1; flat in int v_kind;
  uniform sampler2D u_src; uniform sampler2D u_aux; uniform sampler2D u_dst;
  uniform vec3 u_srcView; uniform vec2 u_srcSize; uniform vec4 u_srcClamp;
  uniform vec3 u_auxView; uniform vec2 u_auxSize;
  uniform vec3 u_dstView; uniform vec2 u_dstSize;
  uniform int u_aux_mode;   // 0 none, 1 mask (×aux alpha), 2 keep alpha (blurred colour, aux alpha)
  uniform int u_matrix_on; uniform float u_m[20]; uniform vec4 u_matrixRect;
  uniform int u_tint_on; uniform vec4 u_tint;
  uniform float u_opacity; uniform vec2 u_offset; uniform int u_blend;
  out vec4 o;
  vec4 fetch(sampler2D t, vec3 view, vec2 size, vec2 p) {
    vec2 texel = vec2((p.x - view.x) / view.z, (view.y - p.y) / view.z);
    return texture(t, texel / size);
  }
  float lum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }
  vec3 clipColor(vec3 c) {
    float l = lum(c); float n = min(min(c.r, c.g), c.b); float x = max(max(c.r, c.g), c.b);
    if (n < 0.0) c = l + (c - l) * l / max(l - n, 1e-6);
    if (x > 1.0) c = l + (c - l) * (1.0 - l) / max(x - l, 1e-6);
    return c;
  }
  vec3 setLum(vec3 c, float l) { return clipColor(c + (l - lum(c))); }
  float sat(vec3 c) { return max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b); }
  vec3 setSat(vec3 c, float s) {
    float mx = max(max(c.r, c.g), c.b), mn = min(min(c.r, c.g), c.b);
    if (mx - mn <= 1e-6) return vec3(0.0);
    return (c - mn) * s / (mx - mn);
  }
  float dodge(float s, float d) { if (d <= 0.0) return 0.0; if (s >= 1.0) return 1.0; return min(1.0, d / (1.0 - s)); }
  float burn(float s, float d) { if (d >= 1.0) return 1.0; if (s <= 0.0) return 0.0; return 1.0 - min(1.0, (1.0 - d) / s); }
  float softLight(float s, float d) {
    if (s <= 0.5) return d - (1.0 - 2.0 * s) * d * (1.0 - d);
    float g = d <= 0.25 ? ((16.0 * d - 12.0) * d + 4.0) * d : sqrt(d);
    return d + (2.0 * s - 1.0) * (g - d);
  }
  float hardLight(float s, float d) { return s <= 0.5 ? d * 2.0 * s : 1.0 - (1.0 - d) * (1.0 - (2.0 * s - 1.0)); }
  vec3 blendFn(int m, vec3 s, vec3 d) {
    if (m == 1) return s * d;
    if (m == 2) return s + d - s * d;
    if (m == 3) return vec3(hardLight(d.r, s.r), hardLight(d.g, s.g), hardLight(d.b, s.b));
    if (m == 4) return min(s, d);
    if (m == 5) return max(s, d);
    if (m == 6) return vec3(dodge(s.r, d.r), dodge(s.g, d.g), dodge(s.b, d.b));
    if (m == 7) return vec3(burn(s.r, d.r), burn(s.g, d.g), burn(s.b, d.b));
    if (m == 8) return vec3(softLight(s.r, d.r), softLight(s.g, d.g), softLight(s.b, d.b));
    if (m == 9) return vec3(hardLight(s.r, d.r), hardLight(s.g, d.g), hardLight(s.b, d.b));
    if (m == 10) return abs(s - d);
    if (m == 11) return s + d - 2.0 * s * d;
    if (m == 12) return setLum(setSat(s, sat(d)), lum(d));
    if (m == 13) return setLum(setSat(d, sat(s)), lum(d));
    if (m == 14) return setLum(s, lum(d));
    if (m == 15) return setLum(d, lum(s));
    return s;
  }
  bool inside(vec2 p, vec4 r) { return p.x >= r.x && p.y >= r.y && p.x <= r.z && p.y <= r.w; }
  void main() {
    vec2 p = v_pos - u_offset;
    vec4 s = inside(p, u_srcClamp) ? fetch(u_src, u_srcView, u_srcSize, p) : vec4(0.0);
    if (u_aux_mode == 1) s *= fetch(u_aux, u_auxView, u_auxSize, v_pos).a;
    else if (u_aux_mode == 2) {
      float a = fetch(u_aux, u_auxView, u_auxSize, v_pos).a;
      s = s.a > 0.0 ? vec4(s.rgb / s.a * a, a) : vec4(0.0);
    }
    if (u_matrix_on == 1 && inside(v_pos, u_matrixRect)) {
      vec4 c = s.a > 0.0 ? vec4(s.rgb / s.a, s.a) : vec4(0.0);
      vec4 r = vec4(
        u_m[0] * c.r + u_m[1] * c.g + u_m[2] * c.b + u_m[3] * c.a + u_m[4],
        u_m[5] * c.r + u_m[6] * c.g + u_m[7] * c.b + u_m[8] * c.a + u_m[9],
        u_m[10] * c.r + u_m[11] * c.g + u_m[12] * c.b + u_m[13] * c.a + u_m[14],
        u_m[15] * c.r + u_m[16] * c.g + u_m[17] * c.b + u_m[18] * c.a + u_m[19]);
      r = clamp(r, 0.0, 1.0);
      s = vec4(r.rgb * r.a, r.a);
    }
    if (u_tint_on == 1) s = u_tint * s.a;
    s *= u_opacity;
    if (u_blend > 0) {
      vec4 d = fetch(u_dst, u_dstView, u_dstSize, v_pos);
      float sa = s.a, da = d.a;
      if (u_blend == 19) {
        // plus-darker: max(0, s + d - 1), premultiplied (the Canvas2D painter's formula).
        float a = max(0.0, sa + da - 1.0);
        o = vec4(min(vec3(a), max(vec3(0.0), s.rgb + d.rgb - vec3(1.0))), a);
        return;
      }
      vec3 cs = sa > 0.0 ? s.rgb / sa : vec3(0.0), cd = da > 0.0 ? d.rgb / da : vec3(0.0);
      vec3 b = clamp(blendFn(u_blend, cs, cd), 0.0, 1.0);
      o = vec4(s.rgb * (1.0 - da) + d.rgb * (1.0 - sa) + sa * da * b, sa + da - sa * da);
      return;
    }
    o = s;
  }`;
  // Full-target passes: gl_FragCoord is the destination texel.
  const VS_PASS = `#version 300 es
  in vec2 a_pos;
  void main() { gl_Position = vec4(a_pos, 0.0, 1.0); }`;
  // Copy (a scaled resample) of a source view into a temporary covering device pixels from
  // (x0, y1) at k per texel; outside the clamp rect is transparent.
  const FS_COPY = `#version 300 es
  precision highp float;
  uniform sampler2D u_src; uniform vec3 u_srcView; uniform vec2 u_srcSize; uniform vec4 u_clamp;
  uniform vec3 u_dstView;
  out vec4 o;
  void main() {
    vec2 p = vec2(u_dstView.x + gl_FragCoord.x * u_dstView.z, u_dstView.y - gl_FragCoord.y * u_dstView.z);
    if (p.x < u_clamp.x || p.y < u_clamp.y || p.x > u_clamp.z || p.y > u_clamp.w) { o = vec4(0.0); return; }
    vec2 texel = vec2((p.x - u_srcView.x) / u_srcView.z, (u_srcView.y - p.y) / u_srcView.z);
    o = texture(u_src, texel / u_srcSize);
  }`;
  const FS_BLUR = `#version 300 es
  precision highp float;
  uniform sampler2D u_src; uniform vec2 u_dir; uniform float u_sigma; uniform int u_radius;
  out vec4 o;
  void main() {
    ivec2 size = textureSize(u_src, 0);
    ivec2 c = ivec2(gl_FragCoord.xy);
    vec4 sum = vec4(0.0); float wsum = 0.0;
    float k = -0.5 / (u_sigma * u_sigma);
    for (int i = -256; i <= 256; i++) {
      if (i < -u_radius) continue;
      if (i > u_radius) break;
      float w = exp(float(i * i) * k);
      ivec2 q = c + ivec2(u_dir) * i;
      wsum += w;
      if (q.x < 0 || q.y < 0 || q.x >= size.x || q.y >= size.y) continue;
      sum += texelFetch(u_src, q, 0) * w;
    }
    o = sum / wsum;
  }`;

  // ---------------------------------------------------------------------------------------
  function createPainter(canvas2d, ctx2d) {
    const overlay = config.mode !== 'blit';
    const glCanvas = document.createElement('canvas');
    if (overlay) {
      glCanvas.style.cssText = 'position:absolute;pointer-events:none;left:0;top:0';
      glCanvas.setAttribute('aria-hidden', 'true');
      canvas2d.after(glCanvas);
    }
    let gl = null;
    try { gl = glCanvas.getContext('webgl2', { alpha: true, premultipliedAlpha: true, antialias: false, depth: false, stencil: false, preserveDrawingBuffer: false, powerPreference: 'high-performance' }); } catch (e) { gl = null; }
    if (!gl) { info.reason = 'WebGL2 unavailable'; glCanvas.remove(); return null; }
    info.active = true;
    const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
    info.renderer = String(debugInfo ? gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER));
    const samples = Math.max(1, Math.min(config.samples | 0 || 1, gl.getParameter(gl.MAX_SAMPLES)));
    info.samples = samples;
    let twoDDirty = true;   // the 2D canvas may hold a Canvas2D frame (before the first, after a fallback)

    function compile(type, source) {
      const s = gl.createShader(type);
      gl.shaderSource(s, source);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error('shader: ' + gl.getShaderInfoLog(s));
      return s;
    }
    function program(vs, fs, attributes) {
      const p = gl.createProgram();
      gl.attachShader(p, compile(gl.VERTEX_SHADER, vs));
      gl.attachShader(p, compile(gl.FRAGMENT_SHADER, fs));
      attributes.forEach((name, index) => gl.bindAttribLocation(p, index, name));
      gl.linkProgram(p);
      if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error('link: ' + gl.getProgramInfoLog(p));
      const uniforms = {};
      const count = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
      for (let i = 0; i < count; i++) {
        const u = gl.getActiveUniform(p, i);
        const name = u.name.replace(/\[0\]$/, '');
        uniforms[name] = gl.getUniformLocation(p, u.name);
      }
      return { p, u: uniforms };
    }
    const MAIN_ATTRS = ['a_pos', 'a_tex', 'a_local', 'a_color', 'a_p0', 'a_p1', 'a_kind'];
    let progMain, progComp, progCopy, progBlur;
    try {
      progMain = program(VS_MAIN, FS_MAIN, MAIN_ATTRS);
      progComp = program(VS_MAIN, FS_COMP, MAIN_ATTRS);
      progCopy = program(VS_PASS, FS_COPY, ['a_pos']);
      progBlur = program(VS_PASS, FS_BLUR, ['a_pos']);
    } catch (e) {
      info.reason = String(e.message || e); info.active = false; glCanvas.remove();
      console.warn('SwiftUIWeb WebGL painter unavailable: ' + info.reason);
      return null;
    }

    // Vertex layout: pos 2, tex 2, local 2, color 4, p0 4, p1 4, kind 1.
    const STRIDE = 19;
    let verts = new Float32Array(STRIDE * 6 * 4096);
    let count = 0;   // vertices in the batch
    const vbo = gl.createBuffer();
    const vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    const sizes = [2, 2, 2, 4, 4, 4, 1];
    let offset = 0;
    sizes.forEach((n, i) => { gl.enableVertexAttribArray(i); gl.vertexAttribPointer(i, n, gl.FLOAT, false, STRIDE * 4, offset * 4); offset += n; });
    const passVao = gl.createVertexArray();
    gl.bindVertexArray(passVao);
    const passVbo = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, passVbo);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    gl.bindVertexArray(null);

    const samplerLinear = gl.createSampler();
    for (const s of [samplerLinear]) {
      gl.samplerParameteri(s, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.samplerParameteri(s, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.samplerParameteri(s, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.samplerParameteri(s, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    }
    const samplerNearest = gl.createSampler();
    gl.samplerParameteri(samplerNearest, gl.TEXTURE_MIN_FILTER, gl.NEAREST); gl.samplerParameteri(samplerNearest, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.samplerParameteri(samplerNearest, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.samplerParameteri(samplerNearest, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    function makeTexture(w, h, data) {
      const t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, data || null);
      return t;
    }

    // --- Gradient ramps: one row a gradient, straight colours interpolated as Canvas2D does.
    const RAMP_W = 1024, RAMP_H = 256;
    const rampData = new Uint8Array(RAMP_W * RAMP_H * 4);
    const rampRows = new Map();
    let rampDirtyLo = RAMP_H, rampDirtyHi = -1;
    const rampTex = makeTexture(RAMP_W, RAMP_H, null);
    function rampRow(stops) {
      let key = '';
      for (let k = 0; k < stops.length; k += 5) key += stops[k] + ',' + stops[k + 1] + ',' + stops[k + 2] + ',' + stops[k + 3] + ',' + stops[k + 4] + ';';
      let row = rampRows.get(key);
      if (row !== undefined) return row;
      if (rampRows.size >= RAMP_H) { flush(); rampRows.clear(); }
      row = rampRows.size;
      rampRows.set(key, row);
      const n = stops.length / 5;
      const base = row * RAMP_W * 4;
      for (let x = 0; x < RAMP_W; x++) {
        const t = x / (RAMP_W - 1);
        let r, g, b, a;
        if (n === 0) { r = g = b = a = 0; }
        else if (t <= stops[0]) { r = stops[1]; g = stops[2]; b = stops[3]; a = stops[4]; }
        else if (t >= stops[(n - 1) * 5]) { const k = (n - 1) * 5; r = stops[k + 1]; g = stops[k + 2]; b = stops[k + 3]; a = stops[k + 4]; }
        else {
          let k = 0;
          while (k < n - 1 && stops[(k + 1) * 5] <= t) k++;
          const s0 = k * 5, s1 = Math.min(n - 1, k + 1) * 5;
          const span = stops[s1] - stops[s0];
          const f = span > 0 ? (t - stops[s0]) / span : 1;
          r = stops[s0 + 1] + (stops[s1 + 1] - stops[s0 + 1]) * f;
          g = stops[s0 + 2] + (stops[s1 + 2] - stops[s0 + 2]) * f;
          b = stops[s0 + 3] + (stops[s1 + 3] - stops[s0 + 3]) * f;
          a = stops[s0 + 4] + (stops[s1 + 4] - stops[s0 + 4]) * f;
        }
        rampData[base + x * 4] = r; rampData[base + x * 4 + 1] = g; rampData[base + x * 4 + 2] = b; rampData[base + x * 4 + 3] = Math.round(a * 255);
      }
      rampDirtyLo = Math.min(rampDirtyLo, row); rampDirtyHi = Math.max(rampDirtyHi, row);
      return row;
    }
    function uploadRamps() {
      if (rampDirtyHi < rampDirtyLo) return;
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, rampTex);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, rampDirtyLo, RAMP_W, rampDirtyHi - rampDirtyLo + 1, gl.RGBA, gl.UNSIGNED_BYTE, rampData.subarray(rampDirtyLo * RAMP_W * 4, (rampDirtyHi + 1) * RAMP_W * 4));
      rampDirtyLo = RAMP_H; rampDirtyHi = -1;
    }

    // --- Text atlas: runs rasterised by Canvas2D, packed in shelves.
    const ATLAS = 2048;
    const atlasCanvas = new OffscreenCanvas(ATLAS, ATLAS);
    const actx = atlasCanvas.getContext('2d', { willReadFrequently: true });
    actx.textBaseline = 'alphabetic';
    const atlasTex = makeTexture(ATLAS, ATLAS, null);
    const atlasEntries = new Map();
    let shelves = [];   // {y, h, x}
    let shelfTop = 0;
    let atlasDirty = null;   // {x0, y0, x1, y1}
    const measureCtx = new OffscreenCanvas(4, 4).getContext('2d');
    measureCtx.textBaseline = 'alphabetic';
    const metricsCache = new Map();
    function resetAtlas() {
      atlasEntries.clear(); shelves = []; shelfTop = 0;
      actx.setTransform(1, 0, 0, 1, 0, 0);
      actx.clearRect(0, 0, ATLAS, ATLAS);
      atlasDirty = { x0: 0, y0: 0, x1: ATLAS, y1: ATLAS };
    }
    function forgetText() { flushIfPossible(); metricsCache.clear(); slotCache.clear(); resetAtlas(); }
    function allocate(w, h) {
      if (w > ATLAS || h > ATLAS) return null;
      const sh = Math.ceil(h / 4) * 4;
      for (const s of shelves) {
        if (s.h >= sh && s.h <= sh * 1.5 + 4 && s.x + w <= ATLAS) { const x = s.x; s.x += w + 1; return { x, y: s.y }; }
      }
      if (shelfTop + sh > ATLAS) return null;
      const s = { y: shelfTop, h: sh, x: w + 1 };
      shelves.push(s);
      shelfTop += sh + 1;
      return { x: 0, y: s.y };
    }
    function uploadAtlas() {
      if (!atlasDirty) return;
      const d = atlasDirty; atlasDirty = null;
      const w = d.x1 - d.x0, h = d.y1 - d.y0;
      if (w <= 0 || h <= 0) return;
      const img = actx.getImageData(d.x0, d.y0, w, h);
      gl.activeTexture(gl.TEXTURE2);
      gl.bindTexture(gl.TEXTURE_2D, atlasTex);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
      gl.texSubImage2D(gl.TEXTURE_2D, 0, d.x0, d.y0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, img.data);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    }
    function textMetrics(font, text) {
      const key = font + '\u0000' + text;
      let m = metricsCache.get(key);
      if (m) return m;
      const spacing = setFont(measureCtx, font);
      const mt = measureCtx.measureText(text);
      const n = Array.from(text).length;
      let width = mt.width + spacing * n;
      if (tabularSlot) { width = 0; for (const ch of Array.from(text)) width += (isDigit(ch) ? tabularSlot : measureCtx.measureText(ch).width) + spacing; }
      m = { left: mt.actualBoundingBoxLeft || 0, right: Math.max(width, mt.actualBoundingBoxRight || 0), ascent: mt.actualBoundingBoxAscent || 0, descent: mt.actualBoundingBoxDescent || 0, size: parseFloat((font.match(/(\d+(?:\.\d+)?)px/) || [0, 12])[1]) };
      if (metricsCache.size > 20000) metricsCache.clear();
      metricsCache.set(key, m);
      return m;
    }
    // Returns {x, y, w, h, ox, oy}: the slot, and the origin's offset in it (device pixels).
    function textEntry(text, font, fill, sx, sy, fx, fy) {
      const key = fill + '\u0000' + font + '\u0000' + text + '\u0000' + sx + ',' + sy + ',' + fx + ',' + fy;
      let e = atlasEntries.get(key);
      if (e) return e;
      const m = textMetrics(font, text);
      const pad = Math.ceil(Math.max(2, m.size * 0.25) * Math.max(sx, sy));
      const padL = Math.ceil(Math.max(0, m.left) * sx) + pad, padT = Math.ceil(Math.max(0, m.ascent) * sy) + pad;
      const w = padL + Math.ceil(m.right * sx + fx) + pad, h = padT + Math.ceil(Math.max(0, m.descent) * sy + fy) + pad;
      let slot = allocate(w, h);
      if (!slot) { flushIfPossible(); resetAtlas(); slot = allocate(w, h); if (!slot) return null; }
      e = { x: slot.x, y: slot.y, w, h, ox: padL, oy: padT };
      actx.save();
      actx.setTransform(1, 0, 0, 1, 0, 0);
      actx.beginPath(); actx.rect(slot.x, slot.y, w, h); actx.clip();
      actx.clearRect(slot.x, slot.y, w, h);
      actx.setTransform(sx, 0, 0, sy, slot.x + padL + fx, slot.y + padT + fy);
      actx.fillStyle = fill;
      const spacing = setFont(actx, font);
      fillSpacedText(actx, text, 0, 0, spacing);
      actx.restore();
      const d = atlasDirty || { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity };
      d.x0 = Math.min(d.x0, slot.x); d.y0 = Math.min(d.y0, slot.y); d.x1 = Math.max(d.x1, slot.x + w); d.y1 = Math.max(d.y1, slot.y + h);
      atlasDirty = d;
      atlasEntries.set(key, e);
      return e;
    }

    // --- Images: loaded by the painter, uploaded once (SVGs rasterised at the drawn size).
    const images = new Map();
    function image(file) {
      let entry = images.get(file);
      if (entry) return entry.ready ? entry : null;
      const absolute = /^([a-z]+:)?\/\//i.test(file);
      const background = absolute;   // AsyncImage URLs (the Canvas2D painter does not count them either)
      const img = new Image();
      entry = { img, ready: false, failed: false, tex: null, svg: /\.svg(\?|$)/i.test(file) || file.startsWith('data:image/svg'), sized: new Map() };
      images.set(file, entry);
      if (!background) glPending++;
      const done = ok => { if (!background) glPending--; if (imageHandler) imageHandler(file, ok); };
      img.onload = () => { entry.ready = true; done(true); };
      img.onerror = () => { entry.failed = true; done(false); };
      const base = (window.__swiftuiwebAssets && window.__swiftuiwebAssets.base) || '';
      if (absolute && !file.startsWith(location.origin + '/')) img.crossOrigin = 'anonymous';
      img.src = absolute || file.startsWith('data:') || file.startsWith('/') ? file : base + file;
      return null;
    }
    function imageTexture(entry, dw, dh) {
      if (!entry.svg) {
        if (!entry.tex) {
          entry.tex = gl.createTexture();
          gl.bindTexture(gl.TEXTURE_2D, entry.tex);
          gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, entry.img);
          gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
          entry.w = entry.img.naturalWidth; entry.h = entry.img.naturalHeight;
        }
        return { tex: entry.tex, w: entry.w, h: entry.h };
      }
      const pw = Math.max(1, Math.min(4096, Math.round(dw))), ph = Math.max(1, Math.min(4096, Math.round(dh)));
      const key = pw + 'x' + ph;
      let t = entry.sized.get(key);
      if (!t) {
        const c = new OffscreenCanvas(pw, ph);
        c.getContext('2d').drawImage(entry.img, 0, 0, pw, ph);
        const tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, c);
        gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
        // Source rects are in the image's own pixels: the texture stands for the natural size.
        t = { tex, w: entry.img.naturalWidth || pw, h: entry.img.naturalHeight || ph };
        if (entry.sized.size > 16) { for (const v of entry.sized.values()) gl.deleteTexture(v.tex); entry.sized.clear(); }
        entry.sized.set(key, t);
      }
      return t;
    }
    // Bitmaps by value arrive afresh every frame: their textures are recycled at frame end.
    let frameTextures = [];

    // --- Render targets: multisampled colour + stencil, and a texture to resolve into.
    const freeTargets = [];
    let allTargets = 0;
    function newTarget(W, H) {
      const t = { W, H, touched: null };
      t.fb = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, t.fb);
      t.color = gl.createRenderbuffer();
      gl.bindRenderbuffer(gl.RENDERBUFFER, t.color);
      if (samples > 1) gl.renderbufferStorageMultisample(gl.RENDERBUFFER, samples, gl.RGBA8, W, H); else gl.renderbufferStorage(gl.RENDERBUFFER, gl.RGBA8, W, H);
      gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, t.color);
      t.stencil = gl.createRenderbuffer();
      gl.bindRenderbuffer(gl.RENDERBUFFER, t.stencil);
      if (samples > 1) gl.renderbufferStorageMultisample(gl.RENDERBUFFER, samples, gl.DEPTH24_STENCIL8, W, H); else gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, W, H);
      gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, t.stencil);
      if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) throw new Error('incomplete target framebuffer');
      t.tex = makeTexture(W, H, null);
      t.resolveFb = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, t.resolveFb);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t.tex, 0);
      allTargets++;
      info.targets = allTargets;
      info.targetBytes += W * H * (8 * samples + 4);
      return t;
    }
    function deleteTarget(t) {
      gl.deleteFramebuffer(t.fb); gl.deleteFramebuffer(t.resolveFb);
      gl.deleteRenderbuffer(t.color); gl.deleteRenderbuffer(t.stencil); gl.deleteTexture(t.tex);
      allTargets--; info.targets = allTargets; info.targetBytes -= t.W * t.H * (8 * samples + 4);
    }
    function acquireTarget(W, H) {
      let t = null;
      for (let k = 0; k < freeTargets.length; k++) if (freeTargets[k].W === W && freeTargets[k].H === H) { t = freeTargets.splice(k, 1)[0]; break; }
      if (!t) t = newTarget(W, H);
      gl.bindFramebuffer(gl.FRAMEBUFFER, t.fb);
      gl.disable(gl.SCISSOR_TEST);
      if (t.touched) {
        const r = t.touched;
        gl.enable(gl.SCISSOR_TEST);
        gl.scissor(r.x0, H - r.y1, r.x1 - r.x0, r.y1 - r.y0);
      }
      if (t.touched !== false) {
        gl.clearColor(0, 0, 0, 0); gl.clearStencil(0); gl.stencilMask(0xFF); gl.colorMask(true, true, true, true);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);
      }
      gl.disable(gl.SCISSOR_TEST);
      t.touched = false;   // clean: nothing drawn yet
      return t;
    }
    function releaseTarget(t, touched) {
      t.touched = touched ? clampInts(touched, t.W, t.H) || false : null;
      freeTargets.push(t);
      if (freeTargets.length > 6) deleteTarget(freeTargets.shift());
    }
    // Temporaries for blurs: single-sampled textures with a framebuffer, recycled every frame.
    const tempPool = [];
    let tempUsed = [];
    function takeTemp(w, h) {
      const W = Math.ceil(w / 32) * 32, H = Math.ceil(h / 32) * 32;
      let t = null;
      for (let k = 0; k < tempPool.length; k++) if (tempPool[k].W === W && tempPool[k].H === H) { t = tempPool.splice(k, 1)[0]; break; }
      if (!t) {
        t = { W, H, tex: makeTexture(W, H, null), fb: gl.createFramebuffer() };
        gl.bindFramebuffer(gl.FRAMEBUFFER, t.fb);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t.tex, 0);
      }
      tempUsed.push(t);
      return t;
    }
    function recycleTemps() {
      for (const t of tempUsed) tempPool.push(t);
      tempUsed = [];
      while (tempPool.length > 12) { const t = tempPool.shift(); gl.deleteTexture(t.tex); gl.deleteFramebuffer(t.fb); }
    }

    // --- Boxes (device pixels).
    function emptyBox() { return { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity }; }
    function unionBox(b, x0, y0, x1, y1) { if (x0 < b.x0) b.x0 = x0; if (y0 < b.y0) b.y0 = y0; if (x1 > b.x1) b.x1 = x1; if (y1 > b.y1) b.y1 = y1; }
    function clampInts(b, W, H, pad) {
      const p = pad || 0;
      const x0 = Math.max(0, Math.floor(b.x0 - p)), y0 = Math.max(0, Math.floor(b.y0 - p));
      const x1 = Math.min(W, Math.ceil(b.x1 + p)), y1 = Math.min(H, Math.ceil(b.y1 + p));
      return x1 > x0 && y1 > y0 ? { x0, y0, x1, y1 } : null;
    }

    // --- Layers: the root target, and one per open group.
    let W = 0, H = 0, DPR = 1;
    let layer = null;   // { target, state, stack, box, touched, ... }
    const layers = [];
    let rootTarget = null;
    function freshState(m) { return { m: m.slice(), scissor: null, clip: 0, clips: [] }; }

    // --- Batch.
    let batchTex = null, batchNearest = false;
    let stats = { draws: 0, flushes: 0, vertices: 0, stencilPaths: 0, groups: 0, texts: 0, atlasMisses: 0 };
    let cr = 0, cg = 0, cb = 0, ca = 0;   // current premultiplied colour
    let p00 = 0, p01 = 0, p02 = 0, p03 = 0, p10 = 0, p11 = 0, p12 = 0, p13 = 0;
    let kind = 0;
    function ensure(n) {
      if ((count + n) * STRIDE > verts.length) {
        const bigger = new Float32Array(Math.max(verts.length * 2, (count + n) * STRIDE));
        bigger.set(verts.subarray(0, count * STRIDE));
        verts = bigger;
      }
    }
    function vert(x, y, tx, ty, lx, ly) {
      let o = count * STRIDE;
      verts[o++] = x; verts[o++] = y; verts[o++] = tx; verts[o++] = ty; verts[o++] = lx; verts[o++] = ly;
      verts[o++] = cr; verts[o++] = cg; verts[o++] = cb; verts[o++] = ca;
      verts[o++] = p00; verts[o++] = p01; verts[o++] = p02; verts[o++] = p03;
      verts[o++] = p10; verts[o++] = p11; verts[o++] = p12; verts[o++] = p13;
      verts[o] = kind;
      count++;
    }
    function setColor(r, g, b, a) { cr = r / 255 * a; cg = g / 255 * a; cb = b / 255 * a; ca = a; }
    function useTexture(tex, nearest) {
      if (tex !== batchTex || nearest !== batchNearest) { if (count) flush(); batchTex = tex; batchNearest = nearest; }
    }
    function applyScissor() {
      const s = layer.state.scissor;
      if (s) { gl.enable(gl.SCISSOR_TEST); gl.scissor(s.x0, H - s.y1, Math.max(0, s.x1 - s.x0), Math.max(0, s.y1 - s.y0)); }
      else gl.disable(gl.SCISSOR_TEST);
    }
    function normalStencil() {
      gl.enable(gl.STENCIL_TEST);
      gl.stencilMask(0x00);
      gl.stencilFunc(gl.EQUAL, layer.state.clip << 4, 0xF0);
      gl.stencilOp(gl.KEEP, gl.KEEP, gl.KEEP);
      gl.colorMask(true, true, true, true);
    }
    function bindMain() {
      gl.useProgram(progMain.p);
      gl.uniform2f(progMain.u.u_size, W, H);
      gl.uniform1i(progMain.u.u_tex, 0); gl.uniform1i(progMain.u.u_ramp, 1); gl.uniform1i(progMain.u.u_atlas, 2);
      gl.uniform2f(progMain.u.u_rampSize, RAMP_W, RAMP_H);
    }
    // Draws the batch with the stencil and colour state `setup` sets (the normal state if none).
    function drawBatch(setup) {
      if (!count) return;
      uploadRamps();
      uploadAtlas();
      gl.bindFramebuffer(gl.FRAMEBUFFER, layer.target.fb);
      gl.viewport(0, 0, W, H);
      applyScissor();
      bindMain();
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, batchTex); gl.bindSampler(0, batchNearest ? samplerNearest : null);
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, rampTex); gl.bindSampler(1, null);
      gl.activeTexture(gl.TEXTURE2); gl.bindTexture(gl.TEXTURE_2D, atlasTex); gl.bindSampler(2, null);
      gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      if (setup) setup(); else normalStencil();
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
      gl.bufferData(gl.ARRAY_BUFFER, verts.subarray(0, count * STRIDE), gl.STREAM_DRAW);
      gl.drawArrays(gl.TRIANGLES, 0, count);
      stats.draws++; stats.vertices += count;
      count = 0;
      gl.colorMask(true, true, true, true);
    }
    function flush() { if (count) { stats.flushes++; drawBatch(null); } }
    function flushIfPossible() { if (layer) flush(); }

    // --- Transform helpers.
    function dev(m, x, y) { return [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]]; }
    function axisAligned(m) { return Math.abs(m[1]) < 1e-9 && Math.abs(m[2]) < 1e-9; }
    function scaleOf(m) { return Math.max(Math.hypot(m[0], m[1]), Math.hypot(m[2], m[3])) || 1; }
    function inverse(m) {
      const det = m[0] * m[3] - m[1] * m[2];
      if (Math.abs(det) < 1e-12) return null;
      const a = m[3] / det, b = -m[1] / det, c = -m[2] / det, d = m[0] / det;
      return [a, b, c, d, -(a * m[4] + c * m[5]), -(b * m[4] + d * m[5])];
    }
    function deviceRectBox(m, x, y, w, h) {
      const b = emptyBox();
      for (const [px, py] of [[x, y], [x + w, y], [x, y + h], [x + w, y + h]]) { const [dx, dy] = dev(m, px, py); unionBox(b, dx, dy, dx, dy); }
      return b;
    }

    // --- Paths: read and flattened in user space into contours ({pts, closed}).
    let contours = [];
    const pathBox = emptyBox();   // user space, points and control points
    function flattenQuad(out, x0, y0, cx, cy, x1, y1, tol) {
      const dd = Math.hypot(x0 - 2 * cx + x1, y0 - 2 * cy + y1);
      const n = Math.max(1, Math.min(256, Math.ceil(Math.sqrt(dd / (4 * tol)))));
      for (let k = 1; k <= n; k++) {
        const t = k / n, u = 1 - t;
        out.push(u * u * x0 + 2 * u * t * cx + t * t * x1, u * u * y0 + 2 * u * t * cy + t * t * y1);
      }
    }
    function flattenCubic(out, x0, y0, c1x, c1y, c2x, c2y, x1, y1, tol) {
      const dd = Math.max(Math.hypot(x0 - 2 * c1x + c2x, y0 - 2 * c1y + c2y), Math.hypot(c1x - 2 * c2x + x1, c1y - 2 * c2y + y1));
      const n = Math.max(1, Math.min(256, Math.ceil(Math.sqrt(3 * dd / (4 * tol)))));
      for (let k = 1; k <= n; k++) {
        const t = k / n, u = 1 - t;
        const a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
        out.push(a * x0 + b * c1x + c * c2x + d * x1, a * y0 + b * c1y + c * c2y + d * y1);
      }
    }
    function readPath(buf, i, m) {
      const tol = 0.2 / scaleOf(m);
      contours = [];
      pathBox.x0 = pathBox.y0 = Infinity; pathBox.x1 = pathBox.y1 = -Infinity;
      const pt = (x, y) => unionBox(pathBox, x, y, x, y);
      const count = buf[i++];
      let cur = null, cx = 0, cy = 0, sx = 0, sy = 0, have = false;
      const start = (x, y) => { cur = { pts: [x, y], closed: false }; contours.push(cur); };
      for (let k = 0; k < count; k++) {
        const tag = buf[i++];
        switch (tag) {
          case 0: { const x = buf[i++], y = buf[i++]; start(x, y); sx = cx = x; sy = cy = y; have = true; pt(x, y); break; }
          case 1: {
            const x = buf[i++], y = buf[i++]; pt(x, y);
            if (!have) { start(x, y); sx = x; sy = y; have = true; }
            else { if (!cur) start(cx, cy); cur.pts.push(x, y); }
            cx = x; cy = y; break;
          }
          case 2: {
            const x = buf[i++], y = buf[i++], qx = buf[i++], qy = buf[i++]; pt(x, y); pt(qx, qy);
            if (!have) { start(qx, qy); sx = cx = qx; sy = cy = qy; have = true; }
            if (!cur) start(cx, cy);
            flattenQuad(cur.pts, cx, cy, qx, qy, x, y, tol); cx = x; cy = y; break;
          }
          case 3: {
            const x = buf[i++], y = buf[i++], c1x = buf[i++], c1y = buf[i++], c2x = buf[i++], c2y = buf[i++]; pt(x, y); pt(c1x, c1y); pt(c2x, c2y);
            if (!have) { start(c1x, c1y); sx = cx = c1x; sy = cy = c1y; have = true; }
            if (!cur) start(cx, cy);
            flattenCubic(cur.pts, cx, cy, c1x, c1y, c2x, c2y, x, y, tol); cx = x; cy = y; break;
          }
          case 4: if (cur) { cur.closed = true; cur = null; } cx = sx; cy = sy; break;
          default: throw new Error('unknown path tag ' + tag);
        }
      }
      return i;
    }
    function rrectContour(x, y, w, h, r, m) {
      r = Math.max(0, Math.min(r, Math.abs(w) / 2, Math.abs(h) / 2));
      const pts = [];
      if (r <= 0) { pts.push(x, y, x + w, y, x + w, y + h, x, y + h); return { pts, closed: true }; }
      const rd = r * scaleOf(m);
      const step = 2 * Math.acos(Math.max(-1, 1 - 0.2 / Math.max(rd, 0.2)));
      const n = Math.max(2, Math.ceil((Math.PI / 2) / Math.max(step, 0.02)));
      const corner = (cx, cy, a0) => { for (let k = 0; k <= n; k++) { const a = a0 + (Math.PI / 2) * k / n; pts.push(cx + r * Math.cos(a), cy + r * Math.sin(a)); } };
      corner(x + w - r, y + r, -Math.PI / 2);
      corner(x + w - r, y + h - r, 0);
      corner(x + r, y + h - r, Math.PI / 2);
      corner(x + r, y + r, Math.PI);
      return { pts, closed: true };
    }

    // Styles for geometry: a colour, or a gradient (kind 4) with parameters read from the buffer.
    // readGradient returns the next index and sets the current style registers.
    let gradTint = 0;
    function readGradient(buf, i, forStroke) {
      const type = buf[i++];
      let t, a0 = 0, a1 = 0, a2 = 0, a3 = 0, b0 = 0, b1 = 0, b2 = 0;
      if (type === 0) { a0 = buf[i++]; a1 = buf[i++]; a2 = buf[i++]; a3 = buf[i++]; t = 0; }
      else if (type === 1) { const cx = buf[i++], cy = buf[i++]; b0 = buf[i++]; b1 = buf[i++]; a0 = a2 = cx; a1 = a3 = cy; t = 1; }
      else if (type === 2) { a0 = buf[i++]; a1 = buf[i++]; a2 = buf[i++]; t = 2; }
      else if (type === 3) { a0 = buf[i++]; a1 = buf[i++]; b0 = buf[i++]; a2 = buf[i++]; a3 = buf[i++]; b1 = buf[i++]; t = 1; }
      else {
        const cx = buf[i++], cy = buf[i++]; b0 = buf[i++]; b1 = buf[i++]; const aspect = buf[i++];
        // Strokes and text take the circle of the horizontal radius (as the Canvas2D painter).
        if (forStroke) { a0 = a2 = cx; a1 = a3 = cy; t = 1; } else { a0 = cx; a1 = cy; b2 = aspect || 1; t = 4; }
      }
      const n = buf[i++];
      const stops = [];
      for (let k = 0; k < n; k++) { stops.push(Math.min(Math.max(buf[i++], 0), 1), buf[i++], buf[i++], buf[i++], buf[i++]); }
      const row = rampRow(stops);
      p00 = a0; p01 = a1; p02 = a2; p03 = a3; p10 = b0; p11 = b1; p12 = b2; p13 = t;
      cr = row; cg = 0; cb = 0; ca = 1;
      gradTint = 1;
      return i;
    }
    function styleColor(r, g, b, a) { setColor(r, g, b, a); kind = 0; gradTint = 0; }

    // Triangles from user-space points (flat array, 3 points a triangle) through m.
    function emitTriangles(tris, m, box) {
      const n = tris.length / 2;
      ensure(n);
      for (let k = 0; k < tris.length; k += 2) {
        const x = tris[k], y = tris[k + 1];
        const dx = m[0] * x + m[2] * y + m[4], dy = m[1] * x + m[3] * y + m[5];
        vert(dx, dy, 0, 0, x, y);
        if (box) unionBox(box, dx, dy, dx, dy);
      }
    }
    function fanTriangles(pts, out) {
      for (let k = 2; k + 3 < pts.length; k += 2) out.push(pts[0], pts[1], pts[k], pts[k + 1], pts[k + 2], pts[k + 3]);
    }
    function isConvex(pts, m) {
      const n = pts.length / 2;
      if (n < 3) return false;
      let sign = 0, turn = 0;
      for (let k = 0; k < n; k++) {
        const ax = pts[2 * k], ay = pts[2 * k + 1];
        const bx = pts[2 * ((k + 1) % n)], by = pts[2 * ((k + 1) % n) + 1];
        const cx = pts[2 * ((k + 2) % n)], cy = pts[2 * ((k + 2) % n) + 1];
        const ux = bx - ax, uy = by - ay, vx = cx - bx, vy = cy - by;
        const cross = ux * vy - uy * vx, dot = ux * vx + uy * vy;
        if (Math.abs(cross) < 1e-12 * (Math.abs(dot) + 1e-12)) { if (dot < 0) return false; continue; }
        const s = cross > 0 ? 1 : -1;
        if (sign === 0) sign = s; else if (s !== sign) return false;
        turn += Math.atan2(cross, dot);
      }
      return Math.abs(Math.abs(turn) - 2 * Math.PI) < 0.01;
    }
    // A cover quad over a device box, its local coordinates through the inverse transform.
    function emitCover(b, m) {
      const inv = inverse(m) || [1, 0, 0, 1, 0, 0];
      ensure(6);
      const q = [[b.x0, b.y0], [b.x1, b.y0], [b.x1, b.y1], [b.x0, b.y0], [b.x1, b.y1], [b.x0, b.y1]];
      for (const [x, y] of q) vert(x, y, 0, 0, inv[0] * x + inv[2] * y + inv[4], inv[1] * x + inv[3] * y + inv[5]);
    }
    // Writes the path's winding into the stencil's low bits (within the current clip level).
    function stencilPath(eo, m) {
      flush();
      const tris = [];
      for (const c of contours) if (c.pts.length >= 6) fanTriangles(c.pts, tris);
      if (!tris.length) return false;
      const saveKind = kind; kind = 0;
      emitTriangles(tris, m, null);
      kind = saveKind;
      const clip = layer.state.clip << 4;
      drawBatch(() => {
        gl.enable(gl.STENCIL_TEST);
        gl.colorMask(false, false, false, false);
        gl.stencilFunc(gl.EQUAL, clip, 0xF0);
        if (eo) { gl.stencilMask(0x01); gl.stencilOp(gl.KEEP, gl.KEEP, gl.INVERT); }
        else { gl.stencilMask(0x0F); gl.stencilOpSeparate(gl.FRONT, gl.KEEP, gl.KEEP, gl.INCR_WRAP); gl.stencilOpSeparate(gl.BACK, gl.KEEP, gl.KEEP, gl.DECR_WRAP); }
      });
      stats.stencilPaths++;
      return true;
    }
    function deviceBoxOfContours(m) {
      const b = emptyBox();
      for (const c of contours) for (let k = 0; k < c.pts.length; k += 2) { const x = c.pts[k], y = c.pts[k + 1]; const dx = m[0] * x + m[2] * y + m[4], dy = m[1] * x + m[3] * y + m[5]; unionBox(b, dx, dy, dx, dy); }
      return b;
    }
    // Fills the contours just read with the current style.
    function fillContours(eo, m) {
      const live = contours.filter(c => c.pts.length >= 6);
      if (!live.length) return;
      const box = deviceBoxOfContours(m);
      if (live.length === 1 && isConvex(live[0].pts, m)) {
        const tris = [];
        fanTriangles(live[0].pts, tris);
        emitTriangles(tris, m, null);
      } else {
        const saved = saveStyle();
        if (!stencilPath(eo, m)) return;
        restoreStyle(saved);
        const b = { x0: Math.floor(box.x0) - 1, y0: Math.floor(box.y0) - 1, x1: Math.ceil(box.x1) + 1, y1: Math.ceil(box.y1) + 1 };
        emitCover(b, m);
        const clip = layer.state.clip << 4;
        drawBatch(() => {
          gl.enable(gl.STENCIL_TEST);
          gl.stencilFunc(gl.LESS, clip, 0xFF);
          gl.stencilMask(0x0F);
          gl.stencilOp(gl.KEEP, gl.KEEP, gl.REPLACE);
        });
      }
      markPainted(box, 1);
    }
    function saveStyle() { return [cr, cg, cb, ca, p00, p01, p02, p03, p10, p11, p12, p13, kind, gradTint]; }
    function restoreStyle(s) { [cr, cg, cb, ca, p00, p01, p02, p03, p10, p11, p12, p13, kind, gradTint] = s; }
    function markPainted(b, pad) {
      const p = pad || 0;
      unionBox(layer.box, b.x0 - p, b.y0 - p, b.x1 + p, b.y1 + p);
      unionBox(layer.touched, b.x0 - p, b.y0 - p, b.x1 + p, b.y1 + p);
    }

    // --- Strokes.
    function dedupe(pts, closed) {
      const out = [pts[0], pts[1]];
      for (let k = 2; k < pts.length; k += 2) {
        const x = pts[k], y = pts[k + 1];
        if (Math.abs(x - out[out.length - 2]) > 1e-9 || Math.abs(y - out[out.length - 1]) > 1e-9) out.push(x, y);
      }
      if (closed && out.length > 4 && Math.abs(out[0] - out[out.length - 2]) < 1e-9 && Math.abs(out[1] - out[out.length - 1]) < 1e-9) out.length -= 2;
      return out;
    }
    function dashContour(pts, closed, dashes, phase, out) {
      const total = dashes.reduce((a, b) => a + b, 0);
      const seq = closed ? pts.concat([pts[0], pts[1]]) : pts;
      let pos = ((phase % total) + total) % total;
      let di = 0;
      while (pos >= dashes[di]) { pos -= dashes[di]; di = (di + 1) % dashes.length; }
      let remaining = dashes[di] - pos;
      let on = di % 2 === 0;
      let piece = on ? [seq[0], seq[1]] : null;
      for (let k = 0; k + 3 < seq.length; k += 2) {
        let ax = seq[k], ay = seq[k + 1];
        const bx = seq[k + 2], by = seq[k + 3];
        let len = Math.hypot(bx - ax, by - ay);
        while (len > 0) {
          if (len < remaining) {
            if (on) piece.push(bx, by);
            remaining -= len; len = 0;
          } else {
            const f = remaining / len;
            const mx = ax + (bx - ax) * f, my = ay + (by - ay) * f;
            if (on) { piece.push(mx, my); out.push({ pts: piece, closed: false }); piece = null; }
            else piece = [mx, my];
            on = !on;
            len -= remaining; ax = mx; ay = my;
            di = (di + 1) % dashes.length;
            remaining = dashes[di];
          }
        }
      }
      if (on && piece && piece.length >= 4) out.push({ pts: piece, closed: false });
    }
    function arcFan(out, cx, cy, ux, uy, vx, vy, r, step) {
      // Fan from direction u to direction v (unit vectors) the short way round.
      const a0 = Math.atan2(uy, ux);
      let da = Math.atan2(vy, vx) - a0;
      while (da > Math.PI) da -= 2 * Math.PI;
      while (da < -Math.PI) da += 2 * Math.PI;
      const n = Math.max(1, Math.ceil(Math.abs(da) / step));
      let px = cx + ux * r, py = cy + uy * r;
      for (let k = 1; k <= n; k++) {
        const a = a0 + da * k / n;
        const qx = cx + Math.cos(a) * r, qy = cy + Math.sin(a) * r;
        out.push(cx, cy, px, py, qx, qy);
        px = qx; py = qy;
      }
    }
    function strokeContour(raw, closed, hw, cap, join, miter, step, out) {
      const p = dedupe(raw, closed);
      const n = p.length / 2;
      if (n === 1) {
        if (raw.length < 4) return;   // a lone moveTo
        const x = p[0], y = p[1];
        if (cap === 1) { arcFan(out, x, y, 1, 0, -1, 0, hw, step); arcFan(out, x, y, -1, 0, 1, 0, hw, step); }
        else if (cap === 2) out.push(x - hw, y - hw, x + hw, y - hw, x + hw, y + hw, x - hw, y - hw, x + hw, y + hw, x - hw, y + hw);
        return;
      }
      const segs = closed ? n : n - 1;
      const dir = [];
      for (let s = 0; s < segs; s++) {
        const a = s, b = (s + 1) % n;
        const dx = p[2 * b] - p[2 * a], dy = p[2 * b + 1] - p[2 * a + 1];
        const l = Math.hypot(dx, dy);
        dir.push(dx / l, dy / l);
        const nx = -dy / l * hw, ny = dx / l * hw;
        const ax = p[2 * a], ay = p[2 * a + 1], bx = p[2 * b], by = p[2 * b + 1];
        out.push(ax + nx, ay + ny, ax - nx, ay - ny, bx - nx, by - ny, ax + nx, ay + ny, bx - nx, by - ny, bx + nx, by + ny);
      }
      const joinAt = (v, s0, s1) => {
        const d0x = dir[2 * s0], d0y = dir[2 * s0 + 1], d1x = dir[2 * s1], d1y = dir[2 * s1 + 1];
        const cross = d0x * d1y - d0y * d1x, dot = d0x * d1x + d0y * d1y;
        if (Math.abs(cross) < 1e-9 && dot > 0) return;
        const side = cross > 0 ? -1 : 1;
        const px = p[2 * v], py = p[2 * v + 1];
        const n0x = -d0y * side, n0y = d0x * side, n1x = -d1y * side, n1y = d1x * side;
        const ax = px + n0x * hw, ay = py + n0y * hw, bx = px + n1x * hw, by = py + n1y * hw;
        if (join === 1) { arcFan(out, px, py, n0x, n0y, n1x, n1y, hw, step); return; }
        if (join === 0) {
          const cosHalf = Math.sqrt(Math.max(0, (1 + dot) / 2));
          if (cosHalf > 1e-9 && 1 / cosHalf <= miter) {
            let mx = n0x + n1x, my = n0y + n1y;
            const ml = Math.hypot(mx, my);
            if (ml > 1e-9) {
              mx = mx / ml * hw / cosHalf; my = my / ml * hw / cosHalf;
              out.push(px, py, ax, ay, px + mx, py + my, px, py, px + mx, py + my, bx, by);
              return;
            }
          }
        }
        out.push(px, py, ax, ay, bx, by);
      };
      if (closed) { for (let v = 0; v < n; v++) joinAt(v, (v - 1 + n) % n, v % segs); }
      else {
        for (let v = 1; v < n - 1; v++) joinAt(v, v - 1, v);
        const capAt = (x, y, dx, dy) => {   // (dx, dy): outward
          const nx = -dy * hw, ny = dx * hw;
          if (cap === 2) { const ex = x + dx * hw, ey = y + dy * hw; out.push(x + nx, y + ny, x - nx, y - ny, ex - nx, ey - ny, x + nx, y + ny, ex - nx, ey - ny, ex + nx, ey + ny); }
          else if (cap === 1) { arcFan(out, x, y, -dy, dx, dx, dy, hw, step); arcFan(out, x, y, dx, dy, dy, -dx, hw, step); }
        };
        capAt(p[0], p[1], -dir[0], -dir[1]);
        capAt(p[2 * (n - 1)], p[2 * (n - 1) + 1], dir[2 * (segs - 1)], dir[2 * (segs - 1) + 1]);
      }
    }
    // Strokes the contours just read with the current style (colour or gradient).
    function strokeContours(width, cap, join, miter, dashes, phase, m, translucent) {
      if (!(width > 0)) return;
      const scale = scaleOf(m);
      let hw = width / 2;
      const devWidth = width * scale;
      let alphaScale = 1;
      if (devWidth < 1) { hw = 0.5 / scale; alphaScale = devWidth; }
      let pieces = contours;
      const total = dashes.reduce((a, b) => a + b, 0);
      if (dashes.length && total > 0 && dashes.every(d => d >= 0 && isFinite(d))) {
        const ds = dashes.length % 2 ? dashes.concat(dashes) : dashes;
        pieces = [];
        for (const c of contours) { const q = dedupe(c.pts, c.closed); if (q.length >= 4) dashContour(q, c.closed, ds, phase, pieces); }
      }
      const step = 2 * Math.acos(Math.max(-1, 1 - 0.2 / Math.max(hw * scale, 0.2)));
      const tris = [];
      for (const c of pieces) if (c.pts.length >= 2) strokeContour(c.pts, c.closed, hw, cap, join, miter, Math.max(step, 0.05), tris);
      if (!tris.length) return;
      if (alphaScale < 1) { cr *= alphaScale; cg *= alphaScale; cb *= alphaScale; ca *= alphaScale; }
      const box = emptyBox();
      if (!translucent && alphaScale === 1) { emitTriangles(tris, m, box); markPainted(box, 1); return; }
      // Overlapping triangles would paint twice: the stencil lets each sample through once.
      const style = saveStyle();
      flush();
      restoreStyle(style);
      emitTriangles(tris, m, box);
      const clip = layer.state.clip << 4;
      drawBatch(() => {
        gl.enable(gl.STENCIL_TEST);
        gl.stencilFunc(gl.EQUAL, clip, 0xFF);
        gl.stencilMask(0x0F);
        gl.stencilOp(gl.KEEP, gl.KEEP, gl.INCR);
      });
      clearLowBits(box);
      markPainted(box, 1);
    }
    function clearLowBits(box) {
      const b = { x0: Math.floor(box.x0) - 1, y0: Math.floor(box.y0) - 1, x1: Math.ceil(box.x1) + 1, y1: Math.ceil(box.y1) + 1 };
      const saveKind = kind; kind = 0;
      emitCover(b, layer.state.m);
      kind = saveKind;
      const clip = layer.state.clip << 4;
      drawBatch(() => {
        gl.enable(gl.STENCIL_TEST);
        gl.colorMask(false, false, false, false);
        gl.stencilFunc(gl.EQUAL, clip, 0xF0);
        gl.stencilMask(0x0F);
        gl.stencilOp(gl.REPLACE, gl.REPLACE, gl.REPLACE);
      });
    }

    // --- Clips.
    function resetClips(toDepth, boxes) {
      if (!boxes.length) return;
      const b = emptyBox();
      for (const c of boxes) unionBox(b, c.x0, c.y0, c.x1, c.y1);
      const saved = saveStyle();
      kind = 0;
      emitCover(b, layer.state.m);
      restoreStyle(saved);
      const ref = toDepth << 4;
      drawBatch(() => {
        gl.enable(gl.STENCIL_TEST);
        gl.colorMask(false, false, false, false);
        gl.stencilFunc(gl.LESS, ref | 0x0F, 0xFF);
        gl.stencilMask(0xF0);
        gl.stencilOp(gl.KEEP, gl.KEEP, gl.REPLACE);
      });
    }

    // stencilFunc's reference is both the test value and what REPLACE writes, so the "promote to
    // the next level" cover uses a test on the low bits only: NOTEQUAL 0 under mask 0x0F within
    // the current level is guaranteed by stencilPath (it only counted inside the level).
    function promoteClip(b, depth) {
      const saved = saveStyle();
      kind = 0;
      emitCover(b, layer.state.m);
      restoreStyle(saved);
      const ref = (depth + 1) << 4;
      drawBatch(() => {
        gl.enable(gl.STENCIL_TEST);
        gl.colorMask(false, false, false, false);
        gl.stencilFunc(gl.NOTEQUAL, ref, 0x0F);   // (stencil & 0x0F) != 0
        gl.stencilMask(0xFF);
        gl.stencilOp(gl.KEEP, gl.KEEP, gl.REPLACE);
      });
    }
    function clipPathOp(eo) {
      const st = layer.state;
      const m = st.m;
      if (st.clip >= 15) { if (info.errors.length < 20) info.errors.push('clip depth over 15'); return; }
      const box = deviceBoxOfContours(m);
      const b = { x0: Math.floor(box.x0) - 1, y0: Math.floor(box.y0) - 1, x1: Math.ceil(box.x1) + 1, y1: Math.ceil(box.y1) + 1 };
      const saved = saveStyle();
      const any = stencilPath(eo, m);
      if (any) promoteClip(b, st.clip);
      restoreStyle(saved);
      st.clip++;
      st.clips = st.clips.concat([b]);
      unionBox(layer.touched, b.x0, b.y0, b.x1, b.y1);
    }
    function clipRectOp(x, y, w, h) {
      const st = layer.state, m = st.m;
      if (axisAligned(m)) {
        const b = deviceRectBox(m, x, y, w, h);
        const near = v => Math.abs(v - Math.round(v)) < 0.01;
        if (near(b.x0) && near(b.y0) && near(b.x1) && near(b.y1)) {
          flush();
          const r = { x0: Math.max(0, Math.round(b.x0)), y0: Math.max(0, Math.round(b.y0)), x1: Math.min(W, Math.round(b.x1)), y1: Math.min(H, Math.round(b.y1)) };
          const s = st.scissor;
          st.scissor = s ? { x0: Math.max(s.x0, r.x0), y0: Math.max(s.y0, r.y0), x1: Math.min(s.x1, r.x1), y1: Math.min(s.y1, r.y1) } : r;
          if (st.scissor.x1 < st.scissor.x0) st.scissor.x1 = st.scissor.x0;
          if (st.scissor.y1 < st.scissor.y0) st.scissor.y1 = st.scissor.y0;
          return;
        }
      }
      contours = [{ pts: [x, y, x + w, y, x + w, y + h, x, y + h], closed: true }];
      clipPathOp(false);
    }

    function save() { const s = layer.state; layer.stack.push(s); layer.state = { m: s.m.slice(), scissor: s.scissor, clip: s.clip, clips: s.clips }; }
    function restore() {
      if (!layer.stack.length) return;
      flush();
      const popped = layer.state;
      layer.state = layer.stack.pop();
      if (popped.clip > layer.state.clip) resetClips(layer.state.clip, popped.clips.slice(layer.state.clip));
    }

    // --- Rect fills.
    function fillRectOp(x, y, w, h, radius) {
      const m = layer.state.m;
      if (w < 0) { x += w; w = -w; }
      if (h < 0) { y += h; h = -h; }
      if (w === 0 || h === 0) return;
      const uniform = Math.abs(Math.abs(m[0]) - Math.abs(m[3])) < 1e-6;
      if (axisAligned(m) && (radius === 0 || uniform)) {
        const b = deviceRectBox(m, x, y, w, h);
        const r = Math.max(0, Math.min(radius, w / 2, h / 2)) * Math.abs(m[0]);
        const savedKind = kind;
        p00 = (b.x0 + b.x1) / 2; p01 = (b.y0 + b.y1) / 2; p02 = (b.x1 - b.x0) / 2; p03 = (b.y1 - b.y0) / 2; p10 = r; p11 = 0; p12 = 0; p13 = 0;
        kind = 1;
        const x0 = Math.floor(b.x0) - 1, y0 = Math.floor(b.y0) - 1, x1 = Math.ceil(b.x1) + 1, y1 = Math.ceil(b.y1) + 1;
        ensure(6);
        vert(x0, y0, 0, 0, 0, 0); vert(x1, y0, 0, 0, 0, 0); vert(x1, y1, 0, 0, 0, 0);
        vert(x0, y0, 0, 0, 0, 0); vert(x1, y1, 0, 0, 0, 0); vert(x0, y1, 0, 0, 0, 0);
        kind = savedKind;
        markPainted(b, 1);
        return;
      }
      contours = [rrectContour(x, y, w, h, radius, m)];
      fillContours(false, m);
    }

    // --- Images.
    function quad(m, x, y, w, h, u0, v0, u1, v1, box) {
      ensure(6);
      const [ax, ay] = dev(m, x, y), [bx, by] = dev(m, x + w, y), [cx, cy] = dev(m, x + w, y + h), [dx, dy] = dev(m, x, y + h);
      vert(ax, ay, u0, v0, x, y); vert(bx, by, u1, v0, x + w, y); vert(cx, cy, u1, v1, x + w, y + h);
      vert(ax, ay, u0, v0, x, y); vert(cx, cy, u1, v1, x + w, y + h); vert(dx, dy, u0, v1, x, y + h);
      if (box) { unionBox(box, Math.min(ax, bx, cx, dx), Math.min(ay, by, cy, dy), Math.max(ax, bx, cx, dx), Math.max(ay, by, cy, dy)); }
    }
    function imagePart(m, tex, sx, sy, sw, sh, dx, dy, dw, dh, tile, scale, box) {
      if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
      const u0 = sx / tex.w, v0 = sy / tex.h, u1 = (sx + sw) / tex.w, v1 = (sy + sh) / tex.h;
      if (!tile) { quad(m, dx, dy, dw, dh, u0, v0, u1, v1, box); return; }
      const tw = sw / scale, th = sh / scale;
      for (let y = dy; y < dy + dh - 1e-9; y += th) {
        for (let x = dx; x < dx + dw - 1e-9; x += tw) {
          const w = Math.min(tw, dx + dw - x), h = Math.min(th, dy + dh - y);
          quad(m, x, y, w, h, u0, v0, u0 + (u1 - u0) * (w / tw), v0 + (v1 - v0) * (h / th), box);
        }
      }
    }
    function drawImageOp(file, scale, pw, ph, x, y, w, h, tile, top, leading, bottom, trailing, smoothing, tintKind, tint) {
      const entry = image(file);
      if (!entry) return;
      const m = layer.state.m;
      const s = scaleOf(m);
      const tex = imageTexture(entry, w * s, h * s);
      useTexture(tex.tex, !smoothing);
      if (tintKind === 0) { kind = 2; cr = cg = cb = 0; ca = 1; }
      else if (tintKind === 1) { kind = 3; setColor(tint[0], tint[1], tint[2], tint[3]); }
      else { kind = 5; }
      const box = emptyBox();
      if (top === 0 && leading === 0 && bottom === 0 && trailing === 0) {
        imagePart(m, tex, 0, 0, tex.w, tex.h, x, y, w, h, tile, scale * (tex.w / (pw || tex.w)), box);
      } else {
        const k = tex.w / (pw || tex.w);
        const l = leading * scale * k, r = trailing * scale * k, t = top * scale * k, b = bottom * scale * k;
        const sxs = [0, l, tex.w - r], sws = [l, tex.w - l - r, r];
        const sys = [0, t, tex.h - b], shs = [t, tex.h - t - b, b];
        const dxs = [x, x + leading, x + w - trailing], dws = [leading, w - leading - trailing, trailing];
        const dys = [y, y + top, y + h - bottom], dhs = [top, h - top - bottom, bottom];
        for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) {
          const rigid = i !== 1 && j !== 1;
          imagePart(m, tex, sxs[i], sys[j], sws[i], shs[j], dxs[i], dys[j], dws[i], dhs[j], tile && !rigid, scale * k, box);
        }
      }
      if (box.x1 > box.x0) markPainted(box, 1);
    }
    function drawBitmapOp(bitmap, x, y, w, h) {
      if (!bitmap) return;
      const tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, bitmap.width, bitmap.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(bitmap.pixels.buffer, bitmap.pixels.byteOffset, bitmap.pixels.byteLength));
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      frameTextures.push(tex);
      useTexture(tex, false);
      kind = 2; cr = cg = cb = 0; ca = 1;
      const box = emptyBox();
      quad(layer.state.m, x, y, w, h, 0, 0, 1, 1, box);
      markPainted(box, 1);
    }

    // --- Text.
    function drawTextOp(text, font, x, y, fill, gradient) {
      if (!text) return;
      stats.texts++;
      const m = layer.state.m;
      let e, x0, y0, sx, sy, k;
      if (axisAligned(m) && m[0] > 0 && m[3] > 0) {
        sx = m[0]; sy = m[3];
        const X = m[0] * x + m[4], Y = m[3] * y + m[5];
        const fx = Math.round((X - Math.floor(X)) * 16) / 16, fy = Math.round((Y - Math.floor(Y)) * 16) / 16;
        e = textEntry(text, font, gradient ? '#fff' : fill, sx, sy, fx, fy);
        if (!e) return;
        x0 = Math.floor(X) - e.ox; y0 = Math.floor(Y) - e.oy;
        useTextureKeep();
        if (gradient) kind = 7; else { kind = 6; cr = cg = cb = 0; ca = 1; }
        ensure(6);
        const u0 = e.x / ATLAS, v0 = e.y / ATLAS, u1 = (e.x + e.w) / ATLAS, v1 = (e.y + e.h) / ATLAS;
        const inv = inverse(m) || [1, 0, 0, 1, 0, 0];
        const L = (px, py) => [inv[0] * px + inv[2] * py + inv[4], inv[1] * px + inv[3] * py + inv[5]];
        const x1 = x0 + e.w, y1 = y0 + e.h;
        const la = L(x0, y0), lb = L(x1, y0), lc = L(x1, y1), ld = L(x0, y1);
        vert(x0, y0, u0, v0, la[0], la[1]); vert(x1, y0, u1, v0, lb[0], lb[1]); vert(x1, y1, u1, v1, lc[0], lc[1]);
        vert(x0, y0, u0, v0, la[0], la[1]); vert(x1, y1, u1, v1, lc[0], lc[1]); vert(x0, y1, u0, v1, ld[0], ld[1]);
        markPainted({ x0, y0, x1, y1 }, 0);
        return;
      }
      k = Math.min(8, scaleOf(m));
      e = textEntry(text, font, gradient ? '#fff' : fill, k, k, 0, 0);
      if (!e) return;
      useTextureKeep();
      if (gradient) kind = 7; else { kind = 6; cr = cg = cb = 0; ca = 1; }
      const box = emptyBox();
      quad(m, x - e.ox / k, y - e.oy / k, e.w / k, e.h / k, e.x / ATLAS, e.y / ATLAS, (e.x + e.w) / ATLAS, (e.y + e.h) / ATLAS, box);
      markPainted(box, 1);
    }
    // Text reads the atlas (its own texture unit): the batch's image texture can stay.
    function useTextureKeep() {}

    // --- Groups.
    function pushLayer(props) {
      flush();
      stats.groups++;
      const parent = layer;
      const target = acquireTarget(W, H);
      layer = Object.assign({ target, state: freshState(parent.state.m), stack: [], box: emptyBox(), touched: emptyBox(), parent }, props);
      layers.push(layer);
    }
    function resolve(target, r) {
      gl.disable(gl.SCISSOR_TEST);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, target.fb);
      gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, target.resolveFb);
      gl.blitFramebuffer(r.x0, H - r.y1, r.x1, H - r.y0, r.x0, H - r.y1, r.x1, H - r.y0, gl.COLOR_BUFFER_BIT, gl.NEAREST);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    }
    function fullView(target) { return { tex: target.tex, x0: 0, y1: H, k: 1, w: target.W, h: target.H }; }
    // A pass over a temporary (full viewport), with the pass program bound by the caller.
    function runPass(temp) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, temp.fb);
      gl.viewport(0, 0, temp.W, temp.H);
      gl.disable(gl.SCISSOR_TEST); gl.disable(gl.STENCIL_TEST); gl.disable(gl.BLEND);
      gl.colorMask(true, true, true, true);
      gl.bindVertexArray(passVao);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
      stats.draws++;
    }
    function bindTex(unit, tex, nearest) { gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, tex); gl.bindSampler(unit, nearest ? samplerNearest : null); }
    // Gaussian blur of `view` within device box r (ints): returns a view of the result.
    function blur(view, r, sigma) {
      const k = sigma > 4 ? Math.max(1, Math.min(8, Math.floor(sigma / 4))) : 1;
      const w = Math.max(1, Math.ceil((r.x1 - r.x0) / k)), h = Math.max(1, Math.ceil((r.y1 - r.y0) / k));
      const a = takeTemp(w, h), b = takeTemp(w, h);
      const dstView = { x0: r.x0, y1: r.y0 + a.H * k, k };
      gl.useProgram(progCopy.p);
      bindTex(0, view.tex, false);
      gl.uniform1i(progCopy.u.u_src, 0);
      gl.uniform3f(progCopy.u.u_srcView, view.x0, view.y1, view.k);
      gl.uniform2f(progCopy.u.u_srcSize, view.w, view.h);
      gl.uniform4f(progCopy.u.u_clamp, r.x0, r.y0, r.x1, r.y1);
      gl.uniform3f(progCopy.u.u_dstView, dstView.x0, dstView.y1, k);
      runPass(a);
      const s = sigma / k;
      const radius = Math.min(256, Math.ceil(s * 3));
      gl.useProgram(progBlur.p);
      gl.uniform1i(progBlur.u.u_src, 0);
      gl.uniform1f(progBlur.u.u_sigma, Math.max(s, 1e-3));
      gl.uniform1i(progBlur.u.u_radius, radius);
      bindTex(0, a.tex, true);
      gl.uniform2f(progBlur.u.u_dir, 1, 0);
      runPass(b);
      bindTex(0, b.tex, true);
      gl.uniform2f(progBlur.u.u_dir, 0, 1);
      runPass(a);
      return { tex: a.tex, x0: dstView.x0, y1: dstView.y1, k, w: a.W, h: a.H };
    }
    // Draws a composite quad over device box r into the current layer's target.
    function composite(r, opts) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, layer.target.fb);
      gl.viewport(0, 0, W, H);
      applyScissor();
      normalStencil();
      gl.useProgram(progComp.p);
      const u = progComp.u;
      gl.uniform2f(u.u_size, W, H);
      const src = opts.src;
      bindTex(0, src.tex, false); gl.uniform1i(u.u_src, 0);
      gl.uniform3f(u.u_srcView, src.x0, src.y1, src.k); gl.uniform2f(u.u_srcSize, src.w, src.h);
      const c = opts.srcClamp || { x0: -1e9, y0: -1e9, x1: 1e9, y1: 1e9 };
      gl.uniform4f(u.u_srcClamp, c.x0, c.y0, c.x1, c.y1);
      const aux = opts.aux;
      gl.uniform1i(u.u_aux_mode, opts.auxMode || 0);
      bindTex(1, aux ? aux.tex : src.tex, false); gl.uniform1i(u.u_aux, 1);
      gl.uniform3f(u.u_auxView, aux ? aux.x0 : 0, aux ? aux.y1 : 0, aux ? aux.k : 1); gl.uniform2f(u.u_auxSize, aux ? aux.w : 1, aux ? aux.h : 1);
      const dst = opts.dst;
      bindTex(3, dst ? dst.tex : src.tex, false); gl.uniform1i(u.u_dst, 3);
      gl.uniform3f(u.u_dstView, dst ? dst.x0 : 0, dst ? dst.y1 : 0, dst ? dst.k : 1); gl.uniform2f(u.u_dstSize, dst ? dst.w : 1, dst ? dst.h : 1);
      gl.uniform1i(u.u_matrix_on, opts.matrix ? 1 : 0);
      if (opts.matrix) { gl.uniform1fv(u.u_m, new Float32Array(opts.matrix)); const mr = opts.matrixRect; gl.uniform4f(u.u_matrixRect, mr.x0, mr.y0, mr.x1, mr.y1); }
      gl.uniform1i(u.u_tint_on, opts.tint ? 1 : 0);
      if (opts.tint) gl.uniform4f(u.u_tint, opts.tint[0], opts.tint[1], opts.tint[2], opts.tint[3]);
      gl.uniform1f(u.u_opacity, opts.opacity === undefined ? 1 : opts.opacity);
      gl.uniform2f(u.u_offset, opts.offset ? opts.offset[0] : 0, opts.offset ? opts.offset[1] : 0);
      gl.uniform1i(u.u_blend, opts.shaderBlend || 0);
      if (opts.shaderBlend) gl.disable(gl.BLEND);
      else {
        gl.enable(gl.BLEND);
        const f = opts.blendFunc || [gl.ONE, gl.ONE_MINUS_SRC_ALPHA];
        gl.blendFunc(f[0], f[1]);
      }
      // The quad as main-program vertices (only the position matters).
      const saved = saveStyle();
      kind = 0; cr = cg = cb = ca = 0;
      const start = count;
      ensure(6);
      vert(r.x0, r.y0, 0, 0, 0, 0); vert(r.x1, r.y0, 0, 0, 0, 0); vert(r.x1, r.y1, 0, 0, 0, 0);
      vert(r.x0, r.y0, 0, 0, 0, 0); vert(r.x1, r.y1, 0, 0, 0, 0); vert(r.x0, r.y1, 0, 0, 0, 0);
      restoreStyle(saved);
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
      gl.bufferData(gl.ARRAY_BUFFER, verts.subarray(start * STRIDE, count * STRIDE), gl.STREAM_DRAW);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
      count = start;
      stats.draws++;
      gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      unionBox(layer.box, r.x0, r.y0, r.x1, r.y1);
      unionBox(layer.touched, r.x0, r.y0, r.x1, r.y1);
    }
    const blendNames = ['source-over', 'multiply', 'screen', 'overlay', 'darken', 'lighten', 'color-dodge', 'color-burn', 'soft-light', 'hard-light',
      'difference', 'exclusion', 'hue', 'saturation', 'color', 'luminosity', 'source-atop', 'destination-over', 'destination-out', 'plus-darker', 'lighter'];
    function blendFuncFor(mode) {
      switch (mode) {
        case 16: return [gl.DST_ALPHA, gl.ONE_MINUS_SRC_ALPHA];
        case 17: return [gl.ONE_MINUS_DST_ALPHA, gl.ONE];
        case 18: return [gl.ZERO, gl.ONE_MINUS_SRC_ALPHA];
        case 20: return [gl.ONE, gl.ONE];
        default: return null;
      }
    }
    function endGroup() {
      flush();
      const g = layers.pop();
      const parent = g.parent;
      layer = parent;
      let region = g.box;
      if (g.filter && g.bounds) region = { x0: Math.min(region.x0, g.bounds.x0), y0: Math.min(region.y0, g.bounds.y0), x1: Math.max(region.x1, g.bounds.x1), y1: Math.max(region.y1, g.bounds.y1) };
      const r = clampInts(region, W, H, 0);
      if (r) {
        resolve(g.target, r);
        let src = fullView(g.target);
        const opts = { src, opacity: g.opacity === undefined ? 1 : g.opacity };
        if (g.maskTarget) { resolve(g.maskTarget, r); opts.aux = fullView(g.maskTarget); opts.auxMode = 1; }
        if (g.filter) {
          if (g.filter.matrix) { opts.matrix = g.filter.matrix; opts.matrixRect = g.bounds; }
          else if (g.filter.sigma > 0 && g.bounds) {
            const br = clampInts(g.bounds, W, H, 0);
            if (br) {
              const blurred = blur(src, br, g.filter.sigma);
              if (g.filter.opaque) { opts.aux = src; opts.auxMode = 2; }
              opts.src = blurred;
              opts.srcClamp = br;
            }
          }
        }
        let reach = 0;
        if (g.shadow) {
          const sigma = g.shadow.radius * DPR;
          const dx = g.shadow.dx * DPR, dy = g.shadow.dy * DPR;
          reach = Math.ceil(sigma * 3) + Math.abs(dx) + Math.abs(dy);
          const sr = clampInts(r, W, H, Math.ceil(sigma * 3) + 1);
          const shadowSrc = sigma > 0 ? blur(src, sr, sigma) : src;
          const c = g.shadow.color;
          const tint = [c[0] / 255 * c[3], c[1] / 255 * c[3], c[2] / 255 * c[3], c[3]];
          const dr = clampInts({ x0: sr.x0 + dx, y0: sr.y0 + dy, x1: sr.x1 + dx, y1: sr.y1 + dy }, W, H, 0);
          if (dr) composite(dr, { src: shadowSrc, srcClamp: sr, tint, offset: [dx, dy], opacity: opts.opacity });
        }
        if (g.blend) {
          const f = blendFuncFor(g.blend);
          if (f) opts.blendFunc = f;
          else if (g.blend > 0) {
            resolve(layer.target, r);
            opts.dst = fullView(layer.target);
            opts.shaderBlend = g.blend;
          }
        }
        composite(r, opts);
        if (reach) { unionBox(layer.box, r.x0 - reach, r.y0 - reach, r.x1 + reach, r.y1 + reach); }
      }
      releaseTarget(g.target, g.touched);
      if (g.maskTarget) releaseTarget(g.maskTarget, g.maskTouched);
    }
    function backdropBlurOp(eo, x, y, w, h, radius, saturation) {
      const m = layer.state.m;
      const probeScale = Math.hypot(m[0], m[1]);
      const sigma = radius * probeScale;
      if (!(sigma > 0)) return;
      const b = clampInts(deviceRectBox(m, x, y, w, h), W, H, Math.ceil(sigma * 3));
      if (!b) return;
      const pathContours = contours;
      flush();
      resolve(layer.target, b);
      const src = fullView(layer.target);
      const blurred = blur(src, b, sigma);
      const opts = { src: blurred, srcClamp: b, aux: src, auxMode: 2 };
      if (saturation !== 1) {
        const s = saturation, lr = 0.2126, lg = 0.7152, lb = 0.0722;
        opts.matrix = [lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0, lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0, lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0, 0, 0, 0, 1, 0];
        opts.matrixRect = b;
      }
      save();
      contours = pathContours;
      clipPathOp(eo);
      composite(b, opts);
      restore();
    }

    // --- The frame.
    function sync2d() {
      if (!overlay) return;
      if (glCanvas.width !== W) glCanvas.width = W;
      if (glCanvas.height !== H) glCanvas.height = H;
      const st = glCanvas.style, cs = canvas2d.style;
      const left = canvas2d.offsetLeft + 'px', top = canvas2d.offsetTop + 'px';
      if (st.left !== left) st.left = left;
      if (st.top !== top) st.top = top;
      if (st.width !== cs.width) st.width = cs.width;
      if (st.height !== cs.height) st.height = cs.height;
      if (st.visibility !== 'visible') st.visibility = 'visible';
      if (glCanvas.previousElementSibling !== canvas2d) canvas2d.after(glCanvas);
    }
    function paint(buf, strings, dpr, w, h, bitmaps, forceSync) {
      const started = performance.now();
      stats = { draws: 0, flushes: 0, vertices: 0, stencilPaths: 0, groups: 0, texts: 0, atlasMisses: 0 };
      DPR = dpr;
      const nW = Math.max(1, Math.round(w * dpr)), nH = Math.max(1, Math.round(h * dpr));
      if (nW !== W || nH !== H || !rootTarget) {
        if (rootTarget) deleteTarget(rootTarget);
        while (freeTargets.length) deleteTarget(freeTargets.pop());
        W = nW; H = nH;
        rootTarget = newTarget(W, H);
      }
      if (overlay) sync2d();
      else { if (glCanvas.width !== W) glCanvas.width = W; if (glCanvas.height !== H) glCanvas.height = H; }
      if (twoDDirty && overlay) { ctx2d.setTransform(1, 0, 0, 1, 0, 0); ctx2d.clearRect(0, 0, canvas2d.width, canvas2d.height); twoDDirty = false; }
      gl.bindFramebuffer(gl.FRAMEBUFFER, rootTarget.fb);
      gl.viewport(0, 0, W, H);
      gl.disable(gl.SCISSOR_TEST);
      gl.clearColor(0, 0, 0, 0); gl.clearStencil(0); gl.stencilMask(0xFF); gl.colorMask(true, true, true, true);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);
      layers.length = 0;
      layer = { target: rootTarget, state: freshState([dpr, 0, 0, dpr, 0, 0]), stack: [], box: emptyBox(), touched: emptyBox(), parent: null };
      batchTex = null; batchNearest = false; count = 0;
      kind = 0;
      let i = 0;
      const n = buf.length;
      try {
        while (i < n) {
          const op = buf[i++];
          const m = layer.state.m;
          switch (op) {
            case 1: save(); break;
            case 2: restore(); break;
            case 3: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++]; clipRectOp(x, y, rw, rh); break; }
            case 4: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++], r = buf[i++]; contours = [rrectContour(x, y, rw, rh, r, m)]; clipPathOp(false); break; }
            case 5: { i = readPath(buf, i, m); clipPathOp(buf[i++] === 1); break; }
            case 6: { const opacity = buf[i++]; pushLayer({ opacity }); break; }
            case 7: { if (layers.length) endGroup(); break; }
            case 8: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++]; styleColor(buf[i++], buf[i++], buf[i++], buf[i++]); fillRectOp(x, y, rw, rh, 0); break; }
            case 9: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++], r = buf[i++]; styleColor(buf[i++], buf[i++], buf[i++], buf[i++]); fillRectOp(x, y, rw, rh, r); break; }
            case 10: { i = readPath(buf, i, m); styleColor(buf[i++], buf[i++], buf[i++], buf[i++]); fillContours(buf[i++] === 1, m); break; }
            case 11: {
              i = readPath(buf, i, m);
              const width = buf[i++], cap = buf[i++], join = buf[i++], miter = buf[i++];
              const dashCount = buf[i++]; const dashes = []; for (let k = 0; k < dashCount; k++) dashes.push(buf[i++]);
              const phase = buf[i++];
              const r = buf[i++], g = buf[i++], b = buf[i++], a = buf[i++];
              styleColor(r, g, b, a);
              strokeContours(width, cap, join, miter, dashes, phase, m, a < 1);
              break;
            }
            case 12: {
              const text = strings[buf[i++]], font = strings[buf[i++]], x = buf[i++], y = buf[i++];
              const r = buf[i++], g = buf[i++], b = buf[i++], a = buf[i++];
              drawTextOp(text, font, x, y, 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')', false);
              break;
            }
            case 13: {
              const file = strings[buf[i++]], scale = buf[i++], pw = buf[i++], ph = buf[i++];
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              const tile = buf[i++] === 1, top = buf[i++], leading = buf[i++], bottom = buf[i++], trailing = buf[i++];
              const smoothing = buf[i++] === 1, tintKind = buf[i++];
              const tint = [buf[i++], buf[i++], buf[i++], buf[i++]];
              if (tintKind === 2) i = readGradient(buf, i, false);
              drawImageOp(file, scale, pw, ph, x, y, rw, rh, tile, top, leading, bottom, trailing, smoothing, tintKind, tint);
              break;
            }
            case 14: {
              const a = buf[i++], b = buf[i++], c = buf[i++], d = buf[i++], e = buf[i++], f = buf[i++];
              const M = layer.state.m;
              layer.state.m = [M[0] * a + M[2] * b, M[1] * a + M[3] * b, M[0] * c + M[2] * d, M[1] * c + M[3] * d, M[0] * e + M[2] * f + M[4], M[1] * e + M[3] * f + M[5]];
              break;
            }
            case 15: { i = readPath(buf, i, m); i = readGradient(buf, i, false); kind = 4; fillContours(buf[i++] === 1, m); break; }
            case 16: {
              i = readPath(buf, i, m);
              const width = buf[i++], cap = buf[i++], join = buf[i++], miter = buf[i++];
              const dashCount = buf[i++]; const dashes = []; for (let k = 0; k < dashCount; k++) dashes.push(buf[i++]);
              const phase = buf[i++];
              i = readGradient(buf, i, true); kind = 4;
              strokeContours(width, cap, join, miter, dashes, phase, m, true);
              break;
            }
            case 17: {
              const text = strings[buf[i++]], font = strings[buf[i++]], x = buf[i++], y = buf[i++];
              i = readGradient(buf, i, true);
              drawTextOp(text, font, x, y, '#fff', true);
              break;
            }
            case 18: {
              const color = [buf[i++], buf[i++], buf[i++], buf[i++]];
              const radius = buf[i++], dx = buf[i++], dy = buf[i++];
              pushLayer({ opacity: 1, shadow: { color, radius, dx, dy } });
              break;
            }
            case 19: {
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              const fk = buf[i++];
              let filter;
              if (fk === 0) { const mm = []; for (let k = 0; k < 20; k++) mm.push(buf[i++]); filter = { matrix: mm }; }
              else { filter = { radius: buf[i++], opaque: buf[i++] === 1 }; }
              const scale = Math.hypot(m[0], m[1]);
              let pad = 0;
              if (filter.radius !== undefined) { filter.sigma = filter.radius * scale; pad = filter.opaque ? 0 : Math.ceil(filter.sigma * 3); }
              const bounds = clampInts(deviceRectBox(m, x, y, rw, rh), W, H, pad) || { x0: 0, y0: 0, x1: 0, y1: 0 };
              pushLayer({ opacity: 1, filter, bounds });
              break;
            }
            case 20: {
              const mode = buf[i++];
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              pushLayer({ opacity: 1, blend: mode | 0, bounds: clampInts(deviceRectBox(m, x, y, rw, rh), W, H, 0) });
              break;
            }
            case 21: { i += 4; pushLayer({ opacity: 1, maskPending: true }); break; }
            case 22: {
              // The mask is drawn: the content gets a target of its own.
              flush();
              const g = layer;
              g.maskTarget = g.target; g.maskTouched = g.touched;
              g.target = acquireTarget(W, H);
              g.state = freshState(g.parent.state.m);
              g.stack = [];
              g.box = emptyBox(); g.touched = emptyBox();
              g.maskPending = false;
              break;
            }
            case 23: {
              i = readPath(buf, i, m);
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              const radius = buf[i++], saturation = buf[i++];
              backdropBlurOp(false, x, y, rw, rh, radius, saturation);
              break;
            }
            case 24: {
              const bitmap = (bitmaps || [])[buf[i++]];
              const bx = buf[i++], by = buf[i++], bw = buf[i++], bh = buf[i++];
              drawBitmapOp(bitmap, bx, by, bw, bh);
              break;
            }
            case 25: {
              // A 3D scene (SceneKit): its renderer draws it into a canvas of its own, shown here as a texture.
              const mx = buf[i++], my = buf[i++], mw = buf[i++], mh = buf[i++];
              const nf = buf[i++];
              const files = [];
              for (let k = 0; k < nf; k++) files.push(strings[buf[i++]]);
              const nv = buf[i++];
              const mesh = window.__swiftuiwebMesh;
              if (mesh && mesh.render) {
                const s = scaleOf(layer.state.m);
                const pw = Math.max(1, Math.min(4096, Math.round(mw * s))), ph = Math.max(1, Math.min(4096, Math.round(mh * s)));
                const drawn = mesh.render(buf, i, nv, files, mw, mh, pw, ph, (f) => { const e = image(f); return e ? e.img : null; });
                if (drawn) {
                  flush();
                  const tex = gl.createTexture();
                  gl.bindTexture(gl.TEXTURE_2D, tex);
                  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
                  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
                  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
                  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, drawn);
                  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
                  frameTextures.push(tex);
                  useTexture(tex, false);
                  kind = 2; cr = cg = cb = 0; ca = 1;
                  const box = emptyBox();
                  quad(layer.state.m, mx, my, mw, mh, 0, 0, 1, 1, box);
                  markPainted(box, 1);
                } else {
                  stats.meshFallback = (stats.meshFallback || 0) + 1;
                }
              }
              i += nv;
              break;
            }
            default: throw new Error('unknown display op ' + op + ' at ' + (i - 1));
          }
        }
        while (layers.length) endGroup();
        flush();
      } catch (e) {
        // Leave the GL state reusable for the next frame.
        count = 0;
        for (const l of layers) { releaseTarget(l.target, l.touched); if (l.maskTarget) releaseTarget(l.maskTarget, l.maskTouched); }
        layers.length = 0;
        recycleTemps();
        for (const t of frameTextures) gl.deleteTexture(t);
        frameTextures = [];
        throw e;
      }
      // Present: resolve the root into the canvas's own framebuffer.
      gl.disable(gl.SCISSOR_TEST);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, rootTarget.fb);
      gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, null);
      gl.blitFramebuffer(0, 0, W, H, 0, 0, W, H, gl.COLOR_BUFFER_BIT, gl.NEAREST);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      recycleTemps();
      for (const t of frameTextures) gl.deleteTexture(t);
      frameTextures = [];
      if (!overlay) {
        ctx2d.save();
        ctx2d.setTransform(1, 0, 0, 1, 0, 0);
        ctx2d.clearRect(0, 0, canvas2d.width, canvas2d.height);
        ctx2d.drawImage(glCanvas, 0, 0);
        ctx2d.restore();
      }
      if (config.sync || forceSync) { const px = new Uint8Array(4); gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px); if (!overlay) ctx2d.getImageData(0, 0, 1, 1); }
      info.stats = stats;
      return performance.now() - started;
    }

    return {
      paint,
      forgetText,
      hide() { twoDDirty = true; if (overlay) glCanvas.style.visibility = 'hidden'; },
    };
  }
})();
