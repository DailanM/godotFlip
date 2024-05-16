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

layout(set = 0, binding = 0, std430) restrict coherent buffer ufActiveFace       {uint activeFace[];     };
layout(set = 0, binding = 1, std430) restrict coherent buffer ufPoints           {REALTYPE points[];     };
layout(set = 0, binding = 2, std430) restrict coherent buffer ufTetra            {uint tetra[];          };
layout(set = 0, binding = 3, std430) restrict coherent buffer ufFaceToTetra      {uint faceToTetra[];    };
layout(set = 0, binding = 4, std430) restrict coherent buffer ufTetraToFace      {uint tetraToFace[];    };
layout(set = 0, binding = 5, std430) restrict coherent buffer ufFlipInfo         {uint flipInfo[];       };
layout(set = 0, binding = 6, std430) restrict coherent buffer ufIndetrmndFaces   {uint indetrmndFaces[]; };
layout(set = 0, binding = 7, std430) restrict coherent buffer ufPredConsts       {REALTYPE predConsts[]; };

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

/*

#define Fast_Two_Diff_Tail(a, b, x, y) \
  bvirt = a - x; \
  y = bvirt - b

#define Fast_Two_Diff(a, b, x, y) \
  x = REALCAST(a - b); \
  Fast_Two_Diff_Tail(a, b, x, y)

*/

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

/*

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

*/

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

/*

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

/*

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

*/

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

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[4], int flen, REALTYPE f[4], REALTYPE h[8])  // h cannot be e or f.
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[4], int flen, REALTYPE f[8], REALTYPE h[16])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[8], int flen, REALTYPE f[4], REALTYPE h[12])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[8], int flen, REALTYPE f[8], REALTYPE h[16])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[8], int flen, REALTYPE f[16], REALTYPE h[24])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[16], int flen, REALTYPE f[8], REALTYPE h[192])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[24], int flen, REALTYPE f[24], REALTYPE h[48])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[48], int flen, REALTYPE f[48], REALTYPE h[96])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[96], int flen, REALTYPE f[96], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[4], REALTYPE h[192])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[12], REALTYPE h[192])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[16], REALTYPE h[192])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[96], REALTYPE h[288])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[288], int flen, REALTYPE f[288], REALTYPE h[576])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[384], int flen, REALTYPE f[384], REALTYPE h[768])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[576], int flen, REALTYPE f[576], REALTYPE h[1152])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[768], int flen, REALTYPE f[384], REALTYPE h[1152])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[1152], int flen, REALTYPE f[1152], REALTYPE h[2304])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[2304], int flen, REALTYPE f[1152], REALTYPE h[3456])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

//int fast_expansion_sum_zeroelim(int elen, REALTYPE e[2304], int flen, REALTYPE f[3456], REALTYPE h[5760])
//{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

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

//int scale_expansion_zeroelim(int elen, REALTYPE e[4], REALTYPE b, REALTYPE h[12])
//{ SCALE_EXP_ZEROELIM_FC_INT }

//int scale_expansion_zeroelim(int elen, REALTYPE e[8], REALTYPE b, REALTYPE h[16])
//{ SCALE_EXP_ZEROELIM_FC_INT }

//int scale_expansion_zeroelim(int elen, REALTYPE e[12], REALTYPE b, REALTYPE h[24])
//{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[24], REALTYPE b, REALTYPE h[48])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[48], REALTYPE b, REALTYPE h[96])
{ SCALE_EXP_ZEROELIM_FC_INT }

//int scale_expansion_zeroelim(int elen, REALTYPE e[96], REALTYPE b, REALTYPE h[192])
//{ SCALE_EXP_ZEROELIM_FC_INT }

//int scale_expansion_zeroelim(int elen, REALTYPE e[192], REALTYPE b, REALTYPE h[384])
//{ SCALE_EXP_ZEROELIM_FC_INT }

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

// This function has 6522 * 4 bytes of variables, including the worst function call.

