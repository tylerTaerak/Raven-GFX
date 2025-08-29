#!/bin/sh

rm -rf gen/*

for dir in $(ls source); do
    vertex_files=$(ls source/$dir/*.vert)
    fragment_files=$(ls source/$dir/*.frag)

    mkdir -p gen/$dir

    glslc $vertex_files -o gen/$dir/vert.spv
    glslc $fragment_files -o gen/$dir/frag.spv
done
