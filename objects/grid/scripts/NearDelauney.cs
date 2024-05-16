using Godot;
using Godot.NativeInterop;
using System;
using System.Diagnostics;
using System.IO;
using System.Numerics;
using System.Runtime.CompilerServices;
using System.Threading;

#pragma warning disable IDE0017
#pragma warning disable IDE0090
#pragma warning disable IDE0056
#pragma warning disable IDE1006
#pragma warning disable CA1050

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// 						Node Begin
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

public partial class NearDelauney : Node3D
{
	// --------------------------   Data   --------------------------
	// CPU SIDE
	float[] _points;
	uint[] _tetra; uint[] _tetraToFace; uint[] _tetraToEdge;
	uint[] _face;  uint[] _faceToTetra;
	uint[] _edge;
		
	// GPU SIDE
	Rid _bfPoints;
	Rid _bfTetra; Rid _bfTetraToFace; Rid _bfTetraToEdge;
	Rid _bfFace;  Rid _bfFaceToTetra;
	Rid _bfEdge;

	// Memory Management
	uint _numTetra; uint _numFaces; uint _numEdges;
	uint _lastTetra; uint _lastFace; uint _lastEdge;
	uint _bfTetraSize; uint _bfFaceSize; uint _bfEdgeSize;

	Rid _bfFreedTetra; Rid _bfFreedFaces; Rid _bfFreedEdges;
	uint _numFreedTetra; uint _numFreedFaces; uint _numFreedEdges;
	uint _bfFreedTetraSize; uint _bfFreedFacesSize; uint _bfFreedEdgesSize;
		
	// Predicate Constants
	Rid _bfPredConsts; bool _predConstsGenerated;


	Godot.FileAccess _debugFile;
	bool DEBUG = false;

	bool DEBUG_COMPLEX = true;
			

	/********************************************************************/
	/* Algorythmic variables											*/
	/* 		pointsToAdd	: points not in the simplicial complex			*/
	/* 		_predConsts	: For exact computation on the GPU				*/
	/* 		rng			: The random number generator					*/
	/* 		rd			: The render device, provided by godot			*/
	/********************************************************************/
	
	uint _activeFacesRemaining; // We iterate on this number in the second while loop.


	Random _rng;
	RenderingDevice _rd = RenderingServer.CreateLocalRenderingDevice();

	/********************************************************************/
	/* Functions														*/
	/********************************************************************/
	public override void _Ready()
	{	
		debugFileInit();
		initRenderDevice();
		loadShaders();


		testTriangulate();
	}

	// Methods
	private partial int gdFlip3D( bool Flipping = true);


