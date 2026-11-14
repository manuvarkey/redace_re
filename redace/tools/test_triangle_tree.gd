extends SceneTree
## World.triangles_hit (triangles tested by box) against testing every triangle (World.faces_hit), on the aircraft and
## ground models: random segments through and around each mesh, and segments that end on, start on or run through
## its vertices and edges. godot --headless --path redace -s tools/test_triangle_tree.gd

const MODELS := ["objects/planes/he111/he111.gltf", "objects/planes/he111/damaged2.gltf", "objects/planes/bf109/bf109.gltf",
	"objects/planes/spitfire/spitfire.gltf", "objects/planes/sopwithcamel/sopwithcamel.gltf", "objects/planes/handleypage/handleypage.gltf",
	"objects/ground/factory/factory.gltf", "objects/ground/bridge/bridge.gltf", "objects/ground/tree1/tree2.gltf",
	"objects/ground/britainfreighter/britainfreighter.gltf"]

var checks := 0
var failures := 0


func _initialize() -> void:
	seed(99)
	var timing := {"tree": 0, "all": 0}
	for rel in MODELS:
		if not ResourceLoader.exists(Ini.data_path(rel)):
			print("skip (not present): ", rel)
			continue
		var model := World.load_model(rel)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var faces: PackedVector3Array = (mi as MeshInstance3D).mesh.get_faces()
			if faces.is_empty():
				continue
			var tree := World.triangle_tree(faces)
			var box: AABB = (mi as MeshInstance3D).mesh.get_aabb()
			var bad := 0
			var hits := 0
			var count := 3000
			for i in count:
				var a: Vector3
				var b: Vector3
				match i % 4:
					0, 1:  # through and around the mesh, short (probes) and long
						a = box.position + Vector3(randf(), randf(), randf()) * box.size * 1.4 - box.size * 0.2
						var length: float = [1.0, 4.0, 15.0][i % 3]
						b = a + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * length
					2:  # ending exactly on a vertex
						var v := faces[randi() % faces.size()]
						a = v + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * 3.0
						b = v
					3:  # through the midpoint of an edge
						var t := (randi() % (faces.size() / 3)) * 3
						var m := (faces[t] + faces[t + 1]) * 0.5
						var d := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
						a = m - d * 2.0
						b = m + d * 2.0
				var s := Time.get_ticks_usec()
				var expected := World.faces_hit(faces, a, b)
				var m2 := Time.get_ticks_usec()
				var got := World.triangles_hit(tree, a, b)
				timing.all += m2 - s
				timing.tree += Time.get_ticks_usec() - m2
				hits += int(expected)
				if got != expected:
					bad += 1
			checks += 1
			if bad:
				failures += 1
				printerr("FAIL: %s %s: %d of %d segments differ" % [rel, mi.name, bad, count])
			print("%s %s: %d triangles, %d segments (%d hits) agree" % [rel, mi.name, faces.size() / 3, count - bad, hits])
		model.free()
	print("time: every triangle %.0f ms, by box %.0f ms" % [timing.all / 1000.0, timing.tree / 1000.0])
	print("Triangle tree: %d meshes, %d failures" % [checks, failures])
	quit(1 if failures else 0)
