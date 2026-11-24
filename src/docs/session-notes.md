# Session notes — TexturedAnimatedQuad port

## Goal

Port `src/sdl-examples/c-examples/TexturedAnimatedQuad.c` to
`src/sdl-examples/textured_animated_quad.jai`, following the pattern of
`basic_triangle.jai` (a port of `BasicTriangle.c`) and `textured_quad.jai`.

## Files added / changed

- `src/sdl-examples/textured_animated_quad.jai` — new port, exports
  `textured_animated_quad_example`.
- `src/examples.jai` — `#load` of the new file; the active `example:` line now
  selects `textured_animated_quad_example` (the previous `textured_quad_example`
  line is commented out, as the other examples are).
- `assets/shader/TexturedQuadWithMatrix.vert.hlsl` — new. The C example uses this
  shader, which did not exist in this repo yet.
- `assets/shader/TexturedQuadWithMultiplyColor.frag.hlsl` — new.
- `assets/compiled/TexturedQuadWithMatrix.vert.{json,DXIL}` and
  `assets/compiled/TexturedQuadWithMultiplyColor.frag.{json,DXIL}` — baked.

## How the code works

Structure mirrors the C example one-to-one: `init` / `update` / `draw` / `quit`,
file-scope handles for pipeline, vertex buffer, index buffer, texture and
sampler, and a file-scope `t: float` advanced by `context.delta_time`.

`draw` binds the pipeline once, then issues four indexed draws of 6 indices,
pushing a fresh vertex matrix and fragment multiply-color before each. The four
corners are bottom-left, bottom-right, top-left, top-right — same order and same
colour formulas as the C source.

Most of `init` is a direct transcription of `textured_quad.jai`'s already-working
SDL3 GPU setup: 4 vertices (`PositionTextureVertex`), 6 `u16` indices, one
transfer buffer shared by vertex and index uploads (indices at
`size_of(PositionTextureVertex) * 4`), a second for texture data, one copy pass,
one submit. Alpha blending is enabled on the color target exactly as in the C
example.

Differences from the C, all deliberate:

- Image loading uses `SDL_LoadBMP` + `SDL_ConvertSurface(..., .SDL_PIXELFORMAT_RGBA32)`,
  matching `load_image()` in `example_common.jai` and the C `LoadImage("ravioli.bmp", 4)`.
  (`textured_quad.jai` uses `SDL_LoadPNG` for `boid.png`; that path is not used here.)
- `textured_quad.jai` has a known bug pattern where `defer SDL_UnmapGPUTransferBuffer`
  ran only after the submit; this port unmaps explicitly before recording the copy
  pass, and uses `defer` only for releasing the transfer buffers.
- `SDL_AcquireGPUCommandBuffer` for the upload is null-checked (the C does not).

## Matrix conventions (the one real trap)

The C example builds each quad's transform as
`Matrix4x4_Multiply(Matrix4x4_CreateRotationZ(t), Matrix4x4_CreateTranslation(x, y, 0))`.
The header those come from defines row-vector maths: points are multiplied on
the left (`p * M`), so in `a * b` the operand `a` is applied first. That is why
the rotation reads `(c, s; -s, c)` — see `make_rotation_z` in
`example_common.jai`, which is character-for-character SDL's function.

Jai's `Math` module is column-vector: `M * p`, and in `a * b` the operand `b` is
applied first. Two consequences:

1. **Operand order swaps.** "Rotate, then translate" becomes
   `multiply(make_translation_matrix4(offset), rotation_z(angle))`. This lives in
   the helper `animated_quad_matrix(angle, offset)`.
2. **The shader must read the matrix as `row_major`.** `Math.Matrix4` stores
   row 1 first with the translation in the last column; HLSL's cbuffer default is
   `column_major`, which would feed the shader the transpose. The vertex shader
   declares `row_major float4x4 MatrixTransform`. `example_common.jai`'s
   `make_rotation_z` is *not* a drop-in for the Math module for the same reason —
   it uses SDL's layout — so the port has its own `rotation_z` built from
   `set_from_axis_and_angle` + `rotation_matrix(Matrix4, q)`.

An earlier draft had the operands the other way round and the quads orbited the
screen centre instead of spinning in place at the four corners. The screenshot
made this obvious (opaque `ravioli.bmp` tiles are much easier to read than the
mostly-transparent `boid.png` sprite, which is why the texture was switched to
match the C example).

## Shader baking

`build-asset.jai` only visits `assets/shader/*.hlsl` and writes `.ca` files; the
`sdl-examples` loader (`load_shader` in `example_common.jai`) reads
`assets/compiled/<name>.<ext>.DXIL` directly. So for a new shader:

```sh
shadercross assets/shader/Foo.vert.hlsl -d JSON -o assets/compiled/Foo.vert.json
shadercross assets/shader/Foo.vert.hlsl -d DXIL -o assets/compiled/Foo.vert.DXIL
```

`shadercross` is at `/c/work/VulkanSDK/1.4.363.0/Bin/shadercross`. The JSON is
the reflection data used to fill in `num_samplers` / `num_uniform_buffers` in the
`load_shader` call.

## Verification done

- `jaic -check examples.jai` clean, including `-no_dce`.
- `jaic -exe examples.exe examples.jai` builds clean.
- Ran the binary and captured the window: four ravioli tiles spinning in place at
  the four corners, with the per-quad multiply-colour tint animating. Matches the
  C example's intent.

---

# Session notes — DepthArray port

## Goal

Port `src/sdl-examples/c-examples/DepthArray.c` to
`src/sdl-examples/depth_array.jai`, using `basic_triangle.jai` as the structural
guide and `depth_sampler.jai` as the sibling example for depth targets, matrices
and fullscreen passes.

