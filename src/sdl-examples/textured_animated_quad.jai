#scope_file

pipeline: *SDL_GPUGraphicsPipeline;
vertex_buffer: *SDL_GPUBuffer;
index_buffer: *SDL_GPUBuffer;
texture: *SDL_GPUTexture;
sampler: *SDL_GPUSampler;

t: float;

FragMultiplyUniform :: struct {
    r, g, b, a: float;
}

TEXTURE_PATH :: #run path_join(#filepath, "../../assets/texture/ravioli.bmp");

// Counter-clockwise rotation about Z, built in the Math module's Matrix4 convention
// (row-major, translation in the last column). example_common's make_rotation_z uses SDL's
// column-vector memory layout instead, so it is not interchangeable here.
rotation_z :: (radians: float) -> Matrix4 {
    q: Quaternion;
    set_from_axis_and_angle(*q, xyz(0, 0, 1), radians);
    return rotation_matrix(Matrix4, q);
}

/// The per-quad transform: spin the quad about its own center, then move it to `offset`.
///
/// The C example writes `Matrix4x4_Multiply(Matrix4x4_CreateRotationZ(t), Matrix4x4_CreateTranslation(...))`,
/// but SDL's Common.h matrices are row-vector (`p * M`), where `a * b` applies `a` first. The Math
/// module is column-vector, (`M * p`, and `a * b` applies `b` first), so the operands swap to
/// produce the same points.
animated_quad_matrix :: (angle: float, offset: Vector3) -> Matrix4 {
    return multiply(make_translation_matrix4(offset), rotation_z(angle));
}

