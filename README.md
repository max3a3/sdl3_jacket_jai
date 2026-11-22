Demo project of llm conversion of .c to .jai, test of using https://github.com/matteopolak/jacket .jai compiler and its built-in sdl3 extension.


src/sdl-examples/  .jai samples from https://github.com/isomorphic-tech/jai-sdl3/  with some new ones that is ported by llm (deepseek-flash) 


Original .c examples in c-examples/ from https://github.com/TheSpydog/SDL_gpu_examples

Main file is in *src/examples.jai*, edit the top part to bring in different example. It needs a compiled shaders to run.

Compile *build-asset.jai* and run *build-asset.exe* if you change/add shader

Only windows .dxil compiled shader is in the repo and tested in build-asset.jai

Shader compilation uses shader-cross https://github.com/libsdl-org/SDL_shadercross/ so make sure it is in the PATH

windows version can be built from https://github.com/howprice/SDL_shadercross_build 

build-asset.jai pipeline is from https://github.com/bqwstt/cutengine


There is no first.jai because this repo is only for demo purpose and a test of llm based coding.



agents.md is from https://github.com/qiekn/ootss-cmd, I set it up so everthing is contained in this project by setting up links (junction) in docs/

src/docs/junction.txt has instruction how to set up docs/ so llm can look for .jai reference

there is also example purely vibecoded .jai project agent.md in https://github.com/jdiaz97/bombjai