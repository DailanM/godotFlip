#[compute]
#version 450

// Make sure the compute keyword is uncommented, and that it doesn't have a comment on the same line.
// Also, the linting plugin only works if the first line is commented, and the file extension is .comp
// Godot only works when the first line is NOT commented and the file extension is .glsl
// What a pain.

#define REAL float            // float or double
#define Rvec3 vec3            // vec3 or dvec3
#define REALTYPE precise REAL
#define REALCAST REAL
#define INEXACT                          /* Nothing */
/* #define INEXACT volatile */

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding =  0, std430) restrict coherent buffer bfPoints        {REALTYPE point[]; };
layout(set = 0, binding =  1, std430) restrict coherent buffer bfBadPoints     {uint badPoints[]; };
layout(set = 0, binding =  2, std430) restrict coherent buffer bfPointsToAdd   {uint pointsToAdd[]; };
layout(set = 0, binding =  3, std430) restrict coherent buffer bfTetOfPoints   {uint tetOfPoints[]; };
layout(set = 0, binding =  4, std430) restrict coherent buffer bfTetraToSplit  {uint tetraToSplit[]; };
layout(set = 0, binding =  5, std430) restrict coherent buffer bfFace          {uint face[]; };
layout(set = 0, binding =  6, std430) restrict coherent buffer bfLocations     {uint locations[]; };
layout(set = 0, binding =  7, std430) restrict coherent buffer ufFreedTetra                       { uint freedTetra[]; };
layout(set = 0, binding =  8, std430) restrict coherent buffer ufFreedFaces                       { uint freedFaces[]; };
layout(set = 0, binding =  9, std430) restrict coherent buffer bfPredConsts    {REALTYPE predConsts[]; };
layout(set = 0, binding = 10, std430) restrict coherent buffer bfParam
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

/* Many of the operations are broken up into two pieces, a main part that    */
/*   performs an approximate operation, and a "tail" that computes the       */
/*   roundoff error of that operation.                                       */
/*                                                                           */
/* The operations Fast_Two_Sum(), Fast_Two_Diff(), Two_Sum(), Two_Diff(),    */
/*   Split(), and Two_Product() are all implemented as described in the      */
/*   reference.  Each of these macros requires certain variables to be       */
/*   defined in the calling routine.  The variables `bvirt', `c', `abig',    */
/*   `_i', `_j', `_k', `_l', `_m', and `_n' are declared `INEXACT' because   */
/*   they store the result of an operation that may incur roundoff error.    */
/*   The input parameter `x' (or the highest numbered `x_' parameter) must   */
/*   also be declared `INEXACT'.                                             */


#define Fast_Two_Sum_Tail(a, b, x, y) \
  bvirt = x - a; \
  y = b - bvirt

#define Fast_Two_Sum(a, b, x, y) \
  x = REALCAST(a + b); \
  Fast_Two_Sum_Tail(a, b, x, y)

#define Fast_Two_Diff_Tail(a, b, x, y) \
  bvirt = a - x; \
  y = bvirt - b

#define Fast_Two_Diff(a, b, x, y) \
  x = REALCAST(a - b); \
  Fast_Two_Diff_Tail(a, b, x, y)

#define Two_Sum_Tail(a, b, x, y) \
  bvirt = REALCAST(x - a); \
  avirt = x - bvirt; \
  bround = b - bvirt; \
  around = a - avirt; \
  y = around + bround

#define Two_Sum(a, b, x, y) \
  x = REALCAST(a + b); \
  Two_Sum_Tail(a, b, x, y)

#define Two_Diff_Tail(a, b, x, y) \
  bvirt = REALCAST(a - x); \
  avirt = x + bvirt; \
  bround = bvirt - b; \
  around = a - avirt; \
  y = around + bround

#define Two_Diff(a, b, x, y) \
  x = REALCAST(a - b); \
  Two_Diff_Tail(a, b, x, y)

#define Split(a, ahi, alo) \
  c = (predConsts[ 1 ] * a); \
  abig = (c - a); \
  ahi = c - abig; \
  alo = a - ahi

#define Two_Product_Tail(a, b, x, y) \
  Split(a, ahi, alo); \
  Split(b, bhi, blo); \
  err1 = x - (ahi * bhi); \
  err2 = err1 - (alo * bhi); \
  err3 = err2 - (ahi * blo); \
  y = (alo * blo) - err3

#define Two_Product(a, b, x, y) \
  x = (a * b); \
  Two_Product_Tail(a, b, x, y)

// Two_Product_Presplit() is Two_Product() where one of the inputs has       
//   already been split.  Avoids redundant splitting.                        

#define Two_Product_Presplit(a, b, bhi, blo, x, y) \
  x = REALCAST(a * b); \
  Split(a, ahi, alo); \
  err1 = x - (ahi * bhi); \
  err2 = err1 - (alo * bhi); \
  err3 = err2 - (ahi * blo); \
  y = (alo * blo) - err3

// Two_Product_2Presplit() is Two_Product() where both of the inputs have    
//   already been split.  Avoids redundant splitting.                        

#define Two_Product_2Presplit(a, ahi, alo, b, bhi, blo, x, y) \
  x = REALCAST(a * b); \
  err1 = x - (ahi * bhi); \
  err2 = err1 - (alo * bhi); \
  err3 = err2 - (ahi * blo); \
  y = (alo * blo) - err3

// Square() can be done more quickly than Two_Product().                     

#define Square_Tail(a, x, y) \
  Split(a, ahi, alo); \
  err1 = x - (ahi * ahi); \
  err3 = err1 - ((ahi + ahi) * alo); \
  y = (alo * alo) - err3

#define Square(a, x, y) \
  x = REALCAST(a * a); \
  Square_Tail(a, x, y)


