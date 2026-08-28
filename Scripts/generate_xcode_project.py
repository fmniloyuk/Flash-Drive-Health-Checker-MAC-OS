#!/usr/bin/env python3
"""Generate FlashScope.xcodeproj without third-party dependencies.

The repository intentionally keeps this generator deterministic so the Xcode project
can be reviewed as text and regenerated after adding source files.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_DIR = ROOT / "FlashScope.xcodeproj"
PBXPROJ = PROJECT_DIR / "project.pbxproj"


def oid(label: str) -> str:
    return hashlib.sha1(label.encode("utf-8")).hexdigest()[:24].upper()


def q(value: str) -> str:
    safe = value.replace('\\', '\\\\').replace('"', '\\"')
    return f'"{safe}"'


def name_for(path: str) -> str:
    return Path(path).name

core_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Sources/FlashScopeCore").glob("*.swift"))
app_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "FlashScope").rglob("*.swift"))
unit_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Tests/FlashScopeCoreTests").glob("*.swift"))
integration_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "FlashScopeIntegrationTests").glob("*.swift"))
ui_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "FlashScopeUITests").glob("*.swift"))

source_sets = {
    "core": core_files,
    "app": app_files,
    "unit": unit_files,
    "integration": integration_files,
    "ui": ui_files,
}

products = {
    "core": ("FlashScopeCore.framework", "wrapper.framework"),
    "app": ("FlashScope.app", "wrapper.application"),
    "unit": ("FlashScopeCoreTests.xctest", "wrapper.cfbundle"),
    "integration": ("FlashScopeIntegrationTests.xctest", "wrapper.cfbundle"),
    "ui": ("FlashScopeUITests.xctest", "wrapper.cfbundle"),
}

target_names = {
    "core": "FlashScopeCore",
    "app": "FlashScope",
    "unit": "FlashScopeCoreTests",
    "integration": "FlashScopeIntegrationTests",
    "ui": "FlashScopeUITests",
}

file_refs: list[str] = []
build_files: list[str] = []
file_ref_ids: dict[str, str] = {}
build_file_ids: dict[tuple[str, str], str] = {}

for target, paths in source_sets.items():
    for path in paths:
        ref = oid(f"file:{path}")
        file_ref_ids[path] = ref
        file_refs.append(f"\t\t{ref} /* {name_for(path)} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = SOURCE_ROOT; }};")
        bf = oid(f"build:{target}:{path}")
        build_file_ids[(target, path)] = bf
        build_files.append(f"\t\t{bf} /* {name_for(path)} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name_for(path)} */; }};")

assets_path = "FlashScope/Resources/Assets.xcassets"
assets_ref = oid(f"file:{assets_path}")
file_refs.append(f"\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {q(assets_path)}; sourceTree = SOURCE_ROOT; }};")
assets_build = oid("build:app:assets")
build_files.append(f"\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};")

for resource, ftype in [("FlashScope/Resources/Info.plist", "text.plist.xml"), ("FlashScope/Resources/FlashScope.entitlements", "text.plist.entitlements")]:
    ref = oid(f"file:{resource}")
    file_ref_ids[resource] = ref
    file_refs.append(f"\t\t{ref} /* {name_for(resource)} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {q(resource)}; sourceTree = SOURCE_ROOT; }};")

product_ref_ids: dict[str, str] = {}
for key, (product, ftype) in products.items():
    ref = oid(f"product:{key}")
    product_ref_ids[key] = ref
    file_refs.append(f"\t\t{ref} /* {product} */ = {{isa = PBXFileReference; explicitFileType = {ftype}; includeInIndex = 0; path = {product}; sourceTree = BUILT_PRODUCTS_DIR; }};")

# Framework references between targets.
link_core_app = oid("link:app:core")
link_core_unit = oid("link:unit:core")
link_core_integration = oid("link:integration:core")
for bf, label in [(link_core_app, "FlashScopeCore.framework in Frameworks"), (link_core_unit, "FlashScopeCore.framework in Frameworks"), (link_core_integration, "FlashScopeCore.framework in Frameworks")]:
    build_files.append(f"\t\t{bf} /* {label} */ = {{isa = PBXBuildFile; fileRef = {product_ref_ids['core']} /* FlashScopeCore.framework */; }};")

# Groups. Source file references keep full SOURCE_ROOT paths, which makes hierarchy cosmetic and regeneration robust.
group_ids = {key: oid(f"group:{key}") for key in ["main", "core", "app", "unit", "integration", "ui", "resources", "products"]}

def group_children(paths: list[str]) -> str:
    return "\n".join(f"\t\t\t\t{file_ref_ids[p]} /* {name_for(p)} */," for p in paths)

groups = []
groups.append(f'''\t\t{group_ids['main']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{group_ids['core']} /* FlashScopeCore */,\n\t\t\t\t{group_ids['app']} /* FlashScope */,\n\t\t\t\t{group_ids['unit']} /* FlashScopeCoreTests */,\n\t\t\t\t{group_ids['integration']} /* FlashScopeIntegrationTests */,\n\t\t\t\t{group_ids['ui']} /* FlashScopeUITests */,\n\t\t\t\t{group_ids['products']} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = "<group>";\n\t\t}};''')
groups.append(f'''\t\t{group_ids['core']} /* FlashScopeCore */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{group_children(core_files)}\n\t\t\t);\n\t\t\tname = FlashScopeCore;\n\t\t\tsourceTree = "<group>";\n\t\t}};''')
app_children = "\n".join(f"\t\t\t\t{file_ref_ids[p]} /* {name_for(p)} */," for p in app_files)
groups.append(f'''\t\t{group_ids['app']} /* FlashScope */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{app_children}\n\t\t\t\t{group_ids['resources']} /* Resources */,\n\t\t\t);\n\t\t\tname = FlashScope;\n\t\t\tsourceTree = "<group>";\n\t\t}};''')
groups.append(f'''\t\t{group_ids['resources']} /* Resources */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{assets_ref} /* Assets.xcassets */,\n\t\t\t\t{file_ref_ids['FlashScope/Resources/Info.plist']} /* Info.plist */,\n\t\t\t\t{file_ref_ids['FlashScope/Resources/FlashScope.entitlements']} /* FlashScope.entitlements */,\n\t\t\t);\n\t\t\tname = Resources;\n\t\t\tsourceTree = "<group>";\n\t\t}};''')
for key, label, paths in [("unit","FlashScopeCoreTests",unit_files),("integration","FlashScopeIntegrationTests",integration_files),("ui","FlashScopeUITests",ui_files)]:
    groups.append(f'''\t\t{group_ids[key]} /* {label} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{group_children(paths)}\n\t\t\t);\n\t\t\tname = {label};\n\t\t\tsourceTree = "<group>";\n\t\t}};''')
product_children = "\n".join(f"\t\t\t\t{product_ref_ids[k]} /* {products[k][0]} */," for k in ["app","core","unit","integration","ui"])
groups.append(f'''\t\t{group_ids['products']} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{product_children}\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = "<group>";\n\t\t}};''')

# Build phases.
phase_ids = {}
phase_objects: list[str] = []
for key in target_names:
    sid = oid(f"phase:sources:{key}")
    fid = oid(f"phase:frameworks:{key}")
    rid = oid(f"phase:resources:{key}")
    phase_ids[key] = (sid, fid, rid)
    source_entries = "\n".join(f"\t\t\t\t{build_file_ids[(key,p)]} /* {name_for(p)} in Sources */," for p in source_sets[key])
    framework_entries = ""
    if key == "app": framework_entries = f"\t\t\t\t{link_core_app} /* FlashScopeCore.framework in Frameworks */,"
    elif key == "unit": framework_entries = f"\t\t\t\t{link_core_unit} /* FlashScopeCore.framework in Frameworks */,"
    elif key == "integration": framework_entries = f"\t\t\t\t{link_core_integration} /* FlashScopeCore.framework in Frameworks */,"
    resource_entries = f"\t\t\t\t{assets_build} /* Assets.xcassets in Resources */," if key == "app" else ""
    phase_objects.append(f'''\t\t{sid} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{source_entries}\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};''')
    phase_objects.append(f'''\t\t{fid} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{framework_entries}\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};''')
    phase_objects.append(f'''\t\t{rid} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{resource_entries}\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};''')

# Target dependency proxies.
target_ids = {k: oid(f"target:{k}") for k in target_names}
dep_pairs = [("app","core"),("unit","core"),("integration","app"),("integration","core"),("ui","app")]
proxy_objects: list[str] = []
dep_objects: list[str] = []
dep_ids: dict[tuple[str,str], str] = {}
project_id = oid("project")
for consumer, provider in dep_pairs:
    proxy = oid(f"proxy:{consumer}:{provider}")
    dep = oid(f"dependency:{consumer}:{provider}")
    dep_ids[(consumer, provider)] = dep
    proxy_objects.append(f'''\t\t{proxy} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {project_id} /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {target_ids[provider]};\n\t\t\tremoteInfo = {target_names[provider]};\n\t\t}};''')
    dep_objects.append(f'''\t\t{dep} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {target_ids[provider]} /* {target_names[provider]} */;\n\t\t\ttargetProxy = {proxy} /* PBXContainerItemProxy */;\n\t\t}};''')

# Native targets.
target_objects: list[str] = []
product_types = {
    "core": "com.apple.product-type.framework",
    "app": "com.apple.product-type.application",
    "unit": "com.apple.product-type.bundle.unit-test",
    "integration": "com.apple.product-type.bundle.unit-test",
    "ui": "com.apple.product-type.bundle.ui-testing",
}
for key, name in target_names.items():
    sid, fid, rid = phase_ids[key]
    deps = [d for (c, _), d in dep_ids.items() if c == key]
    dep_lines = "\n".join(f"\t\t\t\t{d} /* PBXTargetDependency */," for d in deps)
    target_objects.append(f'''\t\t{target_ids[key]} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {oid('configlist:target:'+key)} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n\t\t\tbuildPhases = (\n\t\t\t\t{sid} /* Sources */,\n\t\t\t\t{fid} /* Frameworks */,\n\t\t\t\t{rid} /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{dep_lines}\n\t\t\t);\n\t\t\tname = {name};\n\t\t\tproductName = {name};\n\t\t\tproductReference = {product_ref_ids[key]} /* {products[key][0]} */;\n\t\t\tproductType = {q(product_types[key])};\n\t\t}};''')

# Build settings.
def settings(lines: list[tuple[str,str]], indent="\t\t\t\t") -> str:
    return "\n".join(f"{indent}{k} = {v};" for k,v in lines)

project_common = [
    ("ALWAYS_SEARCH_USER_PATHS", "NO"),
    ("CLANG_ENABLE_MODULES", "YES"),
    ("CLANG_ENABLE_OBJC_ARC", "YES"),
    ("MACOSX_DEPLOYMENT_TARGET", "14.0"),
    ("SDKROOT", "macosx"),
    ("SWIFT_VERSION", "6.0"),
]
project_debug = project_common + [("DEBUG_INFORMATION_FORMAT", "dwarf"), ("ENABLE_TESTABILITY", "YES"), ("ONLY_ACTIVE_ARCH", "YES"), ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", '"DEBUG $(inherited)"')]
project_release = project_common + [("DEBUG_INFORMATION_FORMAT", '"dwarf-with-dsym"'), ("SWIFT_COMPILATION_MODE", "wholemodule")]

app_common = [
    ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
    ("CODE_SIGN_ENTITLEMENTS", "FlashScope/Resources/FlashScope.entitlements"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "1"),
    ("ENABLE_HARDENED_RUNTIME", "YES"),
    ("GENERATE_INFOPLIST_FILE", "NO"),
    ("INFOPLIST_FILE", "FlashScope/Resources/Info.plist"),
    ("LD_RUNPATH_SEARCH_PATHS", '"$(inherited) @executable_path/../Frameworks"'),
    ("MARKETING_VERSION", "1.0.0"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "com.example.FlashScope"),
    ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
    ("SWIFT_EMIT_LOC_STRINGS", "YES"),
    ("SWIFT_STRICT_CONCURRENCY", "complete"),
    ("SWIFT_VERSION", "6.0"),
]
core_common = [
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "1"),
    ("DEFINES_MODULE", "YES"),
    ("DYLIB_COMPATIBILITY_VERSION", "1"),
    ("DYLIB_CURRENT_VERSION", "1"),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("MARKETING_VERSION", "1.0.0"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "com.example.FlashScopeCore"),
    ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
    ("SKIP_INSTALL", "YES"),
    ("SWIFT_STRICT_CONCURRENCY", "complete"),
    ("SWIFT_VERSION", "6.0"),
]
unit_common = [
    ("CODE_SIGN_STYLE", "Automatic"),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "com.example.FlashScopeCoreTests"),
    ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
    ("SWIFT_STRICT_CONCURRENCY", "complete"),
    ("SWIFT_VERSION", "6.0"),
]
integration_common = [
    ("BUNDLE_LOADER", '"$(TEST_HOST)"'),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "com.example.FlashScopeIntegrationTests"),
    ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
    ("SWIFT_STRICT_CONCURRENCY", "complete"),
    ("SWIFT_VERSION", "6.0"),
    ("TEST_HOST", '"$(BUILT_PRODUCTS_DIR)/FlashScope.app/Contents/MacOS/FlashScope"'),
]
ui_common = [
    ("CODE_SIGN_STYLE", "Automatic"),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "com.example.FlashScopeUITests"),
    ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
    ("SWIFT_STRICT_CONCURRENCY", "complete"),
    ("SWIFT_VERSION", "6.0"),
    ("TEST_TARGET_NAME", "FlashScope"),
]
per_target = {"app": app_common, "core": core_common, "unit": unit_common, "integration": integration_common, "ui": ui_common}
config_objects: list[str] = []
config_list_objects: list[str] = []

for variant, vals in [("Debug", project_debug), ("Release", project_release)]:
    cid = oid(f"config:project:{variant}")
    config_objects.append(f'''\t\t{cid} /* {variant} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings(vals)}\n\t\t\t}};\n\t\t\tname = {variant};\n\t\t}};''')
project_config_list = oid("configlist:project")
config_list_objects.append(f'''\t\t{project_config_list} /* Build configuration list for PBXProject \"FlashScope\" */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{oid('config:project:Debug')} /* Debug */,\n\t\t\t\t{oid('config:project:Release')} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};''')

for key, common in per_target.items():
    for variant in ["Debug", "Release"]:
        vals = list(common)
        if variant == "Debug": vals += [("ENABLE_TESTABILITY", "YES"), ("SWIFT_OPTIMIZATION_LEVEL", '"-Onone"')]
        else: vals += [("SWIFT_COMPILATION_MODE", "wholemodule")]
        cid = oid(f"config:target:{key}:{variant}")
        config_objects.append(f'''\t\t{cid} /* {variant} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings(vals)}\n\t\t\t}};\n\t\t\tname = {variant};\n\t\t}};''')
    clid = oid(f"configlist:target:{key}")
    config_list_objects.append(f'''\t\t{clid} /* Build configuration list for PBXNativeTarget \"{target_names[key]}\" */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{oid(f'config:target:{key}:Debug')} /* Debug */,\n\t\t\t\t{oid(f'config:target:{key}:Release')} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};''')

project_obj = f'''\t\t{project_id} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1600;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t\tTargetAttributes = {{\n\t\t\t\t\t{target_ids['app']} = {{ CreatedOnToolsVersion = 16.0; }};\n\t\t\t\t\t{target_ids['core']} = {{ CreatedOnToolsVersion = 16.0; }};\n\t\t\t\t\t{target_ids['unit']} = {{ CreatedOnToolsVersion = 16.0; }};\n\t\t\t\t\t{target_ids['integration']} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {target_ids['app']}; }};\n\t\t\t\t\t{target_ids['ui']} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {target_ids['app']}; }};\n\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"FlashScope\" */;\n\t\t\tcompatibilityVersion = "Xcode 15.0";\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (en, Base);\n\t\t\tmainGroup = {group_ids['main']};\n\t\t\tproductRefGroup = {group_ids['products']} /* Products */;\n\t\t\tprojectDirPath = "";\n\t\t\tprojectRoot = "";\n\t\t\ttargets = (\n\t\t\t\t{target_ids['app']} /* FlashScope */,\n\t\t\t\t{target_ids['core']} /* FlashScopeCore */,\n\t\t\t\t{target_ids['unit']} /* FlashScopeCoreTests */,\n\t\t\t\t{target_ids['integration']} /* FlashScopeIntegrationTests */,\n\t\t\t\t{target_ids['ui']} /* FlashScopeUITests */,\n\t\t\t);\n\t\t}};'''

sections = [
    ("PBXBuildFile", build_files),
    ("PBXContainerItemProxy", proxy_objects),
    ("PBXFileReference", file_refs),
    ("PBXFrameworksBuildPhase", [o for o in phase_objects if "PBXFrameworksBuildPhase" in o]),
    ("PBXGroup", groups),
    ("PBXNativeTarget", target_objects),
    ("PBXProject", [project_obj]),
    ("PBXResourcesBuildPhase", [o for o in phase_objects if "PBXResourcesBuildPhase" in o]),
    ("PBXSourcesBuildPhase", [o for o in phase_objects if "PBXSourcesBuildPhase" in o]),
    ("PBXTargetDependency", dep_objects),
    ("XCBuildConfiguration", config_objects),
    ("XCConfigurationList", config_list_objects),
]

out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {", ""]
for label, objects in sections:
    out.append(f"/* Begin {label} section */")
    out.extend(objects)
    out.append(f"/* End {label} section */")
    out.append("")
out += ["\t};", f"\trootObject = {project_id} /* Project object */;", "}", ""]
PROJECT_DIR.mkdir(parents=True, exist_ok=True)
PBXPROJ.write_text("\n".join(out))
print(f"Generated {PBXPROJ.relative_to(ROOT)} with {sum(map(len, source_sets.values()))} Swift sources")
