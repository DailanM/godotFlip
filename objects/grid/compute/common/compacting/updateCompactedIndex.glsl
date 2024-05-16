#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict coherent buffer ufInData    {uint inData[];     };
layout(set = 0, binding = 1, std430) restrict readonly  coherent buffer ufSumData   {uint sumData[];    };

void main(){
    uint id = gl_WorkGroupID.x;

    uint newIndex = sumData[ inData[id] ] - 1;
    inData[id] = newIndex;
}