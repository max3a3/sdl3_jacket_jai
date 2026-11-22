#scope_file
load_image_png :: (full_path: string) -> *SDL_Surface {
    return SDL_LoadPNG(to_c_string(full_path));
}

pipeline: *SDL_GPUGraphicsPipeline;
vertex_buffer: *SDL_GPUBuffer;
index_buffer: *SDL_GPUBuffer;
texture: *SDL_GPUTexture;
samplers: [6] *SDL_GPUSampler;

current_sampler_index: int;

SAMPLER_NAMES :: string.[
    "PointClamp",
    "PointWrap",
    "LinearClamp",
    "LinearWrap",
    "AnisotropicClamp",
    "AnisotropicWrap",
];

// TEXTURE_PATH :: #run path_join(#filepath, "../../assets/texture/ravioli.bmp");
TEXTURE_PATH :: #run path_join(#filepath, "../../assets/texture/boid.png");

create_sampler :: (filter: SDL_GPUFilter, mipmap_mode: SDL_GPUSamplerMipmapMode, address_mode: SDL_GPUSamplerAddressMode, anisotropic := false) -> *SDL_GPUSampler {
    create_info := SDL_GPUSamplerCreateInfo.{
        min_filter = filter,
        mag_filter = filter,
        mipmap_mode = mipmap_mode,
        address_mode_u = address_mode,
        address_mode_v = address_mode,
        address_mode_w = address_mode
    };

    if anisotropic {
        create_info.enable_anisotropy = true;
        create_info.max_anisotropy = 4;
    }

    return SDL_CreateGPUSampler(context.device, *create_info);
}

