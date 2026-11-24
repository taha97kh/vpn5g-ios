#!/usr/bin/env python3
"""Regenerate vpn5g-ios.xcodeproj/project.pbxproj from the file lists below.

Run from the repo root:  python3 scripts/generate-project.py
IDs are deterministic (first 24 hex chars of sha1 of a stable key), so
re-running produces the same file. The script asserts referential
integrity (every referenced ID is defined exactly once) before writing.
No Xcode is needed to run this script.
"""

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def uid(key: str) -> str:
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()


# (relative path, build phase: sources | resources | none, target: app | tunnel | both)
APP_FILES = [
    ("VPN5G/VPN5GApp.swift", "sources", "app"),
    ("VPN5G/Config/AppConstants.swift", "sources", "both"),
    ("VPN5G/Config/SupabaseConfig.swift", "sources", "app"),
    ("VPN5G/Models/AppConfig.swift", "sources", "app"),
    ("VPN5G/Models/ServerConfig.swift", "sources", "app"),
    ("VPN5G/Models/Subscription.swift", "sources", "app"),
    ("VPN5G/Models/AdConfig.swift", "sources", "app"),
    ("VPN5G/Services/SupabaseAuth.swift", "sources", "app"),
    ("VPN5G/Services/ConfigSync.swift", "sources", "app"),
    ("VPN5G/Services/SingBoxConfigBuilder.swift", "sources", "app"),
    ("VPN5G/Services/TunnelManager.swift", "sources", "app"),
    ("VPN5G/Services/SubscriptionStore.swift", "sources", "app"),
    ("VPN5G/Services/AdManager.swift", "sources", "app"),
    ("VPN5G/Services/SpeedMonitor.swift", "sources", "app"),
    ("VPN5G/Views/StartupView.swift", "sources", "app"),
    ("VPN5G/Views/HomeView.swift", "sources", "app"),
    ("VPN5G/Views/PremiumView.swift", "sources", "app"),
    ("VPN5G/Views/LocationsView.swift", "sources", "app"),
    ("VPN5G/Views/ProfileView.swift", "sources", "app"),
    ("VPN5G/Views/AuthView.swift", "sources", "app"),
    ("VPN5G/Views/AdInterstitialView.swift", "sources", "app"),
    ("VPN5G/Views/Components.swift", "sources", "app"),
    ("VPN5G/Resources/Assets.xcassets", "resources", "app"),
    ("VPN5G/Resources/Localizable.strings", "resources", "app"),
    ("VPN5G/Info.plist", "none", "app"),
    ("VPN5G/VPN5G.entitlements", "none", "app"),
]
TUNNEL_FILES = [
    ("VPN5GTunnel/PacketTunnelProvider.swift", "sources", "tunnel"),
    ("VPN5GTunnel/LibboxPlatformInterface.swift", "sources", "tunnel"),
    ("VPN5GTunnel/SingBoxTrafficPoller.swift", "sources", "tunnel"),
    ("VPN5GTunnel/Info.plist", "none", "tunnel"),
    ("VPN5GTunnel/VPN5GTunnel.entitlements", "none", "tunnel"),
]
FRAMEWORKS = [
    ("NetworkExtension.framework", "System"),
    ("Libbox.xcframework", "core"),
]