## Files added / changed

- `src/sdl-examples/depth_array.jai` — new port, exports `depth_array_example`.
- `src/examples.jai` — `#load` of the new file; the active `example:` line now
  selects `depth_array_example` (the previous `textured_animated_quad_example`
  line is commented out).

No new shaders were needed: `PositionColorTransform.vert`, `Empty.frag`,
`Fullscreen.vert` and `DepthSample.frag` were already compiled into
`assets/compiled/`.

## How it works

Structure mirrors the C one-to-one. The scene is drawn twice, once per layer of a
`D16_UNORM` 2D-array depth texture (no colour target, `num_color_targets = 0`),
each pass with its own view matrix, viewport (`SceneWidth/2 × SceneHeight/2`, at
`(0,0)` for layer 0 and `(SceneWidth/2, SceneHeight/2)` for layer 1) and
`depthStencilTargetInfo.layer`. Then one fullscreen pass binds the depth array to
`DepthSample.frag`, which greyscales it and picks the layer from
`TexCoord.y > 0.5`.

Matrices reuse `example_common.jai`'s `Matrix4x4_CreatePerspectiveFieldOfView` /
`Matrix4x4_CreateLookAt` and `Math.multiply`, exactly as `depth_sampler.jai` does.
Those helpers are byte-for-byte ports of SDL's row-vector `Common.h` functions, so
the pushed bytes match the C. (This is the opposite case from
`textured_animated_quad.jai`, which needed native `Math` matrices.)

## Deliberate deviations from the C

- The final pass draws with `SDL_DrawGPUPrimitives(render_pass, 3, ...)`. The C
  calls `SDL_DrawGPUIndexedPrimitives(..., 3, ...)` there but never binds an index
  buffer; `Fullscreen.vert` is driven entirely by `SV_VertexID`, so the
  non-indexed draw is the correct call.
- The transfer buffer is unmapped explicitly before the copy pass is recorded
  (the same deferred-unmap trap as in `textured_quad.jai`).
- The `SDL_AcquireGPUCommandBuffer` for the upload and the upload
  `SDL_CreateGPU*` results are null-checked (the C does not).
- The C pushes `near/far` as fragment uniform data although `Empty.frag` has no
  uniform buffers; the port keeps the push (harmless) with a comment.

## Verification done

- `jaic -check examples.jai` clean, including `-no_dce`.
- `jaic -exe examples.exe examples.jai` builds clean.
- Ran the binary: no SDL/GPU validation errors on stderr. Captured the window —
  two greyscale depth renders of the cube, top-left (layer 0) and bottom-right
  (layer 1), on the white "depth = 1" background. Matches the C example's intent.

---

# Session notes — CopyAndReadback port

## Goal

Port `src/sdl-examples/c-examples/CopyAndReadback.c` to
`src/sdl-examples/copy_and_readback.jai`. Nothing is drawn from scratch: the
example exercises texture/buffer copies and GPU-to-CPU readback, then blits three
views of the same image.

## Files added / changed

- `src/sdl-examples/copy_and_readback.jai` — new port, exports
  `copy_and_readback_example`.
- `src/examples.jai` — `#load` of the new file; the active `example:` line now
  selects `copy_and_readback_example`.

No new shaders or baked assets were needed (the example has no pipelines at all).

## How it works

`init` loads `ravioli.bmp` and converts it to `SDL_PIXELFORMAT_RGBA32` (the same
conversion `LoadImage(..., 4)` does in the C's `Common.h`). It creates three
`R8G8B8A8_UNORM` textures (original, copy, and a half-size
`SAMPLER | COLOR_TARGET` target) plus two `GRAPHICS_STORAGE_READ` buffers holding
eight `u32`s. A single command buffer records:

1. upload texture + buffer,
2. `SDL_CopyGPUTextureToTexture` and `SDL_CopyGPUBufferToBuffer`,
3. `SDL_BlitGPUTexture` into the half-size texture,
4. `SDL_DownloadFromGPUTexture` / `SDL_DownloadFromGPUBuffer` into a download
   transfer buffer.

It submits with `SDL_SubmitGPUCommandBufferAndAcquireFence`, waits on the fence,
maps the download buffer and `memcmp`s both payloads against the originals
(`memcmp` is a Jai builtin — no import needed).

`draw` clears the swapchain to black in a tiny render pass, then issues three
blits with `SDL_GPU_LOADOP_LOAD`: original top-left, GPU copy top-right, and the
half-size texture stretched into the bottom-centre.

Types worth noting: `u32.[...]` for the buffer payload (the C initialiser leaves
the eighth element zero); `buffer_size` is cast to `u32` because `size_of` is
`s64` and the SDL size fields are `Uint32`.

## Deliberate deviations from the C

- The upload transfer buffer is unmapped explicitly before the copy pass is
  recorded (same deferred-unmap trap as `textured_quad.jai`).
- The upload command buffer, fence and map results are null-checked (the C does
  not).
- `load_image()` from `example_common.jai` is avoided: its `defer
  SDL_DestroySurface(result)` fires after `return` and frees the surface it
  returns. The port does `SDL_LoadBMP` + `SDL_ConvertSurface` directly, as in
  `textured_animated_quad.jai`.

## Verification done

- `jaic -check examples.jai` clean, including `-no_dce`.
- `jaic -exe examples.exe examples.jai` builds clean.
- Ran the binary: no SDL/GPU validation errors on stderr, and stdout printed
  `SUCCESS! Original texture bytes and the downloaded bytes match!` and
  `SUCCESS! Original buffer bytes and the downloaded bytes match!`.
- Captured the window: ravioli top-left, identical copy top-right, and the
  half-size (upscaled, so softened) version bottom-centre on black. Matches the
  C example's intent.

