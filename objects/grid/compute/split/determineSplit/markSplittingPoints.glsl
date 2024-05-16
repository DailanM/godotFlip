#[compute]
#version 450

// Make sure the compute keyword is uncommented, and that it doesn't have a comment on the same line.
// Also, the linting plugin only works if the first line is commented, and the file extension is .comp
// Godot only works when the first line is NOT commented and the file extension is .glsl
// What a pain.

#define REAL float            // float or double
#define Rvec3 vec3
#define REALTYPE highp REAL
#define REALCAST REAL

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 1, std430) restrict coherent readonly  buffer ufpointsToAdd       {uint     pointsToAdd[];    };
layout(set = 0, binding = 2, std430) restrict coherent readonly  buffer ufTetraOfPoints     {uint     tetraOfPoints[];  };
layout(set = 0, binding = 4, std430) restrict coherent readonly  buffer ufTetraIsSplitBy    {uint     tetraIsSplitBy[];   };
layout(set = 0, binding = 5, std430) restrict coherent writeonly buffer ufPointsIsSplitting {uint     pointsIsSplitting[];  };

// For every point to be added in parralell,
void main()
{
    uint id = gl_WorkGroupID.x;

    // Get our point's index, and the index of the tetrahedron that it lies inside.
    uint pointIndex = pointsToAdd[ id ];
    uint tetOfPoint  = tetraOfPoints[ id ];

    pointsIsSplitting[ gl_WorkGroupID.x ] = uint( pointIndex == tetraIsSplitBy[ tetOfPoint ] );
}