# SceneKit WebGL backend: results (Nov 24, 2026)

SCNView records one `drawMesh` display-list op (geometry, materials, lights, camera) instead of
thousands of projected triangles; a 5 KB script draws it with WebGL2 (per-pixel lambert, textures,
depth, sorted transparency) or, without WebGL, with a 2D painter's-algorithm fallback. `?mesh=cpu`
keeps today's CPU path; hit tests and snapshots still use it. CI's WebGL is SwiftShader (software),
so GL draw times below are not representative of a GPU.

| scene | today (CPU) | WebGL on SwiftShader | 2D fallback |
| --- | --- | --- | --- |
| Spheres, 36k triangles | 6.8 fps, 139 ms (Swift 72 ms) | 4.3 fps, 243 ms (Swift 3 ms) | 12.8 fps, 65 ms |
| Waves, 3.1k | 51 fps, 8 ms | 11 fps, 83 ms | 23 fps, 6 ms |
| Globe, 2.3k + live texture | 53 fps, 6 ms | 8 fps, 103 ms | 37 fps, 4 ms |

- Swift work per frame drops 72 ms -> 3 ms on Spheres whatever the GPU; the rest is GPU work.
- Fallback with `--disable-3d-apis`: automatic, same numbers as the 2D column.
- Size (Linux build, custom sections stripped, brotli 11): Counter +2,652 bytes for the op;
  mesh script 5,340 brotli in SceneKit apps only. Counter's runtime probe passes.
- Known gaps: text and 2D overlays in an SCNView draw over the meshes (no shared depth); the
  painter's image cache keeps every data-URL texture (Globe's live texture grows it).

## On a real GPU (Corey's M1 Pro Mac, Nov 24, run 45323269954)

Headless Chromium 129 on the laptop-sweep runner, WebGL2 on ANGLE (Apple M1 Pro, OpenGL 4.1).

| scene | today (CPU) | WebGL | 2D fallback |
| --- | --- | --- | --- |
| Spheres, 36k triangles | 8.8 fps, frame 112 ms | 60 fps, frame 3.4 ms | 20.5 fps, 35 ms |
| Waves, 3.1k | 60 fps, 8.8 ms | 60 fps, 2.6 ms | 60 fps, 4.5 ms |
| Globe, 2.3k + live texture | 60 fps, 6.1 ms | 44 fps, median 2.1 ms but p90 37 ms | 47 fps |

- WebGL turns the heavy scene from unusable into smooth and cuts frame work 2-30x elsewhere.
- Globe stutters because its live texture is re-uploaded (77 uploads in the run): fix before
  adopting. Same numbers with the WebGL painter for everything injected.
