#!/usr/bin/env python3
"""Write YourMark.xcodeproj: app + bundled MarkItDown. Archive with AppStore.

Share stays in Sources/ and in the GitHub disk (build-app.sh). The first Store
upload omits it: Apple will not let automatic signing add App Groups to the
existing com.burbank.yourmark App ID from the CLI.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = sorted((ROOT / "Sources" / "YourMark").glob("*.swift"))
RESOURCE_NAMES = [
    "pdf_enrich.py",
    "markitdown_convert.py",
    "PrivacyInfo.xcprivacy",
    "AppIcon.png",
    "AppIcon.icns",
]


def uid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


IDS = {
    "proj": uid("proj"),
    "target": uid("target:yourMark"),
    "group_root": uid("group:root"),
    "group_src": uid("group:YourMark"),
    "group_res": uid("group:Resources"),
    "group_prod": uid("group:Products"),
    "product": uid("ref:yourMark.app"),
    "info_mas": uid("ref:Info-mas.plist"),
    "ent_mas": uid("ref:YourMark.mas.entitlements"),
    "ent_direct": uid("ref:YourMark.direct.entitlements"),
    "sources": uid("phase:sources"),
    "copy_res": uid("phase:copy-resources"),
    "copy_engine": uid("phase:copy-engine"),
    "frameworks": uid("phase:frameworks"),
    "cfg_t": uid("cfglist:target"),
    "cfg_p": uid("cfglist:project"),
    "debug_t": uid("cfg:debug-t"),
    "release_t": uid("cfg:release-t"),
    "store_t": uid("cfg:store-t"),
    "debug_p": uid("cfg:debug-p"),
    "release_p": uid("cfg:release-p"),
    "store_p": uid("cfg:store-p"),
}

file_ids = {p.name: uid(f"ref:{p.name}") for p in SOURCES}
build_ids = {p.name: uid(f"build:{p.name}") for p in SOURCES}
res_ids = {name: uid(f"ref:res:{name}") for name in RESOURCE_NAMES}
res_build = {name: uid(f"build:res:{name}") for name in RESOURCE_NAMES}
existing_resources = [n for n in RESOURCE_NAMES if (ROOT / "Resources" / n).exists()]


def lines(items) -> str:
    return "\n".join(items)


file_refs = lines(
    f'\t\t{file_ids[p.name]} /* {p.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {p.name}; sourceTree = "<group>"; }};'
    for p in SOURCES
)
build_files = lines(
    f"\t\t{build_ids[p.name]} /* {p.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ids[p.name]} /* {p.name} */; }};"
    for p in SOURCES
)
group_children = lines(f"\t\t\t\t{file_ids[p.name]} /* {p.name} */," for p in SOURCES)
source_builds = lines(f"\t\t\t\t{build_ids[p.name]} /* {p.name} in Sources */," for p in SOURCES)
res_types = {".py": "text.script.python", ".png": "image.png", ".icns": "image.icns", ".xcprivacy": "text.xml"}
res_refs = lines(
    f'\t\t{res_ids[n]} /* {n} */ = {{isa = PBXFileReference; lastKnownFileType = {res_types[Path(n).suffix]}; path = {n}; sourceTree = "<group>"; }};'
    for n in existing_resources
)
res_builds = lines(
    f"\t\t{res_build[n]} /* {n} in Resources */ = {{isa = PBXBuildFile; fileRef = {res_ids[n]} /* {n} */; }};"
    for n in existing_resources
)
res_group = lines(f"\t\t\t\t{res_ids[n]} /* {n} */," for n in existing_resources)
res_phase = lines(f"\t\t\t\t{res_build[n]} /* {n} in Resources */," for n in existing_resources)

direct_target = """
				CODE_SIGN_ENTITLEMENTS = Resources/YourMark.direct.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 66;
				DEVELOPMENT_TEAM = R4SB7G9A32;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = yourMark;
				INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.productivity;
				INFOPLIST_KEY_LSMinimumSystemVersion = 14.0;
				INFOPLIST_KEY_NSHighResolutionCapable = YES;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 0.5.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.burbank.yourmark;
				PRODUCT_NAME = yourMark;
				SDKROOT = macosx;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 6.0;
"""

store_target = """
				CODE_SIGN_ENTITLEMENTS = Resources/YourMark.mas.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 66;
				DEVELOPMENT_TEAM = R4SB7G9A32;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = "Resources/Info-mas.plist";
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 0.5.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.burbank.yourmark;
				PRODUCT_NAME = yourMark;
				PROVISIONING_PROFILE_SPECIFIER = "";
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "APPSTORE $(inherited)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 6.0;
"""

engine_script = r"""set -euo pipefail
if [ "${CONFIGURATION}" != "AppStore" ]; then
  echo "note: skip MarkItDown bundle for ${CONFIGURATION}"
  exit 0
fi
ENGINE="${SRCROOT}/Resources/BundledEngine"
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/python"
if [ ! -x "${ENGINE}/bin/python3" ] && [ ! -x "${ENGINE}/bin/python3.12" ]; then
  echo "error: Resources/BundledEngine is missing. Run Scripts/bundle-engine.sh first." >&2
  exit 1