// Macros for summing expansions of various fixed lengths.  These are all    
//   unrolled versions of Expansion_Sum().                                   

#define Two_One_Sum(a1, a0, b, x2, x1, x0) \
  Two_Sum(a0, b , _i, x0); \
  Two_Sum(a1, _i, x2, x1)

#define Two_One_Diff(a1, a0, b, x2, x1, x0) \
  Two_Diff(a0, b , _i, x0); \
  Two_Sum( a1, _i, x2, x1)

#define Two_Two_Sum(a1, a0, b1, b0, x3, x2, x1, x0) \
  Two_One_Sum(a1, a0, b0, _j, _0, x0); \
  Two_One_Sum(_j, _0, b1, x3, x2, x1)

#define Two_Two_Diff(a1, a0, b1, b0, x3, x2, x1, x0) \
  Two_One_Diff(a1, a0, b0, _j, _0, x0); \
  Two_One_Diff(_j, _0, b1, x3, x2, x1)

#define Four_One_Sum(a3, a2, a1, a0, b, x4, x3, x2, x1, x0) \
  Two_One_Sum(a1, a0, b , _j, x1, x0); \
  Two_One_Sum(a3, a2, _j, x4, x3, x2)

#define Four_Two_Sum(a3, a2, a1, a0, b1, b0, x5, x4, x3, x2, x1, x0) \
  Four_One_Sum(a3, a2, a1, a0, b0, _k, _2, _1, _0, x0); \
  Four_One_Sum(_k, _2, _1, _0, b1, x5, x4, x3, x2, x1)

#define Four_Four_Sum(a3, a2, a1, a0, b4, b3, b1, b0, x7, x6, x5, x4, x3, x2, \
                      x1, x0) \
  Four_Two_Sum(a3, a2, a1, a0, b1, b0, _l, _2, _1, _0, x1, x0); \
  Four_Two_Sum(_l, _2, _1, _0, b4, b3, x7, x6, x5, x4, x3, x2)

#define Eight_One_Sum(a7, a6, a5, a4, a3, a2, a1, a0, b, x8, x7, x6, x5, x4, \
                      x3, x2, x1, x0) \
  Four_One_Sum(a3, a2, a1, a0, b , _j, x3, x2, x1, x0); \
  Four_One_Sum(a7, a6, a5, a4, _j, x8, x7, x6, x5, x4)

#define Eight_Two_Sum(a7, a6, a5, a4, a3, a2, a1, a0, b1, b0, x9, x8, x7, \
                      x6, x5, x4, x3, x2, x1, x0) \
  Eight_One_Sum(a7, a6, a5, a4, a3, a2, a1, a0, b0, _k, _6, _5, _4, _3, _2, \
                _1, _0, x0); \
  Eight_One_Sum(_k, _6, _5, _4, _3, _2, _1, _0, b1, x9, x8, x7, x6, x5, x4, \
                x3, x2, x1)

#define Eight_Four_Sum(a7, a6, a5, a4, a3, a2, a1, a0, b4, b3, b1, b0, x11, \
                       x10, x9, x8, x7, x6, x5, x4, x3, x2, x1, x0) \
  Eight_Two_Sum(a7, a6, a5, a4, a3, a2, a1, a0, b1, b0, _l, _6, _5, _4, _3, \
                _2, _1, _0, x1, x0); \
  Eight_Two_Sum(_l, _6, _5, _4, _3, _2, _1, _0, b4, b3, x11, x10, x9, x8, \
                x7, x6, x5, x4, x3, x2)

// Macros for multiplying expansions of various fixed lengths.               

#define Two_One_Product(a1, a0, b, x3, x2, x1, x0) \
  Split(b, bhi, blo); \
  Two_Product_Presplit(a0, b, bhi, blo, _i, x0); \
  Two_Product_Presplit(a1, b, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _k, x1); \
  Fast_Two_Sum(_j, _k, x3, x2)

#define Four_One_Product(a3, a2, a1, a0, b, x7, x6, x5, x4, x3, x2, x1, x0) \
  Split(b, bhi, blo); \
  Two_Product_Presplit(a0, b, bhi, blo, _i, x0); \
  Two_Product_Presplit(a1, b, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _k, x1); \
  Fast_Two_Sum(_j, _k, _i, x2); \
  Two_Product_Presplit(a2, b, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _k, x3); \
  Fast_Two_Sum(_j, _k, _i, x4); \
  Two_Product_Presplit(a3, b, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _k, x5); \
  Fast_Two_Sum(_j, _k, x7, x6)

#define Two_Two_Product(a1, a0, b1, b0, x7, x6, x5, x4, x3, x2, x1, x0) \
  Split(a0, a0hi, a0lo); \
  Split(b0, bhi, blo); \
  Two_Product_2Presplit(a0, a0hi, a0lo, b0, bhi, blo, _i, x0); \
  Split(a1, a1hi, a1lo); \
  Two_Product_2Presplit(a1, a1hi, a1lo, b0, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _k, _1); \
  Fast_Two_Sum(_j, _k, _l, _2); \
  Split(b1, bhi, blo); \
  Two_Product_2Presplit(a0, a0hi, a0lo, b1, bhi, blo, _i, _0); \
  Two_Sum(_1, _0, _k, x1); \
  Two_Sum(_2, _k, _j, _1); \
  Two_Sum(_l, _j, _m, _2); \
  Two_Product_2Presplit(a1, a1hi, a1lo, b1, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _n, _0); \
  Two_Sum(_1, _0, _i, x2); \
  Two_Sum(_2, _i, _k, _1); \
  Two_Sum(_m, _k, _l, _2); \
  Two_Sum(_j, _n, _k, _0); \
  Two_Sum(_1, _0, _j, x3); \
  Two_Sum(_2, _j, _i, _1); \
  Two_Sum(_l, _i, _m, _2); \
  Two_Sum(_1, _k, _i, x4); \
  Two_Sum(_2, _i, _k, x5); \
  Two_Sum(_m, _k, x7, x6)