init :: () -> int {
    if !common_init(0) {
        return -1;
    }

    // Create the shaders
    vertex_shader := load_shader(context.device, "TexturedQuad.vert", 0, 0, 0, 0);
    if vertex_shader == null {
        log("Failed to create vertex shader!");
        return -1;
    }

    defer SDL_ReleaseGPUShader(context.device, vertex_shader);

    fragment_shader := load_shader(context.device, "TexturedQuad.frag", 1, 0, 0, 0);
    if fragment_shader == null {
        log("Failed to create fragment shader!");
        return -1;
    }

    defer SDL_ReleaseGPUShader(context.device, fragment_shader);

    // Load the image
    image := load_image_png(TEXTURE_PATH);

    if image == null {
        log("Could not load image data!");
        return -1;
    }

    defer SDL_DestroySurface(image);

    log("Loaded image from path: %s, width: %d, height: %d", TEXTURE_PATH, image.w, image.h);


    // Create the pipeline
    // FIX: enable alpha blending. The boid sprite is white everywhere and only its
    // alpha channel makes the arrow shape, so without blending the quad draws solid white.
    color_target_descriptions := SDL_GPUColorTargetDescription.[.{
        format = SDL_GetGPUSwapchainTextureFormat(context.device, context.window),
        blend_state = .{
            enable_blend = true,
            src_color_blendfactor = .SDL_GPU_BLENDFACTOR_SRC_ALPHA,
            dst_color_blendfactor = .SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            color_blend_op = .SDL_GPU_BLENDOP_ADD,
            src_alpha_blendfactor = .SDL_GPU_BLENDFACTOR_ONE,
            dst_alpha_blendfactor = .SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            alpha_blend_op = .SDL_GPU_BLENDOP_ADD,
        }
    }];

    vertex_buffer_descriptions := SDL_GPUVertexBufferDescription.[.{
        slot = 0,
        input_rate = .SDL_GPU_VERTEXINPUTRATE_VERTEX,
        instance_step_rate = 0,
        pitch = size_of(PositionTextureVertex)
    }];

    vertex_attributes := SDL_GPUVertexAttribute.[.{
        buffer_slot = 0,
        format = .SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
        location = 0,
        offset = 0
    }, .{
        buffer_slot = 0,
        format = .SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
        location = 1,
        offset = size_of(float) * 3
    }];

    pipeline_create_info := SDL_GPUGraphicsPipelineCreateInfo.{
        target_info = .{
            num_color_targets = 1,
            color_target_descriptions = color_target_descriptions.data,
        },
        // This is set up to match the vertex shader layout!
        vertex_input_state = .{
            num_vertex_buffers = 1,
            vertex_buffer_descriptions = vertex_buffer_descriptions.data,
            num_vertex_attributes = 2,
            vertex_attributes = vertex_attributes.data
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

    // PointClamp
    samplers[0] = create_sampler(.SDL_GPU_FILTER_NEAREST, .SDL_GPU_SAMPLERMIPMAPMODE_NEAREST, .SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE);
    // PointWrap
    samplers[1] = create_sampler(.SDL_GPU_FILTER_NEAREST, .SDL_GPU_SAMPLERMIPMAPMODE_NEAREST, .SDL_GPU_SAMPLERADDRESSMODE_REPEAT);
    // LinearClamp
    samplers[2] = create_sampler(.SDL_GPU_FILTER_LINEAR, .SDL_GPU_SAMPLERMIPMAPMODE_LINEAR, .SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE);
    // LinearWrap
    samplers[3] = create_sampler(.SDL_GPU_FILTER_LINEAR, .SDL_GPU_SAMPLERMIPMAPMODE_LINEAR, .SDL_GPU_SAMPLERADDRESSMODE_REPEAT);
    // AnisotropicClamp
    samplers[4] = create_sampler(.SDL_GPU_FILTER_LINEAR, .SDL_GPU_SAMPLERMIPMAPMODE_LINEAR, .SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE, true);
    // AnisotropicWrap
    samplers[5] = create_sampler(.SDL_GPU_FILTER_LINEAR, .SDL_GPU_SAMPLERMIPMAPMODE_LINEAR, .SDL_GPU_SAMPLERADDRESSMODE_REPEAT, true);

    // Create the GPU resources
    vertex_buffer = SDL_CreateGPUBuffer(context.device, *(SDL_GPUBufferCreateInfo.{
        usage = SDL_GPU_BUFFERUSAGE_VERTEX,
        size = size_of(PositionTextureVertex) * 4
    }));

    SDL_SetGPUBufferName(context.device, vertex_buffer, "Ravioli Vertex Buffer");

    index_buffer = SDL_CreateGPUBuffer(context.device, *(SDL_GPUBufferCreateInfo.{
        usage = SDL_GPU_BUFFERUSAGE_INDEX,
        size = size_of(u16) * 6
    }));

    texture_image := SDL_ConvertSurface(image, .SDL_PIXELFORMAT_RGBA32);
    // FIX: SDL_ConvertSurface can fail; check before using texture_image.
    if texture_image == null {
        log("Failed to convert image to RGBA32: %", SDL_GetError());
        return -1;
    }

    defer SDL_DestroySurface(texture_image);

    texture = SDL_CreateGPUTexture(context.device, *(SDL_GPUTextureCreateInfo.{
        type = .SDL_GPU_TEXTURETYPE_2D,
        format = .SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        width = cast(u32) texture_image.w,
        height = cast(u32) texture_image.h,
        layer_count_or_depth = 1,
        num_levels = 1,
        usage = SDL_GPU_TEXTUREUSAGE_SAMPLER
    }));

    SDL_SetGPUTextureName(context.device, texture, "Ravioli Texture");

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

    defer SDL_UnmapGPUTransferBuffer(context.device, buffer_transfer_buffer);

    transfer_data[0] = PositionTextureVertex.{ -1, 1, 0, 0, 0 };
    transfer_data[1] = PositionTextureVertex.{ 1, 1, 0, 4, 0 };
    transfer_data[2] = PositionTextureVertex.{ 1, -1, 0, 4, 4 };
    transfer_data[3] = PositionTextureVertex.{ -1, -1, 0, 0, 4 };

    index_data := cast(*u16) *transfer_data[4];
    indices := u16.[0, 1, 2, 0, 2, 3];
    memcpy(index_data, indices.data, size_of(type_of(indices)));

    // FIX: unmap now, before the copy pass is recorded and submitted. The old
    // `defer` unmap only ran when init returned, i.e. after the submit.
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

    // FIX: unmap before the upload (see above).
    SDL_UnmapGPUTransferBuffer(context.device, texture_transfer_buffer);

    // Upload the transfer data to the GPU resources
    upload_cmd_buf := SDL_AcquireGPUCommandBuffer(context.device);
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
            offset = 0, // Zeros out the rest
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

    // Finally, print instructions!
    log("Press Left/Right to switch between sampler states");
    log("Setting sampler state to: %", SAMPLER_NAMES[0]);

    return 0;
}

update :: () -> int {
    if context.left_pressed {
        current_sampler_index -= 1;
        if current_sampler_index < 0 {
            current_sampler_index = SAMPLER_NAMES.count - 1;
        }
        log("Setting sampler state to: %", SAMPLER_NAMES[current_sampler_index]);
    }

    if context.right_pressed {
        current_sampler_index = (current_sampler_index + 1) % SAMPLER_NAMES.count;
        log("Setting sampler state to: %", SAMPLER_NAMES[current_sampler_index]);
    }

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
        color_target_info.clear_color = SDL_FColor.{ 0.5, 0.5, 0.5, 1.0 };
        color_target_info.load_op = .SDL_GPU_LOADOP_CLEAR;
        color_target_info.store_op = .SDL_GPU_STOREOP_STORE;

        render_pass := SDL_BeginGPURenderPass(cmd_buf, *color_target_info, 1, null);

        SDL_BindGPUGraphicsPipeline(render_pass, pipeline);
        SDL_BindGPUVertexBuffers(render_pass, 0, *(SDL_GPUBufferBinding.{ buffer = vertex_buffer, offset = 0 }), 1);
        SDL_BindGPUIndexBuffer(render_pass, *(SDL_GPUBufferBinding.{ buffer = index_buffer, offset = 0 }), .SDL_GPU_INDEXELEMENTSIZE_16BIT);
        SDL_BindGPUFragmentSamplers(render_pass, 0, *(SDL_GPUTextureSamplerBinding.{ texture = texture, sampler = samplers[current_sampler_index] }), 1);
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

    for samplers {
        SDL_ReleaseGPUSampler(context.device, it);
    }

    current_sampler_index = 0;

    common_quit();

    return 0;
}

#scope_export

textured_quad_example := SDLExample.{
    name = "TexturedQuad",
    init = init,
    quit = quit,
    update = update,
    draw = draw
};
