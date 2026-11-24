#scope_file

// Port of src/sdl-examples/c-examples/DepthArray.c.
//
// The example exists to verify that depth texture arrays work. The scene (a cube made
// of six coloured faces) is rendered twice into the two layers of a 2D-array depth
// texture, each layer with its own view matrix and viewport, and with no colour target
// at all. A fullscreen pass then samples the depth array and writes it to the swapchain
// as greyscale; the fragment shader picks the layer from the screen-space y coordinate.

depth_pipeline: *SDL_GPUGraphicsPipeline;
scene_vertex_buffer: *SDL_GPUBuffer;
scene_index_buffer: *SDL_GPUBuffer;
scene_depth_texture: *SDL_GPUTexture;

depth_sample_pipeline: *SDL_GPUGraphicsPipeline;
nearest_sampler: *SDL_GPUSampler;

time: float;
scene_width, scene_height: u32;

init :: () -> int {
    if !common_init(0) {
        return -1;
    }

    // Creates the Shaders & Pipelines
    {
        scene_vertex_shader := load_shader(context.device, "PositionColorTransform.vert", 0, 1, 0, 0);
        if scene_vertex_shader == null {
            log("Failed to create 'PositionColorTransform' vertex shader!");
            return -1;
        }

        defer SDL_ReleaseGPUShader(context.device, scene_vertex_shader);

        scene_fragment_shader := load_shader(context.device, "Empty.frag", 0, 0, 0, 0);
        if scene_fragment_shader == null {
            log("Failed to create fragment shader!");
            return -1;
        }

        defer SDL_ReleaseGPUShader(context.device, scene_fragment_shader);

        fullscreen_vertex_shader := load_shader(context.device, "Fullscreen.vert", 0, 0, 0, 0);
        if fullscreen_vertex_shader == null {
            log("Failed to create fullscreen vertex shader!");
            return -1;
        }

        defer SDL_ReleaseGPUShader(context.device, fullscreen_vertex_shader);

        depth_fragment_shader := load_shader(context.device, "DepthSample.frag", 1, 0, 0, 0);
        if depth_fragment_shader == null {
            log("Failed to create depth sample shader!");
            return -1;
        }

        defer SDL_ReleaseGPUShader(context.device, depth_fragment_shader);

        scene_vertex_buffer_descriptions := SDL_GPUVertexBufferDescription.[.{
            slot = 0,
            input_rate = .SDL_GPU_VERTEXINPUTRATE_VERTEX,
            instance_step_rate = 0,
            pitch = size_of(PositionColorVertex)
        }];

        scene_vertex_attributes := SDL_GPUVertexAttribute.[.{
            buffer_slot = 0,
            format = .SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            location = 0,
            offset = 0
        }, .{
            buffer_slot = 0,
            format = .SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM,
            location = 1,
            offset = size_of(float) * 3
        }];

        // Depth-only pipeline: no colour target, just the D16 array layer being written.
        depth_pipeline_create_info := SDL_GPUGraphicsPipelineCreateInfo.{
            target_info = .{
                num_color_targets = 0,
                color_target_descriptions = null,
                has_depth_stencil_target = true,
                depth_stencil_format = .SDL_GPU_TEXTUREFORMAT_D16_UNORM
            },
            depth_stencil_state = .{
                enable_depth_test = true,
                enable_depth_write = true,
                enable_stencil_test = false,
                compare_op = .SDL_GPU_COMPAREOP_LESS,
                write_mask = 0xFF
            },
            rasterizer_state = .{
                cull_mode = .SDL_GPU_CULLMODE_NONE,
                fill_mode = .SDL_GPU_FILLMODE_FILL,
                front_face = .SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE
            },
            vertex_input_state = .{
                num_vertex_buffers = 1,
                vertex_buffer_descriptions = scene_vertex_buffer_descriptions.data,
                num_vertex_attributes = 2,
                vertex_attributes = scene_vertex_attributes.data
            },
            primitive_type = .SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            vertex_shader = scene_vertex_shader,
            fragment_shader = scene_fragment_shader
        };

        depth_pipeline = SDL_CreateGPUGraphicsPipeline(context.device, *depth_pipeline_create_info);
        if depth_pipeline == null {
            log("Failed to create Depth pipeline!");
            return -1;
        }

        depth_sample_color_target_descriptions := SDL_GPUColorTargetDescription.[.{
            format = SDL_GetGPUSwapchainTextureFormat(context.device, context.window),
            blend_state = .{
                enable_blend = true,
                src_color_blendfactor = .SDL_GPU_BLENDFACTOR_ONE,
                dst_color_blendfactor = .SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                color_blend_op = .SDL_GPU_BLENDOP_ADD,
                src_alpha_blendfactor = .SDL_GPU_BLENDFACTOR_ONE,
                dst_alpha_blendfactor = .SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                alpha_blend_op = .SDL_GPU_BLENDOP_ADD,
            }
        }];

        // The fullscreen triangle has no vertex buffer, and Fullscreen.vert builds its
        // vertices from SV_VertexID, so there is no vertex input state either.
        depth_sample_pipeline_create_info := SDL_GPUGraphicsPipelineCreateInfo.{
            target_info = .{
                num_color_targets = 1,
                color_target_descriptions = depth_sample_color_target_descriptions.data
            },
            rasterizer_state = .{
                cull_mode = .SDL_GPU_CULLMODE_NONE,
                fill_mode = .SDL_GPU_FILLMODE_FILL,
                front_face = .SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE
            },
            primitive_type = .SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            vertex_shader = fullscreen_vertex_shader,
            fragment_shader = depth_fragment_shader
        };

        depth_sample_pipeline = SDL_CreateGPUGraphicsPipeline(context.device, *depth_sample_pipeline_create_info);
        if depth_sample_pipeline == null {
            log("Failed to create Depth Sample pipeline!");
            return -1;
        }
    }

    // Create the Scene Textures
    {
        // Make them smaller so pixels stand out more
        w, h: s32;
        SDL_GetWindowSizeInPixels(context.window, *w, *h);
        scene_width = (cast(u32) w) / 2;
        scene_height = (cast(u32) h) / 2;

        scene_depth_texture = SDL_CreateGPUTexture(context.device, *(SDL_GPUTextureCreateInfo.{
            type = .SDL_GPU_TEXTURETYPE_2D_ARRAY,
            width = scene_width,
            height = scene_height,
            layer_count_or_depth = 2,
            num_levels = 1,
            sample_count = .SDL_GPU_SAMPLECOUNT_1,
            format = .SDL_GPU_TEXTUREFORMAT_D16_UNORM,
            usage = SDL_GPU_TEXTUREUSAGE_SAMPLER | SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET
        }));

        if scene_depth_texture == null {
            log("Failed to create scene depth texture!");
            return -1;
        }
    }

    // Create & Upload Scene Index and Vertex Buffers
    {
        scene_vertex_buffer = SDL_CreateGPUBuffer(context.device, *(SDL_GPUBufferCreateInfo.{
            usage = SDL_GPU_BUFFERUSAGE_VERTEX,
            size = size_of(PositionColorVertex) * 24
        }));

        scene_index_buffer = SDL_CreateGPUBuffer(context.device, *(SDL_GPUBufferCreateInfo.{
            usage = SDL_GPU_BUFFERUSAGE_INDEX,
            size = size_of(u16) * 36
        }));

        buffer_transfer_buffer := SDL_CreateGPUTransferBuffer(context.device, *(SDL_GPUTransferBufferCreateInfo.{
            usage = .SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            size = (size_of(PositionColorVertex) * 24) + (size_of(u16) * 36)
        }));

        defer SDL_ReleaseGPUTransferBuffer(context.device, buffer_transfer_buffer);

        transfer_data := cast(*PositionColorVertex) SDL_MapGPUTransferBuffer(
            context.device,
            buffer_transfer_buffer,
            false);

        transfer_data[0]  = PositionColorVertex.{ -10, -10, -10, 255, 0, 0, 255 };
        transfer_data[1]  = PositionColorVertex.{ 10, -10, -10, 255, 0, 0, 255 };
        transfer_data[2]  = PositionColorVertex.{ 10, 10, -10, 255, 0, 0, 255 };
        transfer_data[3]  = PositionColorVertex.{ -10, 10, -10, 255, 0, 0, 255 };

        transfer_data[4]  = PositionColorVertex.{ -10, -10, 10, 255, 255, 0, 255 };
        transfer_data[5]  = PositionColorVertex.{ 10, -10, 10, 255, 255, 0, 255 };
        transfer_data[6]  = PositionColorVertex.{ 10, 10, 10, 255, 255, 0, 255 };
        transfer_data[7]  = PositionColorVertex.{ -10, 10, 10, 255, 255, 0, 255 };

        transfer_data[8]  = PositionColorVertex.{ -10, -10, -10, 255, 0, 255, 255 };
        transfer_data[9]  = PositionColorVertex.{ -10, 10, -10, 255, 0, 255, 255 };
        transfer_data[10] = PositionColorVertex.{ -10, 10, 10, 255, 0, 255, 255 };
        transfer_data[11] = PositionColorVertex.{ -10, -10, 10, 255, 0, 255, 255 };

        transfer_data[12] = PositionColorVertex.{ 10, -10, -10, 0, 255, 0, 255 };
        transfer_data[13] = PositionColorVertex.{ 10, 10, -10, 0, 255, 0, 255 };
        transfer_data[14] = PositionColorVertex.{ 10, 10, 10, 0, 255, 0, 255 };
        transfer_data[15] = PositionColorVertex.{ 10, -10, 10, 0, 255, 0, 255 };

        transfer_data[16] = PositionColorVertex.{ -10, -10, -10, 0, 255, 255, 255 };
        transfer_data[17] = PositionColorVertex.{ -10, -10, 10, 0, 255, 255, 255 };
        transfer_data[18] = PositionColorVertex.{ 10, -10, 10, 0, 255, 255, 255 };
        transfer_data[19] = PositionColorVertex.{ 10, -10, -10, 0, 255, 255, 255 };

        transfer_data[20] = PositionColorVertex.{ -10, 10, -10, 0, 0, 255, 255 };
        transfer_data[21] = PositionColorVertex.{ -10, 10, 10, 0, 0, 255, 255 };
        transfer_data[22] = PositionColorVertex.{ 10, 10, 10, 0, 0, 255, 255 };
        transfer_data[23] = PositionColorVertex.{ 10, 10, -10, 0, 0, 255, 255 };

        index_data := cast(*u16) *transfer_data[24];
        indices := u16.[
            0, 1, 2, 0, 2, 3,
            4, 5, 6, 4, 6, 7,
            8, 9, 10, 8, 10, 11,
            12, 13, 14, 12, 14, 15,
            16, 17, 18, 16, 18, 19,
            20, 21, 22, 20, 22, 23
        ];
        memcpy(index_data, indices.data, size_of(type_of(indices)));

        // Unmap before the copy pass is recorded and submitted (a deferred unmap would
        // only run after the submit).
        SDL_UnmapGPUTransferBuffer(context.device, buffer_transfer_buffer);

        // Upload the transfer data to the GPU buffers
        upload_cmd_buffer := SDL_AcquireGPUCommandBuffer(context.device);
        if upload_cmd_buffer == null {
            log("Failed to acquire upload command buffer: %", SDL_GetError());
            return -1;
        }

        copy_pass := SDL_BeginGPUCopyPass(upload_cmd_buffer);

        SDL_UploadToGPUBuffer(
            copy_pass,
            *(SDL_GPUTransferBufferLocation.{
                transfer_buffer = buffer_transfer_buffer,
                offset = 0
            }),
            *(SDL_GPUBufferRegion.{
                buffer = scene_vertex_buffer,
                offset = 0,
                size = size_of(PositionColorVertex) * 24
            }),
            false);

        SDL_UploadToGPUBuffer(
            copy_pass,
            *(SDL_GPUTransferBufferLocation.{
                transfer_buffer = buffer_transfer_buffer,
                offset = size_of(PositionColorVertex) * 24
            }),
            *(SDL_GPUBufferRegion.{
                buffer = scene_index_buffer,
                offset = 0,
                size = size_of(u16) * 36
            }),
            false);

        SDL_EndGPUCopyPass(copy_pass);
        SDL_SubmitGPUCommandBuffer(upload_cmd_buffer);
    }

    // Create Outline Effect Sampler
    nearest_sampler = SDL_CreateGPUSampler(context.device, *(SDL_GPUSamplerCreateInfo.{
        min_filter = .SDL_GPU_FILTER_NEAREST,
        mag_filter = .SDL_GPU_FILTER_NEAREST,
        mipmap_mode = .SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        address_mode_u = .SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
        address_mode_v = .SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
        address_mode_w = .SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
    }));

    time = 0;
    return 0;
}