	// --------------------------------------------------------------------------------------------
	// Create the initial tetrahedron, as given in the algorithm.
	// Ensure these points and indecies are always added first.
	public uint Initial_simplex(float circum_radius)
	{	
		// Add points,
		if (_points.Length < 4) {return 1;}

		/* A simplicial complex is composed of the following
		point_list;
		tetra_list; // quadruplets of point indices.
		face_list; // triples of point indices.
		face_to_tetra_list; // doubles of tetra indecies
		tetra_to_face_list; // quadruplets of edge indecies
		----- I really only need this for marching tetrahedra. -----
		edge_list; // doubles of point indices.
		tetra_to_edge_list; // sixtuples of edge indices.
		*/
		
		// POINT_LIST
		// First point	%3*ptind + x/y/z
		_points[ 3*0 + 0] = (float) (circum_radius * 3.0 *  Mathf.Sqrt( (float) (8.0 / 9.0) ));
		_points[ 3*0 + 1] = 0;
		_points[ 3*0 + 2] = (float) ((-1) * circum_radius * 3.0 * ( (float) (1.0 / 3.0) ));

		// Third point
		_points[ 3*1 + 0] = (float) ((-1) * circum_radius * 3.0 * Mathf.Sqrt( (float) (2.0 / 9.0) ));
		_points[ 3*1 + 1] = (float) ((-1) * circum_radius * 3.0 * Mathf.Sqrt( (float) (2.0 / 3.0) ));
		_points[ 3*1 + 2] = (float) ((-1) * circum_radius * 3.0 * ( (float) (1.0 / 3.0) ));

		// Forth point
		_points[ 3*2 + 0 ] = 0;
		_points[ 3*2 + 1 ] = 0;
		_points[ 3*2 + 2 ] = (float) (circum_radius * 3.0);

		// Second point
		_points[ 3*3 + 0] = (float) ((-1) * circum_radius * 3.0 * Mathf.Sqrt( (float)2.0 / (float)9.0));
		_points[ 3*3 + 1] = (float) (circum_radius * 3.0 *  Mathf.Sqrt( (float) (2.0 / 3.0) ));
		_points[ 3*3 + 2] = (float) ((-1) * circum_radius * 3.0 * ( (float) (1.0 / 3.0) ));





		// TETRA_LIST
		_tetra = new uint[4];
		_tetra[0] = 0;
		_tetra[1] = 1;
		_tetra[2] = 2;
		_tetra[3] = 3;

		// FACE_LIST
		_face = new uint[12];
		_face[0   + 0] = 1; _face[0   + 1] = 2; _face[0   + 2] = 3;
		_face[3*1 + 0] = 0; _face[3*1 + 1] = 2; _face[3*1 + 2] = 3;
		_face[3*2 + 0] = 0; _face[3*2 + 1] = 1; _face[3*2 + 2] = 3;
		_face[3*3 + 0] = 0; _face[3*3 + 1] = 1; _face[3*3 + 2] = 2;

		// FACE_TO_TETRA_LIST
		// Each face in general has two attached tetrahedron, but the initial faces have 1.
		_faceToTetra = new uint[12];
		// Face 0
		_faceToTetra[0] = 0; 
		_faceToTetra[1] = 0; // not used
		// Face 1
		_faceToTetra[2] = 0; // not used
		_faceToTetra[3] = 0; // used, odd place is negative orientation
		// Face 2
		_faceToTetra[4] = 0;
		_faceToTetra[5] = 0; // not used
		// Face 3
		_faceToTetra[6] = 0; // not used
		_faceToTetra[7] = 0; // used, implicite neg orientation

		// TETRA_TO_FACE_LIST
		_tetraToFace = new uint[4];
		_tetraToFace[0*4 + 0] = 0;
		_tetraToFace[0*4 + 1] = 1;
		_tetraToFace[0*4 + 2] = 2;
		_tetraToFace[0*4 + 3] = 3;

		// EDGE_LIST
		_edge = new uint[12];
		_edge[0 ] = 0; _edge[1 ] = 1;
		_edge[2 ] = 0; _edge[3 ] = 2;
		_edge[4 ] = 0; _edge[5 ] = 3;
		_edge[6 ] = 1; _edge[7 ] = 2;
		_edge[8 ] = 1; _edge[9 ] = 3;
		_edge[10] = 2; _edge[11] = 3;

		// TETRA_TO_EDGE_LIST
		_tetraToEdge = new uint[6];
		_tetraToEdge[0] = 0;
		_tetraToEdge[1] = 1;
		_tetraToEdge[2] = 2;
		_tetraToEdge[3] = 3;
		_tetraToEdge[4] = 4;
		_tetraToEdge[5] = 5;

		return 0;
	}	
	// --------------------------------------------------------------------------------------------
	// TEMP DESIGN / DEBUG FUNCTIONS


