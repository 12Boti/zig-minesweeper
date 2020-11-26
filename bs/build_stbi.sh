source bs/common.sh

mkdir -p out

echo "${blue}compiling stb_image...${nc} $CFLAGS"
# :( it's impossible to set cache dir with `zig cc` (https://github.com/ziglang/zig/issues/5061)
zig cc -D STB_IMAGE_IMPLEMENTATION -D STBI_NO_STDIO -c -x c deps/stb_image.h -o out/stb_image.obj $CFLAGS