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
