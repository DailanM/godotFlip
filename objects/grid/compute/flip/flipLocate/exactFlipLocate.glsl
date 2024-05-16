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
#define INEXACT                          /* Nothing */
/* #define INEXACT volatile */

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding =  0, std430) buffer coherent readonly ufPoints          { REALTYPE point[];       };
layout(set = 0, binding =  1, std430) buffer coherent readonly ufPointsToAdd     { uint pointsToAdd[];     };
layout(set = 0, binding =  2, std430) restrict coherent buffer ufTetOfPoints     { uint tetOfPoints[];     };
layout(set = 0, binding =  3, std430) restrict coherent buffer ufBadPoints       { uint badPoints[];     };

layout(set = 0, binding =  4, std430)                   buffer ufPointsInFlip    { uint pointsInFlip[];    };
layout(set = 0, binding =  5, std430) restrict coherent buffer ufTetraMarkedFlip { uint tetraMarkedFlip[]; };
layout(set = 0, binding =  6, std430)                   buffer ufLocations       { uint locations[];       };

layout(set = 0, binding =  7, std430)                   buffer ufTetra           { uint tetra[];           };
layout(set = 0, binding =  8, std430)                   buffer ufFaceToTetra     { uint faceToTetra[];     };

layout(set = 0, binding =  9, std430)                   buffer ufActiveFaces     { uint activeFaces[];     };
layout(set = 0, binding = 10, std430)                   buffer ufFlipInfo        { uint flipInfo[];        };
layout(set = 0, binding = 11, std430)                   buffer ufBadFaces        { uint badFaces[];        };
layout(set = 0, binding = 12, std430)                   buffer ufFlipPrefixSum   { uint flipPrefixSum[];   };

layout(set = 0, binding = 13, std430)                   buffer ufThreeTwoAtFlip  { uint threeTwoAtFlip[];  };

layout(set = 0, binding = 14, std430)                   buffer ufFreedTetra      { uint freedTetra[];      };

