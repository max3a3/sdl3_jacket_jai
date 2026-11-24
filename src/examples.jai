#load "sdl-examples/example_common.jai";

#load "sdl-examples/basic_triangle.jai";
#load "sdl-examples/instanced_indexed.jai";
#load "sdl-examples/depth_sampler.jai";
#load "sdl-examples/depth_array.jai";
#load "sdl-examples/compute_uniforms.jai";
#load "sdl-examples/textured_quad.jai";
#load "sdl-examples/textured_animated_quad.jai";

main :: () {
    // example: SDLExample = basic_triangle_example;
    // example: SDLExample = instanced_indexed_example;
    // example: SDLExample = depth_sampler_example;
    example: SDLExample = depth_array_example;
    // example: SDLExample = compute_uniforms_example;
    // example: SDLExample = textured_quad_example;
    // example: SDLExample = textured_animated_quad_example;

    if !SDL_Init(SDL_INIT_VIDEO) {
        log("Failed to initialize SDL: %", SDL_GetError());
        return;
    }


    example.init();

    quit: bool = false;
    last_time := 0.0;
    can_draw: bool = true;

    while (!quit) {
        reset_context();

        event: SDL_Event;
        while SDL_PollEvent(*event) {
            event_type := cast(SDL_EventType) event.type;

            if event_type == {
                case .SDL_EVENT_QUIT;
                    {

                        quit = true;
                    }

                case .SDL_EVENT_KEY_DOWN;
                    {
                        if event.key.key == {

                            case SDLK_LEFT;
                                {
                                    context.left_pressed = true;
                                }

                            case SDLK_RIGHT;
                                {
                                    context.right_pressed = true;
                                }

                            case SDLK_DOWN;
                                {
                                    context.down_pressed = true;
                                }

                            case SDLK_UP;
                                {
                                    context.up_pressed = true;
                                }
                        }
                    }
            }

        }
        new_time := SDL_GetTicks() / 1000.0;
        context.delta_time = new_time - last_time;

        last_time = new_time;
        if example.update() < 0 {
            log("update failed");
            return;
        }

        if can_draw {
            if example.draw() < 0 {
                log("draw failed");
                return;
            }
        }

    }
    print("Exiting main loop.");
}

reset_context :: () {
    context.left_pressed = false;
    context.right_pressed = false;
    context.down_pressed = false;
    context.up_pressed = false;
}
