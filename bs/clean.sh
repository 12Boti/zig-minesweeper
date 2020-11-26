source bs/common.sh

echo "${red}cleaning...${nc}"
rm -rf $@ out
rm -rf $@ zig-cache
rm -rf $@ src/zig-cache