#[compute]
#version 450

// TODO: comment out the unneeded definitions and unneeded functions.

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

layout(set = 0, binding = 0, std430) restrict coherent buffer ActiveFaceUniform       {uint activeFace[];     };
layout(set = 0, binding = 1, std430) restrict coherent buffer pointsUniform           {REALTYPE points[];     };
layout(set = 0, binding = 2, std430) restrict coherent buffer tetraUniform            {uint tetra[];          };
layout(set = 0, binding = 3, std430) restrict coherent buffer faceToTetraUniform      {uint faceToTetra[];    };
layout(set = 0, binding = 4, std430) restrict coherent buffer tetraToFaceUniform      {uint tetraToFace[];    };
layout(set = 0, binding = 5, std430) restrict coherent buffer flipInfoUniform         {uint flipInfo[];       };
layout(set = 0, binding = 6, std430) restrict coherent buffer ufIndetrmndFaces        {uint indetrmndFaces[]; };
layout(set = 0, binding = 7, std430) restrict coherent buffer predConstsUniform       {REALTYPE predConsts[]; };

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

//
// An expansion of length two can be squared more quickly than finding the
//   product of two different expansions of length two, and the result is
//   guaranteed to have no more than six (rather than eight) components.
//

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

// 2 * 4 bytes in function
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

// This function has 34222 * 4 bytes of variables, including the worst function call.

