#scope_file

// Port of src/sdl-examples/c-examples/CopyAndReadback.c.
//
// This example exercises SDL3 GPU's copy and readback paths. It uploads the ravioli
// texture and a small buffer of numbers, copies each on the GPU, and downloads the
// copied texture/buffer back to the CPU. The downloaded bytes are compared with the
// originals and the result is printed. The window then blits three views: the original
// texture, the GPU-side texture copy, and a half-size blit of the original.

original_texture: *SDL_GPUTexture;
texture_copy: *SDL_GPUTexture;
texture_small: *SDL_GPUTexture;

original_buffer: *SDL_GPUBuffer;
buffer_copy: *SDL_GPUBuffer;

texture_width, texture_height: u32;

TEXTURE_PATH :: #run path_join(#filepath, "../../assets/texture/ravioli.bmp");

init :: () -> int {
    if !common_init(0) {
        return -1;
    }

    // Load the image
    texture_path_as_cstring := to_c_string(TEXTURE_PATH);
    defer free(texture_path_as_cstring);

    image := SDL_LoadBMP(texture_path_as_cstring);
    if image == null {
        log("Could not load image data: %", SDL_GetError());
        return -1;
    }

    defer SDL_DestroySurface(image);

    // Same conversion as LoadImage(..., 4) in the C example's Common.h.
    image_data := SDL_ConvertSurface(image, .SDL_PIXELFORMAT_RGBA32);
    if image_data == null {
        log("Could not convert image data: %", SDL_GetError());
        return -1;
    }

    defer SDL_DestroySurface(image_data);

    texture_width = cast(u32) image_data.w;
    texture_height = cast(u32) image_data.h;

    // Create texture resources
    original_texture = SDL_CreateGPUTexture(context.device, *(SDL_GPUTextureCreateInfo.{
        type = .SDL_GPU_TEXTURETYPE_2D,
        format = .SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        width = texture_width,
        height = texture_height,
        layer_count_or_depth = 1,
        num_levels = 1,
        usage = SDL_GPU_TEXTUREUSAGE_SAMPLER
    }));

    if original_texture == null {
        log("Failed to create original texture!");
        return -1;
    }

    texture_copy = SDL_CreateGPUTexture(context.device, *(SDL_GPUTextureCreateInfo.{
        type = .SDL_GPU_TEXTURETYPE_2D,
        format = .SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        width = texture_width,
        height = texture_height,
        layer_count_or_depth = 1,
        num_levels = 1,
        usage = SDL_GPU_TEXTUREUSAGE_SAMPLER
    }));

    if texture_copy == null {
        log("Failed to create texture copy!");
        return -1;
    }

    texture_small = SDL_CreateGPUTexture(context.device, *(SDL_GPUTextureCreateInfo.{
        type = .SDL_GPU_TEXTURETYPE_2D,
        format = .SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        width = texture_width / 2,
        height = texture_height / 2,
        layer_count_or_depth = 1,
        num_levels = 1,
        usage = SDL_GPU_TEXTUREUSAGE_SAMPLER | SDL_GPU_TEXTUREUSAGE_COLOR_TARGET
    }));

    if texture_small == null {
        log("Failed to create small texture!");
        return -1;
    }

    // Eight u32s; the C initialiser only names seven, so the last one is 0.
    buffer_data := u32.[2, 4, 8, 16, 32, 64, 128, 0];
    buffer_size := cast(u32) size_of(type_of(buffer_data));

    original_buffer = SDL_CreateGPUBuffer(context.device, *(SDL_GPUBufferCreateInfo.{
        usage = SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ, // arbitrary
        size = buffer_size
    }));

    buffer_copy = SDL_CreateGPUBuffer(context.device, *(SDL_GPUBufferCreateInfo.{
        usage = SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ, // arbitrary
        size = buffer_size
    }));

    texture_byte_count := texture_width * texture_height * 4;
    transfer_buffer_size := texture_byte_count + buffer_size;

    download_transfer_buffer := SDL_CreateGPUTransferBuffer(context.device, *(SDL_GPUTransferBufferCreateInfo.{
        usage = .SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
        size = transfer_buffer_size
    }));

    defer SDL_ReleaseGPUTransferBuffer(context.device, download_transfer_buffer);

    upload_transfer_buffer := SDL_CreateGPUTransferBuffer(context.device, *(SDL_GPUTransferBufferCreateInfo.{
        usage = .SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        size = transfer_buffer_size
    }));

    defer SDL_ReleaseGPUTransferBuffer(context.device, upload_transfer_buffer);

    upload_transfer_ptr := cast(*u8) SDL_MapGPUTransferBuffer(context.device, upload_transfer_buffer, false);

    memcpy(upload_transfer_ptr, image_data.pixels, texture_byte_count);
    memcpy(upload_transfer_ptr + texture_byte_count, buffer_data.data, buffer_size);

    // Unmap before the copy pass is recorded and submitted.
    SDL_UnmapGPUTransferBuffer(context.device, upload_transfer_buffer);

    cmd_buf := SDL_AcquireGPUCommandBuffer(context.device);
    if cmd_buf == null {
        log("Failed to acquire command buffer: %", SDL_GetError());
        return -1;
    }

    copy_pass := SDL_BeginGPUCopyPass(cmd_buf);

    // Upload original texture
    SDL_UploadToGPUTexture(
        copy_pass,
        *(SDL_GPUTextureTransferInfo.{
            transfer_buffer = upload_transfer_buffer,
            offset = 0 // Zeroes out the rest
        }),
        *(SDL_GPUTextureRegion.{
            texture = original_texture,
            w = texture_width,
            h = texture_height,
            d = 1
        }),
        false);

    // Copy original to copy
    SDL_CopyGPUTextureToTexture(
        copy_pass,
        *(SDL_GPUTextureLocation.{
            texture = original_texture,
            x = 0,
            y = 0,
            z = 0
        }),
        *(SDL_GPUTextureLocation.{
            texture = texture_copy,
            x = 0,
            y = 0,
            z = 0
        }),
        texture_width,
        texture_height,
        1,
        false);

    // Upload original buffer
    SDL_UploadToGPUBuffer(
        copy_pass,
        *(SDL_GPUTransferBufferLocation.{
            transfer_buffer = upload_transfer_buffer,
            offset = texture_byte_count
        }),
        *(SDL_GPUBufferRegion.{
            buffer = original_buffer,
            offset = 0,
            size = buffer_size
        }),
        false);

    // Copy original to copy
    SDL_CopyGPUBufferToBuffer(
        copy_pass,
        *(SDL_GPUBufferLocation.{
            buffer = original_buffer,
            offset = 0
        }),
        *(SDL_GPUBufferLocation.{
            buffer = buffer_copy,
            offset = 0
        }),
        buffer_size,
        false);

    SDL_EndGPUCopyPass(copy_pass);

    // Render the half-size version
    SDL_BlitGPUTexture(cmd_buf, *(SDL_GPUBlitInfo.{
        source = .{
            texture = original_texture,
            w = texture_width,
            h = texture_height
        },
        destination = .{
            texture = texture_small,
            w = texture_width / 2,
            h = texture_height / 2
        },
        load_op = .SDL_GPU_LOADOP_DONT_CARE,
        filter = .SDL_GPU_FILTER_LINEAR
    }));

    // Download the original bytes from the copy
    copy_pass = SDL_BeginGPUCopyPass(cmd_buf);

    SDL_DownloadFromGPUTexture(
        copy_pass,
        *(SDL_GPUTextureRegion.{
            texture = texture_copy,
            w = texture_width,
            h = texture_height,
            d = 1
        }),
        *(SDL_GPUTextureTransferInfo.{
            transfer_buffer = download_transfer_buffer,
            offset = 0 // Zeroes out the rest
        }));

    SDL_DownloadFromGPUBuffer(
        copy_pass,
        *(SDL_GPUBufferRegion.{
            buffer = buffer_copy,
            offset = 0,
            size = buffer_size
        }),
        *(SDL_GPUTransferBufferLocation.{
            transfer_buffer = download_transfer_buffer,
            offset = texture_byte_count
        }));

    SDL_EndGPUCopyPass(copy_pass);

    fence := SDL_SubmitGPUCommandBufferAndAcquireFence(cmd_buf);
    if fence == null {
        log("Failed to submit readback command buffer: %", SDL_GetError());
        return -1;
    }

    SDL_WaitForGPUFences(context.device, true, *fence, 1);
    SDL_ReleaseGPUFence(context.device, fence);

    // Compare the original bytes to the copied bytes
    downloaded_data := cast(*u8) SDL_MapGPUTransferBuffer(context.device, download_transfer_buffer, false);
    if downloaded_data == null {
        log("Failed to map download transfer buffer!");
        return -1;
    }

    if memcmp(downloaded_data, image_data.pixels, texture_byte_count) == 0 {
        log("SUCCESS! Original texture bytes and the downloaded bytes match!");
    } else {
        log("FAILURE! Original texture bytes do not match downloaded bytes!");
    }

    if memcmp(downloaded_data + texture_byte_count, buffer_data.data, buffer_size) == 0 {
        log("SUCCESS! Original buffer bytes and the downloaded bytes match!");
    } else {
        log("FAILURE! Original buffer bytes do not match downloaded bytes!");
    }

    SDL_UnmapGPUTransferBuffer(context.device, download_transfer_buffer);

    return 0;
}

