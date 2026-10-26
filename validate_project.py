"""Validate project packaging on Linux or macOS; does not compile Swift/iOS code."""
from pathlib import Path
import json
import plistlib
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent
project = (root / "Pulse.xcodeproj/project.pbxproj").read_text()
objects = {}
for object_id, body in re.findall(r"^\s*([A-F0-9]{24}) = \{ (.*) \};$", project, re.M):
    assert object_id not in objects, f"Duplicate project object: {object_id}"
    objects[object_id] = body

references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
assert references <= objects.keys(), f"Unresolved project objects: {references - objects.keys()}"
assert len(objects) == len(re.findall(r"^\s*[A-F0-9]{24} = \{", project, re.M))

source_refs = {}
for object_id, body in objects.items():
    if "isa = PBXFileReference;" in body and "sourcecode.swift" in body:
        path = re.search(r'path = "([^"]+)";', body).group(1)
        assert (root / path).is_file(), f"Missing source: {path}"
        source_refs[object_id] = path
actual_sources = {p.relative_to(root).as_posix() for p in (root / "Pulse").rglob("*.swift")}
assert set(source_refs.values()) == actual_sources, "Source files missing from project"
build_refs = {}
for object_id, body in objects.items():
    if "isa = PBXBuildFile;" in body:
        build_refs[object_id] = re.search(r"fileRef = ([A-F0-9]{24});", body).group(1)
phase = next(body for body in objects.values() if "isa = PBXSourcesBuildPhase;" in body)
phase_ids = re.findall(r"\b[A-F0-9]{24}\b", phase)
assert len(phase_ids) == len(set(phase_ids)), "Duplicate source build entry"
assert {build_refs[key] for key in phase_ids} == source_refs.keys()

with (root / "Pulse/Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
assert "audio" in info["UIBackgroundModes"], "Background audio capability missing"
assert info["CFBundleIdentifier"] == "$(PRODUCT_BUNDLE_IDENTIFIER)"
assert "IPHONEOS_DEPLOYMENT_TARGET = 17.0;" in project
assert "INFOPLIST_FILE = Pulse/Info.plist;" in project

for path in root.rglob("*.json"):
    json.loads(path.read_text())
scheme = ET.parse(root / "Pulse.xcodeproj/xcshareddata/xcschemes/Pulse.xcscheme")
for reference in scheme.findall(".//BuildableReference"):
    target = reference.attrib["BlueprintIdentifier"]
    assert "isa = PBXNativeTarget;" in objects[target]
assert scheme.find(".//LaunchAction/BuildableProductRunnable") is not None

print(f"PASS: {len(actual_sources)} Swift files referenced exactly once in Sources phase")
print(f"PASS: {len(objects)} project objects resolve; shared scheme targets Pulse")
print("PASS: Info.plist and asset JSON parse; iOS 17 and background audio configured")
print("NOT RUN: Swift compilation, App Intents extraction, simulator/device checks (requires Xcode)")
