source bs/common.sh

export ZIGFLAGS="--cache-dir out/zig-cache $ZIGFLAGS"
export CFLAGS="$CFLAGS"
export GLSLFLAGS="$GLSLFLAGS"

if [ "$1" = "release" ]; then
    ZIGFLAGS="-O ReleaseFast $ZIGFLAGS"
    CFLAGS="-Ofast $CFLAGS"
else
    GLSLFLAGS="-g $GLSLFLAGS"
fi

./bs/build_stbi.sh
./bs/build_glad.sh
./bs/build_shaders.sh

mkdir -p out

echo "${blue}compiling zig...${nc} $ZIGFLAGS"
zig build-exe src/main.zig -femit-bin=out/main.exe \
    -Ideps -Ideps/glad -Ideps/glfw-3.3.2/include \
    out/stb_image.obj out/glad.obj deps/glfw-3.3.2/out/src/Debug/glfw3.lib \
    -lgdi32 -luser32 -lkernel32 -lshell32 -lc \
    $ZIGFLAGS