layout(set = 0, binding = 15, std430)                   buffer bfPredConsts      { REALTYPE predConsts[];  };
layout(set = 0, binding = 16, std430)                   buffer ufFlipOffsets
{   uint lastTetra; // Not Updated yet for the simplices to be added this flip!
    uint lastFace;
    uint lastEdge;
    uint numFreedTetra;
    uint numFreedFaces;
    uint numFreedEdges;
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

// Lookup
uint _twistB[] = {  0, 2, 3,    // Never has an offset.        (when bfar is b), it's {0, 2, 3}
                    2, 0, 1 };  //                             (when bfar is d), it's {2, 0, 1}

uint _TwoThreeWriteOut[] = {                                                                    // + 55 * faceTwist // indexes writeIn (TODO: remove common assignments between faceTwist)
// ---------------------------------------------------------------------------------------------------------------- //
//       tetU:  0   1   2   3          tetV:  4   5   6   7          tetW:  8   9  10  11               // + 55 * 0 //
               17, 21, 18, 20,               17, 21, 19, 18,               19, 18, 20, 17,                          //
// tetToFaceU: 12  13  14  15    tetToFaceV: 16  17  18  19    tetToFaceW: 20  21  22  23                           //
                5, 23,  2, 24,                6, 22, 24,  3,               23,  4, 22,  7,                          //
// tetToEdgeU: 24  25  26  27  28  29  tetToEdgeV: 30  31  32  33  34  35  tetToEdgeW: 36  37  38  39  40  41       //
               16, 25, 15, 13,  8, 12,             16, 14, 25,  9, 13, 11,             11, 10, 14, 12, 25, 15,      //
// faceV: 42  43  44  faceW: 45  46  47  faceToTetraV: 48  49  faceToTetraW: 50  51  AOldFaceOffsets: 52  53  54    //
          20, 17, 18,        21, 18, 17,                0, 26,                1,  0,                   0,  1,  1,   //
// ---------------------------------------------------------------------------------------------------------------- //
//       tetU:  0   1   2   3          tetV:  4   5   6   7          tetW:  8   9  10  11               // + 55 * 1 //
               17, 20, 21, 18,               17, 21, 19, 18,               18, 17, 20, 19,                          //
// tetToFaceU: 12  13  14  15    tetToFaceV: 16  17  18  19    tetToFaceW: 20  21  22  23                           //
                5, 24, 23,  2,                6, 22, 24,  3,                4,  7, 22, 23,                          //
// tetToEdgeU: 24  25  26  27  28  29  tetToEdgeV: 30  31  32  33  34  35  tetToEdgeW: 36  37  38  39  40  41       //
               15, 16, 25,  8, 12, 13,             16, 14, 25,  9, 13, 11,             25, 12, 11, 15, 14, 10,      //
// faceV: 42  43  44  faceW: 45  46  47  faceToTetraV: 48  49  faceToTetraW: 50  51  AOldFaceOffsets: 52  53  54    //
          20, 18, 17,        21, 18, 17,               26,  0,               1,   0,                   1,  1,  0,   //
// ---------------------------------------------------------------------------------------------------------------- //
//       tetU:  0   1   2   3          tetV:  4   5   6   7          tetW:  8   9  10  11               // + 55 * 2 //
               17, 18, 20, 21,               17, 19, 18, 21,               18, 17, 20, 19,                          //
// tetToFaceU: 12  13  14  15    tetToFaceV: 16  17  18  19    tetToFaceW: 20  21  22  23                           //
                5,  2, 24, 23,                6, 24,  3, 22,               23,  4, 22,  7,                          //
// tetToEdgeU: 24  25  26  27  28  29  tetToEdgeV: 30  31  32  33  34  35  tetToEdgeW: 36  37  38  39  40  41       //
               25, 15, 16, 12, 13,  8,             14, 25, 16, 11,  9, 13,             11, 10, 14, 12, 25, 15,      //
// faceV: 42  43  44  faceW: 45  46  47  faceToTetraV: 48  49  faceToTetraW: 50  51  AOldFaceOffsets: 52  53  54    //
          20, 17, 18,        21, 17, 18,                0, 26,                0,  1,                   1,  0,  1    //
// ---------------------------------------------------------------------------------------------------------------- //
};

uint _ThreeTwoAdapt[] = {                        // num - [threeTwoOver][faceTwist][isQ][isS] // indexes writeIn
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                // 0,
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        // 1, 2, 3, 4, 5,
           20,   21,   19,   18,   17,                                                        //
//     faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                                        // 6, 7, 8, 9, 10, 11
           22,      4,      7,     23,      3,      6,                                        //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                // 12, 13, 14, 15, 16, 17, 18, 19, 20
           11,     24,     14,     10,      12,    15,      9,     13,     16,  //  0 - 0000  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        // + 21 * threeConfig
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  //  1 - 0001  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   21,   19,   18,   17,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
           22,        4,        7,       23,        3,        6,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           11,     24,     14,     10,     12,     15,      9,     13,     16,  //  2 - 0010  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  //  3 - 0011  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   21,   19,   18,   17,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
           22,        4,        7,       23,        3,        6,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           11,     24,     14,     10,      4,     15,      9,     13,     16,  //  4 - 0100  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           21,   20,   19,   17,   18,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
           22,        6,        3,       23,        7,        4,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           14,     24,     11,      9,     16,     13,     10,     15,     12,  //  5 - 0101  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           21,   20,   19,   17,   18,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
           22,        6,        3,       23,        7,        4,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           14,     24,     11,      9,     16,     13,     10,     15,     12,  //  6 - 0110  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   21,   19,   18,   17,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
           22,        4,        7,       23,        3,        6,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           11,     24,     14,     10,     12,     15,      9,     13,     16,  //  7 - 0111  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  //  8 - 0200  // bad
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   21,   17,   19,   18,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            7,       22,        4,        6,       23,        3,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           14,     11,     24,     15,     10,     12,     16,      9,     13,  //  9 - 0201  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   21,   17,   19,   18,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
           13,       22,        4,        6,       23,        3,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           14,     11,     24,     15,     10,     12,     16,      9,     13,  // 10 - 0210  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 11 - 0211  // bad
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   18,   20,   17,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            4,       22,        7,        2,       23,        5,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           12,     15,     24,     11,     10,     14,     13,      8,     16,  // 12 - 1000  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 13 - 1001  // bad
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 14 - 1010  // bad
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   18,   20,   17,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            4,       22,        7,        2,       23,        5,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           12,     15,     24,     11,     10,     14,     13,      8,     16,  // 15 - 1011  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           21,   19,   18,   17,   20,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            2,        5,       22,        4,        7,       23,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     15,     12,     13,     16,      8,     11,     14,     10,  // 16 - 1100  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   17,   18,   20,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            7,        4,       22,        5,        2,       23,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     12,     15,     14,     11,     10,     16,     13,      8,  // 17 - 1101  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   17,   18,   20,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            7,        4,       22,        5,        2,       23,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     12,     15,     14,     11,     10,     16,     13,      8,  // 18 - 1110  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           21,   19,   18,   17,   20,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            2,        5,       22,        4,        7,       23,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     15,     12,     13,     16,      8,     11,     14,     10,  // 19 - 1111  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   17,   18,   20,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            7,        4,       22,        5,        2,       23,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     12,     15,     14,     11,     10,     16,     13,      8,  // 20 - 1200  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 21 - 1201  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   17,   18,   20,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            7,        4,       22,        5,        2,       23,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     12,     15,     14,     11,     10,     16,     13,      8,  // 22 - 1210  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 23 - 1211  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   20,   17,   21,   18,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            6,       22,        3,        5,       23,        2,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           16,     13,     24,     14,      9,     11,     15,      8,     12,  // 24 - 2000  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 25 - 2001  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   20,   17,   21,   18,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            6,       22,        3,        5,       23,        2,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           16,     13,     24,     14,      9,     11,     15,      8,     12,  // 26 - 2010  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 27 - 2011  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   19,   17,   18,   21,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            5,        2,       22,        6,        3,       23,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     13,     16,     15,     12,      8,     14,     11,     23,  // 28 - 2100  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   20,   21,   18,   17,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
           22,        3,        6,       23,        2,        5,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           13,     24,     16,      9,     11,     14,      8,     12,     15,  // 29 - 2101  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   20,   21,   18,   17,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
           22,        3,        6,       23,        2,        5,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           13,     24,     16,      9,     11,     14,      8,     12,     15,  // 30 - 2110  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   19,   17,   18,   21,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
           11,        2,       22,        6,        3,       23,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     13,     16,     15,     12,      8,     14,     11,      9,  // 31 - 2111  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   19,   18,   21,   17,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            2,       22,        5,        3,       23,        6,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           13,     16,     24,     12,      8,     15,     11,      9,     14,  // 32 - 2200  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 33 - 2201  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   19,   18,   21,   17,                                                        //
//   faceXV, faceYV, faceZV, faceXU, faceYU, faceZU,                              //
            2,       22,        5,        3,       23,        6,                              //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           13,     16,     24,     12,      8,     15,     11,      9,     14,  // 34 - 2210  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0   // 35 - 2211  // unused
// ------------------------------------------------------------------------------------------ //
};

#define pointOfInd( Ind ) Rvec3(point[ 3 * Ind + 0 ], point[ 3 * Ind + 1 ], point[ 3 * Ind + 2 ] )

void main() {
    uint id = gl_WorkGroupID.x;

    uint indeterminantId = badPoints[id];

    uint pointInFlip = pointsInFlip[ indeterminantId ];
    uint tetOfPoint  = tetOfPoints[  pointInFlip ];
    uint badFaceOfFlip = tetraMarkedFlip[ tetOfPoint ] - 1;
    uint flipID = flipPrefixSum[ badFaceOfFlip ] - 1;

    uint flippingFaceInActiveFace = badFaces[ badFaceOfFlip ];
    uint flippingFace = activeFaces[ flippingFaceInActiveFace ];

    uint pointIndex  = pointsToAdd[ pointInFlip ];
    Rvec3 pTest = pointOfInd( pointIndex );

    // The non-convex faces became the faces to check, so the aggregate info now reads
    // ----------------------------------------------------------------------------------------------
    // | canFlip | isOfQ | isOfS | AfarIsa | BfarIsb | faceTwist | faceTwist | cantTwoThreeFlip | ...
    // ----------------------------------------------------------------------------------------------
    // ... | Face 2 can 3-2 over | Face 1 can 3-2 over | Face 0 can 3-2 over | Face 2 Indeterminant | ...
    // ----------------------------------------------------------------------------------------------
    //                                            ... | Face 1 Indeterminant | Face 0 Indeterminant |  Each space is a bit
    uint info = flipInfo[ badFaceOfFlip ];
    uint located = locations[ indeterminantId ] >> 1; // marks indeterminant faces if we don't locate a point.

    uint writeIn[27];

    uint threeTwoFlipsAtFlip = threeTwoAtFlip[ flipID ];
    
    uint tetA; uint tetB;

    uint AfarInd; uint BfarInd;
    uint uInd; uint vInd; uint wInd;

    uint AfarIsa; uint BfarIsb; uint faceTwist;

    uint twistFaceB[3]; // uint twistEdgeNearB[3]; uint twistEdgeFarB[3];
    // uint twistFaceA[3]; /* uint twistEdgeNearA[3]; */ uint twistEdgeFarA[3];

    // -------- Grab data --------
    AfarIsa   = ( info >> 10 ) & 1;
    BfarIsb   = ( info >>  9 ) & 1;
    faceTwist = ( info >>  7 ) & 3;

    // twistFaceA and twistFaceB are connected via the shared face between tetA and tetB.
    // It will help to think of the array as cyclic, which explains the all of the mod(X, 3) when applying offsets.
    twistFaceB[0] = _twistB[ 3 * (1 - BfarIsb) + 0 ];
    twistFaceB[1] = _twistB[ 3 * (1 - BfarIsb) + 1 ];
    twistFaceB[2] = _twistB[ 3 * (1 - BfarIsb) + 2 ];

    // -------- 2 Tetra --------
    tetA = faceToTetra[ 2*flippingFace + 0 ]; // The tetra in which we are positively oriented.
    tetB = faceToTetra[ 2*flippingFace + 1 ]; // The tetra in which we are negatively oriented.

    // -------- 5 Points --------
    AfarInd = tetra[ 4 * tetA + 0 + 2 * ( 1 - int(AfarIsa) ) ]; // spits out the a index of tetA if Afar Is a, spits out the c index of tetA if Afar is not a (since it must be c).
    BfarInd = tetra[ 4 * tetB + 1 + 2 * ( 1 - int(BfarIsb) ) ]; // spits out the b index of tetB if Bfar Is b, spits out the d index of tetB if Bfar is not b (since it must be d).

    uInd = tetra[ 4 * tetB + twistFaceB[0] ];
    vInd = tetra[ 4 * tetB + twistFaceB[1] ];
    wInd = tetra[ 4 * tetB + twistFaceB[2] ];

    writeIn = uint[](
    // Reserved for any Flip
    // tetU, tetV,                           //  0,  1
        0, 0,

        0, 0, 0, 0, 0, 0,
    //    faceAU, faceAV, faceAW,              //  2,  3,  4,
    //    faceBU, faceBV, faceBW,              //  5,  6,  7,
                                             //
        0, 0, 0, 0, 0, 0, 0, 0, 0,
    //    edgeNearU, edgeNearV, edgeNearW,     //  8,  9, 10,
    //    edgeFarBU, edgeFarBV, edgeFarBW,     // 11, 12, 13,
    //    edgeFarAU, edgeFarAV, edgeFarAW,     // 14, 15, 16,
                                             //
        AfarInd, BfarInd, uInd, vInd, wInd,                 // 17, 18, 19, 20, 21

    // Reserved for Two-Three Flips
    // faceU, faceV, faceW, edgeAB, tetw           // 22, 23, 24, 25, 26
        
    // Reserved for Three-Two Flips
    // faceUfarInC, faceVfarInC, edgeC // 22, 23, 24 rename faceCU faceCV

    0, 0, 0, 0, 0// 
    
    );


    bool isThreeTwo   = ( ((info >> 5 ) & 1) == 1 ) || ( ((info >> 4 ) & 1) == 1 ) || ( ((info >> 3 ) & 1) == 1 ); // only one of these evaluate to true.
    
    if( !isThreeTwo ){  // ------------------------ Is Two Three ------------------------ //

        uint tetU; uint tetV; uint tetW;

        uint TwoThreeID = flipID - threeTwoFlipsAtFlip; //represents the number of threeTwoFlips left at this flip

        tetU = tetA; tetV = tetB;
        if( 1 * TwoThreeID     < numFreedTetra ) { tetW   = freedTetra[ (numFreedTetra - 1) - (1 * TwoThreeID + 0) ] ; } // Pull freed simplices off the end
        else                                     { tetW   = (lastTetra + 1) + ( (1 * TwoThreeID + 0) - numFreedTetra); }

        // check orientation across each new face.

        REALTYPE orFaceU = REALCAST( ( mod( ( located >> 1) , pow( 3, 1 ) ) / pow( 3, 1 - 1 ) ) - 1 );
        REALTYPE orFaceV = REALCAST( ( mod( ( located >> 1) , pow( 3, 2 ) ) / pow( 3, 2 - 1 ) ) - 1 );
        REALTYPE orFaceW = REALCAST( ( mod( ( located >> 1) , pow( 3, 3 ) ) / pow( 3, 3 - 1 ) ) - 1 );

        if( orFaceU == 0 ){ orFaceU = orient3drobust( pointOfInd(uInd), pointOfInd(BfarInd), pointOfInd(AfarInd), pTest ); }
        if( orFaceV == 0 ){ orFaceV = orient3drobust( pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 42 ] ] ),
                                                      pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 43 ] ] ),
                                                      pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 44 ] ] ),
                                                      pTest ); }

        
        if(
            ( (faceTwist == 2) && ( orFaceU >= 0 ) && (orFaceV >= 0) ) ||
            ( (faceTwist == 1) && ( orFaceU >= 0 ) && (orFaceV <= 0) ) ||
            ( (faceTwist == 0) && ( orFaceU >= 0 ) && (orFaceV >= 0) )    )
        {
            // We lie in tetW!
            tetOfPoints[ pointInFlip ] = tetW;

        } else  {

            if( orFaceW == 0 ){ orFaceW = orient3drobust( pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 42 ] ] ),
                                                          pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 43 ] ] ),
                                                          pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 44 ] ] ),
                                                          pTest ); }

            if(
                ( (faceTwist == 2) && ( orFaceU <= 0 ) && (orFaceW <= 0) ) ||
                ( (faceTwist == 1) && ( orFaceU <= 0 ) && (orFaceW >= 0) ) ||
                ( (faceTwist == 0) && ( orFaceU <= 0 ) && (orFaceW >= 0) )    )
            {
                // We lie in tetV!
                tetOfPoints[ pointInFlip ] = tetV;

            } else if(
                ( (faceTwist == 2) && ( orFaceV <= 0 ) && (orFaceW >= 0) ) ||
                ( (faceTwist == 1) && ( orFaceV >= 0 ) && (orFaceW <= 0) ) ||
                ( (faceTwist == 0) && ( orFaceV <= 0 ) && (orFaceW <= 0) )    )
            {
                // We lie in tetU!
                tetOfPoints[ pointInFlip ] = tetU;

            }
        }

    } else {            // ------------------------ Is Three Two ------------------------ //

        uint tetU; uint tetV;
        tetU = tetA; tetV = tetB;

        uint ThreeTwoOver = ( ((info >> 5 ) & 1)  * 2 )  + ( ((info >> 4 ) & 1)  * 1 )  + ( ((info >> 3 ) & 1)  * 0 );
        uint isQ = ( info >> 12 ) & 1;
        uint isS = ( info >> 11 ) & 1;
        uint threeConfig = (ThreeTwoOver * 3 + faceTwist) * 4 + isQ * 2 + isS;

        uint xInd = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   3 ] ];
        uint yInd = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   4 ] ];
        uint zInd = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   5 ] ];

        // check orientation across xyz face

        REALTYPE orFaceUV = orient3drobust( pointOfInd(xInd), pointOfInd(yInd), pointOfInd(zInd), pTest );

        if( orFaceUV <= 0 ){
            tetOfPoints[ pointInFlip ] = tetU;
        } else {
            tetOfPoints[ pointInFlip ] = tetV;
        }
        
    }
}
