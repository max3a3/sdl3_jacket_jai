#import "File_Utilities";
#import "String";
#load "src/engine/asset_baker.jai";
#load "src/engine/asset_format.jai";
#load "src/engine/model.jai"; // Baker needs the 'Vertex' definition
ROOT_DIR   :: #filepath;
ASSETS_DIR :: #run path_join(ROOT_DIR, "assets");
SHADER_DIR :: #run path_join(ASSETS_DIR, "shader");

bake_shaders :: ()
{
    shader_proc :: (info: *File_Visit_Info, data: *void) {
        if ends_with(info.short_name, ".hlsl")  write_asset(info.full_name);
    }

    visit_files(
        dir_name=SHADER_DIR,
        recursive=true,
        user_data=null,
        proc=shader_proc,
    );
}

main::() {
    bake_shaders();
}