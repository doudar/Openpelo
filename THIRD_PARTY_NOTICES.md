# Third-party notices

## scrcpy server 3.3.4

OpenPelo bundles the unmodified `scrcpy-server-v3.3.4` Android server to power
the desktop live-view feature. It is an asset of the official
[Genymobile scrcpy v3.3.4 release](https://github.com/Genymobile/scrcpy/releases/tag/v3.3.4).

- Source asset: <https://github.com/Genymobile/scrcpy/releases/download/v3.3.4/scrcpy-server-v3.3.4>
- Repository and source: <https://github.com/Genymobile/scrcpy/tree/v3.3.4>
- Installed path: `assets/scrcpy/scrcpy-server-v3.3.4`
- SHA-256: `8588238c9a5a00aa542906b6ec7e6d5541d9ffb9b5d0f6e1bc0e365e2303079e`
- Verification: this value matches the digest published for that asset by the
  GitHub release API and `SHA256SUMS.txt` release asset.

Copyright (C) 2018 Genymobile
Copyright (C) 2018-2025 Romain Vimont

scrcpy is licensed under the Apache License, Version 2.0. The complete upstream
license, including its copyright notice, is bundled as
`assets/licenses/scrcpy-LICENSE.txt`.

## media_kit

OpenPelo uses `media_kit` 1.2.6, `media_kit_video` 2.0.1, and
`media_kit_libs_video` 1.0.7 for embedded desktop video playback. These
packages select matching platform-native packages during the Flutter build.
On Linux, `media_kit_video` links the distribution-provided `libmpv` and
`libepoxy`; they are installed in CI through `libmpv-dev` and `libepoxy-dev`.
Windows and macOS use their media_kit native packages to supply the build-time
video runtime, so they need no separately installed native dependency in this
project's CI workflow.

- Primary package: <https://pub.dev/packages/media_kit/versions/1.2.6>
- Video widget package: <https://pub.dev/packages/media_kit_video/versions/2.0.1>
- Native-library selector: <https://pub.dev/packages/media_kit_libs_video/versions/1.0.7>
- Upstream repository: <https://github.com/media-kit/media-kit>

The listed media_kit Dart/plugin packages are licensed under the MIT License,
copyright (c) 2021 and onwards Hitesh Kumar Saini. A complete copy is bundled as
`assets/licenses/media-kit-LICENSE.txt`. Their native binaries have separate
licenses; the MIT license for the wrapper does not replace those licenses.

### Native playback components and source locations

The resolved Windows package is `media_kit_libs_windows_video` 1.0.11. It uses
the `mpv-dev-x86_64-20230924-git-652a1dd.7z` artifact from
<https://github.com/media-kit/libmpv-win32-video-build/releases/tag/2023-09-24>.
Its upstream build recipes and dependency source references are at
<https://github.com/media-kit/libmpv-win32-video-build>. The libmpv and FFmpeg
recipes disable GPL-only features. libmpv and FFmpeg retain their applicable
GNU Lesser General Public License terms and individual source-file notices.
The bundled `mpv-Copyright.txt` and `FFmpeg-LICENSE.md` describe the upstream
license choices; complete GNU LGPL 2.1/3.0 and GPL 2.0/3.0 texts are included
under `assets/licenses/` for those choices and their incorporated terms.

The Windows package also uses ANGLE's `v1.0.1` binary distribution from
<https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v1.0.1>.
It contains ANGLE, SwiftShader, Vulkan Loader, zlib, and the Microsoft Direct3D
compiler runtime. Upstream license texts for ANGLE (BSD), SwiftShader and
Vulkan Loader (Apache 2.0), and zlib are bundled under `assets/licenses/`.
The Microsoft runtime remains governed by Microsoft's redistribution terms.
Source projects are <https://github.com/google/angle>,
<https://github.com/google/swiftshader>,
<https://github.com/KhronosGroup/Vulkan-Loader>, and
<https://github.com/madler/zlib>.

The resolved macOS package is `media_kit_libs_macos_video` 1.1.4. It uses the
`v0.6.0` macOS universal `video-default` frameworks from
<https://github.com/media-kit/libmpv-darwin-build/releases/tag/v0.6.0>.
Build recipes, source revisions, and dependency configuration are available at
<https://github.com/media-kit/libmpv-darwin-build/tree/v0.6.0>.
The build-project license is bundled as `libmpv-darwin-build-LICENSE.txt`;
it does not replace the licenses of libmpv, FFmpeg, or their dependencies.

Linux uses distribution-provided libmpv/libepoxy and their dependencies rather
than redistributing those libraries in the OpenPelo archive. Their matching
source packages and copyright files are supplied by the Linux distribution.

OpenPelo does not modify these native components. Preserve their upstream
notices and corresponding-source obligations when redistributing binaries;
the source/build links above identify the native artifacts selected by the
locked packages. These notices cover the named playback components and are not
an exhaustive inventory of every transitive native library in those artifacts.

This notices file and `assets/licenses/` are declared as Flutter assets, so
they accompany the application even when distributed without the source tree.

## Apache License, Version 2.0

Copyright (C) 2018 Genymobile
Copyright (C) 2018-2025 Romain Vimont

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy of
the License at <http://www.apache.org/licenses/LICENSE-2.0>.

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.

The complete Apache License, Version 2.0 text is included in
`assets/licenses/scrcpy-LICENSE.txt`.

## MIT License for media_kit packages

Copyright (c) 2021 and onwards Hitesh Kumar Saini

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