fi
echo "note: copying bundled MarkItDown into the app"
rm -rf "${DEST}"
ditto --norsrc --noextattr --noqtn "${ENGINE}" "${DEST}"
IDENT="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "${IDENT}" ]; then IDENT="${CODE_SIGN_IDENTITY:-}"; fi
chmod +x "${SRCROOT}/Scripts/sign-nested-python.sh"
"${SRCROOT}/Scripts/sign-nested-python.sh" "${DEST}" "${IDENT}"
"""
engine_escaped = engine_script.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
I = IDS

pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

{build_files}
{res_builds}

/* Begin PBXCopyFilesBuildPhase section */
		{I["copy_res"]} /* Copy Resources */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 7;
			files = (
{res_phase}
			);
			name = "Copy Resources";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		{I["product"]} /* yourMark.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = yourMark.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I["info_mas"]} /* Info-mas.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Info-mas.plist"; sourceTree = "<group>"; }};
		{I["ent_mas"]} /* YourMark.mas.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = YourMark.mas.entitlements; sourceTree = "<group>"; }};
		{I["ent_direct"]} /* YourMark.direct.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = YourMark.direct.entitlements; sourceTree = "<group>"; }};
{file_refs}
{res_refs}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{I["frameworks"]} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I["group_root"]} = {{
			isa = PBXGroup;
			children = (
				{I["group_src"]} /* YourMark */,
				{I["group_res"]} /* Resources */,
				{I["group_prod"]} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I["group_src"]} /* YourMark */ = {{
			isa = PBXGroup;
			children = (
{group_children}
			);
			name = YourMark;
			path = Sources/YourMark;
			sourceTree = "<group>";
		}};
		{I["group_res"]} /* Resources */ = {{
			isa = PBXGroup;
			children = (
{res_group}
				{I["info_mas"]} /* Info-mas.plist */,
				{I["ent_mas"]} /* YourMark.mas.entitlements */,
				{I["ent_direct"]} /* YourMark.direct.entitlements */,
			);
			path = Resources;
			sourceTree = "<group>";
		}};
		{I["group_prod"]} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I["product"]} /* yourMark.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I["target"]} /* yourMark */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I["cfg_t"]} /* Build configuration list for PBXNativeTarget "yourMark" */;
			buildPhases = (
				{I["sources"]} /* Sources */,
				{I["frameworks"]} /* Frameworks */,
				{I["copy_res"]} /* Copy Resources */,
				{I["copy_engine"]} /* Bundle MarkItDown */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = yourMark;
			productName = yourMark;
			productReference = {I["product"]} /* yourMark.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I["proj"]} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
			}};
			buildConfigurationList = {I["cfg_p"]} /* Build configuration list for PBXProject "YourMark" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {I["group_root"]};
			productRefGroup = {I["group_prod"]} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I["target"]} /* yourMark */,
			);
		}};
/* End PBXProject section */

/* Begin PBXShellScriptBuildPhase section */
		{I["copy_engine"]} /* Bundle MarkItDown */ = {{
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
			);
			name = "Bundle MarkItDown";
			outputFileListPaths = (
			);
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/zsh;
			shellScript = "{engine_escaped}";
		}};
/* End PBXShellScriptBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I["sources"]} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{source_builds}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{I["debug_p"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{I["release_p"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
			}};
			name = Release;
		}};
		{I["store_p"]} /* AppStore */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "APPSTORE $(inherited)";
				SWIFT_COMPILATION_MODE = wholemodule;
			}};
			name = AppStore;
		}};
		{I["debug_t"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{direct_target}
			}};
			name = Debug;
		}};
		{I["release_t"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{direct_target}
			}};
			name = Release;
		}};
		{I["store_t"]} /* AppStore */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{store_target}
			}};
			name = AppStore;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{I["cfg_p"]} /* Build configuration list for PBXProject "YourMark" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I["debug_p"]} /* Debug */,
				{I["release_p"]} /* Release */,
				{I["store_p"]} /* AppStore */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I["cfg_t"]} /* Build configuration list for PBXNativeTarget "yourMark" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I["debug_t"]} /* Debug */,
				{I["release_t"]} /* Release */,
				{I["store_t"]} /* AppStore */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {I["proj"]} /* Project object */;
}}
"""

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{I["target"]}"
               BuildableName = "yourMark.app"
               BlueprintName = "yourMark"
               ReferencedContainer = "container:YourMark.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{I["target"]}"
            BuildableName = "yourMark.app"
            BlueprintName = "yourMark"
            ReferencedContainer = "container:YourMark.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{I["target"]}"
            BuildableName = "yourMark.app"
            BlueprintName = "yourMark"
            ReferencedContainer = "container:YourMark.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "AppStore"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

out = ROOT / "YourMark.xcodeproj"
out.mkdir(exist_ok=True)
(out / "project.pbxproj").write_text(pbx)
schemes = out / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / "yourMark.xcscheme").write_text(scheme)
print(f"Wrote {out / 'project.pbxproj'} ({len(SOURCES)} Swift files, {len(existing_resources)} resources, no Share)")
