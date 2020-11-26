source bs/common.sh

mkdir -p out

echo "${blue}compiling glad...${nc} $CFLAGS"
# :( it's impossible to set cache dir with `zig cc` (https://github.com/ziglang/zig/issues/5061)
zig cc -c deps/glad/glad.c -o out/glad.obj $CFLAGS