// An expansion of length two can be squared more quickly than finding the   
//   product of two different expansions of length two, and the result is    
//   guaranteed to have no more than six (rather than eight) components.     

#define Two_Square(a1, a0, x5, x4, x3, x2, x1, x0) \
  Square(a0, _j, x0); \
  _0 = a0 + a0; \
  Two_Product(a1, _0, _k, _1); \
  Two_One_Sum(_k, _1, _j, _l, _2, x1); \
  Square(a1, _j, _1); \
  Two_Two_Sum(_j, _1, _l, _2, x5, x4, x3, x2)

//                                                                           
//  fast_expansion_sum_zeroelim()   Sum two expansions, eliminating zero     
//                                  components from the output expansion.    
//                                                                           
//  Sets h = e + f.  See the long version of my paper for details.           
//                                                                           
//  If round-to-even is used (as with IEEE 754), maintains the strongly      
//  nonoverlapping property.  (That is, if e is strongly nonoverlapping, h   
//  will be also.)  Does NOT maintain the nonoverlapping or nonadjacent      
//  properties.
//

// 12 * 4 bytes in function
#define FAST_EXPANSION_SUM_ZEROELIM_FC_INT \
REALTYPE Q; \
INEXACT REALTYPE Qnew; \
INEXACT REALTYPE hh; \
INEXACT REALTYPE bvirt; \
REALTYPE avirt, bround, around; \
int eindex, findex, hindex; \
REALTYPE enow, fnow; \
enow = e[0]; \
fnow = f[0]; \
eindex = findex = 0; \
if ((fnow > enow) == (fnow > -enow)) { \
  Q = enow; \
  enow = e[++eindex]; \
} else { \
  Q = fnow; \
  fnow = f[++findex]; \
} \
hindex = 0; \
if ((eindex < elen) && (findex < flen)) { \
  if ((fnow > enow) == (fnow > -enow)) { \
    Fast_Two_Sum(enow, Q, Qnew, hh); \
    enow = e[++eindex]; \
  } else { \
    Fast_Two_Sum(fnow, Q, Qnew, hh); \
    fnow = f[++findex]; \
  } \
  Q = Qnew; \
  if (hh != 0.0) { \
    h[hindex++] = hh; \
  } \
  while ((eindex < elen) && (findex < flen)) { \
    if ((fnow > enow) == (fnow > -enow)) { \
      Two_Sum(Q, enow, Qnew, hh); \
      enow = e[++eindex]; \
    } else { \
      Two_Sum(Q, fnow, Qnew, hh); \
      fnow = f[++findex]; \
    } \
    Q = Qnew; \
    if (hh != 0.0) { \
      h[hindex++] = hh; \
    } \
  } \
} \
while (eindex < elen) { \
  Two_Sum(Q, enow, Qnew, hh); \
  enow = e[++eindex]; \
  Q = Qnew; \
  if (hh != 0.0) { \
    h[hindex++] = hh; \
  } \
} \
while (findex < flen) { \
  Two_Sum(Q, fnow, Qnew, hh); \
  fnow = f[++findex]; \
  Q = Qnew; \
  if (hh != 0.0) { \
    h[hindex++] = hh; \
  } \
} \
if ((Q != 0.0) || (hindex == 0)) { \
  h[hindex++] = Q; \
} \
return hindex;

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[4], int flen, REALTYPE f[4], REALTYPE h[8])  // h cannot be e or f.
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[4], int flen, REALTYPE f[8], REALTYPE h[16])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[8], int flen, REALTYPE f[4], REALTYPE h[12])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[8], int flen, REALTYPE f[8], REALTYPE h[16])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[8], int flen, REALTYPE f[16], REALTYPE h[24])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[16], int flen, REALTYPE f[8], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[24], int flen, REALTYPE f[24], REALTYPE h[48])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[48], int flen, REALTYPE f[48], REALTYPE h[96])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[96], int flen, REALTYPE f[96], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[4], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[12], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[16], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[96], REALTYPE h[288])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[288], int flen, REALTYPE f[288], REALTYPE h[576])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[384], int flen, REALTYPE f[384], REALTYPE h[768])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[576], int flen, REALTYPE f[576], REALTYPE h[1152])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[768], int flen, REALTYPE f[384], REALTYPE h[1152])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[1152], int flen, REALTYPE f[1152], REALTYPE h[2304])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[2304], int flen, REALTYPE f[1152], REALTYPE h[3456])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[2304], int flen, REALTYPE f[3456], REALTYPE h[5760])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }


//
//  scale_expansion_zeroelim()   Multiply an expansion by a scalar,
//                               eliminating zero components from the
//                               output expansion.
//  
//  Sets h = be.  See either version of my paper for details.                
//  
//  Maintains the nonoverlapping property.  If round-to-even is used (as
//  with IEEE 754), maintains the strongly nonoverlapping and nonadjacent
//  properties as well.  (That is, if e has one of these properties, so
//  will h.)
//