def main() -> int:
    defined = {}

    def reg(kind: str, key: str) -> str:
        i = uid(f"{kind}:{key}")
        if i in defined and defined[i] != (kind, key):
            raise SystemExit(f"ID collision for {kind}:{key}")
        defined[i] = (kind, key)
        return i

    # Object ids
    project = reg("project", "VPN5G")
    app_target = reg("target", "app")
    tunnel_target = reg("target", "tunnel")
    app_product = reg("product", "app")
    tunnel_product = reg("product", "tunnel")
    main_group = reg("group", "root")
    products_group = reg("group", "products")
    frameworks_group = reg("group", "frameworks")
    app_group = reg("group", "VPN5G")
    tunnel_group = reg("group", "VPN5GTunnel")
    config_group = reg("group", "VPN5G/Config")
    models_group = reg("group", "VPN5G/Models")
    services_group = reg("group", "VPN5G/Services")
    views_group = reg("group", "VPN5G/Views")
    resources_group = reg("group", "VPN5G/Resources")
    project_config_list = reg("configlist", "project")
    app_config_list = reg("configlist", "app")
    tunnel_config_list = reg("configlist", "tunnel")
    proj_debug = reg("config", "project-debug")
    proj_release = reg("config", "project-release")
    app_debug = reg("config", "app-debug")
    app_release = reg("config", "app-release")
    tun_debug = reg("config", "tunnel-debug")
    tun_release = reg("config", "tunnel-release")
    app_sources = reg("phase", "app-sources")
    app_frameworks = reg("phase", "app-frameworks")
    app_resources = reg("phase", "app-resources")
    app_embed = reg("phase", "app-embed-extensions")
    tun_sources = reg("phase", "tunnel-sources")
    tun_frameworks = reg("phase", "tunnel-frameworks")
    tun_resources = reg("phase", "tunnel-resources")
    app_dep_tunnel = reg("targetdep", "app->tunnel")
    app_dep_proxy = reg("containerproxy", "app->tunnel")

    filerefs = {}
    buildfiles = {}
    for path, phase, _ in APP_FILES + TUNNEL_FILES:
        filerefs[path] = reg("fileref", path)
        if phase != "none":
            buildfiles[path] = reg("buildfile", path)
    # Files shared with the tunnel target ("both") get a second PBXBuildFile
    # (same fileRef, distinct id) — exactly what Xcode creates when a file
    # is added to a second target. One PBXBuildFile cannot be listed in two
    # build phases, so the tunnel phase uses this second entry.
    tun_buildfiles = {}
    for path, phase, target in APP_FILES:
        if phase != "none" and target == "both":
            tun_buildfiles[path] = reg("buildfile", path + "|tunnel")
    fw_refs = {}
    fw_build = {}
    for name, _ in FRAMEWORKS:
        fw_refs[name] = reg("fileref", f"fw:{name}")
        fw_build[name] = reg("buildfile", f"fw:{name}")

    def group_children(group_key, paths):
        return ",\n".join(f"\t\t\t\t{filerefs[p]} /* {os.path.basename(p)} */" for p in paths)

    app_paths = [p for p, _, _ in APP_FILES]
    tun_paths = [p for p, _, _ in TUNNEL_FILES]

    def subgroup(group_id, name, paths):
        kids = group_children(group_id, paths)
        return (f"\t\t{group_id} /* {name} */ = {{\n"
                "\t\t\tisa = PBXGroup;\n"
                "\t\t\tchildren = (\n"
                f"{kids},\n"
                "\t\t\t);\n"
                f"\t\t\tname = {name};\n"
                "\t\t\tsourceTree = \"<group>\";\n"
                "\t\t};\n")

    out = []
    out.append("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n")

    # PBXBuildFile
    for path, phase, target in APP_FILES + TUNNEL_FILES:
        if phase == "none":
            continue
        out.append(f"\t\t{buildfiles[path]} /* {os.path.basename(path)} in {'Sources' if phase == 'sources' else 'Resources'} */ = {{isa = PBXBuildFile; fileRef = {filerefs[path]} /* {os.path.basename(path)} */; }};\n")
    for path, bf in tun_buildfiles.items():
        out.append(f"\t\t{bf} /* {os.path.basename(path)} in Sources */ = {{isa = PBXBuildFile; fileRef = {filerefs[path]} /* {os.path.basename(path)} */; }};\n")
    for name, _ in FRAMEWORKS:
        out.append(f"\t\t{fw_build[name]} /* {name} in Frameworks */ = {{isa = PBXBuildFile; fileRef = {fw_refs[name]} /* {name} */; }};\n")

    # PBXFileReference
    def file_type(path):
        if path.endswith(".swift"):
            return "sourcecode.swift"
        if path.endswith(".plist"):
            return "text.plist.xml"
        if path.endswith(".entitlements"):
            return "text.plist.entitlements"
        if path.endswith(".xcassets"):
            return "folder.assetcatalog"
        if path.endswith(".strings"):
            return "text.plist.strings"
        if path.endswith(".framework"):
            return "wrapper.framework"
        if path.endswith(".xcframework"):
            return "wrapper.xcframework"
        return "text"

    for path, _, _ in APP_FILES + TUNNEL_FILES:
        out.append(f"\t\t{filerefs[path]} /* {os.path.basename(path)} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type(path)}; path = {path}; sourceTree = \"<group>\"; }};\n")
    out.append(f"\t\t{fw_refs['NetworkExtension.framework']} /* NetworkExtension.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = NetworkExtension.framework; path = System/Library/Frameworks/NetworkExtension.framework; sourceTree = SDKROOT; }};\n")
    out.append(f"\t\t{fw_refs['Libbox.xcframework']} /* Libbox.xcframework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; path = core/Libbox.xcframework; sourceTree = \"<group>\"; }};\n")
    out.append(f"\t\t{app_product} /* VPN5G.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = VPN5G.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    out.append(f"\t\t{tunnel_product} /* VPN5GTunnel.appex */ = {{isa = PBXFileReference; explicitFileType = wrapper.app-extension; includeInIndex = 0; path = VPN5GTunnel.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n")

    # PBXFrameworksBuildPhase
    out.append(f"\t\t{app_frameworks} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (\n\t\t\t\t{fw_build['NetworkExtension.framework']} /* NetworkExtension.framework in Frameworks */,\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};\n")
    out.append(f"\t\t{tun_frameworks} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (\n\t\t\t\t{fw_build['NetworkExtension.framework']} /* NetworkExtension.framework in Frameworks */,\n\t\t\t\t{fw_build['Libbox.xcframework']} /* Libbox.xcframework in Frameworks */,\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};\n")

    # PBXGroup
    out.append(subgroup(config_group, "Config", [p for p in app_paths if p.startswith("VPN5G/Config/")]))
    out.append(subgroup(models_group, "Models", [p for p in app_paths if p.startswith("VPN5G/Models/")]))
    out.append(subgroup(services_group, "Services", [p for p in app_paths if p.startswith("VPN5G/Services/")]))
    out.append(subgroup(views_group, "Views", [p for p in app_paths if p.startswith("VPN5G/Views/")]))
    out.append(subgroup(resources_group, "Resources", [p for p in app_paths if p.startswith("VPN5G/Resources/")]))
    app_top = [p for p in app_paths if p.startswith("VPN5G/") and p.count("/") == 1]
    out.append(f"\t\t{app_group} /* VPN5G */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
               f"\t\t\t\t{config_group} /* Config */,\n\t\t\t\t{models_group} /* Models */,\n\t\t\t\t{services_group} /* Services */,\n\t\t\t\t{views_group} /* Views */,\n\t\t\t\t{resources_group} /* Resources */,\n"
               + "".join(f"\t\t\t\t{filerefs[p]} /* {os.path.basename(p)} */,\n" for p in app_top)
               + "\t\t\t);\n\t\t\tpath = VPN5G;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n")
    out.append(subgroup(tunnel_group, "VPN5GTunnel", tun_paths))
    out.append(f"\t\t{frameworks_group} /* Frameworks */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{fw_refs['NetworkExtension.framework']} /* NetworkExtension.framework */,\n\t\t\t\t{fw_refs['Libbox.xcframework']} /* Libbox.xcframework */,\n\t\t\t);\n\t\t\tname = Frameworks;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    out.append(f"\t\t{products_group} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{app_product} /* VPN5G.app */,\n\t\t\t\t{tunnel_product} /* VPN5GTunnel.appex */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    out.append(f"\t\t{main_group} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{app_group} /* VPN5G */,\n\t\t\t\t{tunnel_group} /* VPN5GTunnel */,\n\t\t\t\t{frameworks_group} /* Frameworks */,\n\t\t\t\t{products_group} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")

    # PBXNativeTarget
    def target_block(tid, name, product_type, product, phases, config_list, deps=()):
        ph = ",\n".join(f"\t\t\t\t{p} /* {n} */" for p, n in phases)
        dep_lines = "".join(f"\t\t\t\t{d} /* PBXTargetDependency */,\n" for d in deps)
        return (f"\t\t{tid} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
                f"\t\t\tbuildConfigurationList = {config_list} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n"
                f"\t\t\tbuildPhases = (\n{ph},\n\t\t\t);\n"
                f"\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{dep_lines}\t\t\t);\n"
                f"\t\t\tname = {name};\n\t\t\tproductName = {name};\n"
                f"\t\t\tproductReference = {product} /* {name}.{'app' if name == 'VPN5G' else 'appex'} */;\n"
                f"\t\t\tproductType = \"{product_type}\";\n\t\t}};\n")

    out.append(target_block(app_target, "VPN5G", "com.apple.product-type.application", app_product,
                            [(app_sources, "Sources"), (app_frameworks, "Frameworks"), (app_resources, "Resources"), (app_embed, "Embed App Extensions")], app_config_list, deps=(app_dep_tunnel,)))
    out.append(target_block(tunnel_target, "VPN5GTunnel", "com.apple.product-type.app-extension", tunnel_product,
                            [(tun_sources, "Sources"), (tun_frameworks, "Frameworks"), (tun_resources, "Resources")], tunnel_config_list))

    # PBXTargetDependency + PBXContainerItemProxy (app embeds the tunnel)
    out.append(f"\t\t{app_dep_tunnel} /* PBXTargetDependency */ = {{isa = PBXTargetDependency; target = {tunnel_target} /* VPN5GTunnel */; targetProxy = {app_dep_proxy} /* PBXContainerItemProxy */; }};\n")
    out.append(f"\t\t{app_dep_proxy} /* PBXContainerItemProxy */ = {{isa = PBXContainerItemProxy; containerPortal = {project} /* Project object */; proxyType = 1; remoteGlobalIDString = {tunnel_target}; remoteInfo = VPN5GTunnel; }};\n")

    # PBXProject
    out.append(f"\t\t{project} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n"
               f"\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t\tTargetAttributes = {{\n"
               f"\t\t\t\t\t{app_target} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n"
               f"\t\t\t\t\t{tunnel_target} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n\t\t\t\t}};\n\t\t\t}};\n"
               f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"vpn5g-ios\" */;\n"
               f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n\t\t\tdevelopmentRegion = fa;\n"
               f"\t\t\tisTemplate = 0;\n\t\t\tmainGroup = {main_group};\n"
               f"\t\t\tproductRefGroup = {products_group} /* Products */;\n\t\t\tprojectDirPath = \"\";\n"
               f"\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n\t\t\t\t{app_target} /* VPN5G */,\n\t\t\t\t{tunnel_target} /* VPN5GTunnel */,\n\t\t\t);\n\t\t}};\n")

    # PBXResourcesBuildPhase / PBXSourcesBuildPhase / PBXCopyFilesBuildPhase
    def files_list(paths, phase_name, bfmap=None):
        bfmap = bfmap if bfmap is not None else buildfiles
        return ",\n".join(f"\t\t\t\t{bfmap[p]} /* {os.path.basename(p)} in {phase_name} */" for p in paths)

    app_src = [p for p, ph, _ in APP_FILES if ph == "sources"]
    app_res = [p for p, ph, _ in APP_FILES if ph == "resources"]
    tun_src = [p for p, ph, _ in TUNNEL_FILES if ph == "sources"] + \
              [p for p, ph, t in APP_FILES if ph == "sources" and t == "both"]
    tun_bfmap = {**buildfiles, **tun_buildfiles}
    out.append(f"\t\t{app_sources} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\n{files_list(app_src, 'Sources')},\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};\n")
    out.append(f"\t\t{tun_sources} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\n{files_list(tun_src, 'Sources', tun_bfmap)},\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};\n")
    out.append(f"\t\t{app_resources} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (\n{files_list(app_res, 'Resources')},\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};\n")
    out.append(f"\t\t{tun_resources} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};\n")
    out.append(f"\t\t{app_embed} /* Embed App Extensions */ = {{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = \"\"; dstSubfolderSpec = 13; files = (\n\t\t\t\t{reg('embedfile', 'tunnel')} /* VPN5GTunnel.appex in Embed App Extensions */,\n\t\t\t); name = \"Embed App Extensions\"; runOnlyForDeploymentPostprocessing = 0; }};\n")

    # PBXCopyFilesBuildPhase build file for the embedded appex
    out.append(f"\t\t{reg('embedfile', 'tunnel')} /* VPN5GTunnel.appex in Embed App Extensions */ = {{isa = PBXBuildFile; fileRef = {tunnel_product} /* VPN5GTunnel.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")

    # XCBuildConfiguration
    def config_block(cid, name, settings):
        body = "\n".join(f"\t\t\t\t{k} = {v};" for k, v in settings.items())
        return f"\t\t{cid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{body}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n"

    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CODE_SIGN_STYLE": "Automatic",
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
        "LOCALIZATION_PREFS": "fa",
        "MARKETING_VERSION": "1.0.0",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1"',
    }
    out.append(config_block(proj_debug, "Debug", {**common, "DEBUG_INFORMATION_FORMAT": "dwarf", "MTL_ENABLE_DEBUG_INFO": "YES", "SWIFT_COMPILATION_MODE": "singlefile", "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"'}))
    out.append(config_block(proj_release, "Release", common))
    out.append(config_block(app_debug, "Debug", {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": "VPN5G/VPN5G.entitlements",
        "CURRENT_PROJECT_VERSION": "1",
                "INFOPLIST_FILE": "VPN5G/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        "PRODUCT_BUNDLE_IDENTIFIER": "com.taha97kh.vpn5g",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMBED_LIBRARIES_WITH_INSTALL": "YES",
    }))
    out.append(config_block(app_release, "Release", {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": "VPN5G/VPN5G.entitlements",
        "CURRENT_PROJECT_VERSION": "1",
                "INFOPLIST_FILE": "VPN5G/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        "PRODUCT_BUNDLE_IDENTIFIER": "com.taha97kh.vpn5g",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMBED_LIBRARIES_WITH_INSTALL": "YES",
    }))
    out.append(config_block(tun_debug, "Debug", {
        "CODE_SIGN_ENTITLEMENTS": "VPN5GTunnel/VPN5GTunnel.entitlements",
        "CURRENT_PROJECT_VERSION": "1",
                "INFOPLIST_FILE": "VPN5GTunnel/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/../../Frameworks"',
        "PRODUCT_BUNDLE_IDENTIFIER": "com.taha97kh.vpn5g.PacketTunnel",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SKIP_INSTALL": "YES",
        "SWIFT_EMBED_LIBRARIES_WITH_INSTALL": "YES",
    }))
    out.append(config_block(tun_release, "Release", {
        "CODE_SIGN_ENTITLEMENTS": "VPN5GTunnel/VPN5GTunnel.entitlements",
        "CURRENT_PROJECT_VERSION": "1",
                "INFOPLIST_FILE": "VPN5GTunnel/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/../../Frameworks"',
        "PRODUCT_BUNDLE_IDENTIFIER": "com.taha97kh.vpn5g.PacketTunnel",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SKIP_INSTALL": "YES",
        "SWIFT_EMBED_LIBRARIES_WITH_INSTALL": "YES",
    }))

    # XCConfigurationList
    def config_list_block(cid, name, debug_id, release_id):
        return (f"\t\t{cid} /* Build configuration list for PBXProject \"vpn5g-ios\" */ = {{\n"
                f"\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
                f"\t\t\t\t{debug_id} /* Debug */,\n\t\t\t\t{release_id} /* Release */,\n\t\t\t);\n"
                f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")

    out.append(config_list_block(project_config_list, "project", proj_debug, proj_release))
    out.append(config_list_block(app_config_list, "app", app_debug, app_release))
    out.append(config_list_block(tunnel_config_list, "tunnel", tun_debug, tun_release))

    out.append("\t};\n")
    out.append(f"\trootObject = {project} /* Project object */;\n")
    out.append("}\n")

    text = "".join(out)
    # Referential integrity: every 24-hex token referenced must be defined.
    import re
    tokens = set(re.findall(r"\b[0-9A-F]{24}\b", text))
    missing = tokens - set(defined)
    if missing:
        raise SystemExit(f"Missing object definitions for IDs: {sorted(missing)}")

    dest = os.path.join(ROOT, "vpn5g-ios.xcodeproj", "project.pbxproj")
    with open(dest, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"Wrote {dest} ({len(text)} bytes, {len(defined)} objects)")


if __name__ == "__main__":
    sys.exit(main())
