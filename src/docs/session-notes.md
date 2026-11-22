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