REALTYPE insphere_adapt( Rvec3 pa, Rvec3 pb, Rvec3 pc, Rvec3 pd, Rvec3 pe )     // ( 5 *   3 * 4 byte)
{
  INEXACT REALTYPE aex, bex, cex, dex, aey, bey, cey, dey, aez, bez, cez, dez;  // (      12 * 4 byte)
  REALTYPE alift, blift, clift, dlift;                                          // (       4 * 4 byte)
  REALTYPE aezplus, bezplus, cezplus, dezplus;                                  // (       4 * 4 byte)
  REALTYPE aexbeyplus, bexaeyplus, bexceyplus, cexbeyplus;                      // (       4 * 4 byte)
  REALTYPE cexdeyplus, dexceyplus, dexaeyplus, aexdeyplus;                      // (       4 * 4 byte)
  REALTYPE aexceyplus, cexaeyplus, bexdeyplus, dexbeyplus;                      // (       4 * 4 byte)
  REALTYPE det, permanent, errbound;                                            // (       3 * 4 byte)

  INEXACT REALTYPE aexbey1, bexaey1, bexcey1, cexbey1;                          // (       4 * 4 byte)
  INEXACT REALTYPE cexdey1, dexcey1, dexaey1, aexdey1;                          // (       4 * 4 byte)
  INEXACT REALTYPE aexcey1, cexaey1, bexdey1, dexbey1;                          // (       4 * 4 byte)
  REALTYPE aexbey0, bexaey0, bexcey0, cexbey0;                                  // (       4 * 4 byte)
  REALTYPE cexdey0, dexcey0, dexaey0, aexdey0;                                  // (       4 * 4 byte)
  REALTYPE aexcey0, cexaey0, bexdey0, dexbey0;                                  // (       4 * 4 byte)
  REALTYPE ab[4], bc[4], cd[4], da[4], ac[4], bd[4];                            // ( 6 *   4 * 4 byte)
  INEXACT REALTYPE ab3, bc3, cd3, da3, ac3, bd3;                                // (       6 * 4 byte)
  REALTYPE abeps, bceps, cdeps, daeps, aceps, bdeps;                            // (       6 * 4 byte)
  REALTYPE temp8a[8], temp8b[8], temp8c[8], temp16[16], temp24[24], temp48[48]; // ( (3 * 8 + 16 + 24 + 48) * 4 byte)
  int temp8alen, temp8blen, temp8clen, temp16len, temp24len, temp48len;         // (       6 * 4 byte)
  REALTYPE xdet[96], ydet[96], zdet[96], xydet[192];                            // ( (3 * 96 + 192) * 4 byte)
  int xlen, ylen, zlen, xylen;                                                  // (       4 * 4 byte)
  REALTYPE adet[288], bdet[288], cdet[288], ddet[288];                          // ( 4 * 288 * 4 byte)
  int alen, blen, clen, dlen;                                                   // (       4 * 4 byte)
  REALTYPE abdet[576], cddet[576];                                              // ( 2 * 576 * 4 byte)
  int ablen, cdlen;                                                             // (       2 * 4 byte)
  REALTYPE fin1[1152];                                                          // (    1152 * 4 byte)
  int finlength;                                                                // (       1 * 4 byte)

  REALTYPE aextail, bextail, cextail, dextail;                                  // (       4 * 4 byte)
  REALTYPE aeytail, beytail, ceytail, deytail;                                  // (       4 * 4 byte)
  REALTYPE aeztail, beztail, ceztail, deztail;                                  // (       4 * 4 byte)

  INEXACT REALTYPE bvirt;                                                       // (       1 * 4 byte)
  REALTYPE avirt, bround, around;                                               // (       3 * 4 byte)
  INEXACT REALTYPE c;                                                           // (       1 * 4 byte)
  INEXACT REALTYPE abig;                                                        // (       1 * 4 byte)
  REALTYPE ahi, alo, bhi, blo;                                                  // (       4 * 4 byte)
  REALTYPE err1, err2, err3;                                                    // (       3 * 4 byte)
  INEXACT REALTYPE _i, _j;                                                      // (       2 * 4 byte)
  REALTYPE _0;                                                                  // (       2 * 4 byte)

  //                                                                            // Total: 4204 * 4 bytes
  // Fast insphere part

  aex = REALCAST(pa[0] - pe[0]);
  bex = REALCAST(pb[0] - pe[0]);
  cex = REALCAST(pc[0] - pe[0]);
  dex = REALCAST(pd[0] - pe[0]);
  aey = REALCAST(pa[1] - pe[1]);
  bey = REALCAST(pb[1] - pe[1]);
  cey = REALCAST(pc[1] - pe[1]);
  dey = REALCAST(pd[1] - pe[1]);
  aez = REALCAST(pa[2] - pe[2]);
  bez = REALCAST(pb[2] - pe[2]);
  cez = REALCAST(pc[2] - pe[2]);
  dez = REALCAST(pd[2] - pe[2]);

  aexbey1 = aex * bey;
  bexaey1 = bex * aey;
  bexcey1 = bex * cey;
  cexbey1 = cex * bey;
  cexdey1 = cex * dey;
  dexcey1 = dex * cey;
  dexaey1 = dex * aey;
  aexdey1 = aex * dey;
  aexcey1 = aex * cey;
  cexaey1 = cex * aey;
  bexdey1 = bex * dey;
  dexbey1 = dex * bey;

  alift = aex * aex + aey * aey + aez * aez;
  blift = bex * bex + bey * bey + bez * bez;
  clift = cex * cex + cey * cey + cez * cez;
  dlift = dex * dex + dey * dey + dez * dez;

  aezplus = Absolute(aez);
  bezplus = Absolute(bez);
  cezplus = Absolute(cez);
  dezplus = Absolute(dez);
  aexbeyplus = Absolute(aexbey1);
  bexaeyplus = Absolute(bexaey1);
  bexceyplus = Absolute(bexcey1);
  cexbeyplus = Absolute(cexbey1);
  cexdeyplus = Absolute(cexdey1);
  dexceyplus = Absolute(dexcey1);
  dexaeyplus = Absolute(dexaey1);
  aexdeyplus = Absolute(aexdey1);
  aexceyplus = Absolute(aexcey1);
  cexaeyplus = Absolute(cexaey1);
  bexdeyplus = Absolute(bexdey1);
  dexbeyplus = Absolute(dexbey1);

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

  // adapt insphere part

  // The Two_Product calls below overwrites aexbey1 ... dexbey1.
  Two_Product(aex, bey, aexbey1, aexbey0);
  Two_Product(bex, aey, bexaey1, bexaey0);
  Two_Two_Diff(aexbey1, aexbey0, bexaey1, bexaey0, ab3, ab[2], ab[1], ab[0]);
  ab[3] = ab3;

  Two_Product(bex, cey, bexcey1, bexcey0);
  Two_Product(cex, bey, cexbey1, cexbey0);
  Two_Two_Diff(bexcey1, bexcey0, cexbey1, cexbey0, bc3, bc[2], bc[1], bc[0]);
  bc[3] = bc3;

  Two_Product(cex, dey, cexdey1, cexdey0);
  Two_Product(dex, cey, dexcey1, dexcey0);
  Two_Two_Diff(cexdey1, cexdey0, dexcey1, dexcey0, cd3, cd[2], cd[1], cd[0]);
  cd[3] = cd3;

  Two_Product(dex, aey, dexaey1, dexaey0);
  Two_Product(aex, dey, aexdey1, aexdey0);
  Two_Two_Diff(dexaey1, dexaey0, aexdey1, aexdey0, da3, da[2], da[1], da[0]);
  da[3] = da3;

  Two_Product(aex, cey, aexcey1, aexcey0);
  Two_Product(cex, aey, cexaey1, cexaey0);
  Two_Two_Diff(aexcey1, aexcey0, cexaey1, cexaey0, ac3, ac[2], ac[1], ac[0]);
  ac[3] = ac3;

  Two_Product(bex, dey, bexdey1, bexdey0);
  Two_Product(dex, bey, dexbey1, dexbey0);
  Two_Two_Diff(bexdey1, bexdey0, dexbey1, dexbey0, bd3, bd[2], bd[1], bd[0]);
  bd[3] = bd3;

  temp8alen = scale_expansion_zeroelim(4, cd, bez, temp8a);                               // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, bd, -cez, temp8b);                              // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp8clen = scale_expansion_zeroelim(4, bc, dez, temp8c);                               // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +   8 + 1 +  8 +   16 + 12) * 4 bytes
  temp24len = fast_expansion_sum_zeroelim(temp8clen, temp8c, temp16len, temp16, temp24);  // (1 +   8 + 1 + 16 +   24 + 12) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, aex, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  xlen = scale_expansion_zeroelim(temp48len, temp48, -aex, xdet);                         // (1 +  48 + 1 + 96        + 21) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, aey, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(temp48len, temp48, -aey, ydet);                         // (1 +  48 + 1 + 96        + 21) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, aez, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(temp48len, temp48, -aez, zdet);                         // (1 +  48 + 1 + 96        + 21) * 4 bytes
  xylen = fast_expansion_sum_zeroelim(xlen, xdet, ylen, ydet, xydet);                     // (1 +  96 + 1 + 96 +  192 + 12) * 4 bytes
  alen = fast_expansion_sum_zeroelim(xylen, xydet, zlen, zdet, adet);                     // (1 + 192 + 1 + 96 +  288 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, da, cez, temp8a);                               // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, ac, dez, temp8b);                               // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp8clen = scale_expansion_zeroelim(4, cd, aez, temp8c);                               // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +   8 + 1 +  8 +   16 + 12) * 4 bytes
  temp24len = fast_expansion_sum_zeroelim(temp8clen, temp8c, temp16len, temp16, temp24);  // (1 +   8 + 1 + 16 +   24 + 12) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, bex, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  xlen = scale_expansion_zeroelim(temp48len, temp48, bex, xdet);                          // (1 +  48 + 1 + 96        + 21) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, bey, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(temp48len, temp48, bey, ydet);                          // (1 +  48 + 1 + 96        + 21) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, bez, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(temp48len, temp48, bez, zdet);                          // (1 +  48 + 1 + 96        + 21) * 4 bytes
  xylen = fast_expansion_sum_zeroelim(xlen, xdet, ylen, ydet, xydet);                     // (1 +  96 + 1 + 96 +  192 + 12) * 4 bytes
  blen = fast_expansion_sum_zeroelim(xylen, xydet, zlen, zdet, bdet);                     // (1 + 192 + 1 + 96 +  288 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, ab, dez, temp8a);                               // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, bd, aez, temp8b);                               // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp8clen = scale_expansion_zeroelim(4, da, bez, temp8c);                               // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +   8 + 1 +  8 +   16 + 12) * 4 bytes
  temp24len = fast_expansion_sum_zeroelim(temp8clen, temp8c, temp16len, temp16, temp24);  // (1 +   8 + 1 + 16 +   24 + 12) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, cex, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  xlen = scale_expansion_zeroelim(temp48len, temp48, -cex, xdet);                         // (1 +  48 + 1 + 96        + 21) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, cey, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(temp48len, temp48, -cey, ydet);                         // (1 +  48 + 1 + 96        + 21) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, cez, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(temp48len, temp48, -cez, zdet);                         // (1 +  48 + 1 + 96        + 21) * 4 bytes
  xylen = fast_expansion_sum_zeroelim(xlen, xdet, ylen, ydet, xydet);                     // (1 +  96 + 1 + 96 +  192 + 12) * 4 bytes
  clen = fast_expansion_sum_zeroelim(xylen, xydet, zlen, zdet, cdet);                     // (1 + 192 + 1 + 96 +  288 + 12) * 4 bytes

  temp8alen = scale_expansion_zeroelim(4, bc, aez, temp8a);                               // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp8blen = scale_expansion_zeroelim(4, ac, -bez, temp8b);                              // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp8clen = scale_expansion_zeroelim(4, ab, cez, temp8c);                               // (1 +   4 + 1 +  8        + 21) * 4 bytes
  temp16len = fast_expansion_sum_zeroelim(temp8alen, temp8a, temp8blen, temp8b, temp16);  // (1 +   8 + 1 +  8 +   16 + 12) * 4 bytes
  temp24len = fast_expansion_sum_zeroelim(temp8clen, temp8c, temp16len, temp16, temp24);  // (1 +   8 + 1 + 16 +   24 + 12) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, dex, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  xlen = scale_expansion_zeroelim(temp48len, temp48, dex, xdet);                          // (1 +  48 + 1 + 96        + 21) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, dey, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  ylen = scale_expansion_zeroelim(temp48len, temp48, dey, ydet);                          // (1 +  48 + 1 + 96        + 21) * 4 bytes
  temp48len = scale_expansion_zeroelim(temp24len, temp24, dez, temp48);                   // (1 +  24 + 1 + 48        + 21) * 4 bytes
  zlen = scale_expansion_zeroelim(temp48len, temp48, dez, zdet);                          // (1 +  48 + 1 + 96        + 21) * 4 bytes
  xylen = fast_expansion_sum_zeroelim(xlen, xdet, ylen, ydet, xydet);                     // (1 +  96 + 1 + 96 +  192 + 12) * 4 bytes
  dlen = fast_expansion_sum_zeroelim(xylen, xydet, zlen, zdet, ddet);                     // (1 + 192 + 1 + 96 +  288 + 12) * 4 bytes

  ablen = fast_expansion_sum_zeroelim(alen, adet, blen, bdet, abdet);                     // (1 + 288 + 1 + 288 +  576 + 12) * 4 bytes
  cdlen = fast_expansion_sum_zeroelim(clen, cdet, dlen, ddet, cddet);                     // (1 + 288 + 1 + 288 +  576 + 12) * 4 bytes
  finlength = fast_expansion_sum_zeroelim(ablen, abdet, cdlen, cddet, fin1);              // (1 + 576 + 1 + 576 + 1152 + 12) * 4 bytes    BIGGEST CALL

  det = estimate(finlength, fin1);                                                        // (1 + 1152 + 2) * 4 bytes
  errbound = predConsts[13] * permanent;
  if ((det >= errbound) || (-det >= errbound)) {
    // No longer indeterminant:
    Reset_Indeterminant_Delaunay( flipInfo[ indetrmndFaces[ gl_WorkGroupID.x ] ] );

    return det;
  }

  Two_Diff_Tail(pa[0], pe[0], aex, aextail);
  Two_Diff_Tail(pa[1], pe[1], aey, aeytail);
  Two_Diff_Tail(pa[2], pe[2], aez, aeztail);
  Two_Diff_Tail(pb[0], pe[0], bex, bextail);
  Two_Diff_Tail(pb[1], pe[1], bey, beytail);
  Two_Diff_Tail(pb[2], pe[2], bez, beztail);
  Two_Diff_Tail(pc[0], pe[0], cex, cextail);
  Two_Diff_Tail(pc[1], pe[1], cey, ceytail);
  Two_Diff_Tail(pc[2], pe[2], cez, ceztail);
  Two_Diff_Tail(pd[0], pe[0], dex, dextail);
  Two_Diff_Tail(pd[1], pe[1], dey, deytail);
  Two_Diff_Tail(pd[2], pe[2], dez, deztail);
  if ((aextail == 0.0) && (aeytail == 0.0) && (aeztail == 0.0)
      && (bextail == 0.0) && (beytail == 0.0) && (beztail == 0.0)
      && (cextail == 0.0) && (ceytail == 0.0) && (ceztail == 0.0)
      && (dextail == 0.0) && (deytail == 0.0) && (deztail == 0.0)) {
    // No longer indeterminant:
    Reset_Indeterminant_Delaunay( flipInfo[ indetrmndFaces[ gl_WorkGroupID.x ] ] );

    return det;
  }

  errbound = predConsts[14] * permanent + predConsts[2] * Absolute(det);
  abeps = (aex * beytail + bey * aextail)
        - (aey * bextail + bex * aeytail);
  bceps = (bex * ceytail + cey * bextail)
        - (bey * cextail + cex * beytail);
  cdeps = (cex * deytail + dey * cextail)
        - (cey * dextail + dex * ceytail);
  daeps = (dex * aeytail + aey * dextail)
        - (dey * aextail + aex * deytail);
  aceps = (aex * ceytail + cey * aextail)
        - (aey * cextail + cex * aeytail);
  bdeps = (bex * deytail + dey * bextail)
        - (bey * dextail + dex * beytail);
  det += (((bex * bex + bey * bey + bez * bez)
           * ((cez * daeps + dez * aceps + aez * cdeps)
              + (ceztail * da3 + deztail * ac3 + aeztail * cd3))
           + (dex * dex + dey * dey + dez * dez)
           * ((aez * bceps - bez * aceps + cez * abeps)
              + (aeztail * bc3 - beztail * ac3 + ceztail * ab3)))
          - ((aex * aex + aey * aey + aez * aez)
           * ((bez * cdeps - cez * bdeps + dez * bceps)
              + (beztail * cd3 - ceztail * bd3 + deztail * bc3))
           + (cex * cex + cey * cey + cez * cez)
           * ((dez * abeps + aez * bdeps + bez * daeps)
              + (deztail * ab3 + aeztail * bd3 + beztail * da3))))
       + 2.0 * (((bex * bextail + bey * beytail + bez * beztail)
                 * (cez * da3 + dez * ac3 + aez * cd3)
                 + (dex * dextail + dey * deytail + dez * deztail)
                 * (aez * bc3 - bez * ac3 + cez * ab3))
                - ((aex * aextail + aey * aeytail + aez * aeztail)
                 * (bez * cd3 - cez * bd3 + dez * bc3)
                 + (cex * cextail + cey * ceytail + cez * ceztail)
                 * (dez * ab3 + aez * bd3 + bez * da3)));
  if ((det >= errbound) || (-det >= errbound)) {
    return det;
  }

  return 0.0; // STILL bad.
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

  float insphere = sign( insphere_adapt(Ba, Bb, Bc, Bd, Afar) );

  if( insphere == 0.0 ){
  }
  else if( insphere < 0.0 ){
    Set_Is_Not_Delaunay( flipInfo[ gl_WorkGroupID.x ] );
    Reset_Indeterminant_Delaunay( flipInfo[ indetrmndFaces[ gl_WorkGroupID.x ] ] );
  }
  else{
    Reset_Indeterminant_Delaunay( flipInfo[ indetrmndFaces[ gl_WorkGroupID.x ] ] );
  }

}
