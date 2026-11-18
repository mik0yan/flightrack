#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project from the checked-in Swift sources."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "SkyLens.xcodeproj"

def identifier(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

def existing_signing_settings(project_file):
    """Keep Xcode's per-target signing choices when regenerating source entries."""
    if not project_file.exists():
        return {}
    try:
        # plutil reads OpenStep project files, including Xcode's comments and
        # multiline formatting. Regex extraction can confuse project and target
        # configurations, which are both named Debug/Release.
        converted = subprocess.run(
            ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(project_file)],
            check=True, capture_output=True, text=True,
        )
        project_objects = json.loads(converted.stdout)["objects"]
        preserved = {}
        for target_id, target in project_objects.items():
            if target.get("isa") != "PBXNativeTarget":
                continue
            config_list = project_objects[target["buildConfigurationList"]]
            for config_id in config_list["buildConfigurations"]:
                configuration = project_objects[config_id]
                name = configuration["name"]
                if name not in ("Debug", "Release"):
                    continue
                settings = configuration.get("buildSettings", {})
                signing = {
                    key: settings[key]
                    for key in ("DEVELOPMENT_TEAM", "PRODUCT_BUNDLE_IDENTIFIER")
                    if key in settings
                }
                if any(not isinstance(value, str) for value in signing.values()):
                    raise ValueError("Signing settings must be strings")
                # Stable object IDs retain choices after a target rename. Names
                # also match projects whose IDs have been changed by Xcode.
                preserved[(target_id, name)] = signing
                preserved[(target["name"], name)] = signing
        return preserved
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError, AttributeError) as error:
        raise SystemExit(
            f"Cannot read signing settings from {project_file}; existing project was not regenerated: {error}"
        ) from error

preserved_signing = existing_signing_settings(PROJECT / "project.pbxproj")
PROJECT.mkdir(exist_ok=True)

objects = []
def obj(key, value):
    objects.append(f"\t\t{identifier(key)} = {{ {value} }};")

def ids(values):
    return "(" + ", ".join(identifier(value) for value in values) + ",)"

sources = sorted(ROOT.glob("FlightTrack/**/*.swift"))
source_keys = []
file_keys = []
for path in sources:
    relative = path.relative_to(ROOT).as_posix()
    file_key, build_key = "file:" + relative, "build:" + relative
    obj(file_key, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(relative)}; sourceTree = SOURCE_ROOT;")
    obj(build_key, f"isa = PBXBuildFile; fileRef = {identifier(file_key)};")
    source_keys.append(build_key)
    file_keys.append(file_key)

obj("assets", "isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = FlightTrack/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;")
obj("assets-build", f"isa = PBXBuildFile; fileRef = {identifier('assets')};")
obj("info", "isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = FlightTrack/Resources/Info.plist; sourceTree = SOURCE_ROOT;")
obj("readme", "isa = PBXFileReference; lastKnownFileType = net.daringfireball.markdown; path = README.md; sourceTree = SOURCE_ROOT;")
obj("product", "isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SkyLens.app; sourceTree = BUILT_PRODUCTS_DIR;")
obj("products", f"isa = PBXGroup; children = {ids(['product'])}; name = Products; sourceTree = \"<group>\";")
obj("main-group", f"isa = PBXGroup; children = {ids(file_keys + ['assets', 'info', 'readme', 'products'])}; sourceTree = \"<group>\";")
obj("sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {ids(source_keys)}; runOnlyForDeploymentPostprocessing = 0;")
obj("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {ids(['assets-build'])}; runOnlyForDeploymentPostprocessing = 0;")
obj("frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")

project_settings = {
    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
}
target_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "52AJW92F8Y",
    "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "FlightTrack/Resources/Info.plist",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.xiaonewmi.skylens", "PRODUCT_NAME": "SkyLens",
    "MARKETING_VERSION": "1.0.0", "CURRENT_PROJECT_VERSION": "1",
    "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}
for scope, settings in [("project", project_settings), ("target", target_settings)]:
    for name in ["Debug", "Release"]:
        configured = dict(settings)
        if scope == "target":
            configured.update(preserved_signing.get(
                (identifier("target"), name), preserved_signing.get(("SkyLens", name), {})
            ))
        configured["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if name == "Debug" else "-O"
        configured["DEBUG_INFORMATION_FORMAT"] = "dwarf" if name == "Debug" else "dwarf-with-dsym"
        if name == "Debug":
            configured["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
        body = " ".join(f"{key} = {quote(value)};" for key, value in sorted(configured.items()))
        obj(f"{scope}-{name}", f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {name};")
    obj(f"{scope}-configs", f"isa = XCConfigurationList; buildConfigurations = {ids([scope+'-Debug', scope+'-Release'])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

obj("target", f"isa = PBXNativeTarget; buildConfigurationList = {identifier('target-configs')}; buildPhases = {ids(['sources', 'frameworks', 'resources'])}; buildRules = (); dependencies = (); name = SkyLens; productName = SkyLens; productReference = {identifier('product')}; productType = \"com.apple.product-type.application\";")
obj("project", f"isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; TargetAttributes = {{ {identifier('target')} = {{ CreatedOnToolsVersion = 27.0; }}; }}; }}; buildConfigurationList = {identifier('project-configs')}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = (\"zh-Hans\", en, Base); mainGroup = {identifier('main-group')}; productRefGroup = {identifier('products')}; projectDirPath = \"\"; projectRoot = \"\"; targets = {ids(['target'])};")

pbx = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {identifier('project')};\n}}\n"
(PROJECT / "project.pbxproj").write_text(pbx)
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier("target")}" BuildableName="SkyLens.app" BlueprintName="SkyLens" ReferencedContainer="container:SkyLens.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(scheme_dir / "SkyLens.xcscheme").write_text(scheme)
print(f"Generated {PROJECT.name}: {len(sources)} Swift files")
