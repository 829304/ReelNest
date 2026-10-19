# ReelNest Windows libmpv runtime

This directory documents the pinned Windows x64 libmpv runtime used by ReelNest. It is a third-party binary dependency, separate from ReelNest's Apache-2.0 source license. This file is a source/build/notice record, not a legal opinion or a declaration that distribution obligations are already complete.

## Scope and integration

- Applies to the Windows x64 desktop build only. macOS and Linux keep their platform-provided media-kit/libmpv arrangements.
- ReelNest pins one `libmpv-2.dll` and uses that same DLL for the Dart libmpv API and the C++ Flutter texture plugin. The Windows build replaces only `libmpv-2.dll` in `PLUGIN_BUNDLED_LIBRARIES`; it does not overwrite media-kit's import library or headers and does not modify PubCache. See [`apps/client/windows/mpv_runtime.cmake`](../../apps/client/windows/mpv_runtime.cmake).
- CMake installs this directory into the Windows bundle at `data/third_party/mpv`; the bundled license/copyright texts therefore travel with the runtime. These texts do not yet constitute notices for every actual linked dependency.
- Keep the archive, DLL and source identities pinned by exact version and SHA-256. Do not silently switch to a floating `latest` URL or auto-update to a new upstream build. A runtime update requires updating the reviewed hashes and this document together with its evidence.
- The pinned archive contains `libmpv-2.dll`, `libmpv.dll.a` and mpv client/render headers. It does not contain license texts, third-party notices or corresponding source.

## Pinned binary and provenance

