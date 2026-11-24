// The browser renderer for SceneKit's meshes (MeshRendering.swift has the payload): installed by the
// browser host before the first frame that draws one. Kept here so apps without SceneKit carry none of it.

/// The renderer's JavaScript.
let _meshScript: String = #"""
// SceneKit's meshes through WebGL2 (the payload is SceneKit's MeshRendering.swift): the scene is
// drawn into a canvas of its own (depth buffer, multisampling, per-pixel lighting, mipmapped
// textures) and copied into the page's canvas; without WebGL2, a painter's-algorithm drawing.
window.__swiftuiwebMesh = (function () {
  'use strict';
  const MAX_LIGHTS = 8, MATERIAL = 18;
  const config = window.__swiftuiwebMeshConfig || {};
  const forced2D = config.mode === '2d' || /[?&]mesh=2d\b/.test(location.search);
  let canvas = null, gl = null, failed = false, frame = 0;
  let prog = null, loc = null;
  const geoms = new Map(), textures = new Map();
  const stats = { frames: 0, gl: 0, fallback: 0, ms: 0, meshes: 0, triangles: 0, uploads: 0, renderer: '' };

  const VS = `#version 300 es
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_nrm;
layout(location = 2) in vec2 a_uv;
uniform mat4 u_model, u_view;
uniform vec4 u_proj;
uniform float u_ortho;
out vec3 v_world; out vec3 v_nrm; out vec2 v_uv;
void main() {
  vec4 w = u_model * vec4(a_pos, 1.0);
  v_world = w.xyz; v_nrm = mat3(u_model) * a_nrm; v_uv = a_uv;
  vec4 c = u_view * w;
  float d = -c.z;
  gl_Position = vec4(c.x * u_proj.x, c.y * u_proj.y, u_proj.z * d + u_proj.w, u_ortho > 0.5 ? 1.0 : d);
}`;
  const FS = `#version 300 es
precision highp float;
in vec3 v_world; in vec3 v_nrm; in vec2 v_uv;
uniform vec4 u_diffuse;
uniform vec3 u_emis, u_mult;
uniform float u_alpha, u_lit, u_tex;
uniform sampler2D u_s;
uniform int u_nl;
uniform vec4 u_lc[${MAX_LIGHTS}];
uniform vec3 u_lp[${MAX_LIGHTS}], u_ld[${MAX_LIGHTS}];
out vec4 o;
void main() {
  vec4 base = u_diffuse;
  if (u_tex > 0.5) base *= texture(u_s, v_uv);
  vec3 col = base.rgb;
  if (u_lit > 0.5) {
    vec3 n = normalize(v_nrm);
    if (!gl_FrontFacing) n = -n;
    vec3 L = vec3(0.0);
    for (int k = 0; k < ${MAX_LIGHTS}; k++) {
      if (k >= u_nl) break;
      float t = u_lc[k].w, amount = 1.0;
      if (t > 1.5) amount = max(0.0, dot(n, normalize(u_lp[k] - v_world)));
      else if (t > 0.5) amount = max(0.0, dot(n, -u_ld[k]));
      L += u_lc[k].rgb * amount;
    }
    col *= L;
  }
  col = (col + u_emis) * u_mult;
  float a = clamp(base.a * u_alpha, 0.0, 1.0);
  o = vec4(clamp(col, 0.0, 1.0) * a, a);
}`;

  function shader(type, source) {
    const s = gl.createShader(type);
    gl.shaderSource(s, source);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }
  function init() {
    if (gl || failed) return gl;
    if (forced2D) { failed = true; return null; }
    try {
      canvas = document.createElement('canvas');
      gl = canvas.getContext('webgl2', { antialias: true, alpha: true, premultipliedAlpha: true, depth: true, stencil: false, preserveDrawingBuffer: false });
      if (!gl) throw new Error('no WebGL2');
      prog = gl.createProgram();
      gl.attachShader(prog, shader(gl.VERTEX_SHADER, VS));
      gl.attachShader(prog, shader(gl.FRAGMENT_SHADER, FS));
      gl.linkProgram(prog);
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
      loc = {};
      for (const name of ['u_model', 'u_view', 'u_proj', 'u_ortho', 'u_diffuse', 'u_emis', 'u_mult', 'u_alpha', 'u_lit', 'u_tex', 'u_s', 'u_nl', 'u_lc', 'u_lp', 'u_ld']) {
        loc[name] = gl.getUniformLocation(prog, name);
      }
      const info = gl.getExtension('WEBGL_debug_renderer_info');
      stats.renderer = info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
      canvas.addEventListener('webglcontextlost', (e) => { e.preventDefault(); gl = null; failed = true; geoms.clear(); textures.clear(); });
    } catch (e) {
      console.warn('SwiftUIWeb: SceneKit draws without WebGL (' + (e && e.message) + ')');
      gl = null; failed = true;
    }
    return gl;
  }

  // The payload's header and its mesh records, without touching the GPU.
  function header(buf, i) {
    const h = { ortho: buf[i + 1] === 1, focal: buf[i + 2], near: buf[i + 3], far: buf[i + 4], eye: [buf[i + 5], buf[i + 6], buf[i + 7]] };
    let p = i + 8;
    h.view = buf.subarray(p, p + 16); p += 16;
    const nl = buf[p++];
    h.lights = [];
    for (let k = 0; k < nl; k++, p += 10) h.lights.push(buf.subarray(p, p + 10));
    h.meshCount = buf[p++];
    h.start = p;
    return h;
  }
  function eachMesh(buf, h, fn) {
    let p = h.start;
    for (let m = 0; m < h.meshCount; m++) {
      const id = buf[p], version = buf[p + 1];
      const model = buf.subarray(p + 2, p + 18);
      p += 18;
      const nv = buf[p++];
      const vstart = p;
      p += nv * 8;
      const ne = buf[p++];
      const elements = [];
      for (let e = 0; e < ne; e++) {
        const mat = buf.subarray(p, p + MATERIAL);
        p += MATERIAL;
        const ni = buf[p++];
        elements.push({ mat, istart: p, ni });
        p += ni;
      }
      fn({ id, version, model, nv, vstart, elements });
    }
  }
  // Row-vector transforms (SceneKit's layout): p · M.
  function point(m, x, y, z) {
    return [x * m[0] + y * m[4] + z * m[8] + m[12], x * m[1] + y * m[5] + z * m[9] + m[13], x * m[2] + y * m[6] + z * m[10] + m[14]];
  }
  function edges(buf, start, n) {
    const seen = new Set(), out = [];
    for (let k = 0; k < n; k += 3) {
      const t = [buf[start + k], buf[start + k + 1], buf[start + k + 2]];
      for (let e = 0; e < 3; e++) {
        const a = t[e], b = t[(e + 1) % 3];
        const key = a < b ? a * 4194304 + b : b * 4194304 + a;
        if (seen.has(key)) continue;
        seen.add(key); out.push(a, b);
      }
    }
    return out;
  }
  function texture(file, image) {
    let entry = textures.get(file);
    if (entry) { entry.used = frame; return entry.tex; }
    const img = image(file);
    if (!img) return null;
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
    gl.generateMipmap(gl.TEXTURE_2D);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    const aniso = gl.getExtension('EXT_texture_filter_anisotropic');
    if (aniso) gl.texParameterf(gl.TEXTURE_2D, aniso.TEXTURE_MAX_ANISOTROPY_EXT, 4);
    textures.set(file, { tex, used: frame });
    stats.uploads++;
    return tex;
  }
  function wrap(mode) { return mode === 2 ? gl.REPEAT : mode === 4 ? gl.MIRRORED_REPEAT : gl.CLAMP_TO_EDGE; }

  // Draws the payload into the scene canvas at pw × ph pixels for a w × h point view.
  function render(buf, i, nv, files, w, h, pw, ph, image) {
    const g = init();
    if (!g) return null;
    frame++;
    const hd = header(buf, i);
    if (canvas.width !== pw) canvas.width = pw;
    if (canvas.height !== ph) canvas.height = ph;
    gl.viewport(0, 0, pw, ph);
    gl.clearColor(0, 0, 0, 0);
    gl.clearDepth(1);
    gl.depthMask(true);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.enable(gl.DEPTH_TEST);
    gl.depthFunc(gl.LEQUAL);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    gl.useProgram(prog);
    gl.uniformMatrix4fv(loc.u_view, false, new Float32Array(hd.view));
    const n = hd.near, f = hd.far, sx = 2 * hd.focal / w, sy = 2 * hd.focal / h;
    if (hd.ortho) gl.uniform4f(loc.u_proj, sx, sy, 2 / (f - n), -(f + n) / (f - n));
    else gl.uniform4f(loc.u_proj, sx, sy, (f + n) / (f - n), -2 * f * n / (f - n));
    gl.uniform1f(loc.u_ortho, hd.ortho ? 1 : 0);
    const lc = new Float32Array(MAX_LIGHTS * 4), lp = new Float32Array(MAX_LIGHTS * 3), ld = new Float32Array(MAX_LIGHTS * 3);
    const nl = Math.min(hd.lights.length, MAX_LIGHTS);
    for (let k = 0; k < nl; k++) {
      const l = hd.lights[k];
      lc.set([l[1], l[2], l[3], l[0]], k * 4); lp.set([l[4], l[5], l[6]], k * 3); ld.set([l[7], l[8], l[9]], k * 3);
    }
    gl.uniform1i(loc.u_nl, nl);
    gl.uniform4fv(loc.u_lc, lc); gl.uniform3fv(loc.u_lp, lp); gl.uniform3fv(loc.u_ld, ld);
    gl.uniform1i(loc.u_s, 0);
    gl.activeTexture(gl.TEXTURE0);
    const v = hd.view;
    const draws = [];
    let triangles = 0;
    eachMesh(buf, hd, (mesh) => {
      let gm = geoms.get(mesh.id);
      const fresh = !gm || gm.version !== mesh.version;
      if (fresh) {
        if (gm) { gl.deleteBuffer(gm.vbo); for (const e of gm.elements) if (e) { gl.deleteBuffer(e.tri); if (e.line) gl.deleteBuffer(e.line); } gl.deleteVertexArray(gm.vao); }
        gm = { version: mesh.version, vao: gl.createVertexArray(), vbo: gl.createBuffer(), elements: [] };
        gl.bindVertexArray(gm.vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, gm.vbo);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(buf.subarray(mesh.vstart, mesh.vstart + mesh.nv * 8)), gl.STATIC_DRAW);
        gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 32, 0);
        gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 3, gl.FLOAT, false, 32, 12);
        gl.enableVertexAttribArray(2); gl.vertexAttribPointer(2, 2, gl.FLOAT, false, 32, 24);
        gl.bindVertexArray(null);
        geoms.set(mesh.id, gm);
        stats.uploads++;
      }
      gm.used = frame;
      const m = mesh.model;
      const c = point(v, m[12], m[13], m[14]);
      mesh.elements.forEach((el, e) => {
        let ge = gm.elements[e];
        const lines = el.mat[1] === 1;
        if (!ge) {
          ge = gm.elements[e] = { tri: gl.createBuffer(), count: el.ni, line: null, lineCount: 0 };
          gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ge.tri);
          gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint32Array(buf.subarray(el.istart, el.istart + el.ni)), gl.STATIC_DRAW);
        }
        if (lines && !ge.line) {
          const list = edges(buf, el.istart, el.ni);
          ge.line = gl.createBuffer(); ge.lineCount = list.length;
          gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ge.line);
          gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint32Array(list), gl.STATIC_DRAW);
        }
        const mat = el.mat;
        const transparent = mat[13] * mat[6] < 0.999;
        draws.push({ gm, ge, mat, model: m, lines, transparent, order: mat[17], depth: -c[2] });
        triangles += el.ni / 3;
      });
    });
    draws.sort((a, b) => a.order - b.order || (a.transparent - b.transparent) || (a.transparent ? b.depth - a.depth : 0));
    for (const d of draws) {
      const mat = d.mat;
      gl.bindVertexArray(d.gm.vao);
      gl.uniformMatrix4fv(loc.u_model, false, new Float32Array(d.model));
      const file = mat[14] >= 0 ? files[mat[14]] : null;
      const tex = file ? texture(file, image) : null;
      if (file && !tex) gl.uniform4f(loc.u_diffuse, 0.5 * mat[3], 0.5 * mat[3], 0.5 * mat[3], 1);   // loading: mid grey
      else gl.uniform4f(loc.u_diffuse, mat[3], mat[4], mat[5], mat[6]);
      gl.uniform1f(loc.u_tex, tex ? 1 : 0);
      if (tex) {
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap(mat[15]));
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap(mat[16]));
      }
      gl.uniform3f(loc.u_emis, mat[7], mat[8], mat[9]);
      gl.uniform3f(loc.u_mult, mat[10], mat[11], mat[12]);
      gl.uniform1f(loc.u_alpha, mat[13]);
      gl.uniform1f(loc.u_lit, mat[2]);
      gl.depthMask(!d.transparent);
      if (mat[0] === 2 || d.lines) gl.disable(gl.CULL_FACE);
      else { gl.enable(gl.CULL_FACE); gl.cullFace(mat[0] === 1 ? gl.FRONT : gl.BACK); }
      if (d.lines) { gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, d.ge.line); gl.drawElements(gl.LINES, d.ge.lineCount, gl.UNSIGNED_INT, 0); }
      else { gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, d.ge.tri); gl.drawElements(gl.TRIANGLES, d.ge.count, gl.UNSIGNED_INT, 0); }
    }
    gl.bindVertexArray(null);
    // Meshes and textures no frame has drawn for a while are let go.
    if (frame % 300 === 0) {
      for (const [id, gm] of geoms) if (frame - gm.used > 600) { gl.deleteBuffer(gm.vbo); for (const e of gm.elements) if (e) { gl.deleteBuffer(e.tri); if (e.line) gl.deleteBuffer(e.line); } gl.deleteVertexArray(gm.vao); geoms.delete(id); }
      for (const [file, t] of textures) if (frame - t.used > 600) { gl.deleteTexture(t.tex); textures.delete(file); }
    }
    stats.meshes = draws.length; stats.triangles = triangles;
    return canvas;
  }

  // Without WebGL: each triangle projected, flat shaded and painted far to near (SceneKit's CPU path).
  function draw2D(ctx, buf, i, x, y, w, h) {
    const hd = header(buf, i);
    const v = hd.view, items = [];
    const project = (p) => {
      const c = point(v, p[0], p[1], p[2]);
      const d = -c[2];
      if (hd.ortho) return [w / 2 + c[0] * hd.focal, h / 2 - c[1] * hd.focal, d];
      if (d <= hd.near) return null;
      return [w / 2 + c[0] / d * hd.focal, h / 2 - c[1] / d * hd.focal, d];
    };
    eachMesh(buf, hd, (mesh) => {
      const world = [];
      for (let k = 0; k < mesh.nv; k++) {
        const o = mesh.vstart + k * 8;
        world.push(point(mesh.model, buf[o], buf[o + 1], buf[o + 2]));
      }
      const screen = world.map(project);
      for (const el of mesh.elements) {
        const mat = el.mat;
        const base = mat[14] >= 0 ? [0.5 * mat[3], 0.5 * mat[3], 0.5 * mat[3], 1] : [mat[3], mat[4], mat[5], mat[6]];
        const lines = mat[1] === 1;
        for (let k = 0; k < el.ni; k += 3) {
          const ia = buf[el.istart + k], ib = buf[el.istart + k + 1], ic = buf[el.istart + k + 2];
          const a = world[ia], b = world[ib], c = world[ic];
          const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], t = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
          let nrm = [u[1] * t[2] - u[2] * t[1], u[2] * t[0] - u[0] * t[2], u[0] * t[1] - u[1] * t[0]];
          const len = Math.hypot(nrm[0], nrm[1], nrm[2]);
          if (len < 1e-12) continue;
          nrm = [nrm[0] / len, nrm[1] / len, nrm[2] / len];
          const center = [(a[0] + b[0] + c[0]) / 3, (a[1] + b[1] + c[1]) / 3, (a[2] + b[2] + c[2]) / 3];
          const toEye = hd.ortho ? [v[2], v[6], v[10]] : [hd.eye[0] - a[0], hd.eye[1] - a[1], hd.eye[2] - a[2]];
          const front = nrm[0] * toEye[0] + nrm[1] * toEye[1] + nrm[2] * toEye[2] > 0;
          if (!lines && mat[0] === 0 && !front) continue;
          if (!lines && mat[0] === 1 && front) continue;
          const pa = screen[ia], pb = screen[ib], pc = screen[ic];
          if (!pa || !pb || !pc) continue;
          if (!front) nrm = [-nrm[0], -nrm[1], -nrm[2]];
          let r = base[0], g = base[1], bl = base[2];
          if (mat[2] === 1) {
            let lr = 0, lg = 0, lb = 0;
            for (const l of hd.lights) {
              let amount = 1;
              if (l[0] === 1) amount = Math.max(0, -(nrm[0] * l[7] + nrm[1] * l[8] + nrm[2] * l[9]));
              else if (l[0] === 2) {
                const dx = l[4] - center[0], dy = l[5] - center[1], dz = l[6] - center[2], dl = Math.hypot(dx, dy, dz) || 1;
                amount = Math.max(0, (nrm[0] * dx + nrm[1] * dy + nrm[2] * dz) / dl);
              }
              lr += l[1] * amount; lg += l[2] * amount; lb += l[3] * amount;
            }
            r *= lr; g *= lg; bl *= lb;
          }
          r = (r + mat[7]) * mat[10]; g = (g + mat[8]) * mat[11]; bl = (bl + mat[9]) * mat[12];
          const alpha = Math.min(1, Math.max(0, base[3] * mat[13]));
          if (alpha < 0.001) continue;
          const color = 'rgba(' + Math.round(Math.min(1, Math.max(0, r)) * 255) + ',' + Math.round(Math.min(1, Math.max(0, g)) * 255) + ',' + Math.round(Math.min(1, Math.max(0, bl)) * 255) + ',' + alpha + ')';
          items.push({ pts: [pa, pb, pc], color, alpha, lines, order: mat[17], depth: (pa[2] + pb[2] + pc[2]) / 3 });
        }
      }
    });
    items.sort((a, b) => a.order - b.order || b.depth - a.depth);
    ctx.save();
    ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip();
    ctx.translate(x, y);
    for (const it of items) {
      const [a, b, c] = it.pts;
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.lineTo(c[0], c[1]); ctx.closePath();
      if (it.lines) { ctx.strokeStyle = it.color; ctx.lineWidth = 1; ctx.stroke(); continue; }
      ctx.fillStyle = it.color; ctx.fill();
      if (it.alpha >= 0.999) { ctx.strokeStyle = it.color; ctx.lineWidth = 0.5; ctx.stroke(); }
    }
    ctx.restore();
  }

  // The painter's op: draws the scene into `ctx` over the view's rect (x, y, w, h).
  function draw(ctx, buf, i, nv, files, x, y, w, h, dpr, image) {
    const started = performance.now();
    const m = ctx.getTransform();
    const scale = Math.hypot(m.a, m.b) || dpr || 1;
    const pw = Math.max(1, Math.min(4096, Math.round(w * scale))), ph = Math.max(1, Math.min(4096, Math.round(h * scale)));
    let drawn = null;
    try { drawn = render(buf, i, nv, files, w, h, pw, ph, image); } catch (e) { console.error('SwiftUIWeb: SceneKit WebGL frame failed', e); drawn = null; }
    if (drawn) { ctx.drawImage(drawn, 0, 0, pw, ph, x, y, w, h); stats.gl++; }
    else { draw2D(ctx, buf, i, x, y, w, h); stats.fallback++; }
    stats.frames++;
    stats.ms = performance.now() - started;
  }

  return { draw, render, draw2D, stats, get active() { return !!gl; } };
})();
"""#