REALTYPE insphere_exact( Rvec3 pa, Rvec3 pb, Rvec3 pc, Rvec3 pd, Rvec3 pe)       //( 5 *    3 * 4 byte)
{
  INEXACT REALTYPE axby1, bxcy1, cxdy1, dxey1, exay1;                           //(        5 * 4 byte)
  INEXACT REALTYPE bxay1, cxby1, dxcy1, exdy1, axey1;                           //(        5 * 4 byte)
  INEXACT REALTYPE axcy1, bxdy1, cxey1, dxay1, exby1;                           //(        5 * 4 byte)
  INEXACT REALTYPE cxay1, dxby1, excy1, axdy1, bxey1;                           //(        5 * 4 byte)
  REALTYPE axby0, bxcy0, cxdy0, dxey0, exay0;                                   //(        5 * 4 byte)
  REALTYPE bxay0, cxby0, dxcy0, exdy0, axey0;                                   //(        5 * 4 byte)
  REALTYPE axcy0, bxdy0, cxey0, dxay0, exby0;                                   //(        5 * 4 byte)
  REALTYPE cxay0, dxby0, excy0, axdy0, bxey0;                                   //(        5 * 4 byte)
  REALTYPE ab[4], bc[4], cd[4], de[4], ea[4];                                   //( 5 *    4 * 4 byte)
  REALTYPE ac[4], bd[4], ce[4], da[4], eb[4];                                   //( 5 *    4 * 4 byte)
  REALTYPE temp8a[8], temp8b[8], temp16[16];                                    //( (8 + 8 + 16) * 4 byte)
  int temp8alen, temp8blen, temp16len;                                          //(        3 * 4 byte)
  REALTYPE abc[24], bcd[24], cde[24], dea[24], eab[24];                         //( 5 *   24 * 4 byte)
  REALTYPE abd[24], bce[24], cda[24], deb[24], eac[24];                         //( 5 *   24 * 4 byte)
  int abclen, bcdlen, cdelen, dealen, eablen;                                   //(        5 * 4 byte)
  int abdlen, bcelen, cdalen, deblen, eaclen;                                   //(        5 * 4 byte)
  REALTYPE temp48a[48], temp48b[48];                                            //( 2 *   48 * 4 byte)
  int temp48alen, temp48blen;                                                   //(        2 * 4 byte)
  REALTYPE abcd[96], bcde[96], cdea[96], deab[96], eabc[96];                    //( 5 *   96 * 4 byte)
  int abcdlen, bcdelen, cdealen, deablen, eabclen;                              //(        5 * 4 byte)
  REALTYPE temp192[192];                                                        //( 1 *  192 * 4 byte)
  REALTYPE det384x[384], det384y[384], det384z[384];                            //( 3 *  384 * 4 byte)
  int xlen, ylen, zlen;                                                         //(        3 * 4 byte)
  REALTYPE detxy[768];                                                          //( 1 *  768 * 4 byte)
  int xylen;                                                                    //(        1 * 4 byte)
  REALTYPE adet[1152], bdet[1152], cdet[1152], ddet[1152], edet[1152];          //( 5 * 1152 * 4 byte)
  int alen, blen, clen, dlen, elen;                                             //(        5 * 4 byte)
  REALTYPE abdet[2304], cddet[2304], cdedet[3456];                              //( (2304 + 2304 + 3456) * 4 byte)
  int ablen, cdlen;                                                             //(        2 * 4 byte)
  REALTYPE deter[5760];                                                         //( 1 * 5760 * 4 byte)
  int deterlen;                                                                 //(        1 * 4 byte)
  int i;                                                                        //(        1 * 4 byte)

  INEXACT REALTYPE bvirt;                                                       //(        1 * 4 byte)
  REALTYPE avirt, bround, around;                                               //(        3 * 4 byte)
  INEXACT REALTYPE c;                                                           //(        1 * 4 byte)
  INEXACT REALTYPE abig;                                                        //(        1 * 4 byte)
  REALTYPE ahi, alo, bhi, blo;                                                  //(        4 * 4 byte)
  REALTYPE err1, err2, err3;                                                    //(        3 * 4 byte)
  INEXACT REALTYPE _i, _j;                                                      //(        2 * 4 byte)
  REALTYPE _0;                                                                  //(        1 * 4 byte)
  //                                                                            // Total: 22688 * 4 bytes

  Two_Product(pa[0], pb[1], axby1, axby0);
  Two_Product(pb[0], pa[1], bxay1, bxay0);
  Two_Two_Diff(axby1, axby0, bxay1, bxay0, ab[3], ab[2], ab[1], ab[0]);

  Two_Product(pb[0], pc[1], bxcy1, bxcy0);
  Two_Product(pc[0], pb[1], cxby1, cxby0);
  Two_Two_Diff(bxcy1, bxcy0, cxby1, cxby0, bc[3], bc[2], bc[1], bc[0]);

  Two_Product(pc[0], pd[1], cxdy1, cxdy0);
  Two_Product(pd[0], pc[1], dxcy1, dxcy0);
  Two_Two_Diff(cxdy1, cxdy0, dxcy1, dxcy0, cd[3], cd[2], cd[1], cd[0]);

  Two_Product(pd[0], pe[1], dxey1, dxey0);
  Two_Product(pe[0], pd[1], exdy1, exdy0);
  Two_Two_Diff(dxey1, dxey0, exdy1, exdy0, de[3], de[2], de[1], de[0]);

  Two_Product(pe[0], pa[1], exay1, exay0);
  Two_Product(pa[0], pe[1], axey1, axey0);
  Two_Two_Diff(exay1, exay0, axey1, axey0, ea[3], ea[2], ea[1], ea[0]);

  Two_Product(pa[0], pc[1], axcy1, axcy0);
  Two_Product(pc[0], pa[1], cxay1, cxay0);
  Two_Two_Diff(axcy1, axcy0, cxay1, cxay0, ac[3], ac[2], ac[1], ac[0]);

  Two_Product(pb[0], pd[1], bxdy1, bxdy0);
  Two_Product(pd[0], pb[1], dxby1, dxby0);
  Two_Two_Diff(bxdy1, bxdy0, dxby1, dxby0, bd[3], bd[2], bd[1], bd[0]);

  Two_Product(pc[0], pe[1], cxey1, cxey0);
  Two_Product(pe[0], pc[1], excy1, excy0);
  Two_Two_Diff(cxey1, cxey0, excy1, excy0, ce[3], ce[2], ce[1], ce[0]);

  Two_Product(pd[0], pa[1], dxay1, dxay0);
  Two_Product(pa[0], pd[1], axdy1, axdy0);
  Two_Two_Diff(dxay1, dxay0, axdy1, axdy0, da[3], da[2], da[1], da[0]);

  Two_Product(pe[0], pb[1], exby1, exby0);
  Two_Product(pb[0], pe[1], bxey1, bxey0);
  Two_Two_Diff(exby1, exby0, bxey1, bxey0, eb[3], eb[2], eb[1], eb[0]);

  temp8alen = scale_expansion_zeroelim(4, bc, pa[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, ac, -pb[2], temp8b);                            // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +    8 + 1 +    8 +   16 + 12) * 4 bytes
  temp8alen = scale_expansion_zeroelim(4, ab, pc[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  abclen = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp16len, temp16, abc);        // (1 +    8 + 1 +   16 +   24 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, cd, pb[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, bd, -pc[2], temp8b);                            // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +    8 + 1 +    8 +   16 + 12) * 4 bytes
  temp8alen = scale_expansion_zeroelim(4, bc, pd[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  bcdlen = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp16len, temp16, bcd);        // (1 +    8 + 1 +   16 +   24 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, de, pc[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, ce, -pd[2], temp8b);                            // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +    8 + 1 +    8 +   16 + 12) * 4 bytes
  temp8alen = scale_expansion_zeroelim(4, cd, pe[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  cdelen = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp16len, temp16, cde);        // (1 +    8 + 1 +   16 +   24 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, ea, pd[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, da, -pe[2], temp8b);                            // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +    8 + 1 +    8 +   16 + 12) * 4 bytes
  temp8alen = scale_expansion_zeroelim(4, de, pa[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  dealen = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp16len, temp16, dea);        // (1 +    8 + 1 +   16 +   24 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, ab, pe[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, eb, -pa[2], temp8b);                            // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +    8 + 1 +    8 +   16 + 12) * 4 bytes
  temp8alen = scale_expansion_zeroelim(4, ea, pb[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  eablen = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp16len, temp16, eab);        // (1 +    8 + 1 +   16 +   24 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, bd, pa[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, da, pb[2], temp8b);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +    8 + 1 +    8 +   16 + 12) * 4 bytes
  temp8alen = scale_expansion_zeroelim(4, ab, pd[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  abdlen = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp16len, temp16, abd);        // (1 +    8 + 1 +   16 +   24 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, ce, pb[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, eb, pc[2], temp8b);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +    8 + 1 +    8 +   16 + 12) * 4 bytes
  temp8alen = scale_expansion_zeroelim(4, bc, pe[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  bcelen = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp16len, temp16, bce);        // (1 +    8 + 1 +   16 +   24 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, da, pc[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, ac, pd[2], temp8b);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +    8 + 1 +    8 +   16 + 12) * 4 bytes
  temp8alen = scale_expansion_zeroelim(4, cd, pa[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  cdalen = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp16len, temp16, cda);        // (1 +    8 + 1 +   16 +   24 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, eb, pd[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, bd, pe[2], temp8b);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +    8 + 1 +    8 +   16 + 12) * 4 bytes
  temp8alen = scale_expansion_zeroelim(4, de, pb[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  deblen = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp16len, temp16, deb);        // (1 +    8 + 1 +   16 +   24 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, ac, pe[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, ce, pa[2], temp8b);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +    8 + 1 +    8 +   16 + 12) * 4 bytes
  temp8alen = scale_expansion_zeroelim(4, ea, pc[2], temp8a);                             // (1 +    4 + 1 +    8        + 21) * 4 bytes
  eaclen = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp16len, temp16, eac);        // (1 +    8 + 1 +   16 +   24 + 12) * 4 bytes

  temp48alen = fast_expansion_sum_zeroelim(cdelen, cde, bcelen, bce, temp48a);            // (1 +   24 + 1 +   24 +   48 + 12) * 4 bytes
  temp48blen = fast_expansion_sum_zeroelim(deblen, deb, bcdlen, bcd, temp48b);            // (1 +   24 + 1 +   24 +   48 + 12) * 4 bytes
  for (i = 0; i < temp48blen; i++) {
    temp48b[i] = -temp48b[i];
  }
  bcdelen = fast_expansion_sum_zeroelim(temp48alen, temp48a, temp48blen, temp48b, bcde);  // (1 +   48 + 1 +   48 +   96 + 12) * 4 bytes
  xlen = scale_expansion_zeroelim(bcdelen, bcde, pa[0], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  xlen = scale_expansion_zeroelim(xlen, temp192, pa[0], det384x);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(bcdelen, bcde, pa[1], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(ylen, temp192, pa[1], det384y);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(bcdelen, bcde, pa[2], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(zlen, temp192, pa[2], det384z);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  xylen = fast_expansion_sum_zeroelim(xlen, det384x, ylen, det384y, detxy);               // (1 +  384 + 1 +  384 +  768 + 12) * 4 bytes
  alen = fast_expansion_sum_zeroelim(xylen, detxy, zlen, det384z, adet);                  // (1 +  768 + 1 +  384 + 1152 + 12) * 4 bytes

  temp48alen = fast_expansion_sum_zeroelim(dealen, dea, cdalen, cda, temp48a);            // (1 +   24 + 1 +   24 +   48 + 12) * 4 bytes
  temp48blen = fast_expansion_sum_zeroelim(eaclen, eac, cdelen, cde, temp48b);            // (1 +   24 + 1 +   24 +   48 + 12) * 4 bytes
  for (i = 0; i < temp48blen; i++) {
    temp48b[i] = -temp48b[i];
  }
  cdealen = fast_expansion_sum_zeroelim(temp48alen, temp48a, temp48blen, temp48b, cdea);
  xlen = scale_expansion_zeroelim(cdealen, cdea, pb[0], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  xlen = scale_expansion_zeroelim(xlen, temp192, pb[0], det384x);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(cdealen, cdea, pb[1], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(ylen, temp192, pb[1], det384y);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(cdealen, cdea, pb[2], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(zlen, temp192, pb[2], det384z);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  xylen = fast_expansion_sum_zeroelim(xlen, det384x, ylen, det384y, detxy);               // (1 +  384 + 1 +  384 +  768 + 12) * 4 bytes
  blen = fast_expansion_sum_zeroelim(xylen, detxy, zlen, det384z, bdet);                  // (1 +  768 + 1 +  384 + 1152 + 12) * 4 bytes

  temp48alen = fast_expansion_sum_zeroelim(eablen, eab, deblen, deb, temp48a);            // (1 +   24 + 1 +   24 +   48 + 12) * 4 bytes
  temp48blen = fast_expansion_sum_zeroelim(abdlen, abd, dealen, dea, temp48b);            // (1 +   24 + 1 +   24 +   48 + 12) * 4 bytes
  for (i = 0; i < temp48blen; i++) {
    temp48b[i] = -temp48b[i];
  }
  deablen = fast_expansion_sum_zeroelim(temp48alen, temp48a, temp48blen, temp48b, deab);
  xlen = scale_expansion_zeroelim(deablen, deab, pc[0], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  xlen = scale_expansion_zeroelim(xlen, temp192, pc[0], det384x);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(deablen, deab, pc[1], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(ylen, temp192, pc[1], det384y);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(deablen, deab, pc[2], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(zlen, temp192, pc[2], det384z);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  xylen = fast_expansion_sum_zeroelim(xlen, det384x, ylen, det384y, detxy);               // (1 +  384 + 1 +  384 +  768 + 12) * 4 bytes
  clen = fast_expansion_sum_zeroelim(xylen, detxy, zlen, det384z, cdet);                  // (1 +  768 + 1 +  384 + 1152 + 12) * 4 bytes

  temp48alen = fast_expansion_sum_zeroelim(abclen, abc, eaclen, eac, temp48a);            // (1 +   24 + 1 +   24 +   48 + 12) * 4 bytes
  temp48blen = fast_expansion_sum_zeroelim(bcelen, bce, eablen, eab, temp48b);            // (1 +   24 + 1 +   24 +   48 + 12) * 4 bytes
  for (i = 0; i < temp48blen; i++) {
    temp48b[i] = -temp48b[i];
  }
  eabclen = fast_expansion_sum_zeroelim(temp48alen, temp48a, temp48blen, temp48b, eabc);
  xlen = scale_expansion_zeroelim(eabclen, eabc, pd[0], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  xlen = scale_expansion_zeroelim(xlen, temp192, pd[0], det384x);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(eabclen, eabc, pd[1], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(ylen, temp192, pd[1], det384y);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(eabclen, eabc, pd[2], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(zlen, temp192, pd[2], det384z);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  xylen = fast_expansion_sum_zeroelim(xlen, det384x, ylen, det384y, detxy);               // (1 +  384 + 1 +  384 +  768 + 12) * 4 bytes
  dlen = fast_expansion_sum_zeroelim(xylen, detxy, zlen, det384z, ddet);                  // (1 +  768 + 1 +  384 + 1152 + 12) * 4 bytes

  temp48alen = fast_expansion_sum_zeroelim(bcdlen, bcd, abdlen, abd, temp48a);            // (1 +   24 + 1 +   24 +   48 + 12) * 4 bytes
  temp48blen = fast_expansion_sum_zeroelim(cdalen, cda, abclen, abc, temp48b);            // (1 +   24 + 1 +   24 +   48 + 12) * 4 bytes
  for (i = 0; i < temp48blen; i++) {
    temp48b[i] = -temp48b[i];
  }
  abcdlen = fast_expansion_sum_zeroelim(temp48alen, temp48a, temp48blen, temp48b, abcd);
  xlen = scale_expansion_zeroelim(abcdlen, abcd, pe[0], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  xlen = scale_expansion_zeroelim(xlen, temp192, pe[0], det384x);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(abcdlen, abcd, pe[1], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(ylen, temp192, pe[1], det384y);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(abcdlen, abcd, pe[2], temp192);                         // (1 +   96 + 1 +  192        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(zlen, temp192, pe[2], det384z);                         // (1 +  192 + 1 +  384        + 21) * 4 bytes
  xylen = fast_expansion_sum_zeroelim(xlen, det384x, ylen, det384y, detxy);               // (1 +  384 + 1 +  384 +  768 + 12) * 4 bytes
  elen = fast_expansion_sum_zeroelim(xylen, detxy, zlen, det384z, edet);                  // (1 +  768 + 1 +  384 + 1152 + 12) * 4 bytes

  ablen = fast_expansion_sum_zeroelim(alen, adet, blen, bdet, abdet);                     // (1 + 1152 + 1 + 1152 + 2304 + 12) * 4 bytes
  cdlen = fast_expansion_sum_zeroelim(clen, cdet, dlen, ddet, cddet);                     // (1 + 1152 + 1 + 1152 + 2304 + 12) * 4 bytes
  cdelen = fast_expansion_sum_zeroelim(cdlen, cddet, elen, edet, cdedet);                 // (1 + 2304 + 1 + 1152 + 3456 + 12) * 4 bytes
  deterlen = fast_expansion_sum_zeroelim(ablen, abdet, cdelen, cdedet, deter);            // (1 + 2304 + 1 + 3456 + 5760 + 12) * 4 bytes BIGGEST CALL

  return deter[deterlen - 1];
}

// ---- Functions for readability ----

Rvec3 pointOfIndex( uint n )
{
  return Rvec3(points[ 3 * n + 0 ], points[ 3 * n + 1 ], points[ 3 * n + 2 ]);
}

// ---- Main ----

void main(){
  // Get the indetermined face of this invocation.
  uint IndeterminedFaceInd = indetrmndFaces[ gl_WorkGroupID.x ];
  Reset_Indeterminant_Delaunay( flipInfo[ gl_WorkGroupID.x ] );

  // Get the active face
  uint IndexOfActiveFace = activeFace[ IndeterminedFaceInd ];

  // Get the tetrahedra
  uint tetA = faceToTetra[ 2*IndexOfActiveFace + 0 ]; // The tetra in which we are positively oriented.
  uint tetB = faceToTetra[ 2*IndexOfActiveFace + 1 ]; // The tetra in which we are negatively oriented.

  // Get the verticies of tetB
  uint BaInd = tetra[ 4 * tetB + 0 ];  Rvec3 Ba = pointOfIndex( BaInd );
  uint BbInd = tetra[ 4 * tetB + 1 ];  Rvec3 Bb = pointOfIndex( BbInd );
  uint BcInd = tetra[ 4 * tetB + 2 ];  Rvec3 Bc = pointOfIndex( BcInd );
  uint BdInd = tetra[ 4 * tetB + 3 ];  Rvec3 Bd = pointOfIndex( BdInd );

  // Get Afar (the vertex away from the face in A).
  uint AfarInA = 2 * (1 - int( IndexOfActiveFace == tetraToFace[ 4 * tetA + 0 ] ) ); //int( bool ) = 1 if true, 0 if false.
  uint AfarInd = tetra[ 4 * tetA + AfarInA ];  Rvec3 Afar = pointOfIndex( AfarInd );

  float insphere = sign( insphere_exact(Ba, Bb, Bc, Bd, Afar) );

  if( insphere < 0.0 ){
    // The active face fails the insphere test, and so we mark that it is _not_ locally Delaunay.
    Set_Is_Not_Delaunay( flipInfo[ gl_WorkGroupID.x ] );
  }

}