init :: () -> int {
    if !common_init(0) {
        return -1;
    }

    // Create the shaders
    vertex_shader := load_shader(context.device, "TexturedQuadWithMatrix.vert", 0, 1, 0, 0);
    if vertex_shader == null {
        log("Failed to create vertex shader!");
        return -1;
    }

    defer SDL_ReleaseGPUShader(context.device, vertex_shader);

    fragment_shader := load_shader(context.device, "TexturedQuadWithMultiplyColor.frag", 1, 1, 0, 0);
    if fragment_shader == null {
        log("Failed to create fragment shader!");
        return -1;
    }

    defer SDL_ReleaseGPUShader(context.device, fragment_shader);

    // Load the image
    texture_path_as_cstring := to_c_string(TEXTURE_PATH);
    defer free(texture_path_as_cstring);

    image := SDL_LoadBMP(texture_path_as_cstring);
    if image == null {
        log("Could not load image data: %", SDL_GetError());
        return -1;
    }

    defer SDL_DestroySurface(image);

    texture_image := SDL_ConvertSurface(image, .SDL_PIXELFORMAT_RGBA32);
    if texture_image == null {
        log("Failed to convert image to RGBA32: %", SDL_GetError());
        return -1;
    }

    defer SDL_DestroySurface(texture_image);

    color_target_descriptions := SDL_GPUColorTargetDescription.[.{
        format = SDL_GetGPUSwapchainTextureFormat(context.device, context.window),
        blend_state = .{
            enable_blend = true,
            alpha_blend_op = .SDL_GPU_BLENDOP_ADD,
            color_blend_op = .SDL_GPU_BLENDOP_ADD,
            src_color_blendfactor = .SDL_GPU_BLENDFACTOR_SRC_ALPHA,
            src_alpha_blendfactor = .SDL_GPU_BLENDFACTOR_SRC_ALPHA,
            dst_color_blendfactor = .SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            dst_alpha_blendfactor = .SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
        }
    }];

    // Create the pipeline
    pipeline_create_info := SDL_GPUGraphicsPipelineCreateInfo.{
        target_info = .{
            num_color_targets = 1,
            color_target_descriptions = color_target_descriptions.data
        },
        // This is set up to match the vertex shader layout!
        vertex_input_state = .{
            num_vertex_buffers = 1,
            vertex_buffer_descriptions = SDL_GPUVertexBufferDescription.[.{
                slot = 0,
                input_rate = .SDL_GPU_VERTEXINPUTRATE_VERTEX,
                instance_step_rate = 0,
                pitch = size_of(PositionTextureVertex)
            }].data,
            num_vertex_attributes = 2,
            vertex_attributes = SDL_GPUVertexAttribute.[.{
                buffer_slot = 0,
                format = .SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                location = 0,
                offset = 0
            }, .{
                buffer_slot = 0,
                format = .SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                location = 1,
                offset = size_of(float) * 3
            }].data
        },
        primitive_type = .SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader
    };

    pipeline = SDL_CreateGPUGraphicsPipeline(context.device, *pipeline_create_info);
    if pipeline == null {
        log("Failed to create pipeline!");
        return -1;
    }

    // Create the GPU resources
    vertex_buffer = SDL_CreateGPUBuffer(context.device, *(SDL_GPUBufferCreateInfo.{
        usage = SDL_GPU_BUFFERUSAGE_VERTEX,
        size = size_of(PositionTextureVertex) * 4
    }));

    index_buffer = SDL_CreateGPUBuffer(context.device, *(SDL_GPUBufferCreateInfo.{
        usage = SDL_GPU_BUFFERUSAGE_INDEX,
        size = size_of(u16) * 6
    }));

    texture = SDL_CreateGPUTexture(context.device, *(SDL_GPUTextureCreateInfo.{
        type = .SDL_GPU_TEXTURETYPE_2D,
        format = .SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        width = cast(u32) texture_image.w,
        height = cast(u32) texture_image.h,
        layer_count_or_depth = 1,
        num_levels = 1,
        usage = SDL_GPU_TEXTUREUSAGE_SAMPLER
    }));

    sampler = SDL_CreateGPUSampler(context.device, *(SDL_GPUSamplerCreateInfo.{
        min_filter = .SDL_GPU_FILTER_NEAREST,
        mag_filter = .SDL_GPU_FILTER_NEAREST,
        mipmap_mode = .SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        address_mode_u = .SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        address_mode_v = .SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        address_mode_w = .SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
    }));

    // Set up buffer data
    buffer_transfer_buffer := SDL_CreateGPUTransferBuffer(context.device, *(SDL_GPUTransferBufferCreateInfo.{
        usage = .SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        size = (size_of(PositionTextureVertex) * 4) + (size_of(u16) * 6)
    }));

    defer SDL_ReleaseGPUTransferBuffer(context.device, buffer_transfer_buffer);

    transfer_data := cast(*PositionTextureVertex) SDL_MapGPUTransferBuffer(
        context.device,
        buffer_transfer_buffer,
        false
    );

    transfer_data[0] = PositionTextureVertex.{ -0.5, -0.5, 0, 0, 0 };
    transfer_data[1] = PositionTextureVertex.{  0.5, -0.5, 0, 1, 0 };
    transfer_data[2] = PositionTextureVertex.{  0.5,  0.5, 0, 1, 1 };
    transfer_data[3] = PositionTextureVertex.{ -0.5,  0.5, 0, 0, 1 };

    index_data := cast(*u16) *transfer_data[4];
    index_data[0] = 0;
    index_data[1] = 1;
    index_data[2] = 2;
    index_data[3] = 0;
    index_data[4] = 2;
    index_data[5] = 3;

    SDL_UnmapGPUTransferBuffer(context.device, buffer_transfer_buffer);

    // Set up texture data
    texture_transfer_buffer := SDL_CreateGPUTransferBuffer(context.device, *(SDL_GPUTransferBufferCreateInfo.{
        usage = .SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        size = cast(u32) (texture_image.w * texture_image.h * 4)
    }));

    defer SDL_ReleaseGPUTransferBuffer(context.device, texture_transfer_buffer);

    texture_transfer_ptr := SDL_MapGPUTransferBuffer(
        context.device,
        texture_transfer_buffer,
        false
    );

    memcpy(texture_transfer_ptr, texture_image.pixels, texture_image.w * texture_image.h * 4);

    SDL_UnmapGPUTransferBuffer(context.device, texture_transfer_buffer);

    // Upload the transfer data to the GPU resources
    upload_cmd_buf := SDL_AcquireGPUCommandBuffer(context.device);
    if upload_cmd_buf == null {
        log("Failed to acquire upload command buffer: %", SDL_GetError());
        return -1;
    }

    copy_pass := SDL_BeginGPUCopyPass(upload_cmd_buf);

    SDL_UploadToGPUBuffer(
        copy_pass,
        *(SDL_GPUTransferBufferLocation.{
            transfer_buffer = buffer_transfer_buffer,
            offset = 0
        }),
        *(SDL_GPUBufferRegion.{
            buffer = vertex_buffer,
            offset = 0,
            size = size_of(PositionTextureVertex) * 4
        }),
        false);

    SDL_UploadToGPUBuffer(
        copy_pass,
        *(SDL_GPUTransferBufferLocation.{
            transfer_buffer = buffer_transfer_buffer,
            offset = size_of(PositionTextureVertex) * 4
        }),
        *(SDL_GPUBufferRegion.{
            buffer = index_buffer,
            offset = 0,
            size = size_of(u16) * 6
        }),
        false);

    SDL_UploadToGPUTexture(
        copy_pass,
        *(SDL_GPUTextureTransferInfo.{
            transfer_buffer = texture_transfer_buffer,
            offset = 0, // Zeroes out the rest
        }),
        *(SDL_GPUTextureRegion.{
            texture = texture,
            w = cast(u32) texture_image.w,
            h = cast(u32) texture_image.h,
            d = 1
        }),
        false);

    SDL_EndGPUCopyPass(copy_pass);
    SDL_SubmitGPUCommandBuffer(upload_cmd_buf);

    t = 0;

    return 0;
}

