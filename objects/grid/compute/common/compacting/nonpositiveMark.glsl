#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly  coherent buffer ufInData          {uint inData[];  };
layout(set = 0, binding = 1, std430) restrict writeonly coherent buffer ufOutData         {uint outData[]; };

void main(){
    uint id       = gl_WorkGroupID.x;
    outData[ id ] = 1 - uint( inData[ id ] > 0);
}