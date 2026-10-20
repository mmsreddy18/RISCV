#!/bin/bash
# Fetch the third-party sources at the pinned versions used for verification into build/third_party.
set -e
D=${1:-build/third_party}; mkdir -p $D; cd $D
get() { n=$1; url=$2; ref=$3; [ -d $n/.git ] && return; mkdir $n; git -C $n init -q; git -C $n remote add origin $url
        git -C $n fetch -q --depth 1 origin $ref; git -C $n checkout -q FETCH_HEAD; }
get obi                 https://github.com/pulp-platform/obi                f29d4cc421248dfb5c32986bbf9918e2a1ca7556
get common_cells        https://github.com/pulp-platform/common_cells      v1.38.0
get common_verification https://github.com/pulp-platform/common_verification c5d97a1fae01d2d8e8e311dee341b6b8849dcf38
