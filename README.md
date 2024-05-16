This was a personal project. My main goal was to learn principles of parralell programming. If anyone has a use for this, I can give it a permissive license.

## godotFlip

**WIP** 3D triangulation flipping algorithm approximating a delaunay triangulation. The algorithm is more or less gFlip3D as seen the in the [PhD Thesis of Ashwin Nanjappa](https://www.comp.nus.edu.sg/~tants/gdel3d_files/AshwinNanjappaThesis.pdf).
You can find a much better implementation [here](https://github.com/ashwin/gDel3D/tree/master).

This implementation was written from scratch, and enforces a certain orienation condition on the triangulation. This theoretically reduces performance by adding more stuck configurations.

The compute shaders employ Jonathan Shewchuck's robust geometric [predicates](https://www.cs.cmu.edu/~quake/robust.html), and so shouldn't be sensitive to floating point precision issues. IIRC it should work just fine on any modern graphics card.

FLipping is done with large lookup tables, to minimize divergence. The scratchwork for those is in the included blender file.

### Current Limitations / TODO

- It's not very good at it's job! The current seed gives a point set that gets stuck very quickly. It looks like a 4-4 flip would help a lot.

- I think there are likely errors in my table, and I need to make some tests to find them. A good place to start would be to ensure each tetrahedron is actually oriented correctly in space (not just abstractly).

- My solution for the initial triangulation is messy. Right now we can't handle adding points that don't lie inside a currently instantiated tetrahedron, so I'm simply making a very big one to get things started.

- The way I'm dealing with the data in the simplicial complex seems pretty memory ineffecient.

### Future work

It's currently unknown whether you can find the Delaunay triangulation of the convex hull of any 3D point set via flipping. In the future I would like to use this repo to test different strategies to get to the Delaunay configuration by flipping,
and so I need to better abstract the flipping operations.

I have some idea of where to go after that, but the holdup is that I need to do some pretty tedious math.

### Orientation info
Tetrahedra are given a standard orientation as an ordered quadruple (Negative by Jonathan Shewchuck's predicates).

Drawing from algebraic topology, we require the boundary map descends this orientation (order-wise) to a consistent orientation of the faces. By the boudary map, I mean the standard one in simplicial homology (ignoring signs):
tetrahedra are each associated to a ordered quadrouple of 4 face, which are the faces you obtain by ignoring the kth vertex of the tetrahedron. You can equivalently think of it as a glueing condition: there are four spots to glue,
and you can only glue faces together if their normals are aligned.

My motivation for the condition is that is simplifies the casework involved with probing adjacent tetra in the complex. It also doesn't introduce too many new ways to get stuck: any 2-3 flip is possible,
and only 4 out of 28 configurations of 3-2 flips don't work. Further, it's easy to show that any triangulation has such a configuration,[^1] so you might expect that it won't be an impediment to obtaining a delaunay triangulation.

[^1]: Suppose we have a manifold triangulization of a point-set in $$\mathbb{R}^3$$. Note that the boundary faces form a triangulation of an orientable manifold. Consider the dual graph of this triangulation, with one vertex correponding to
the exterior region. Every vertex of this graph has an even number of connected edges, so there is a cycle passing through every vertex, and covering each edge once. The orientation of the edges decend to an orientation of the triangulation
with our desired properties.