| Item | Pinned value |
|---|---|
| Upstream project | [zhongfly/mpv-winbuild](https://github.com/zhongfly/mpv-winbuild) |
| Release | [`2026-10-16-a2cd83c56d`](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-10-16-a2cd83c56d) |
| Archive | [`mpv-dev-lgpl-x86_64-20261016-git-a2cd83c56d.7z`](https://github.com/zhongfly/mpv-winbuild/releases/download/2026-10-16-a2cd83c56d/mpv-dev-lgpl-x86_64-20261016-git-a2cd83c56d.7z) |
| Archive SHA-256 | `63baee08e7a242952aa9a78a6bd172aaf3a2654cdb64361687c9d139e46fefcf` |
| Runtime DLL SHA-256 | `22a7cb13ded0a6e80137661f5321de9a43c586780e798e46c39d3395488ece5f` |
| Build workflow | [GitHub Actions run 38897527900](https://github.com/zhongfly/mpv-winbuild/actions/runs/38897527900), repository revision `8a39c5134b8e16f104ee56a5d85e36a592ad9477` |
| mpv source | `v0.41.0-1186-ga2cd83c56`, upstream commit `a2cd83c56d` |
| FFmpeg source | `N-127579-g5cb9fcd21`; the captured `configuration.json` has `ffmpeg-configuration: null`, so the final FFmpeg configure flags still need to be obtained from the build logs/configuration output |

Source references: [mpv pinned commit](https://github.com/mpv-player/mpv/tree/a2cd83c56d), [FFmpeg pinned commit](https://github.com/FFmpeg/FFmpeg/tree/5cb9fcd21), and the [Zhongfly LGPL build patch pinned to workflow revision](https://github.com/zhongfly/mpv-winbuild/blob/8a39c5134b8e16f104ee56a5d85e36a592ad9477/compile-lgpl-libmpv.patch). For release reproducibility, retain source snapshots rather than depending only on these remote links.

The archive hash has been checked against the upstream Actions artifact digest and the isolated local archive. The DLL hash is pinned independently by the Windows CMake script. Recompute both values when preparing release inputs; do not infer the DLL digest from the archive digest.

The upstream README says only builds from the last 30 days are retained. This creates a release reproducibility risk: the pinned download may disappear even though the source tag remains documented. Before formal release, retain the exact archive, extracted DLL, matching source snapshots, build patch/scripts, and license/notice materials in a persistent project-controlled release/dependency location. Keep the archive and sources together with their hashes. This is release preparation; this document does not create or upload a mirror.

### Download/cache preparation evidence

A fresh-cache large-file network download probe was not successful in the observed network conditions: `curl` returned status 56 and a .NET request ended with EOF, while a small checksum request returned HTTP 200. This demonstrates interruption on that probe, not a bad pin or checksum. Do not claim that a cold-cache network download succeeded.

`apps/client/windows/mpv_runtime.cmake` makes up to three attempts for the exact pinned archive URL, keeps TLS verification enabled, and accepts a download only after the archive SHA-256 matches. Extraction occurs only after that match, then the extracted DLL SHA-256 is checked; failure after retries or either mismatch is fatal. There is no floating-`latest` fallback and no PowerShell download alternative. An independent CMake run with the already verified archive manually placed in a new cache validated archive checking, extraction, DLL checking, and preservation of unrelated DLLs. This verifies the populated-cache path, not cold-cache network download success.

## Build configuration and filter evidence

The captured `configuration.json` reports the following mpv/Meson options (build-agent prefix and generated cross-file paths omitted):

```text
-Dgpl=false
-Ddefault_library=shared
-Dprefer_static=true
-Ddebug=true
-Db_ndebug=true
-Doptimization=3
-Db_lto=true
-Db_lto_mode=thin
-Dcplayer=false
-Dlibmpv=true
-Dpdf-build=disabled
-Dlua=enabled
-Djavascript=enabled
-Dsdl2-gamepad=enabled
-Dlibarchive=enabled
-Dlibbluray=enabled
-Ddvdnav=disabled
-Duchardet=enabled
-Drubberband=disabled
-Dlcms2=enabled
-Dopenal=disabled
-Dspirv-cross=enabled
-Dvulkan=enabled
-Dvapoursynth=enabled
-Dsubrandr=enabled
-Dsixel=enabled
-Dgl=enabled
-Degl-angle=enabled
-Dlibcurl=enabled
-Dc_args=-Wno-error=int-conversion
--cross-file=<generated MinGW cross-file>
```

The upstream [LGPL build patch at the workflow revision](https://github.com/zhongfly/mpv-winbuild/blob/8a39c5134b8e16f104ee56a5d85e36a592ad9477/compile-lgpl-libmpv.patch) removes FFmpeg's `--enable-gpl` and removes x264, x265, davs2, Avisynth, DVDNav/DVDRead, Rubber Band and libzvbi FFmpeg dependencies/enablement; it also disables LZO in libarchive. `--enable-version3` remains in the FFmpeg recipe. The patch does not disable all FFmpeg filters. However, because the captured FFmpeg configuration field is null, the exact final FFmpeg configure flags and linked library set have not yet been independently recorded.

Isolated headless testing of this pinned DLL reports `hflip`, `vflip` and the combined mirror chain working. The subsequent Windows Profile texture test passed the five display controls; changing the deinterlace property to `auto` was checked, then changing it to `on` produced `deinterlace-active=yes`. This does not establish that mpv selected the software `bwdif` filter rather than VO deinterlacing, nor prove every playback/render path.

### Unsharp and hqdn3d runtime probe (2026-10-18)

An isolated native probe against the current pinned Windows LGPL runtime successfully set and read back the four `unsharp` mode structures used by ReelNest (`off`, `light`, `medium`, `strong`). This establishes option acceptance and structure readback only, not rendered sharpening behavior. See the [sharpen and filter-chain plan](../../docs/PLAYER_VIDEO_SHARPEN_PLAN.zh-CN.md) for implementation and validation status.

The same runtime rejected `hqdn3d` with `Option vf-add: 'hqdn3d' isn't supported`; no denoise filter was applied and no denoised output was produced. This records runtime behavior only and does not change the pinned runtime identification, hashes, configuration evidence, bundled license materials, or project license conclusions. The captured FFmpeg configuration is still `null`, so this probe is not evidence that the full FFmpeg configure/link closure has been reviewed.

## License and redistribution boundary

The upstream README declares `mpv-dev-lgpl` as libmpv under LGPL-2.1-or-later and says it statically links FFmpeg under LGPLv3. It also says the maintainer is not a lawyer and cannot guarantee that every LGPL-incompatible package has been disabled. The upstream repository's own MIT license covers that build repository, not the binary's complete license set.

The included [`mpv-Copyright`](mpv-Copyright) explains that `-Dgpl=false` is a build convenience, not itself a license grant: mpv can be LGPL only when no GPL-only source is used, and linked libraries (including FFmpeg) can affect the resulting binary's license. The pinned build patch removes several known GPL-enabling FFmpeg libraries, but build flags and package names alone do not prove the exact static-link closure. The generic upstream package list still names GPL components such as `libdvdcss`; that list is not an artifact-level bill of materials, and the pinned archive does not ship a separate `libdvdcss` binary. Confirm from the exact build logs and link evidence whether any such component is linked into `libmpv-2.dll` before release.

License texts currently kept beside this document:

- [`LICENSE.LGPL-2.1`](LICENSE.LGPL-2.1)
- [`LICENSE.LGPL-3.0`](LICENSE.LGPL-3.0)
- [`LICENSE.GPL-3.0`](LICENSE.GPL-3.0), required as part of LGPLv3 license materials
- [`mpv-Copyright`](mpv-Copyright)

These files are useful starting materials, not a complete third-party notice bundle. Before packaging a Windows release:

1. Preserve the precise mpv/FFmpeg source corresponding to the pinned commits, the upstream build-script revision, and all applied patches. The release workflow/source snapshot must remain obtainable after upstream artifact retention expires.
2. Record the actual FFmpeg configure summary and the libraries statically linked into libmpv, plus any runtime DLL dependencies. Resolve the generic-manifest GPL candidates against that evidence rather than assuming they are present or absent.
3. Include applicable LGPL/GPL license texts, copyright notices, changes/source references, and notices for the actual linked/bundled third-party libraries. Keep ReelNest's Apache-2.0 license and any Apache NOTICE separate from the third-party license materials; neither replaces the other.
4. Provide the corresponding source and a practical way to replace/relink the LGPL library as required by the applicable LGPL version and distribution form. Preserve enough application/object/build material for the selected compliance method. Confirm the exact distribution method against the actual bundle before publishing.

No legal conclusion is made here about whether a particular combination or distribution method satisfies every license condition. The release bundle must not be published until its applicable license, source and notice materials are present. This is an ordinary release-readiness condition, not a reason to block isolated engineering validation.

## Current validation status

- Headless hflip/vflip/both: passed on the pinned candidate.
- Windows Profile texture, all five controls: passed in the reported test. Pixel comparisons confirmed 16:9 letterboxing, crop-fill removing black bars, square aspect and horizontal/vertical/bidirectional mirror. Rotation getter and native property combinations passed, but a separate rotation pixel-image comparison was not performed.
- Combined settings: aspect 4:3 + balanced crop + auto deinterlace + 270° rotation + both flips passed; the combination checked the property state, not `deinterlace-active`. A separate switch from `auto` to forced `on` returned `deinterlace-active=yes`. The test did not establish bwdif selection. Rotation getter normalized the 90° case to `9/16` as expected by the test.
- Mirror pixel tests use an mpv-sized square fixture to compare only equivalent video regions. A one-pixel difference seen with a 225 px odd-letterbox fixture comes from comparing a whole-viewport flip against mpv's video-region-only flip; it is a test-comparison rounding mismatch, not a reported product bug.
- Restore/default and interaction checks: restoring defaults, pause position and playback state, and hwdec configuration passed. The earlier viewport-size assertion only proved the Flutter container changed, not that native mpv output resized while paused.
- Strict paused resize check passed (11.7-second patch build, 5-second test): at a 480x270 viewport while paused, mpv `osd-dimensions` reported `w=480 h=270`; restoring a 400x400 viewport retained letterboxing, and pause position/playing/hwdec remained unchanged. Before the fix `VideoOutput::SetSize` recorded width/height but did not call `CheckAndResize`/`Render`, and a paused player could receive no later mpv callback. ReelNest's [`media_kit_viewport.cmake`](../../apps/client/windows/media_kit_viewport.cmake) generates a project-local `video_output.cc` source with a `destroyed_` guard and `CheckAndResize()` + `Render()` on the existing render queue. It does not seek, unpause, change playback properties, or edit PubCache.
- Full Flutter suite: 768 passed / 7 skipped in 52 seconds; seven explicit native DLL checks, strict paused resize, and analyzer passed. `dart format` checked 304 Dart files with zero changes; diff-check passed.
- Previous Windows production Release (`flutter build windows --release --no-pub --target lib/main.dart`): succeeded in 44.4 seconds. After the CMake retry change, incremental Release succeeded in 45.1 seconds. Five-second smoke at `2026-10-16T23:39:17.7412689+08:00` reported `HiddenWindowResponding=true`, `ClosedNormally=true`, `ExitCode=0`.
- Release artifact: `data/app.so` 11,895,688 bytes, last written `2026-10-16 23:28:55 +08:00`; `libmpv-2.dll` SHA-256 `22a7cb13ded0a6e80137661f5321de9a43c586780e798e46c39d3395488ece5f`, size 101,261,312 bytes (about 68.2 MiB larger than the previous 29,764,622-byte DLL). The LGPL/GPL license and mpv copyright files in this directory are installed under `data/third_party/mpv`.
- Existing Windows Profile playback-stats texture regression: passed; all compared counters/estimates matched the prior runtime, with `renderPasses=false` and HTTP cache readings available. Do not switch VO to force render-pass reporting.
- Real Emby playback, macOS/Linux native validation, and manual UI/visual review: pending. Before formal distribution, retain a long-lived project-controlled mirror of the exact archive and corresponding source/build/license materials (upstream build assets are retained for only 30 days) and finish checking the actual linked-dependency notice/source set. No schema change, user data deletion, commit, or push occurred in this validation batch.
- Final source/third-party license/NOTICE and LGPL relink-material bundle: pending before formal distribution.
