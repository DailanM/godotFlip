#[compute]
#version 450

// Make sure the compute keyword is uncommented, and that it doesn't have a comment on the same line.
// Also, the linting plugin only works if the first line is commented, and the file extension is .comp
// Godot only works when the first line is NOT commented and the file extension is .glsl
// What a pain.

// float or double
#define REAL float            

// vec3 or dvec3
#define Rvec3 vec3

#define REALTYPE precise REAL
#define REALCAST REAL
// Nothing
#define INEXACT

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer coherent readonly bfPoints        { REALTYPE point[]; };

layout(set = 0, binding = 1, std430) buffer coherent readonly bfPointsToAdd   { uint pointsToAdd[]; };

layout(set = 0, binding = 2, std430) buffer coherent bfTetOfPoints            { uint tetOfPoints[]; };

layout(set = 0, binding = 3, std430) buffer bfTetraToSplit                    { uint tetraToSplit[]; };

layout(set = 0, binding = 4, std430) buffer bfFace                            { uint face[]; };

layout(set = 0, binding = 5, std430) buffer bfLocations                       { uint locations[]; };

layout(set = 0, binding = 6, std430) buffer ufFreedTetra                       { uint freedTetra[]; };

layout(set = 0, binding = 7, std430) buffer ufFreedFaces                       { uint freedFaces[]; };

layout(set = 0, binding = 8, std430) buffer bfPredConsts                      { REALTYPE predConsts[]; };

layout(set = 0, binding = 9, std430) buffer restrict coherent bfParam
{
    uint lastTetra;
    uint lastFace;
    uint lastEdge;
    uint numFreedTetra;
    uint numFreedFaces;
    uint numFreedEdges;
    uint numSplitTetra;
};


/* Which of the following two methods of finding the absolute values is      */
/*   fastest is compiler-dependent.  A few compilers can inline and optimize */
/*   the fabs() call; but most will incur the overhead of a function call,   */
/*   which is disastrously slow.  A faster way on IEEE machines might be to  */
/*   mask the appropriate bit, but that's difficult to do in C.              */

#define Absolute(a)  ((a) >= 0.0 ? (a) : -(a))
/* #define Absolute(a)  fabs(a) */
      
//  orient3d_fast()   Adaptive exact 3D orientation test.  Robust.                
//                                                                           
//               Return a positive value if the point pd lies below the      
//               plane passing through pa, pb, and pc; "below" is defined so 
//               that pa, pb, and pc appear in counterclockwise order when   
//               viewed from above the plane.  Returns a negative value if   
//               pd lies above the plane.  Returns zero if the points are    
//               'nearly' coplanar.
//                                                                           
//  Only the first and last routine should be used; the middle two are for   
//  timings.                                                                 
//                                                                           
//  The last three use exact arithmetic to ensure a correct answer.  The     
//  result returned is the determinant of a matrix.  In orient3d() only,     
//  this determinant is computed adaptively, in the sense that exact         
//  arithmetic is used only to the degree it is needed to ensure that the    
//  returned value has the correct sign.  Hence, orient3d() is usually quite 
//  fast, but will run more slowly when the input points are coplanar or     
//  nearly so.                                                               
//                                                                           

REALTYPE orient3d_fast(Rvec3 pa,Rvec3 pb,Rvec3 pc,Rvec3 pd)
{
  REALTYPE adx, bdx, cdx, ady, bdy, cdy, adz, bdz, cdz;
  REALTYPE bdxcdy, cdxbdy, cdxady, adxcdy, adxbdy, bdxady;
  REALTYPE det;
  REALTYPE permanent, errbound;

  adx = pa[0] - pd[0];
  bdx = pb[0] - pd[0];
  cdx = pc[0] - pd[0];
  ady = pa[1] - pd[1];
  bdy = pb[1] - pd[1];
  cdy = pc[1] - pd[1];
  adz = pa[2] - pd[2];
  bdz = pb[2] - pd[2];
  cdz = pc[2] - pd[2];

  bdxcdy = bdx * cdy;
  cdxbdy = cdx * bdy;

  cdxady = cdx * ady;
  adxcdy = adx * cdy;

  adxbdy = adx * bdy;
  bdxady = bdx * ady;

  det = adz * (bdxcdy - cdxbdy) 
      + bdz * (cdxady - adxcdy)
      + cdz * (adxbdy - bdxady);

  permanent = (Absolute(bdxcdy) + Absolute(cdxbdy)) * Absolute(adz)
            + (Absolute(cdxady) + Absolute(adxcdy)) * Absolute(bdz)
            + (Absolute(adxbdy) + Absolute(bdxady)) * Absolute(cdz);
  errbound = predConsts[ 6 ] * permanent;
  if ((det > errbound) || (-det > errbound)) {
    return det;
  }

  return 0;
}

