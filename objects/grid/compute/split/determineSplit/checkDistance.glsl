#[compute]
#version 450

#define REAL float            // float or double
#define Rvec3 vec3
#define REALTYPE highp REAL
#define REALCAST REAL

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// TODO: Optimize with readonly, writeonly, coherent, and so on.
layout(set = 0, binding = 0, std430) restrict coherent readonly  buffer ufPoints            {REALTYPE points[];             };
layout(set = 0, binding = 1, std430) restrict coherent readonly  buffer ufpointsToAdd       {uint     pointsToAdd[];        };
layout(set = 0, binding = 2, std430) restrict coherent readonly  buffer ufTetraOfPoints     {uint     tetraOfPoints[];      };
layout(set = 0, binding = 3, std430) restrict coherent readonly  buffer ufTetra             {uint     tetra[];              };
layout(set = 0, binding = 4, std430) restrict coherent           buffer ufTetraIsSplitBy    {uint     tetraIsSplitBy[];     };
layout(set = 0, binding = 6, std430) restrict coherent writeonly buffer ufCircDistance      {uint     circDistance[];       };

// "the distance of the point from the circumcenter of its enclosing tetrahedron ...
// ... is nothing but the determinant of the matrix used in the insphere predicate."
REALTYPE squareDistToCircumcenter( Rvec3 pa, Rvec3 pb, Rvec3 pc, Rvec3 pd, Rvec3 pe)
{
    REALTYPE denominator;
    REALTYPE dist;
 
    // Use coordinates relative to point 'a' of the tetrahedron.
 
    // ba = b - a
    REALTYPE ba_x = pb[0] - pa[0];
    REALTYPE ba_y = pb[1] - pa[1];
    REALTYPE ba_z = pb[2] - pa[2];
 
    // ca = c - a
    REALTYPE ca_x = pc[0] - pa[0];
    REALTYPE ca_y = pc[1] - pa[1];
    REALTYPE ca_z = pc[2] - pa[2];
 
    // da = d - a
    REALTYPE da_x = pd[0] - pa[0];
    REALTYPE da_y = pd[1] - pa[1];
    REALTYPE da_z = pd[2] - pa[2];
 
    // Squares of lengths of the edges incident to 'a'.
    REALTYPE len_ba = ba_x * ba_x + ba_y * ba_y + ba_z * ba_z;
    REALTYPE len_ca = ca_x * ca_x + ca_y * ca_y + ca_z * ca_z;
    REALTYPE len_da = da_x * da_x + da_y * da_y + da_z * da_z;
 
    // Cross products of these edges.
 
    // c cross d
    REALTYPE cross_cd_x = ca_y * da_z - da_y * ca_z;
    REALTYPE cross_cd_y = ca_z * da_x - da_z * ca_x;
    REALTYPE cross_cd_z = ca_x * da_y - da_x * ca_y;
 
    // d cross b
    REALTYPE cross_db_x = da_y * ba_z - ba_y * da_z;
    REALTYPE cross_db_y = da_z * ba_x - ba_z * da_x;
    REALTYPE cross_db_z = da_x * ba_y - ba_x * da_y;
 
    // b cross c
    REALTYPE cross_bc_x = ba_y * ca_z - ca_y * ba_z;
    REALTYPE cross_bc_y = ba_z * ca_x - ca_z * ba_x;
    REALTYPE cross_bc_z = ba_x * ca_y - ca_x * ba_y;
 
    // Calculate the denominator of the formula.
    denominator = 0.5 / (ba_x * cross_cd_x + ba_y * cross_cd_y + ba_z * cross_cd_z);
 
    // Calculate offset (from 'a') of circumcenter.
    REALTYPE circ_x = (len_ba * cross_cd_x + len_ca * cross_db_x + len_da * cross_bc_x) * denominator;
    REALTYPE circ_y = (len_ba * cross_cd_y + len_ca * cross_db_y + len_da * cross_bc_y) * denominator;
    REALTYPE circ_z = (len_ba * cross_cd_z + len_ca * cross_db_z + len_da * cross_bc_z) * denominator;

    // ea = e - a
    REALTYPE ea_x = pe[0] - pa[0];
    REALTYPE ea_y = pe[1] - pa[1];
    REALTYPE ea_z = pe[2] - pa[2];

    dist = (circ_x - ea_x)*(circ_x - ea_x) + (circ_y - ea_y)*(circ_y - ea_y) + (circ_z - ea_z)*(circ_z - ea_z);

    return dist;
}

// For every point to be added in parralell,
void main()
{
    uint id = gl_WorkGroupID.x;

    // Get our point's index, and the index of the tetrahedron that it lies inside.
    uint pointIndex = pointsToAdd[ id ];
    uint tetOfPoint  = tetraOfPoints[ id ];

    // Get the actual vector, and then vectors of the tetrahedron.
    Rvec3 ourPoint = Rvec3( points[ 3 * pointIndex + 0 ],
                            points[ 3 * pointIndex + 1 ],
                            points[ 3 * pointIndex + 2 ] );

    Rvec3 tet0     = Rvec3( points[ 3 * tetra[ tetOfPoint + 0 ] + 0 ],
                            points[ 3 * tetra[ tetOfPoint + 0 ] + 1 ],
                            points[ 3 * tetra[ tetOfPoint + 0 ] + 2 ] );
        
    Rvec3 tet1     = Rvec3( points[ 3 * tetra[ tetOfPoint + 1 ] + 0 ],
                            points[ 3 * tetra[ tetOfPoint + 1 ] + 1 ],
                            points[ 3 * tetra[ tetOfPoint + 1 ] + 2 ] );
        
    Rvec3 tet2     = Rvec3( points[ 3 * tetra[ tetOfPoint + 2 ] + 0 ],
                            points[ 3 * tetra[ tetOfPoint + 2 ] + 1 ],
                            points[ 3 * tetra[ tetOfPoint + 2 ] + 2 ] );
        
    Rvec3 tet3     = Rvec3( points[ 3 * tetra[ tetOfPoint + 3 ] + 0 ],
                            points[ 3 * tetra[ tetOfPoint + 3 ] + 1 ],
                            points[ 3 * tetra[ tetOfPoint + 3 ] + 2 ] );

    // Get the distance to the circumcenter, ensuring that it is actually a float.
    float dist = squareDistToCircumcenter(tet0, tet1, tet2, tet3, ourPoint);

    // We convert the float to a uint bitwise, preserving the order of non-negative floats.
    uint scale = floatBitsToUint( abs( dist ) );

    atomicMin( tetraIsSplitBy[ tetOfPoint ], scale ); // Maybe optimize by reading if we can write first? Is that actually faster?

    circDistance[ id ] = scale;
}