	// --------------------------------------------------------------------------------------------
	// Test point distribution and compute shaders. Pulling points from a file will be much the same.
	// TOO SLOW WITH LOTS OF POINTS: 10000 points OK
	public void Fill_Random_With_Super_Tetra(uint number_of_points, float within_radius, float epsilon, float mindist) 
	{	// I might as well write directly in the main array here.
		float max = within_radius;
		_points = new float[ (number_of_points+4) * 3 ];
		//uint[] sorted_index = new uint[N]; // Sort later.

		// Add the initial tetrahedron, of circum_radius one plus epsilon.
		Initial_simplex( (float) ( within_radius + epsilon ) );
		// Adding the other N points.
		float[] new_point = new float[3];
		float[] check_point = new float[3];
		for (int i = 0; i < number_of_points; i++) //try to add N points. (Forcing N points would be similar)
		{	
			bool append = true;

			new_point[0] = random_in_radius(max);
			new_point[1] = random_in_radius(max);
			new_point[2] = random_in_radius(max);

			for(int j = 0; j < i; j++)
			{
				
				check_point[0] = _points[ 3*(j+4) + 0 ];
				check_point[1] = _points[ 3*(j+4) + 1 ];
				check_point[2] = _points[ 3*(j+4) + 2 ];

				if ( dvec_distance(new_point, check_point) < mindist )
				{
					i--; number_of_points--;
					append = false;
					break;
				}
			}
			if (append == true)
			{
				_points[ 3*(i+4) + 0] = new_point[0];
				_points[ 3*(i+4) + 1] = new_point[1];
				_points[ 3*(i+4) + 2] = new_point[2];
				// TODO: sort list of points here along hilbert curve?
			}
		}
		/* // Debug
		for (int i = 0; i < N; i++) //try to add N points. (Forcing N points would be similar)
		{
			debugLogAddLine( point_cloud[i] , i);
		}
		*/
	}
	

	float dvec_distance(float[] a, float[] b, uint offseta, uint offsetb)
	{
		float diffx_sqd = (a[ offseta + 0 ] - b[offsetb + 0])*(a[ offseta + 0 ] - b[offsetb + 0]);
		float diffy_sqd = (a[ offseta + 1 ] - b[offsetb + 1])*(a[ offseta + 1 ] - b[offsetb + 1]);
		float diffz_sqd = (a[ offseta + 2 ] - b[offsetb + 2])*(a[ offseta + 2 ] - b[offsetb + 2]);
		return (float) Math.Sqrt(diffx_sqd + diffy_sqd + diffz_sqd);
	}
	float dvec_distance(float[] a, float[] b)
	{
		float diffx_sqd = (a[0] - b[0])*(a[0] - b[0]);
		float diffy_sqd = (a[1] - b[1])*(a[1] - b[1]);
		float diffz_sqd = (a[2] - b[2])*(a[2] - b[2]);
		return (float) Math.Sqrt(diffx_sqd + diffy_sqd + diffz_sqd);
	}

	float random_in_radius(float radius)
	{
		return (float) ((_rng.NextDouble() * 2.0) - 1) * radius;
	}


