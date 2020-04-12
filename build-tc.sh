#!/usr/bin/env bash

# Function to show an informational message
function msg() {
    echo -e "\e[1;32m$*\e[0m"
}

# Set Chat ID, to push Notifications
CHATID="-1001232545787"

# Set a directory
DIR="$(pwd ...)"

# Inlined function to post a message
export BOT_MSG_URL="https://api.telegram.org/bot$TOKEN/sendMessage"
function tg_post_msg {
	curl -s -X POST "$BOT_MSG_URL" -d chat_id="$CHATID" \
	-d "disable_web_page_preview=true" \
	-d "parse_mode=html" \
	-d text="$1"

}

# Build Info
rel_date="$(date "+%Y%m%d")" # ISO 8601 format
rel_friendly_date="$(date "+%B %-d, %Y")" # "Month day, year" format
builder_commit="$(git rev-parse HEAD)"

# Send a notificaton to TG
tg_post_msg "<b>Azure Clang Compilation Started</b>%0A<b>Date : </b><code>$rel_friendly_date</code>%0A<b>Toolchain Script Commit : </b><code>$builder_commit</code>%0A"

# Build LLVM
msg "Building LLVM..."
tg_post_msg "<code>Building LLVM</code>"
./build-llvm.py \
	--clang-vendor "Azure" \
	--projects "clang;compiler-rt;lld;polly" \
	--targets "ARM;AArch64" \
	--shallow-clone \
	--incremental \
	--build-type "Release" \
	--pgo \
	--lto full

# Build binutils
msg "Building binutils..."
tg_post_msg "<code>Building Binutils</code>"
./build-binutils.py --targets arm aarch64

# Remove unused products
msg "Removing unused products..."
tg_post_msg "<code>Removing unused products...</code>"
rm -fr install/include
rm -f install/lib/*.a install/lib/*.la

# Strip remaining products
msg "Stripping remaining products..."
tg_post_msg "<code>Stripping remaining products...</code>"
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
	strip "${f: : -1}"
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
msg "Setting library load paths for portability..."
tg_post_msg "<code>Setting library load paths for portability...</code>"
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
	# Remove last character from file output (':')
	bin="${bin: : -1}"

	echo "$bin"
	patchelf --set-rpath "$DIR/install/lib" "$bin"
done

# Release Info
pushd llvm-project || exit
llvm_commit="$(git rev-parse HEAD)"
short_llvm_commit="$(cut -c-8 <<< "$llvm_commit")"
popd || exit

llvm_commit_url="https://github.com/llvm/llvm-project/commit/$short_llvm_commit"
binutils_ver="$(ls ./*binutils-* | sed "s/binutils-//g")"
clang_version="$(install/bin/clang --version | head -n1 | cut -d' ' -f4)"

tg_post_msg "<b>Azure clang compilation Finished</b>%0A<b>Clang Version : </b><code>$clang_version</code>%0A<b>LLVM Commit : </b><code>$llvm_commit_url</code>%0A<b>Binutils Version : </b><code>$binutils_ver</code>"

# Push to GitHub
# Update Git repository
tg_post_msg "<code>Preparing for Github Repository..</code>"
git config --global user.name "Panchajanya1999"
git config --global user.email "panchajanya@azure-dev.live"
git clone "https://Panchajanya1999:$GITHUB_TOKEN@github.com/Panchajanya1999/azure-clang.git" rel_repo
pushd rel_repo || exit
rm -fr ./*
cp -r ../install/* .
git checkout README.md # keep this as it's not part of the toolchain itself
git add .
git commit -am "Update to $rel_date build

LLVM commit: $llvm_commit_url
binutils version: $binutils_ver
Builder commit: https://github.com/Panchajanya1999/tc-build/commit/$builder_commit"
git push -f
popd || exit
tg_post_msg "<b>Toolchain Compilation Finished and pushed</b>"
