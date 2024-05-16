#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict coherent readonly  buffer bfOld {uint old[]; };
layout(set = 0, binding = 1, std430) restrict coherent writeonly buffer bfNew {uint new[]; };

// The code we want to execute in each invocation
void main(){
    uint id = gl_WorkGroupID.x;
    new[id] = old[id];
}