extends SceneTree
func _init():
    var files = []
    _collect_gd("res://", files)
    var failures = []
    for path in files:
        if load(path) == null:
            failures.append(path)
    if failures.is_empty():
        print("ALL ", files.size(), " SCRIPTS PARSED OK")
    else:
        for path in failures:
            print("FAIL ", path)
    quit()
func _collect_gd(dir: String, files: Array):
    var d = DirAccess.open(dir)
    if d == null:
        return
    d.list_dir_begin()
    var name = d.get_next()
    while name != "":
        if name.begins_with("."):
            name = d.get_next()
            continue
        var p = dir.path_join(name)
        if d.current_is_dir():
            _collect_gd(p, files)
        elif name.ends_with(".gd"):
            files.append(p)
        name = d.get_next()
