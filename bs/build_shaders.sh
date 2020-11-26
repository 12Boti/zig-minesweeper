source bs/common.sh

mkdir -p out/shaders

echo "${blue}compiling shaders...${nc} $GLSLFLAGS"
for shader in src/shaders/*; do
    spv=${shader%\.glsl}.spv
    spv=out/${spv#src/}
    glslangValidator -G $shader -o $spv -e main --quiet $GLSLFLAGS
done
#glslangValidator -G src/shaders/ident.vert.glsl -o out/shaders/ident.vert.spv -e main -g --quiet
#glslangValidator -G src/shaders/white.frag.glsl -o out/shaders/white.frag.spv -e main -g --quiet