// The code we want to execute in each invocation
// we iterate over the points remaining after we have removed the split points.
void main()
{ 
    // ----------------- Grab all the info we need up front -----------------
    uint id                      =  gl_WorkGroupID.x;
    uint pointIndex              =  pointsToAdd[ id ];
    uint presplitTetraOfPoint    =  tetOfPoints[ id ]; // This is what we're responsible for updating.
    uint splitOfPoint            = tetraToSplit[ presplitTetraOfPoint ] - 1;      // For offsets and such.

    uint tetraExpansionOffset = lastTetra + 1; // The index of the first empty space in the expanded space
    uint faceExpansionOffset  = lastFace + 1; // The index of the first empty space in the expanded space

    uint tetA = presplitTetraOfPoint;
    uint tetB;
    uint tetC;
    uint tetD;

    // these guys seem to be returning undefined values.
    if( splitOfPoint * 3 + 0 < numFreedTetra ){ tetB = freedTetra[ ( splitOfPoint * 3 ) + 0 ]; } else { tetB = tetraExpansionOffset + ( ( ( splitOfPoint * 3 ) + 0) - numFreedTetra ); }
    if( splitOfPoint * 3 + 1 < numFreedTetra ){ tetC = freedTetra[ ( splitOfPoint * 3 ) + 1 ]; } else { tetC = tetraExpansionOffset + ( ( ( splitOfPoint * 3 ) + 1) - numFreedTetra ); }
    if( splitOfPoint * 3 + 2 < numFreedTetra ){ tetD = freedTetra[ ( splitOfPoint * 3 ) + 2 ]; } else { tetD = tetraExpansionOffset + ( ( ( splitOfPoint * 3 ) + 2) - numFreedTetra ); }

    uint fABE;
    uint fAEC;
    uint fAED;
    uint fBEC;
    uint fBED;
    uint fCDE;

    if( splitOfPoint * 6 + 0 < numFreedFaces ){ fABE = freedFaces[ ( splitOfPoint * 6 ) + 0 ]; } else { fABE = faceExpansionOffset + ( ( ( splitOfPoint * 6 ) + 0) - numFreedFaces ); }
    if( splitOfPoint * 6 + 1 < numFreedFaces ){ fAEC = freedFaces[ ( splitOfPoint * 6 ) + 1 ]; } else { fAEC = faceExpansionOffset + ( ( ( splitOfPoint * 6 ) + 1) - numFreedFaces ); }
    if( splitOfPoint * 6 + 2 < numFreedFaces ){ fAED = freedFaces[ ( splitOfPoint * 6 ) + 2 ]; } else { fAED = faceExpansionOffset + ( ( ( splitOfPoint * 6 ) + 2) - numFreedFaces ); }
    if( splitOfPoint * 6 + 3 < numFreedFaces ){ fBEC = freedFaces[ ( splitOfPoint * 6 ) + 3 ]; } else { fBEC = faceExpansionOffset + ( ( ( splitOfPoint * 6 ) + 3) - numFreedFaces ); }
    if( splitOfPoint * 6 + 4 < numFreedFaces ){ fBED = freedFaces[ ( splitOfPoint * 6 ) + 4 ]; } else { fBED = faceExpansionOffset + ( ( ( splitOfPoint * 6 ) + 4) - numFreedFaces ); }
    if( splitOfPoint * 6 + 5 < numFreedFaces ){ fCDE = freedFaces[ ( splitOfPoint * 6 ) + 5 ]; } else { fCDE = faceExpansionOffset + ( ( ( splitOfPoint * 6 ) + 5) - numFreedFaces ); }

    // Not the cleanest way to get the point indices, but it works.
    uint indA = face[ 3*fABE + 0 ];
    uint indB = face[ 3*fABE + 1 ];
    uint indC = face[ 3*fAEC + 2 ];
    uint indD = face[ 3*fAED + 2 ];
    uint indE = face[ 3*fABE + 2 ];

    Rvec3 pA = Rvec3( point[ 3 * indA + 0 ], point[ 3 * indA + 1 ], point[ 3 * indA + 2 ] );
    Rvec3 pB = Rvec3( point[ 3 * indB + 0 ], point[ 3 * indB + 1 ], point[ 3 * indB + 2 ] );
    Rvec3 pC = Rvec3( point[ 3 * indC + 0 ], point[ 3 * indC + 1 ], point[ 3 * indC + 2 ] );
    Rvec3 pD = Rvec3( point[ 3 * indD + 0 ], point[ 3 * indD + 1 ], point[ 3 * indD + 2 ] );
    Rvec3 pE = Rvec3( point[ 3 * indE + 0 ], point[ 3 * indE + 1 ], point[ 3 * indE + 2 ] );

    Rvec3 pTest = Rvec3(point[ 3 * pointIndex + 0 ], point[ 3 * pointIndex + 1 ], point[ 3 * pointIndex + 2 ] );

    // ----------------- start sorting -----------------
    // HINT: For face X, we need to compute the orientation of our point wrt the faces that don't contain the point x.
    // 'x' is the point of the presplit tetra that the split sub-tetra X does not contain. The faces are precisely the faces added.
    // Look at the splitting kernel for more info.

    REALTYPE orABE;
    REALTYPE orAEC;
    REALTYPE orAED;
    REALTYPE orBEC;
    REALTYPE orBED;
    REALTYPE orCDE;

    // Logs the result of our computation.
    //  10 bits of location data in a base 3 expantion, one bit to flag whether the point was actually located.
    uint located = 0;

    orBEC = orient3d_fast( pB, pE, pC, pTest);
    orBED = orient3d_fast( pB, pE, pD, pTest);
    orCDE = orient3d_fast( pC, pD, pE, pTest);
    
    // encode.
    located += ( int(sign( orBEC )) + 1 ) * ( uint(pow(3,0)) );
    located += ( int(sign( orBED )) + 1 ) * ( uint(pow(3,1)) );
    located += ( int(sign( orCDE )) + 1 ) * ( uint(pow(3,2)) );


    // TODO: match case, and then remove the if statements.

    // check tetA
    if( ( orBEC > 0 ) && ( orBED < 0 ) && ( orCDE < 0 ) ){
      // This point belongs to tetA!
      tetOfPoints[ id ] = tetA;
      located = (located << 1) + 0;
      
    } else {
      orAEC = orient3d_fast( pA, pE, pC, pTest);
      orAED = orient3d_fast( pA, pE, pD, pTest);

      // encode.
      located += ( int(sign( orAEC )) + 1 ) * ( uint(pow(3,3)) );
      located += ( int(sign( orAED )) + 1 ) * ( uint(pow(3,4)) );

      // check tetB
      if( ( orAEC < 0.0 ) && ( orAED > 0.0 ) && ( orCDE > 0.0 ) ){
        // This point belongs to tetB!
        tetOfPoints[ id ] = tetB;
        located = (located << 1) + 0;

      } else {

        orABE = orient3d_fast( pA, pB, pE, pTest);

        // encode.
        located += ( int(sign( orABE )) + 1 ) * ( uint(pow(3,5)) );

        // check tetC
        if( ( orABE < 0.0 ) && ( orAED < 0.0 ) && ( orBED > 0.0 ) ){
          // This point belongs to tetC!
          tetOfPoints[ id ] = tetC;
          located = (located << 1) + 0;

        } else {

          // check tetD
          if( ( orABE > 0.0 ) && ( orAEC > 0.0 ) && ( orBEC < 0.0 ) ){
            // This point belongs to tetD!
            tetOfPoints[ id ] = tetD;
            located = (located << 1) + 0;

          } else {
            located = (located << 1) + 1; // Flag not found. We need more precision!
          }
        }
      }
    }
    locations[id] = located;
    // Now location should tell us if our point is assigned, and we have assigned if we can.
    // Move to compact the point list so we can do a high precision computation where needed.
}