// 21 * 4 bytes in function
#define SCALE_EXP_ZEROELIM_FC_INT \
INEXACT REALTYPE Q, sum; \
REALTYPE hh; \
INEXACT REALTYPE product1; \
REALTYPE product0; \
int eindex, hindex; \
REALTYPE enow; \
INEXACT REALTYPE bvirt; \
REALTYPE avirt, bround, around; \
INEXACT REALTYPE c; \
INEXACT REALTYPE abig; \
REALTYPE ahi, alo, bhi, blo; \
REALTYPE err1, err2, err3; \
Split(b, bhi, blo); \
Two_Product_Presplit(e[0], b, bhi, blo, Q, hh); \
hindex = 0; \
if (hh != 0) { \
  h[hindex++] = hh; \
} \
for (eindex = 1; eindex < elen; eindex++) { \
  enow = e[eindex]; \
  Two_Product_Presplit(enow, b, bhi, blo, product1, product0); \
  Two_Sum(Q, product0, sum, hh); \
  if (hh != 0) { \
    h[hindex++] = hh; \
  } \
  Fast_Two_Sum(product1, sum, Q, hh); \
  if (hh != 0) { \
    h[hindex++] = hh; \
  } \
} \
if ((Q != 0.0) || (hindex == 0)) { \
  h[hindex++] = Q; \
} \
return hindex;

// Added multiple overloads for different array sizes~
int scale_expansion_zeroelim(int elen, REALTYPE e[4], REALTYPE b, REALTYPE h[8])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[4], REALTYPE b, REALTYPE h[12])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[8], REALTYPE b, REALTYPE h[16])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[12], REALTYPE b, REALTYPE h[24])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[24], REALTYPE b, REALTYPE h[48])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[48], REALTYPE b, REALTYPE h[96])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[96], REALTYPE b, REALTYPE h[192])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[192], REALTYPE b, REALTYPE h[384])
{ SCALE_EXP_ZEROELIM_FC_INT }

//                                                                           
//  estimate()   Produce a one-word estimate of an expansion's value.        
//                                                                           
//  See either version of my paper for details.                              
//

#define ESTIMATE_FC_INT \
REALTYPE Q; \
int eindex; \
Q = e[0]; \
for (eindex = 1; eindex < elen; eindex++) { \
  Q += e[eindex]; \
} \
return Q; \

REALTYPE estimate(int elen, REALTYPE e[192])
{ ESTIMATE_FC_INT }

REALTYPE estimate(int elen, REALTYPE e[1152])
{ ESTIMATE_FC_INT }

//                                                                           
//  orient3dfast()   Approximate 3D orientation test.  Nonrobust.            
//  orient3dexact()   Exact 3D orientation test.  Robust.                    
//  orient3dslow()   Another exact 3D orientation test.  Robust.             
//  orient3d()   Adaptive exact 3D orientation test.  Robust.                
//                                                                           
//               Return a positive value if the point pd lies below the      
//               plane passing through pa, pb, and pc; "below" is defined so 
//               that pa, pb, and pc appear in counterclockwise order when   
//               viewed from above the plane.  Returns a negative value if   
//               pd lies above the plane.  Returns zero if the points are    
//               coplanar.  The result is also a rough approximation of six  
//               times the signed volume of the tetrahedron defined by the   
//               four points.                                                
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

