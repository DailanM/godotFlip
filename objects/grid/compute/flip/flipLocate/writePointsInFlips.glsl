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


layout(set = 0, binding = 0, std430) restrict coherent readonly  buffer ufTetOfPoints     { uint tetOfPoints[];      };
layout(set = 0, binding = 1, std430) restrict coherent readonly buffer ufMarkPointInFlip { uint markPointInFlip[];  };
layout(set = 0, binding = 2, std430) restrict coherent readonly  buffer ufTetraMarkedFlip { uint tetraMarkedFlip[];  };
//layout(set = 0, binding = 3, std430) restrict coherent readonly  buffer ufFlipInfo        { uint flipInfo[];         };
layout(set = 0, binding = 4, std430) restrict coherent writeonly  buffer ufPointsInFlips   { uint pointsInFlips[];    };

void main()
{
    uint id = gl_WorkGroupID.x;
    uint tetraOfPoint = tetOfPoints[ id ];
    uint flipOfTetra = tetraMarkedFlip[ tetraOfPoint ];
    if( flipOfTetra > 0 ){
        pointsInFlips[ markPointInFlip[ id ] - 1 ] = id;
    }
}