update :: () -> int {
    return 0;
}

draw :: () -> int {
    cmd_buf := SDL_AcquireGPUCommandBuffer(context.device);
    if cmd_buf == null {
        log("AcquireGPUCommandBuffer failed: %", SDL_GetError());
        return -1;
    }

    swapchain_texture: *SDL_GPUTexture;
    w, h: u32;
    if !SDL_WaitAndAcquireGPUSwapchainTexture(cmd_buf, context.window, *swapchain_texture, *w, *h) {
        log("WaitAndAcquireGPUSwapchainTexture failed: %", SDL_GetError());
        return -1;
    }

    if swapchain_texture != null {
        // Clear the swapchain to black first
        swapchain_target_info: SDL_GPUColorTargetInfo;
        swapchain_target_info.texture = swapchain_texture;
        swapchain_target_info.load_op = .SDL_GPU_LOADOP_CLEAR;
        swapchain_target_info.store_op = .SDL_GPU_STOREOP_STORE;
        swapchain_target_info.clear_color = SDL_FColor.{ 0, 0, 0, 1 };
        swapchain_target_info.cycle = false;

        clear_pass := SDL_BeginGPURenderPass(cmd_buf, *swapchain_target_info, 1, null);
        SDL_EndGPURenderPass(clear_pass);

        // Top-left: the original texture
        SDL_BlitGPUTexture(cmd_buf, *(SDL_GPUBlitInfo.{
            source = .{
                texture = original_texture,
                w = texture_width,
                h = texture_height
            },
            destination = .{
                texture = swapchain_texture,
                w = w / 2,
                h = h / 2
            },
            load_op = .SDL_GPU_LOADOP_LOAD,
            filter = .SDL_GPU_FILTER_NEAREST
        }));

        // Top-right: the GPU-side texture copy
        SDL_BlitGPUTexture(cmd_buf, *(SDL_GPUBlitInfo.{
            source = .{
                texture = texture_copy,
                w = texture_width,
                h = texture_height
            },
            destination = .{
                texture = swapchain_texture,
                x = w / 2,
                w = w / 2,
                h = h / 2
            },
            load_op = .SDL_GPU_LOADOP_LOAD,
            filter = .SDL_GPU_FILTER_NEAREST
        }));

        // Bottom-centre: the half-size blit of the original
        SDL_BlitGPUTexture(cmd_buf, *(SDL_GPUBlitInfo.{
            source = .{
                texture = texture_small,
                w = texture_width / 2,
                h = texture_height / 2
            },
            destination = .{
                texture = swapchain_texture,
                x = w / 4,
                y = h / 2,
                w = w / 2,
                h = h / 2
            },
            load_op = .SDL_GPU_LOADOP_LOAD,
            filter = .SDL_GPU_FILTER_NEAREST
        }));
    }

    SDL_SubmitGPUCommandBuffer(cmd_buf);

    return 0;
}

quit :: () -> int {
    SDL_ReleaseGPUTexture(context.device, original_texture);
    SDL_ReleaseGPUTexture(context.device, texture_copy);
    SDL_ReleaseGPUTexture(context.device, texture_small);

    SDL_ReleaseGPUBuffer(context.device, original_buffer);
    SDL_ReleaseGPUBuffer(context.device, buffer_copy);

    common_quit();

    return 0;
}

#scope_export

copy_and_readback_example := SDLExample.{
    name = "CopyAndReadback",
    init = init,
    quit = quit,
    update = update,
    draw = draw
};