// This function has 1631 * 4 bytes of variables, including the worst function call.
REALTYPE orient3drobust(Rvec3 pa,Rvec3 pb,Rvec3 pc,Rvec3 pd )             // ( 4 *   3 * 4 byte)
{
  INEXACT REALTYPE adx, bdx, cdx, ady, bdy, cdy, adz, bdz, cdz;           // (       9 * 4 byte)
  REALTYPE det, permanent, errbound;                                      // (       3 * 4 byte)

  INEXACT REALTYPE bdxcdy1, cdxbdy1, cdxady1, adxcdy1, adxbdy1, bdxady1;  // (       6 * 4 byte)
          REALTYPE bdxcdy0, cdxbdy0, cdxady0, adxcdy0, adxbdy0, bdxady0;  // (       6 * 4 byte)
  REALTYPE bc[4], ca[4], ab[4];                                           // ( 3 *   4 * 4 byte)
  INEXACT REALTYPE bc3, ca3, ab3;                                         // (       3 * 4 byte)
  REALTYPE adet[8], bdet[8], cdet[8];                                     // ( 3 *   8 * 4 byte)
  int alen, blen, clen;                                                   // (       3 * 4 byte)
  REALTYPE abdet[16];                                                     // ( 1 *  16 * 4 byte)
  int ablen;                                                              // (       1 * 4 byte)
  REALTYPE finnow[192], finother[192], finswap[192];                      // ( 3 * 192 * 4 byte)
  REALTYPE fin1[192], fin2[192];                                          // ( 2 * 192 * 4 byte)
  int finlength;                                                          // (       1 * 4 byte)

  REALTYPE adxtail, bdxtail, cdxtail;                                     // (       3 * 4 byte)
  REALTYPE adytail, bdytail, cdytail;                                     // (       3 * 4 byte)
  REALTYPE adztail, bdztail, cdztail;                                     // (       3 * 4 byte)
  INEXACT REALTYPE at_blarge, at_clarge;                                  // (       2 * 4 byte)
  INEXACT REALTYPE bt_clarge, bt_alarge;                                  // (       2 * 4 byte)
  INEXACT REALTYPE ct_alarge, ct_blarge;                                  // (       2 * 4 byte)
  REALTYPE at_b[4], at_c[4], bt_c[4], bt_a[4], ct_a[4], ct_b[4];          // ( 6 *   4 * 4 byte)
  int at_blen, at_clen, bt_clen, bt_alen, ct_alen, ct_blen;               // (       6 * 4 byte)
  INEXACT REALTYPE bdxt_cdy1, cdxt_bdy1, cdxt_ady1;                       // (       3 * 4 byte)
  INEXACT REALTYPE adxt_cdy1, adxt_bdy1, bdxt_ady1;                       // (       3 * 4 byte)
  REALTYPE bdxt_cdy0, cdxt_bdy0, cdxt_ady0;                               // (       3 * 4 byte)
  REALTYPE adxt_cdy0, adxt_bdy0, bdxt_ady0;                               // (       3 * 4 byte)
  INEXACT REALTYPE bdyt_cdx1, cdyt_bdx1, cdyt_adx1;                       // (       3 * 4 byte)
  INEXACT REALTYPE adyt_cdx1, adyt_bdx1, bdyt_adx1;                       // (       3 * 4 byte)
  REALTYPE bdyt_cdx0, cdyt_bdx0, cdyt_adx0;                               // (       3 * 4 byte)
  REALTYPE adyt_cdx0, adyt_bdx0, bdyt_adx0;                               // (       3 * 4 byte)
  REALTYPE bct[8], cat[8], abt[8];                                        // ( 3 *   8 * 4 byte)
  int bctlen, catlen, abtlen;                                             // (       3 * 4 byte)
  INEXACT REALTYPE bdxt_cdyt1, cdxt_bdyt1, cdxt_adyt1;                    // (       3 * 4 byte)
  INEXACT REALTYPE adxt_cdyt1, adxt_bdyt1, bdxt_adyt1;                    // (       3 * 4 byte)
  REALTYPE bdxt_cdyt0, cdxt_bdyt0, cdxt_adyt0;                            // (       3 * 4 byte)
  REALTYPE adxt_cdyt0, adxt_bdyt0, bdxt_adyt0;                            // (       3 * 4 byte)
  REALTYPE u[4], v[12], w[16];                                            // ( (4 + 12 + 16) * 4 byte)
  INEXACT REALTYPE u3;                                                    // (       1 * 4 byte)
  int vlength, wlength;                                                   // (       2 * 4 byte)
  REALTYPE negate;                                                        // (       1 * 4 byte)

  INEXACT REALTYPE bvirt;                                                 // (       1 * 4 byte)
  REALTYPE avirt, bround, around;                                         // (       3 * 4 byte)
  INEXACT REALTYPE c;                                                     // (       1 * 4 byte)
  INEXACT REALTYPE abig;                                                  // (       1 * 4 byte)
  REALTYPE ahi, alo, bhi, blo;                                            // (       4 * 4 byte)
  REALTYPE err1, err2, err3;                                              // (       3 * 4 byte)
  INEXACT REALTYPE _i, _j, _k;                                            // (       3 * 4 byte)
  REALTYPE _0;                                                            // (       1 * 4 byte)

 //                                                                            // Total: 1217 * 4 bytes

  // Fast orient part

  adx = REALCAST(pa[0] - pd[0]);
  bdx = REALCAST(pb[0] - pd[0]);
  cdx = REALCAST(pc[0] - pd[0]);
  ady = REALCAST(pa[1] - pd[1]);
  bdy = REALCAST(pb[1] - pd[1]);
  cdy = REALCAST(pc[1] - pd[1]);
  adz = REALCAST(pa[2] - pd[2]);
  bdz = REALCAST(pb[2] - pd[2]);
  cdz = REALCAST(pc[2] - pd[2]);

  bdxcdy1 = bdx * cdy;
  cdxbdy1 = cdx * bdy;

  cdxady1 = cdx * ady;
  adxcdy1 = adx * cdy;

  adxbdy1 = adx * bdy;
  bdxady1 = bdx * ady;

  det = adz * (bdxcdy1 - cdxbdy1) 
      + bdz * (cdxady1 - adxcdy1)
      + cdz * (adxbdy1 - bdxady1);

  permanent = (Absolute(bdxcdy1) + Absolute(cdxbdy1)) * Absolute(adz)
            + (Absolute(cdxady1) + Absolute(adxcdy1)) * Absolute(bdz)
            + (Absolute(adxbdy1) + Absolute(bdxady1)) * Absolute(cdz);

  // Orient3d adapt part

  Two_Product(bdx, cdy, bdxcdy1, bdxcdy0);
  Two_Product(cdx, bdy, cdxbdy1, cdxbdy0);
  Two_Two_Diff(bdxcdy1, bdxcdy0, cdxbdy1, cdxbdy0, bc3, bc[2], bc[1], bc[0]);
  bc[3] = bc3;
  alen = scale_expansion_zeroelim(4, bc, adz, adet);                                    // (1 + 4 + 1 + 8 + 21) * 4 bytes

  Two_Product(cdx, ady, cdxady1, cdxady0);
  Two_Product(adx, cdy, adxcdy1, adxcdy0);
  Two_Two_Diff(cdxady1, cdxady0, adxcdy1, adxcdy0, ca3, ca[2], ca[1], ca[0]);
  ca[3] = ca3;
  blen = scale_expansion_zeroelim(4, ca, bdz, bdet);                                    // (1 + 4 + 1 + 8 + 21) * 4 bytes

  Two_Product(adx, bdy, adxbdy1, adxbdy0);
  Two_Product(bdx, ady, bdxady1, bdxady0);
  Two_Two_Diff(adxbdy1, adxbdy0, bdxady1, bdxady0, ab3, ab[2], ab[1], ab[0]);
  ab[3] = ab3;
  clen = scale_expansion_zeroelim(4, ab, cdz, cdet);                                    // (1 + 4 + 1 + 8 + 21) * 4 bytes

  ablen = fast_expansion_sum_zeroelim(alen, adet, blen, bdet, abdet);                   // ( 1 +  8 + 1 + 8 +  16 + 12 ) * 4 bytes
  finlength = fast_expansion_sum_zeroelim(ablen, abdet, clen, cdet, fin1);              // ( 1 + 16 + 1 + 8 + 192 + 12 ) * 4 bytes

  det = estimate(finlength, fin1);                                                      // 1 * 4 bytes
  errbound = predConsts[ 7 ] * permanent;
  if ((det >= errbound) || (-det >= errbound)) {
    return det;
  }

  Two_Diff_Tail(pa[0], pd[0], adx, adxtail);
  Two_Diff_Tail(pb[0], pd[0], bdx, bdxtail);
  Two_Diff_Tail(pc[0], pd[0], cdx, cdxtail);
  Two_Diff_Tail(pa[1], pd[1], ady, adytail);
  Two_Diff_Tail(pb[1], pd[1], bdy, bdytail);
  Two_Diff_Tail(pc[1], pd[1], cdy, cdytail);
  Two_Diff_Tail(pa[2], pd[2], adz, adztail);
  Two_Diff_Tail(pb[2], pd[2], bdz, bdztail);
  Two_Diff_Tail(pc[2], pd[2], cdz, cdztail);

  if ((adxtail == 0.0) && (bdxtail == 0.0) && (cdxtail == 0.0)
      && (adytail == 0.0) && (bdytail == 0.0) && (cdytail == 0.0)
      && (adztail == 0.0) && (bdztail == 0.0) && (cdztail == 0.0)) {
    return det;
  }

  errbound = predConsts[ 8 ] * permanent + predConsts[ 2 ] * Absolute(det);
  det += (adz * ((bdx * cdytail + cdy * bdxtail)
                 - (bdy * cdxtail + cdx * bdytail))
          + adztail * (bdx * cdy - bdy * cdx))
       + (bdz * ((cdx * adytail + ady * cdxtail)
                 - (cdy * adxtail + adx * cdytail))
          + bdztail * (cdx * ady - cdy * adx))
       + (cdz * ((adx * bdytail + bdy * adxtail)
                 - (ady * bdxtail + bdx * adytail))
          + cdztail * (adx * bdy - ady * bdx));
  if ((det >= errbound) || (-det >= errbound)) {
    return det;
  }

  finnow = fin1;
  finother = fin2;

  if (adxtail == 0.0) {
    if (adytail == 0.0) {
      at_b[0] = 0.0;
      at_blen = 1;
      at_c[0] = 0.0;
      at_clen = 1;
    } else {
      negate = -adytail;
      Two_Product(negate, bdx, at_blarge, at_b[0]);
      at_b[1] = at_blarge;
      at_blen = 2;
      Two_Product(adytail, cdx, at_clarge, at_c[0]);
      at_c[1] = at_clarge;
      at_clen = 2;
    }
  } else {
    if (adytail == 0.0) {
      Two_Product(adxtail, bdy, at_blarge, at_b[0]);
      at_b[1] = at_blarge;
      at_blen = 2;
      negate = -adxtail;
      Two_Product(negate, cdy, at_clarge, at_c[0]);
      at_c[1] = at_clarge;
      at_clen = 2;
    } else {
      Two_Product(adxtail, bdy, adxt_bdy1, adxt_bdy0);
      Two_Product(adytail, bdx, adyt_bdx1, adyt_bdx0);
      Two_Two_Diff(adxt_bdy1, adxt_bdy0, adyt_bdx1, adyt_bdx0,
                   at_blarge, at_b[2], at_b[1], at_b[0]);
      at_b[3] = at_blarge;
      at_blen = 4;
      Two_Product(adytail, cdx, adyt_cdx1, adyt_cdx0);
      Two_Product(adxtail, cdy, adxt_cdy1, adxt_cdy0);
      Two_Two_Diff(adyt_cdx1, adyt_cdx0, adxt_cdy1, adxt_cdy0,
                   at_clarge, at_c[2], at_c[1], at_c[0]);
      at_c[3] = at_clarge;
      at_clen = 4;
    }
  }
  if (bdxtail == 0.0) {
    if (bdytail == 0.0) {
      bt_c[0] = 0.0;
      bt_clen = 1;
      bt_a[0] = 0.0;
      bt_alen = 1;
    } else {
      negate = -bdytail;
      Two_Product(negate, cdx, bt_clarge, bt_c[0]);
      bt_c[1] = bt_clarge;
      bt_clen = 2;
      Two_Product(bdytail, adx, bt_alarge, bt_a[0]);
      bt_a[1] = bt_alarge;
      bt_alen = 2;
    }
  } else {
    if (bdytail == 0.0) {
      Two_Product(bdxtail, cdy, bt_clarge, bt_c[0]);
      bt_c[1] = bt_clarge;
      bt_clen = 2;
      negate = -bdxtail;
      Two_Product(negate, ady, bt_alarge, bt_a[0]);
      bt_a[1] = bt_alarge;
      bt_alen = 2;
    } else {
      Two_Product(bdxtail, cdy, bdxt_cdy1, bdxt_cdy0);
      Two_Product(bdytail, cdx, bdyt_cdx1, bdyt_cdx0);
      Two_Two_Diff(bdxt_cdy1, bdxt_cdy0, bdyt_cdx1, bdyt_cdx0,
                   bt_clarge, bt_c[2], bt_c[1], bt_c[0]);
      bt_c[3] = bt_clarge;
      bt_clen = 4;
      Two_Product(bdytail, adx, bdyt_adx1, bdyt_adx0);
      Two_Product(bdxtail, ady, bdxt_ady1, bdxt_ady0);
      Two_Two_Diff(bdyt_adx1, bdyt_adx0, bdxt_ady1, bdxt_ady0,
                  bt_alarge, bt_a[2], bt_a[1], bt_a[0]);
      bt_a[3] = bt_alarge;
      bt_alen = 4;
    }
  }
  if (cdxtail == 0.0) {
    if (cdytail == 0.0) {
      ct_a[0] = 0.0;
      ct_alen = 1;
      ct_b[0] = 0.0;
      ct_blen = 1;
    } else {
      negate = -cdytail;
      Two_Product(negate, adx, ct_alarge, ct_a[0]);
      ct_a[1] = ct_alarge;
      ct_alen = 2;
      Two_Product(cdytail, bdx, ct_blarge, ct_b[0]);
      ct_b[1] = ct_blarge;
      ct_blen = 2;
    }
  } else {
    if (cdytail == 0.0) {
      Two_Product(cdxtail, ady, ct_alarge, ct_a[0]);
      ct_a[1] = ct_alarge;
      ct_alen = 2;
      negate = -cdxtail;
      Two_Product(negate, bdy, ct_blarge, ct_b[0]);
      ct_b[1] = ct_blarge;
      ct_blen = 2;
    } else {
      Two_Product(cdxtail, ady, cdxt_ady1, cdxt_ady0);
      Two_Product(cdytail, adx, cdyt_adx1, cdyt_adx0);
      Two_Two_Diff(cdxt_ady1, cdxt_ady0, cdyt_adx1, cdyt_adx0,
                   ct_alarge, ct_a[2], ct_a[1], ct_a[0]);
      ct_a[3] = ct_alarge;
      ct_alen = 4;
      Two_Product(cdytail, bdx, cdyt_bdx1, cdyt_bdx0);
      Two_Product(cdxtail, bdy, cdxt_bdy1, cdxt_bdy0);
      Two_Two_Diff(cdyt_bdx1, cdyt_bdx0, cdxt_bdy1, cdxt_bdy0,
                   ct_blarge, ct_b[2], ct_b[1], ct_b[0]);
      ct_b[3] = ct_blarge;
      ct_blen = 4;
    }
  }

  bctlen = fast_expansion_sum_zeroelim(bt_clen, bt_c, ct_blen, ct_b, bct);              // ( 1 +   4 + 1 +  4 + 8 + 12) * 4 bytes
  wlength = scale_expansion_zeroelim(bctlen, bct, adz, w);                              // ( 1 +   8 + 1 + 16 + 21) * 4 bytes
  finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);     // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
  finswap = finnow; finnow = finother; finother = finswap;

  catlen = fast_expansion_sum_zeroelim(ct_alen, ct_a, at_clen, at_c, cat);              // ( 1 +   4 + 1 +  4 + 8 + 12) * 4 bytes
  wlength = scale_expansion_zeroelim(catlen, cat, bdz, w);                              // ( 1 +   8 + 1 + 16 + 21) * 4 bytes
  finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);     // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
  finswap = finnow; finnow = finother; finother = finswap;

  abtlen = fast_expansion_sum_zeroelim(at_blen, at_b, bt_alen, bt_a, abt);              // ( 1 +   4 + 1 +  4 + 8 + 12) * 4 bytes
  wlength = scale_expansion_zeroelim(abtlen, abt, cdz, w);                              // ( 1 +   8 + 1 + 16 + 21) * 4 bytes
  finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);     // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
  finswap = finnow; finnow = finother; finother = finswap;

  if (adztail != 0.0) {
    vlength = scale_expansion_zeroelim(4, bc, adztail, v);                              // ( 1 +   4 + 1 + 12 + 21) * 4 bytes
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, vlength, v, finother);   // ( 1 + 192 + 1 + 12 + 192 + 12) * 4 bytes
    finswap = finnow; finnow = finother; finother = finswap;
  }
  if (bdztail != 0.0) {
    vlength = scale_expansion_zeroelim(4, ca, bdztail, v);                              // ( 1 +   4 + 1 + 12 + 21) * 4 bytes
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, vlength, v, finother);   // ( 1 + 192 + 1 + 12 + 192 + 12) * 4 bytes
    finswap = finnow; finnow = finother; finother = finswap;
  }
  if (cdztail != 0.0) {
    vlength = scale_expansion_zeroelim(4, ab, cdztail, v);                              // ( 1 +   4 + 1 + 12 + 21) * 4 bytes
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, vlength, v, finother);   // ( 1 + 192 + 1 + 12 + 192 + 12) * 4 bytes
    finswap = finnow; finnow = finother; finother = finswap;
  }

  if (adxtail != 0.0) {
    if (bdytail != 0.0) {
      Two_Product(adxtail, bdytail, adxt_bdyt1, adxt_bdyt0);
      Two_One_Product(adxt_bdyt1, adxt_bdyt0, cdz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (cdztail != 0.0) {
        Two_One_Product(adxt_bdyt1, adxt_bdyt0, cdztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
    if (cdytail != 0.0) {
      negate = -adxtail;
      Two_Product(negate, cdytail, adxt_cdyt1, adxt_cdyt0);
      Two_One_Product(adxt_cdyt1, adxt_cdyt0, bdz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (bdztail != 0.0) {
        Two_One_Product(adxt_cdyt1, adxt_cdyt0, bdztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
  }
  if (bdxtail != 0.0) {
    if (cdytail != 0.0) {
      Two_Product(bdxtail, cdytail, bdxt_cdyt1, bdxt_cdyt0);
      Two_One_Product(bdxt_cdyt1, bdxt_cdyt0, adz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (adztail != 0.0) {
        Two_One_Product(bdxt_cdyt1, bdxt_cdyt0, adztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
    if (adytail != 0.0) {
      negate = -bdxtail;
      Two_Product(negate, adytail, bdxt_adyt1, bdxt_adyt0);
      Two_One_Product(bdxt_adyt1, bdxt_adyt0, cdz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (cdztail != 0.0) {
        Two_One_Product(bdxt_adyt1, bdxt_adyt0, cdztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
  }
  if (cdxtail != 0.0) {
    if (adytail != 0.0) {
      Two_Product(cdxtail, adytail, cdxt_adyt1, cdxt_adyt0);
      Two_One_Product(cdxt_adyt1, cdxt_adyt0, bdz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (bdztail != 0.0) {
        Two_One_Product(cdxt_adyt1, cdxt_adyt0, bdztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
    if (bdytail != 0.0) {
      negate = -cdxtail;
      Two_Product(negate, bdytail, cdxt_bdyt1, cdxt_bdyt0);
      Two_One_Product(cdxt_bdyt1, cdxt_bdyt0, adz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (adztail != 0.0) {
        Two_One_Product(cdxt_bdyt1, cdxt_bdyt0, adztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
  }

  if (adztail != 0.0) {
    wlength = scale_expansion_zeroelim(bctlen, bct, adztail, w);
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);   // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
    finswap = finnow; finnow = finother; finother = finswap;
  }
  if (bdztail != 0.0) {
    wlength = scale_expansion_zeroelim(catlen, cat, bdztail, w);
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);   // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
    finswap = finnow; finnow = finother; finother = finswap;
  }
  if (cdztail != 0.0) {
    wlength = scale_expansion_zeroelim(abtlen, abt, cdztail, w);
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);   // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
    finswap = finnow; finnow = finother; finother = finswap;
  }

  return finnow[finlength - 1];
}

uint modulus(uint x, uint y){
  return x - (y * (x / y) );
}

// The code we want to execute in each invocation
void main()
{ 
    // ----------------- Grab all the info we need up front -----------------
    uint id                   = gl_WorkGroupID.x;
    uint badPoint             = badPoints[ id ];
    uint pointIndex           = pointsToAdd[ badPoint ];
    uint presplitTetraOfPoint = tetOfPoints[ badPoint ]; // This is what we're responsible for updating.
    uint splitOfPoint         = tetraToSplit[ presplitTetraOfPoint ] - 1;      // For offsets and such.

    uint tetraExpansionOffset = lastTetra + 1; // The index of the first empty space in the expanded space
    uint faceExpansionOffset  = lastFace + 1; // The index of the first empty space in the expanded space

    uint tetA = presplitTetraOfPoint;
    uint tetB = 0;
    uint tetC = 0;
    uint tetD = 0;

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
    //
    // Fill with orientation information if we already have it. The actual value doesn't matter, but the sign does. TODO: idk if I trust the type casts yet

                              // Kills higher terms                                 Kills lower terms
    REALTYPE orABE = REALCAST( ( modulus( ( locations[ badPoint ] >> 1) , 3                     ) / ( 1                 ) ) - 1 );
    REALTYPE orAEC = REALCAST( ( modulus( ( locations[ badPoint ] >> 1) , 3 * 3                 ) / ( 3                 ) ) - 1 );
    REALTYPE orAED = REALCAST( ( modulus( ( locations[ badPoint ] >> 1) , 3 * 3 * 3             ) / ( 3 * 3             ) ) - 1 );
    REALTYPE orBEC = REALCAST( ( modulus( ( locations[ badPoint ] >> 1) , 3 * 3 * 3 * 3         ) / ( 3 * 3 * 3         ) ) - 1 );
    REALTYPE orBED = REALCAST( ( modulus( ( locations[ badPoint ] >> 1) , 3 * 3 * 3 * 3 * 3     ) / ( 3 * 3 * 3 * 3     ) ) - 1 );
    REALTYPE orCDE = REALCAST( ( modulus( ( locations[ badPoint ] >> 1) , 3 * 3 * 3 * 3 * 3 * 3 ) / ( 3 * 3 * 3 * 3 * 3 ) ) - 1 );

    uint newLocated = 0;

    // Calculate the orientation if it was planar or nearly so in our last check.
    if( orBEC == 0.0 ){ orBEC = orient3drobust( pB, pE, pC, pTest); }
    if( orBED == 0.0 ){ orBED = orient3drobust( pB, pE, pD, pTest); }
    if( orCDE == 0.0 ){ orCDE = orient3drobust( pC, pD, pE, pTest); }

    newLocated += ( int(sign( orBEC )) + 1 ) * ( uint(pow(3,0)) );
    newLocated += ( int(sign( orBED )) + 1 ) * ( uint(pow(3,1)) );
    newLocated += ( int(sign( orCDE )) + 1 ) * ( uint(pow(3,2)) );

    // check tetA
    if( ( orBEC >= 0.0 ) && ( orBED <= 0.0 ) && ( orCDE <= 0.0 ) ){ // The bounds here are OK
      // This point belongs to tetA!
      tetOfPoints[ badPoint ] = tetA;
      
    } else {

      if( orAEC == 0.0 ){ orAEC = orient3drobust( pA, pE, pC, pTest); }
      if( orAED == 0.0 ){ orAED = orient3drobust( pA, pE, pD, pTest); }

      newLocated += ( int(sign( orAEC )) + 1 ) * ( uint(pow(3,3)) );
      newLocated += ( int(sign( orAED )) + 1 ) * ( uint(pow(3,4)) );

      // check tetB
      if( ( orAEC <= 0.0 ) && ( orAED >= 0.0 ) && ( orCDE >= 0.0 ) ){
        // This point belongs to tetB!
        tetOfPoints[ badPoint ] = tetB;

      } else {

        if( orABE == 0.0 ){ orABE = orient3drobust( pA, pB, pE, pTest); }

        newLocated += ( int(sign( orABE )) + 1 ) * ( uint(pow(3,5)) );

        // check tetC
        if( ( orABE <= 0.0 ) && ( orAED <= 0.0 ) && ( orBED >= 0.0 ) ){
          // This point belongs to tetC!
          tetOfPoints[ badPoint ] = tetC;

        } else {

          // assign tetD (The only other possibility)
          //if( ( orABE > 0 ) && ( orAEC > 0 ) && ( orBEC < 0 ) ){
            // This point belongs to tetD!
            tetOfPoints[ badPoint ] = tetD;

          //} 
        }
      }
    }


    locations[ badPoint ] = newLocated << 1;
    // All the points should now be updates.
}