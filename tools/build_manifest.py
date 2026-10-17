"""Build build/manifest.json from default.project.json using Rojo's file rules.

Studio fetches the manifest over localhost (see tools/studio_sync.luau) and rebuilds
each Rojo-managed root, so code reaches Studio without the Rojo plugin.
Supported: folders, init scripts, .server/.client/module scripts, nested
default.project.json files (Wally packages). Other file types are ignored.
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT_EXTS = (".luau", ".lua")
INIT_NAMES = {
    "init.server.luau": "Script",
    "init.server.lua": "Script",
    "init.client.luau": "LocalScript",
    "init.client.lua": "LocalScript",
    "init.luau": "ModuleScript",
    "init.lua": "ModuleScript",
}


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def script_class(filename):
    for ext in SCRIPT_EXTS:
        if filename.endswith(".server" + ext):
            return "Script", filename[: -len(".server" + ext)]
        if filename.endswith(".client" + ext):
            return "LocalScript", filename[: -len(".client" + ext)]
        if filename.endswith(ext):
            return "ModuleScript", filename[: -len(ext)]
    return None, None


def from_path(path, name):
    """Turn a file or directory into a manifest node, or None if Rojo would skip it."""
    if os.path.isdir(path):
        nested = os.path.join(path, "default.project.json")
        if os.path.isfile(nested):
            project = json.loads(read(nested))
            node = from_tree(project["tree"], path, name)
            return node
        entries = sorted(os.listdir(path))
        node = {"n": name, "c": "Folder", "k": []}
        for entry in entries:
            if entry in INIT_NAMES:
                node["c"] = INIT_NAMES[entry]
                node["s"] = read(os.path.join(path, entry))
        for entry in entries:
            if entry in INIT_NAMES or entry.startswith("."):
                continue
            full = os.path.join(path, entry)
            if os.path.isdir(full):
                child = from_path(full, entry)
            else:
                cls, child_name = script_class(entry)
                child = {"n": child_name, "c": cls, "s": read(full)} if cls else None
            if child:
                node["k"].append(child)
        return node
    cls, _ = script_class(os.path.basename(path))
    if not cls:
        return None
    return {"n": name, "c": cls, "s": read(path)}


def from_tree(tree, base, name):
    if "$path" in tree:
        node = from_path(os.path.join(base, tree["$path"]), name)
        if node is None:
            return None
    else:
        node = {"n": name, "c": tree.get("$className", "Folder"), "k": []}
    node.setdefault("k", [])
    for key, child in tree.items():
        if key.startswith("$"):
            continue
        child_node = from_tree(child, base, key)
        if child_node:
            node["k"].append(child_node)
    return node


def collect_roots(tree, base, parent_path, roots):
    """Every node with a $path becomes a root that Studio replaces whole."""
    for key, child in tree.items():
        if key.startswith("$"):
            continue
        path = f"{parent_path}.{key}" if parent_path else key
        if "$path" in child:
            if not os.path.exists(os.path.join(base, child["$path"])):
                continue
            node = from_tree(child, base, key)
            if node:
                roots.append({"parent": parent_path, "node": node})
        else:
            collect_roots(child, base, path, roots)


def count(node):
    return 1 + sum(count(c) for c in node.get("k", []))


def main():
    project_file = sys.argv[1] if len(sys.argv) > 1 else "default.project.json"
    project = json.loads(read(os.path.join(ROOT, project_file)))
    roots = []
    collect_roots(project["tree"], ROOT, "", roots)
    out_dir = os.path.join(ROOT, "build")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"roots": roots}, f)
    for root in roots:
        print(f"{root['parent']}.{root['node']['n']}: {count(root['node'])} instances")


if __name__ == "__main__":
    main()