update :: () -> int {
    time += context.delta_time;
    return 0;
}

draw :: () -> int {
    cmd_buf := SDL_AcquireGPUCommandBuffer(context.device);
    if cmd_buf == null {
        log("AcquireGPUCommandBuffer failed: %", SDL_GetError());
        return -1;
    }

    swapchain_texture: *SDL_GPUTexture;
    if !SDL_WaitAndAcquireGPUSwapchainTexture(cmd_buf, context.window, *swapchain_texture, null, null) {
        log("WaitAndAcquireGPUSwapchainTexture failed: %", SDL_GetError());
        return -1;
    }

    if swapchain_texture != null {
        // Render the 3D Scene (Depth-only, once per depth-array layer)
        near_plane := 20.0;
        far_plane := 60.0;

        // example_common's Matrix4x4_* helpers are byte-for-byte ports of SDL's Common.h
        // (row-vector layout), and Math's multiply computes the same matrix product that
        // SDL's Matrix4x4_Multiply does, so these bytes feed PositionColorTransform.vert
        // exactly as the C example does.
        proj := Matrix4x4_CreatePerspectiveFieldOfView(
            75.0 * PI / 180.0,
            scene_width / cast(float) scene_height,
            near_plane,
            far_plane);

        view := Matrix4x4_CreateLookAt(
            .{ cos(time) * 30, 30, sin(time) * 30 },
            .{ 0, 0, 0 },
            .{ 0, 1, 0 });

        view2 := Matrix4x4_CreateLookAt(
            .{ cos(time) * 30, 30, cos(time) * 30 },
            .{ 0, 0, 0 },
            .{ 0, 1, 0 });

        view_proj := multiply(view, proj);
        view_proj2 := multiply(view2, proj);

        viewport := SDL_GPUViewport.{
            x = 0,
            y = 0,
            w = cast(float) scene_width / 2,
            h = cast(float) scene_height / 2,
            min_depth = 0,
            max_depth = 1
        };

        viewport2 := SDL_GPUViewport.{
            x = cast(float) scene_width / 2,
            y = cast(float) scene_height / 2,
            w = cast(float) scene_width / 2,
            h = cast(float) scene_height / 2,
            min_depth = 0,
            max_depth = 1
        };

        depth_stencil_target_info: SDL_GPUDepthStencilTargetInfo;
        depth_stencil_target_info.texture = scene_depth_texture;
        depth_stencil_target_info.layer = 0;
        depth_stencil_target_info.clear_depth = 1;
        depth_stencil_target_info.clear_stencil = 0;
        depth_stencil_target_info.load_op = .SDL_GPU_LOADOP_CLEAR;
        depth_stencil_target_info.store_op = .SDL_GPU_STOREOP_STORE;
        depth_stencil_target_info.stencil_load_op = .SDL_GPU_LOADOP_CLEAR;
        depth_stencil_target_info.stencil_store_op = .SDL_GPU_STOREOP_STORE;

        SDL_PushGPUVertexUniformData(cmd_buf, 0, *view_proj, size_of(type_of(view_proj)));
        // Empty.frag declares no uniform buffers, so this push is ignored; it is kept to
        // mirror the C example.
        SDL_PushGPUFragmentUniformData(cmd_buf, 0, float.[near_plane, far_plane].data, 8);

        vertex_buffer_binding := SDL_GPUBufferBinding.{ buffer = scene_vertex_buffer, offset = 0 };
        index_buffer_binding := SDL_GPUBufferBinding.{ buffer = scene_index_buffer, offset = 0 };

        render_pass := SDL_BeginGPURenderPass(cmd_buf, null, 0, *depth_stencil_target_info);
        SDL_SetGPUViewport(render_pass, *viewport);
        SDL_BindGPUVertexBuffers(render_pass, 0, *vertex_buffer_binding, 1);
        SDL_BindGPUIndexBuffer(render_pass, *index_buffer_binding, .SDL_GPU_INDEXELEMENTSIZE_16BIT);
        SDL_BindGPUGraphicsPipeline(render_pass, depth_pipeline);
        SDL_DrawGPUIndexedPrimitives(render_pass, 36, 1, 0, 0, 0);
        SDL_EndGPURenderPass(render_pass);

        SDL_PushGPUVertexUniformData(cmd_buf, 0, *view_proj2, size_of(type_of(view_proj2)));

        depth_stencil_target_info.layer = 1;

        render_pass = SDL_BeginGPURenderPass(cmd_buf, null, 0, *depth_stencil_target_info);
        SDL_SetGPUViewport(render_pass, *viewport2);
        SDL_BindGPUVertexBuffers(render_pass, 0, *vertex_buffer_binding, 1);
        SDL_BindGPUIndexBuffer(render_pass, *index_buffer_binding, .SDL_GPU_INDEXELEMENTSIZE_16BIT);
        SDL_BindGPUGraphicsPipeline(render_pass, depth_pipeline);
        SDL_DrawGPUIndexedPrimitives(render_pass, 36, 1, 0, 0, 0);
        SDL_EndGPURenderPass(render_pass);

        // Render the Depth Values sampled from the whole Color/Depth texture array
        swapchain_target_info: SDL_GPUColorTargetInfo;
        swapchain_target_info.texture = swapchain_texture;
        swapchain_target_info.clear_color = SDL_FColor.{ 0.2, 0.5, 0.4, 1.0 };
        swapchain_target_info.load_op = .SDL_GPU_LOADOP_CLEAR;
        swapchain_target_info.store_op = .SDL_GPU_STOREOP_STORE;

        depth_texture_sampler_binding := SDL_GPUTextureSamplerBinding.{
            texture = scene_depth_texture,
            sampler = nearest_sampler
        };

        render_pass = SDL_BeginGPURenderPass(cmd_buf, *swapchain_target_info, 1, null);
        SDL_BindGPUGraphicsPipeline(render_pass, depth_sample_pipeline);
        SDL_BindGPUFragmentSamplers(render_pass, 0, *depth_texture_sampler_binding, 1);
        // The C example calls SDL_DrawGPUIndexedPrimitives(..., 3, ...) here without ever
        // binding an index buffer; the shader is driven by SV_VertexID, so draw the three
        // vertices non-indexed instead.
        SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);
        SDL_EndGPURenderPass(render_pass);
    }

    SDL_SubmitGPUCommandBuffer(cmd_buf);

    return 0;
}

quit :: () -> int {
    SDL_ReleaseGPUGraphicsPipeline(context.device, depth_pipeline);
    SDL_ReleaseGPUGraphicsPipeline(context.device, depth_sample_pipeline);
    SDL_ReleaseGPUTexture(context.device, scene_depth_texture);
    SDL_ReleaseGPUBuffer(context.device, scene_vertex_buffer);
    SDL_ReleaseGPUBuffer(context.device, scene_index_buffer);
    SDL_ReleaseGPUSampler(context.device, nearest_sampler);

    time = 0;

    common_quit();

    return 0;
}

#scope_export

depth_array_example := SDLExample.{
    name = "DepthArray",
    init = init,
    quit = quit,
    update = update,
    draw = draw
};
