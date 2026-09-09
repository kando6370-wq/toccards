#!/bin/sh
set -eu

BASE_IMAGE=${NODE_RUNTIME_BASE_IMAGE:-eclipse-temurin:21.0.11_10-jre}
OUTPUT_IMAGE=${NODE_RUNTIME_IMAGE:-toccards-node-runtime:22}
NODE_BINARY=$(readlink -f "${NODE_BINARY:-$(command -v node)}")

if [ ! -x "$NODE_BINARY" ]; then
  echo "Node binary is unavailable: $NODE_BINARY" >&2
  exit 1
fi

if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  echo "Required offline base image is unavailable: $BASE_IMAGE" >&2
  exit 1
fi

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT INT TERM
mkdir -p "$workspace/rootfs"

copy_path() {
  source_path=$1
  target_path="$workspace/rootfs$source_path"
  mkdir -p "$(dirname "$target_path")"
  cp -L "$source_path" "$target_path"
}

copy_path "$NODE_BINARY"
if [ "$NODE_BINARY" != "/usr/bin/node" ]; then
  mkdir -p "$workspace/rootfs/usr/bin"
  ln -s "$NODE_BINARY" "$workspace/rootfs/usr/bin/node"
fi

ldd "$NODE_BINARY" | awk '
  /=> \// { print $3 }
  /^\// { print $1 }
' | while IFS= read -r dependency; do
  copy_path "$dependency"
done

for builtin_resource in \
  /usr/share/nodejs/acorn/dist/acorn.js \
  /usr/share/nodejs/acorn-walk/dist/walk.js \
  /usr/share/nodejs/cjs-module-lexer/dist/lexer.js \
  /usr/share/nodejs/cjs-module-lexer/lexer.js \
  /usr/share/nodejs/minimatch/dist/cjs/index.bundle.js \
  /usr/share/nodejs/undici/undici-fetch.js; do
  copy_path "$builtin_resource"
done

cat > "$workspace/Dockerfile" <<EOF
FROM $BASE_IMAGE
COPY rootfs/ /
ENTRYPOINT []
CMD ["node", "--version"]
EOF

docker build --network=none -t "$OUTPUT_IMAGE" "$workspace"
docker run --rm "$OUTPUT_IMAGE" node -e 'console.log(process.version)'
