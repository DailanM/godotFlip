#[compute]
#version 450

// Make sure the compute keyword is uncommented, and that it doesn't have a comment on the same line.
// Also, the linting plugin only works if the first line is commented, and the file extension is .comp
// Godot only works when the first line is NOT commented and the file extension is .glsl
// What a pain.
#define REAL float            // float or double
#define Rvec3 vec3            // vec3 or dvec3
#define REALTYPE highp REAL
#define REALCAST REAL
#define INEXACT               // nothing

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict coherent buffer ufTetraMarkedFlip {uint tetraMarkedFlip[]; };
layout(set = 0, binding = 1, std430) restrict coherent buffer ufFlipInfo        {uint flipInfo[];        };

    // Aggregate info currently reads
    // ----------------------------------------------------------------------------------------------
    // | canFlip | isOfQ | isOfS | AfarIsa | BfarIsb | faceTwist | faceTwist | cantTwoThreeFlip | ...
    // ----------------------------------------------------------------------------------------------
    // ... | Face 2 can 3-2 over | Face 1 can 3-2 over | Face 0 can 3-2 over | Face 2 Indeterminant | ...
    // ----------------------------------------------------------------------------------------------
    //                                            ... | Face 1 Indeterminant | Face 0 Indeterminant |  Each space is a bit

void main()
{
    uint id = gl_WorkGroupID.x;
    uint flipOfTet = tetraMarkedFlip[ id ]; // zero was reserved for the case where no flip was tested
    uint info;
    if( flipOfTet > 0 ){
        info = flipInfo[ flipOfTet - 1 ];
        tetraMarkedFlip[ id ] = flipOfTet * ( (info >> 13) & 1 ); // ( (info >> 13) & 1 ) = 1 if the flip ocers, 0 otherwise.
    }
}