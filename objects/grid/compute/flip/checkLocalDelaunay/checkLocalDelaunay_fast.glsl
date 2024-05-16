#[compute]
#version 450

// Minimal

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

layout(set = 0, binding = 0, std430) restrict coherent buffer ufActiveFace       {uint activeFace[]; };
layout(set = 0, binding = 1, std430) restrict coherent buffer ufPoints           {REALTYPE points[]; };
layout(set = 0, binding = 2, std430) restrict coherent buffer ufTetra            {uint tetra[]; };
layout(set = 0, binding = 3, std430) restrict coherent buffer ufFaceToTetra      {uint faceToTetra[]; };
layout(set = 0, binding = 4, std430) restrict coherent buffer ufTetraToFace      {uint tetraToFace[]; };
layout(set = 0, binding = 5, std430) restrict coherent buffer ufFlipInfo         {uint flipInfo[]; };
layout(set = 0, binding = 6, std430) restrict coherent buffer ufPredConsts       {REALTYPE predConsts[]; };

// ---- flip info set/get ----

// two bits for Delaunay / Indeterminant.
#define Set_Is_Not_Delaunay( INFO ) \
    INFO = ( INFO | 1 )

#define Get_Is_Not_Delaunay( INFO ) \
    ( INFO & 1 )

#define Set_Indeterminant_Delaunay( INFO ) \
    INFO = ( INFO | 2 )

#define Reset_Indeterminant_Delaunay( INFO ) \
    INFO = ( INFO & ( (uint(0) - uint(1) ) - uint(2) ) )

#define Get_Indeterminant_Delaunay( INFO ) \
    ( (INFO & 2 ) >> 1 )

// ---- Predicates ----

/* Which of the following two methods of finding the absolute values is      */
/*   fastest is compiler-dependent.  A few compilers can inline and optimize */
/*   the fabs() call; but most will incur the overhead of a function call,   */
/*   which is disastrously slow.  A faster way on IEEE machines might be to  */
/*   mask the appropriate bit, but that's difficult to do in C.              */

#define Absolute(a)  ((a) >= 0.0 ? (a) : -(a))
/* #define Absolute(a)  fabs(a) */

/*****************************************************************************/
/*                                                                           */
/*  inspherefast()   Approximate 3D insphere test.  Nonrobust.               */
/*  insphereexact()   Exact 3D insphere test.  Robust.                       */
/*  insphereslow()   Another exact 3D insphere test.  Robust.                */
/*  insphere()   Adaptive exact 3D insphere test.  Robust.                   */
/*                                                                           */
/*               Return a positive value if the point pe lies inside the     */
/*               sphere passing through pa, pb, pc, and pd; a negative value */
/*               if it lies outside; and zero if the five points are         */
/*               cospherical.  The points pa, pb, pc, and pd must be ordered */
/*               so that they have a positive orientation (as defined by     */
/*               orient3d()), or the sign of the result will be reversed.    */
/*                                                                           */
/*  Only the first and last routine should be used; the middle two are for   */
/*  timings.                                                                 */
/*                                                                           */
/*  The last three use exact arithmetic to ensure a correct answer.  The     */
/*  result returned is the determinant of a matrix.  In insphere() only,     */
/*  this determinant is computed adaptively, in the sense that exact         */
/*  arithmetic is used only to the degree it is needed to ensure that the    */
/*  returned value has the correct sign.  Hence, insphere() is usually quite */
/*  fast, but will run more slowly when the input points are cospherical or  */
/*  nearly so.                                                               */
/*                                                                           */
/*****************************************************************************/

