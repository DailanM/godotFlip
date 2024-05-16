#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict coherent writeonly buffer bfData  { uint data[]; };
layout(set = 0, binding = 1, std430) restrict coherent readonly  buffer bfParam { uint start;  };

void main() {
    uint id = gl_WorkGroupID.x;
    data[ id ] = start + id;
}