update :: () -> int {
    t += context.delta_time;
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
        color_target_info: SDL_GPUColorTargetInfo;
        color_target_info.texture = swapchain_texture;
        color_target_info.clear_color = SDL_FColor.{ 0.0, 0.0, 0.0, 1.0 };
        color_target_info.load_op = .SDL_GPU_LOADOP_CLEAR;
        color_target_info.store_op = .SDL_GPU_STOREOP_STORE;

        render_pass := SDL_BeginGPURenderPass(cmd_buf, *color_target_info, 1, null);

        SDL_BindGPUGraphicsPipeline(render_pass, pipeline);
        SDL_BindGPUVertexBuffers(render_pass, 0, *(SDL_GPUBufferBinding.{ buffer = vertex_buffer, offset = 0 }), 1);
        SDL_BindGPUIndexBuffer(render_pass, *(SDL_GPUBufferBinding.{ buffer = index_buffer, offset = 0 }), .SDL_GPU_INDEXELEMENTSIZE_16BIT);
        SDL_BindGPUFragmentSamplers(render_pass, 0, *(SDL_GPUTextureSamplerBinding.{ texture = texture, sampler = sampler }), 1);

        // Bottom-left
        matrix_uniform := animated_quad_matrix(t, xyz(-0.5, -0.5, 0));
        SDL_PushGPUVertexUniformData(cmd_buf, 0, *matrix_uniform, size_of(type_of(matrix_uniform)));
        multiply_color := FragMultiplyUniform.{ 1.0, 0.5 + sin(t) * 0.5, 1.0, 1.0 };
        SDL_PushGPUFragmentUniformData(cmd_buf, 0, *multiply_color, size_of(type_of(multiply_color)));
        SDL_DrawGPUIndexedPrimitives(render_pass, 6, 1, 0, 0, 0);

        // Bottom-right
        matrix_uniform = animated_quad_matrix((2.0 * PI) - t, xyz(0.5, -0.5, 0));
        SDL_PushGPUVertexUniformData(cmd_buf, 0, *matrix_uniform, size_of(type_of(matrix_uniform)));
        multiply_color = FragMultiplyUniform.{ 1.0, 0.5 + cos(t) * 0.5, 1.0, 1.0 };
        SDL_PushGPUFragmentUniformData(cmd_buf, 0, *multiply_color, size_of(type_of(multiply_color)));
        SDL_DrawGPUIndexedPrimitives(render_pass, 6, 1, 0, 0, 0);

        // Top-left
        matrix_uniform = animated_quad_matrix(t, xyz(-0.5, 0.5, 0));
        SDL_PushGPUVertexUniformData(cmd_buf, 0, *matrix_uniform, size_of(type_of(matrix_uniform)));
        multiply_color = FragMultiplyUniform.{ 1.0, 0.5 + sin(t) * 0.2, 1.0, 1.0 };
        SDL_PushGPUFragmentUniformData(cmd_buf, 0, *multiply_color, size_of(type_of(multiply_color)));
        SDL_DrawGPUIndexedPrimitives(render_pass, 6, 1, 0, 0, 0);

        // Top-right
        matrix_uniform = animated_quad_matrix(t, xyz(0.5, 0.5, 0));
        SDL_PushGPUVertexUniformData(cmd_buf, 0, *matrix_uniform, size_of(type_of(matrix_uniform)));
        multiply_color = FragMultiplyUniform.{ 1.0, 0.5 + cos(t) * 1.0, 1.0, 1.0 };
        SDL_PushGPUFragmentUniformData(cmd_buf, 0, *multiply_color, size_of(type_of(multiply_color)));
        SDL_DrawGPUIndexedPrimitives(render_pass, 6, 1, 0, 0, 0);

        SDL_EndGPURenderPass(render_pass);
    }

    SDL_SubmitGPUCommandBuffer(cmd_buf);

    return 0;
}

quit :: () -> int {
    SDL_ReleaseGPUGraphicsPipeline(context.device, pipeline);
    SDL_ReleaseGPUBuffer(context.device, vertex_buffer);
    SDL_ReleaseGPUBuffer(context.device, index_buffer);
    SDL_ReleaseGPUTexture(context.device, texture);
    SDL_ReleaseGPUSampler(context.device, sampler);

    t = 0;

    common_quit();

    return 0;
}

#scope_export

textured_animated_quad_example := SDLExample.{
    name = "TexturedAnimatedQuad",
    init = init,
    quit = quit,
    update = update,
    draw = draw
};