REALTYPE insphere_fast( Rvec3 pa, Rvec3 pb, Rvec3 pc, Rvec3 pd, Rvec3 pe)
{
  REALTYPE aex, bex, cex, dex;
  REALTYPE aey, bey, cey, dey;
  REALTYPE aez, bez, cez, dez;
  REALTYPE aexbey, bexaey, bexcey, cexbey, cexdey, dexcey, dexaey, aexdey;
  REALTYPE aexcey, cexaey, bexdey, dexbey;
  REALTYPE alift, blift, clift, dlift;
  REALTYPE ab, bc, cd, da, ac, bd;
  REALTYPE abc, bcd, cda, dab;
  REALTYPE aezplus, bezplus, cezplus, dezplus;
  REALTYPE aexbeyplus, bexaeyplus, bexceyplus, cexbeyplus;
  REALTYPE cexdeyplus, dexceyplus, dexaeyplus, aexdeyplus;
  REALTYPE aexceyplus, cexaeyplus, bexdeyplus, dexbeyplus;
  REALTYPE det;
  REALTYPE permanent, errbound;

  aex = pa[0] - pe[0];
  bex = pb[0] - pe[0];
  cex = pc[0] - pe[0];
  dex = pd[0] - pe[0];
  aey = pa[1] - pe[1];
  bey = pb[1] - pe[1];
  cey = pc[1] - pe[1];
  dey = pd[1] - pe[1];
  aez = pa[2] - pe[2];
  bez = pb[2] - pe[2];
  cez = pc[2] - pe[2];
  dez = pd[2] - pe[2];

  aexbey = aex * bey;
  bexaey = bex * aey;
  ab = aexbey - bexaey;
  bexcey = bex * cey;
  cexbey = cex * bey;
  bc = bexcey - cexbey;
  cexdey = cex * dey;
  dexcey = dex * cey;
  cd = cexdey - dexcey;
  dexaey = dex * aey;
  aexdey = aex * dey;
  da = dexaey - aexdey;

  aexcey = aex * cey;
  cexaey = cex * aey;
  ac = aexcey - cexaey;
  bexdey = bex * dey;
  dexbey = dex * bey;
  bd = bexdey - dexbey;

  abc = aez * bc - bez * ac + cez * ab;
  bcd = bez * cd - cez * bd + dez * bc;
  cda = cez * da + dez * ac + aez * cd;
  dab = dez * ab + aez * bd + bez * da;

  alift = aex * aex + aey * aey + aez * aez;
  blift = bex * bex + bey * bey + bez * bez;
  clift = cex * cex + cey * cey + cez * cez;
  dlift = dex * dex + dey * dey + dez * dez;

  det = (dlift * abc - clift * dab) + (blift * cda - alift * bcd);

  aezplus = Absolute(aez);
  bezplus = Absolute(bez);
  cezplus = Absolute(cez);
  dezplus = Absolute(dez);
  aexbeyplus = Absolute(aexbey);
  bexaeyplus = Absolute(bexaey);
  bexceyplus = Absolute(bexcey);
  cexbeyplus = Absolute(cexbey);
  cexdeyplus = Absolute(cexdey);
  dexceyplus = Absolute(dexcey);
  dexaeyplus = Absolute(dexaey);
  aexdeyplus = Absolute(aexdey);
  aexceyplus = Absolute(aexcey);
  cexaeyplus = Absolute(cexaey);
  bexdeyplus = Absolute(bexdey);
  dexbeyplus = Absolute(dexbey);
  permanent = ((cexdeyplus + dexceyplus) * bezplus
               + (dexbeyplus + bexdeyplus) * cezplus
               + (bexceyplus + cexbeyplus) * dezplus)
            * alift
            + ((dexaeyplus + aexdeyplus) * cezplus
               + (aexceyplus + cexaeyplus) * dezplus
               + (cexdeyplus + dexceyplus) * aezplus)
            * blift
            + ((aexbeyplus + bexaeyplus) * dezplus
               + (bexdeyplus + dexbeyplus) * aezplus
               + (dexaeyplus + aexdeyplus) * bezplus)
            * clift
            + ((bexceyplus + cexbeyplus) * aezplus
               + (cexaeyplus + aexceyplus) * bezplus
               + (aexbeyplus + bexaeyplus) * cezplus)
            * dlift;
  errbound = predConsts[12] * permanent;
  if ((det > errbound) || (-det > errbound)) {
    return det;
  }
  
  // Indeterminant means that the point is nearly cosphereical, so we'll return this estimation:
  return 0.0;
}

// ---- Functions for readability ----

Rvec3 pointOfIndex( uint n )
{
  return Rvec3(points[ 3 * n + 0 ], points[ 3 * n + 1 ], points[ 3 * n + 2 ]);
}

// ---- Main ----

void main(){
  // zero the info:
  flipInfo[ gl_WorkGroupID.x ] = 0;

  // Get the active face
  uint activeFaceIndex = activeFace[ gl_WorkGroupID.x ];

  // Get the tetrahedra
  uint tetA = faceToTetra[ 2*activeFaceIndex + 0 ]; // The tetra in which we are positively oriented.
  uint tetB = faceToTetra[ 2*activeFaceIndex + 1 ]; // The tetra in which we are negatively oriented.

  // Get the verticies of tetB
  uint BaInd = tetra[ 4 * tetB + 0 ];  Rvec3 Ba = pointOfIndex( BaInd );
  uint BbInd = tetra[ 4 * tetB + 1 ];  Rvec3 Bb = pointOfIndex( BbInd );
  uint BcInd = tetra[ 4 * tetB + 2 ];  Rvec3 Bc = pointOfIndex( BcInd );
  uint BdInd = tetra[ 4 * tetB + 3 ];  Rvec3 Bd = pointOfIndex( BdInd );

  // Get Afar (the vertex away from the face in A).
  uint AfarInA = 2 * (1 - int( activeFaceIndex == tetraToFace[ 4 * tetA + 0 ] ) ); //int( bool ) = 1 if true, 0 if false.
  uint AfarInd = tetra[ 4 * tetA + AfarInA ];  Rvec3 Afar = pointOfIndex( AfarInd );

  float insphere = sign( insphere_fast(Ba, Bb, Bc, Bd, Afar) );

  if( insphere == 0.0 ){
    Set_Indeterminant_Delaunay( flipInfo[ gl_WorkGroupID.x ] );
  }
  else if( insphere < 0.0 ){
    Set_Is_Not_Delaunay( flipInfo[ gl_WorkGroupID.x ] );
  }
  else{
    // Do nothing, we are Delaunay.
  }

}