	public void testTriangulate(){
		// ----- SETUP -----
		_rng = new Random( 1934 );
		
		// ----- TESTING -----
		uint points_to_sort = 14;
		// Probably the slowest part of the program at this point.
		Fill_Random_With_Super_Tetra(points_to_sort, 10, (float) 18, (float) 0.05 );

		// Debug: check that we actually have enough points:
		// number of points plus 3:
		debugLogAddLine("Sorting " + points_to_sort.ToString() + " points.");

		gdFlip3D( true );

		_tetra = bfToUint( _bfTetra, 4 * _numTetra );
		_face = bfToUint( _bfFace, 3 * _numFaces );
		_edge = bfToUint( _bfEdge, 2 * _numEdges );

		uint[] delauneyFaces = bfToUint( _bfDelauneyFaces, _numDelauneyFaces );
		uint[] nonDelauneyFaces = bfToUint( _bfNonDelauneyFaces, _numNonDelauneyFaces );

		int[] faceList = new int[ _face.Length];
		for(uint i = 0; i < _face.Length; i++){
			faceList[i] = (int) _face[i];
		}

		int[] delauneyFaceList = new int[ 3 * (_numDelauneyFaces + 4) ];
		for(uint i = 0; i < 4; i++){
			delauneyFaceList[ 3 * i + 0 ] = (int) _face[ 3 * i + 0 ];
			delauneyFaceList[ 3 * i + 1 ] = (int) _face[ 3 * i + 1 ];
			delauneyFaceList[ 3 * i + 2 ] = (int) _face[ 3 * i + 2 ];
		}
		for(uint i = 0; i < _numDelauneyFaces; i++){
			delauneyFaceList[ 3 * (i + 4) + 0 ] = (int) _face[ 3 * delauneyFaces[ i ] + 0 ];
			delauneyFaceList[ 3 * (i + 4) + 1 ] = (int) _face[ 3 * delauneyFaces[ i ] + 1 ];
			delauneyFaceList[ 3 * (i + 4) + 2 ] = (int) _face[ 3 * delauneyFaces[ i ] + 2 ];
		}

		int[] nondelauneyFaceList = new int[ 3 * _numNonDelauneyFaces ];
		for(uint i = 0; i < _numNonDelauneyFaces; i++){
			nondelauneyFaceList[ 3 * i + 0 ] = (int) _face[ 3 * nonDelauneyFaces[ i ] + 0 ];
			nondelauneyFaceList[ 3 * i + 1 ] = (int) _face[ 3 * nonDelauneyFaces[ i ] + 1 ];
			nondelauneyFaceList[ 3 * i + 2 ] = (int) _face[ 3 * nonDelauneyFaces[ i ] + 2 ];
		}


		int[] edgeList = new int[ _edge.Length];
		for(uint i = 0; i < _edge.Length; i++){
			edgeList[i] = (int) _edge[i];
		}

		debugLogAddLine( "number of tetra:" + (_tetra.Length / 4) );
		debugLogAddLine( "number of points:" + (_points.Length / 3) );

		Label3D[] pointlabels = new Label3D[ _points.Length / 3 ];
		Godot.Vector3[] pointList = new Godot.Vector3[ _points.Length / 3 ];
		for(uint i = 0; i < _points.Length/3; i++){
			pointList[i].X = (float) _points[ 3*i +0 ];
			pointList[i].Y = (float) _points[ 3*i +1 ];
			pointList[i].Z = (float) _points[ 3*i +2 ];

			// labels
			pointlabels[i] = new Label3D();
			pointlabels[i].Text = "" + i;

			pointlabels[i].FontSize = 80;
			pointlabels[i].Translate(pointList[i]);
			base.AddChild(pointlabels[i]);
		}

		Node3D[] faceNormal = new Node3D[ _face.Length / 3 ];
		for(uint i = 0; i < _face.Length / 3; i++){
			Godot.Vector3 u; u.X =  _points[ 3 * _face[ 3 * i + 0 ] + 0 ]; u.Y =  _points[ 3 * _face[ 3 * i + 0 ] + 1 ]; u.Z =  _points[ 3 * _face[ 3 * i + 0 ] + 2 ];
			Godot.Vector3 v; v.X =  _points[ 3 * _face[ 3 * i + 1 ] + 0 ]; v.Y =  _points[ 3 * _face[ 3 * i + 1 ] + 1 ]; v.Z =  _points[ 3 * _face[ 3 * i + 1 ] + 2 ];
			Godot.Vector3 w; w.X =  _points[ 3 * _face[ 3 * i + 2 ] + 0 ]; w.Y =  _points[ 3 * _face[ 3 * i + 2 ] + 1 ]; w.Z =  _points[ 3 * _face[ 3 * i + 2 ] + 2 ];

			Godot.Vector3 x = u - w;
			Godot.Vector3 y = v - w;

			Godot.Vector3 normal = x.Cross(y).Normalized();
			Godot.Vector3 position = ( ( x + y ) / 3 ) + w;

			Transform3D t = new Transform3D();
			t.Basis = new Basis( x.Normalized(), normal, x.Normalized().Cross(normal) );
			t.Origin = position;

			// labels
			faceNormal[i] = new Node3D();
			faceNormal[i].AddChild( ResourceLoader.Load<PackedScene>("res://objects/grid/mesh/arrow1.glb").Instantiate() );
			faceNormal[i].Transform = t;

			base.AddChild( faceNormal[i] );
		}


		Node3D[] tetNormal = new Node3D[ _tetra.Length ];
		for(uint i = 0; i < (_tetra.Length / 4); i++){
			for(uint j = 0; j < 4; j++){

				uint[] tetFacePt = new uint[3];
				tetFacePt[0] = _tetra[ 4 * i + ( (0 + j) % 4 ) ];
				tetFacePt[1] = _tetra[ 4 * i + ( (1 + j) % 4 ) ];
				tetFacePt[2] = _tetra[ 4 * i + ( (2 + j) % 4 ) ];
				
				Godot.Vector3 u; u.X =  _points[ 3 * tetFacePt[0] + 0 ]; u.Y =  _points[ 3 * tetFacePt[0] + 1 ]; u.Z =  _points[ 3 * tetFacePt[0] + 2 ];
				Godot.Vector3 v; v.X =  _points[ 3 * tetFacePt[1] + 0 ]; v.Y =  _points[ 3 * tetFacePt[1] + 1 ]; v.Z =  _points[ 3 * tetFacePt[1] + 2 ];
				Godot.Vector3 w; w.X =  _points[ 3 * tetFacePt[2] + 0 ]; w.Y =  _points[ 3 * tetFacePt[2] + 1 ]; w.Z =  _points[ 3 * tetFacePt[2] + 2 ];

				Godot.Vector3 x = u - w;
				Godot.Vector3 y = v - w;

				Godot.Vector3 normal = x.Cross(y).Normalized();
				Godot.Vector3 position = ( ( x + y ) / 3 ) + w;

				Transform3D t = new Transform3D();
				t.Basis = new Basis( x.Normalized(), normal, x.Normalized().Cross(normal) );
				t.Origin = position;

				tetNormal[ 4 * i + j ] = new Node3D();

				tetNormal[ 4 * i + j ].AddChild( ResourceLoader.Load<PackedScene>("res://objects/grid/mesh/arrow2.glb").Instantiate() );
				tetNormal[ 4 * i + j ].Transform = t;

				base.AddChild( tetNormal[ 4 * i + j ] );
			}
		}

		//create grid line mesh
		var lineArray = new Godot.Collections.Array();
		lineArray.Resize((int)Mesh.ArrayType.Max);
		lineArray[(int)Mesh.ArrayType.Vertex] = pointList;
		lineArray[(int)Mesh.ArrayType.Index] = edgeList;
		var lineArrMesh = new ArrayMesh();
		lineArrMesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Lines, lineArray);
		var lineMeshInstance = new MeshInstance3D();
		lineMeshInstance.Mesh = lineArrMesh;
		base.AddChild(lineMeshInstance);

