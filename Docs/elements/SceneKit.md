# SceneKit (objc bridging thread, 2026-11-23)

SceneKit for SwiftUIWeb: `import SceneKit` unchanged (`Sources/SceneKit`, product `SceneKit`).
A page has no Metal or OpenGL, so `SCNView` draws its scene on the CPU into its own drawing:
every triangle is projected through the camera, faces turned away are culled, and the rest are
painted far to near with one flat colour each. That is enough for the scenes apps put in a
corner of a screen (a spinning globe, a wireframe, a row of labelled boxes). It is not a
renderer for games: there is no depth buffer, so faces that cut through each other can sort
wrongly, and there are no textures.

## What is there

| API | Status |
|---|---|
| `SCNVector3`, `SCNVector4`, `SCNQuaternion`, `SCNMatrix4` and the `SCNMatrix4Make…`, `Mult`, `Translate`, `Scale`, `Rotate`, `Invert` functions; `NSValue(scnVector3:)`, `(scnVector4:)`, `(scnMatrix4:)` | implemented (row vectors, as SceneKit's: `SCNMatrix4Mult(a, b)` applies `a` first) |
| simd: `simd_float3` and the other vector names, `simd_float3x3` / `simd_float4x4` (`float3x3`, `matrix_identity_float4x4`), `simd_quatf` (from an angle and axis, two directions or a rotation matrix; `act`, `inverse`, `angle`, `axis`), `simd_normalize`, `simd_length`, `simd_dot`, `simd_cross`, `simd_mix`, `simd_mul`, `simd_inverse`, `simd_slerp` and the rest of the common functions; the nodes' `simdPosition`, `simdScale`, `simdEulerAngles`, `simdOrientation`, `simdRotation`, `simdTransform`, `simdPivot`, `simdWorld…`, `simdConvertPosition` / `simdConvertVector`, `simdLook(at:)`; `SCNVector3(simd_float3)`, `SCNMatrix4(simd_float4x4)` and back | implemented (2026-11-24): Apple's SceneKit brings the simd module with it, so a file importing SceneKit names these; on Apple's platforms the module is re-exported, elsewhere WebGraphics' `WebSIMD` is (column-major matrices, quaternions as (ix, iy, iz, r)), the module the `simd` shadow re-exports on wasm |
| `SCNScene` (`rootNode`, `background`, attributes, `isPaused`) | implemented; `SCNScene(named:)` is nil and `init(url:)` throws: there is no scene file reader |
| `SCNNode`: `position`, `scale`, `pivot`, `orientation`, `rotation`, `eulerAngles`, `transform`, `worldTransform`, `worldPosition`, `worldOrientation`, `convertPosition` / `convertVector`, `look(at:)`, the child hierarchy, `childNode(withName:recursively:)`, `clone`, `boundingBox` / `boundingSphere`, `opacity`, `isHidden`, `renderingOrder`, values by key | implemented; `presentation` is the node itself |
| Geometry: `SCNSphere`, `SCNBox` (chamfered corners drawn square), `SCNPlane` (rounded corners), `SCNCylinder`, `SCNCone`, `SCNTube`, `SCNCapsule`, `SCNTorus`, `SCNPyramid`, `SCNFloor` | implemented as triangle meshes |
| `SCNText` | approximate: the string drawn flat on the text's front plane through the page's text engine, in the font's size in scene units; no extrusion is drawn |
| `SCNShape` | approximate: the path filled flat on its front plane |
| `SCNMaterial`: `diffuse`, `emission`, `multiply` colours, `lightingModel`, `fillMode` (`.lines` draws the edges), `isDoubleSided`, `cullMode`, `transparency` | implemented; image contents draw as mid grey; specular, normal, metalness and roughness are kept and not drawn |
| `SCNLight` (`.ambient`, `.omni`, `.directional`; spot lights shine as omni lights), `autoenablesDefaultLighting` | implemented as flat Lambert shading per face, the colour times `intensity` / 1000; no shadows |
| `SCNCamera` (`fieldOfView`, `zNear`, `usesOrthographicProjection`, `orthographicScale`) | implemented; with no camera the view frames the scene's bounds from in front |
| `SCNAction`: wait, run, custom, rotate by / to / about an axis, move, scale, fade, hide, remove, sequence, group, repeat, repeat forever, `reversed()`, `timingMode`, `speed`; `runAction` with keys and completion handlers | implemented, stepped each frame |
| `CABasicAnimation`, `CAKeyframeAnimation` and `CAAnimationGroup` on nodes, for `rotation`, `orientation`, `eulerAngles`, `position`, `scale` (and their `.x`, `.y`, `.z`) and `opacity` | implemented (linear timing; `repeatCount`, `autoreverses`, `isAdditive`, `beginTime`, `speed`) |
| `SCNLookAtConstraint` | implemented |
| `SCNBillboardConstraint` | accepted, not applied |
| `SCNTransaction` | accepted: changes apply at once |
| `SCNView` (`scene`, `pointOfView`, `allowsCameraControl` orbiting on a pan and zooming on a pinch, `defaultCameraController`, `rendersContinuously`, `delegate` update and render callbacks, `projectPoint`, `unprojectPoint`, `hitTest` against the faces last drawn, `snapshot`) | implemented |
| `SceneView` (SwiftUI) with its options | implemented over `SCNView` |
| Physics, particles, skinning, morphers, shaders, `SCNTechnique`, audio | accepted where apps name them; nothing runs |

## How a frame is drawn

1. A frame clock steps every live view's scene: actions advance by the frame's time, finished
   animations come off, constraints apply. It keeps running while anything moves, and stops
   when nothing does.
2. Any change to a node or a material's contents asks for a new frame, so a timer that changes a
   colour redraws the view.
3. The view picks its camera, collects its lights, and projects each node's triangles with the
   animations applied at the current time.
4. Each face's colour is its material's diffuse colour lit by the lights, plus emission, times
   transparency and the nodes' opacity. A face with no lights in the scene (and no default
   lighting) shows its full diffuse colour.
5. The faces are sorted by `renderingOrder`, then far to near, and filled. Opaque faces get a
   hairline of their own colour so no seams show between them.