		//create Delauney grid triangle mesh
		/*
		var delauneyTriArray = new Godot.Collections.Array();
		delauneyTriArray.Resize((int)Mesh.ArrayType.Max);
		delauneyTriArray[(int)Mesh.ArrayType.Vertex] = pointList;
		delauneyTriArray[(int)Mesh.ArrayType.Index] = delauneyFaceList;
		var delauneyTriMesh = new ArrayMesh();
		delauneyTriMesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, delauneyTriArray);
		var delauneyTriMeshInstance = new MeshInstance3D();
		delauneyTriMeshInstance.Mesh = delauneyTriMesh;
		delauneyTriMeshInstance.MaterialOverride = ResourceLoader.Load<Material>("res://objects/grid/mesh/delauney.tres");
		base.AddChild(delauneyTriMeshInstance);
		*/

		//create nonDelauney grid triangle mesh
		var nondelauneyTriArray = new Godot.Collections.Array();
		nondelauneyTriArray.Resize((int)Mesh.ArrayType.Max);
		nondelauneyTriArray[(int)Mesh.ArrayType.Vertex] = pointList;
		nondelauneyTriArray[(int)Mesh.ArrayType.Index] = nondelauneyFaceList;
		var nondelauneyTriMesh = new ArrayMesh();
		nondelauneyTriMesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, nondelauneyTriArray);
		var nondelauneyTriMeshInstance = new MeshInstance3D();
		nondelauneyTriMeshInstance.Mesh = nondelauneyTriMesh;
		nondelauneyTriMeshInstance.MaterialOverride = ResourceLoader.Load<Material>("res://objects/grid/mesh/nondelauney.tres");
		base.AddChild(nondelauneyTriMeshInstance);
		
	}


	/* ------------------------------------------------------------------------------------------------------------------------- */
	/*                                                                                                                           */
	/*                                                Memory And Buffer Management                                               */
	/*                                                                                                                           */
	/* ------------------------------------------------------------------------------------------------------------------------- */


	private Rid toBuffer( uint[] data)
	{
		byte[] data_bytes = new byte[data.Length * 4]; // Four bytes per index.
		Buffer.BlockCopy(data, 0, data_bytes, 0, data_bytes.Length);
		Rid buffer = _rd.StorageBufferCreate((uint)data_bytes.Length, data_bytes);
		return buffer;
	}


	private Rid toBuffer( float[] data)
	{
		byte[] data_bytes = new byte[data.Length * 4]; // Four bytes per index.
		Buffer.BlockCopy(data, 0, data_bytes, 0, data_bytes.Length);
		Rid buffer = _rd.StorageBufferCreate((uint)data_bytes.Length, data_bytes);
		return buffer;
	}


	private Rid newBuffer( uint length ) 
		// Reserves space on GPU only.
	{
		Rid buffer = _rd.StorageBufferCreate( length * 4);
		return buffer;
	}
	

	private uint nthPlaceOfBuffer( uint n, Rid buffer)
	{
		byte[] data = _rd.BufferGetData(buffer, 4*n, 4);
		uint[] uint_array = new uint[1];
		Buffer.BlockCopy( data, 0, uint_array, 0, data.Length);
		return uint_array[0];
	}


	private int InitComplexBuffers(){	
		// Make sure we have something to do: we need one point in addition to an initial tetra.
		if ( _points.Length < 3 * 5 | !( _tetra.Length == 4) ){return -1;}
		
		// _numTetra = 1; _numFaces = 4; _numEdges = 6;
		_numPointsRemaining = (uint)( ( _points.Length / 3 ) - 4 );

		//											( 4 bytes per float or index )
		_bfPointsToAdd   = _rd.StorageBufferCreate( _numPointsRemaining * 4 ); incrementalFill( 	_bfPointsToAdd,   _numPointsRemaining, 4); // add all but 0,1,2,3
		_bfTetraOfPoints = _rd.StorageBufferCreate( _numPointsRemaining * 4 ); zeroFill( 		_bfTetraOfPoints, _numPointsRemaining   ); // all belong in tet 0

		// These three numbers are tuning parameters. They should depend on the number of points.
		uint estimateNumTetra = 1;
		uint estimateNumFaces = 4;
		uint estimateNumEdges = 6;

		// init complex buffers
		_bfTetraSize = estimateNumTetra;
		_bfTetra 			= _rd.StorageBufferCreate( estimateNumTetra * 4 * 4 ); // 4 indx/tet * 4 byte/indx
		_bfTetraToFace		= _rd.StorageBufferCreate( estimateNumTetra * 4 * 4 ); // 4 indx/tet * 4 byte/indx
		_bfTetraToEdge		= _rd.StorageBufferCreate( estimateNumTetra * 6 * 4 ); // 6 indx/tet * 4 byte/indx

		_bfFaceSize = estimateNumFaces;
		_bfFace 			= _rd.StorageBufferCreate( estimateNumFaces * 3 * 4 ); // 3 indx/face * 4 byte/indx
		_bfFaceToTetra		= _rd.StorageBufferCreate( estimateNumFaces * 2 * 4 ); // 2 indx/face * 4 byte/indx

		_bfEdgeSize = estimateNumEdges;
		_bfEdge 			= _rd.StorageBufferCreate( estimateNumEdges * 2 * 4 ); // 2 indx/edge * 4 byte/indx

		// fill complex Buffers. Here we're minimizing the number of indicies to pass to the GPU
		Rid bfInitTetra 		= toBuffer( _tetra );		copyFill( bfInitTetra, 	     _bfTetra, 	     4 ); _rd.FreeRid( bfInitTetra );
		Rid bfInitTetraToFace	= toBuffer( _tetraToFace ); copyFill( bfInitTetraToFace, _bfTetraToFace, 4 ); _rd.FreeRid( bfInitTetraToFace );
		Rid bfInitTetraToEdge	= toBuffer( _tetraToEdge ); copyFill( bfInitTetraToEdge, _bfTetraToEdge, 6 ); _rd.FreeRid( bfInitTetraToEdge );
		
		Rid bfInitFace 		  = toBuffer( _face ); 		  copyFill( bfInitFace,        _bfFace,        12 );  _rd.FreeRid( bfInitFace );
		Rid bfInitFaceToTetra = toBuffer( _faceToTetra ); copyFill( bfInitFaceToTetra, _bfFaceToTetra,  8 );  _rd.FreeRid( bfInitFaceToTetra);

		Rid bfInitEdge = toBuffer( _edge ); copyFill( bfInitEdge, _bfEdge, 12 );_rd.FreeRid( bfInitEdge );

		// The number of simplicies overall.
		_numTetra = 1; _numFaces = 4; _numEdges = 6;
		// The index of last filled simplex. (Different because there might be 'freed space' where simplicies got deleted in a flipping operation.)
		_lastTetra = 0; _lastFace = 3; _lastEdge = 5;

		// Copy all the points over to the GPU:
		_bfPoints = toBuffer( _points );

		// Now initialize freed simplicies.
		_numFreedTetra = 0; _numFreedFaces = 0; _numFreedEdges = 0;

		// These three numbers are tuning parameters. They could depend on the number of points.
		uint estimateNumFreedTetra = 1;
		uint estimateNumFreedFaces = 2;
		uint estimateNumFreedEdges = 1;

		_bfFreedTetraSize = estimateNumFreedTetra;
		_bfFreedTetra = newBuffer( _bfFreedTetraSize );
		
		_bfFreedFacesSize = estimateNumFreedFaces;
		_bfFreedFaces = newBuffer( _bfFreedFacesSize );
		
		_bfFreedEdgesSize = estimateNumFreedEdges;
		_bfFreedEdges = newBuffer( _bfFreedEdgesSize );

		// Generate predicate constants, if needed.
		if( !_predConstsGenerated ){ genPredConsts(); }

		return 1;
	}

	/* ------------------------------------------------------------------------------------------------------------------------- */
	/*                                                                                                                           */
	/*                                                           Debug                                                           */
	/*                                                                                                                           */
	/* ------------------------------------------------------------------------------------------------------------------------- */

	private void debugFileInit(){
		_debugFile = Godot.FileAccess.Open("res://objects/grid/log.txt", Godot.FileAccess.ModeFlags.Write);
	}

	private void debugLogAddLine( String s ){
		_debugFile.StoreString(s + System.Environment.NewLine);
	}

	private void debugLogFlush( ){
		_debugFile.Flush();
	}

	private static uint uintPow(uint a, uint b)
	{
		uint result = 1;
		for(uint i = 0; i < b; i++)
		{
			result *= a;
		}
		return result;
	}

	private static string tripletToString(uint[] data){
		if(data.Length == 0){return "[]";} else {
			string s = "[ ";
			for(uint i = 0; i < (data.Length/3) -1 ; i++){
				s += "(" +	data[3*i + 0] + ", ";
				s += 		data[3*i + 1] + ", ";
				s += 		data[3*i + 2] + "), ";
			}
			s += "(" + 	data[3*((data.Length -1)/3) + 0] + ", ";
			s +=        data[3*((data.Length -1)/3) + 1] + ", ";
			s +=        data[3*((data.Length -1)/3) + 2] + ") ]";

			return s;
		}
	}

	private static string doubletToString(uint[] data){
		if(data.Length == 0){return "[]";} else {
			string s = "[ ";
			for(uint i = 0; i < (data.Length/2) -1 ; i++){
				s += "(" + 	data[2*i + 0] + ", ";
				s += 		data[2*i + 1] + "), ";
			}
			s += "(" + 	data[2*((data.Length -1)/2) + 0] + ", ";
			s +=		data[2*((data.Length -1)/2) + 1] + ") ]";

			return s;
		}
	}

	private static string singleToString(uint[] data){
		if(data.Length == 0){return "[]";} else {
			string s = "[ ";
			for(uint i = 0; i < (data.Length - 1) ; i++)
			{
				s += data[i] + ", ";
			}
			s += data[ data.Length - 1 ] + " ]";

			return s;
		}
	}

	private static string singleToString(float[] data){
		if(data.Length == 0){return "[]";} else {
			string s = "[ ";
			for(uint i = 0; i < (data.Length - 1) ; i++)
			{
				s += "(" + data[i] + "), ";
			}
			s += "(" + 	data[data.Length -1] + ") ]";

			return s;
		}
	}

	private static string singleToString( byte[] data){ // TODO: I have no idea if this is correctly displaying the order.
		if(data.Length == 0){return "[]";} else {
			string s = "[ ";
			for(uint i = 0; i < ( data.Length / 4 ) - 1 ; i++)
			{
				s +=  //byteToString( data[ 4 * i + 3 ] )
					 byteToString( data[ 4 * i + 2 ] )
					+ byteToString( data[ 4 * i + 1 ] )
					+ byteToString( data[ 4 * i + 0 ] ) + ", ";
			}
			s +=  //byteToString( data[ 4 * (( data.Length / 4 ) - 1) + 3 ] )
				 byteToString( data[ 4 * (( data.Length / 4 ) - 1) + 2 ] )
				+ byteToString( data[ 4 * (( data.Length / 4 ) - 1) + 1 ] )
				+ byteToString( data[ 4 * (( data.Length / 4 ) - 1) + 0 ] ) + " ]";
			return s;
		}
	}

	private static string byteToString( byte data ){
		string s = Convert.ToString(data, 2);
		while(s.Length < 8){
			s = "0" + s;
		}
		return s;
	}


	private static string quadrupletToString(uint[] data){
		if(data.Length == 0){return "[]";} else {
			string s = "[ ";
			for(uint i = 0; i < (data.Length/4) -1 ; i++)
			{
				s += "(" + 	data[4*i + 0] + ", ";
				s += 		data[4*i + 1] + ", ";
				s += 		data[4*i + 2] + ", ";
				s += 		data[4*i + 3] + "), ";
			}
			s += "(" + 	data[4*((data.Length/4) -1) + 0] + ", ";
			s += 		data[4*((data.Length/4) -1) + 1] + ", ";
			s += 		data[4*((data.Length/4) -1) + 2] + ", ";
			s +=		data[4*((data.Length/4) -1) + 3] + ") ]";

			return s;
		}
	}

	private uint[] bfToUint( Rid buffer, uint size)
	{
		uint[] array = new uint[size];
		Buffer.BlockCopy( _rd.BufferGetData( buffer, 0, 4 * size), 0, array, 0, (int) (4 * size) );
		return array;
	}

	private byte[] bfToByte( Rid buffer, uint size)
	{
		byte[] array = new byte[4 * size];
		Buffer.BlockCopy( _rd.BufferGetData( buffer, 0, 4 * size), 0, array, 0, (int) (4 * size) );
		return array;
	}
	
	private float[] bfToFloat( Rid buffer, uint size)
	{
		float[] array = new float[size];
		Buffer.BlockCopy( _rd.BufferGetData( buffer, 0, 4 * size), 0, array, 0, (int) (4 * size) );
		return array;
	}

}