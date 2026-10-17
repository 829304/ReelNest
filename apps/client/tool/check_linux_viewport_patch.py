"""Compile the generated Linux resize code against a renderer test double.

Requires pub get, Python, CMake and a C++ compiler. This validates generation,
GPU notification, software frame dimensions and guards, not GTK/EGL rendering.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import unquote, urlparse


def function(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


STUB = r'''
#undef NDEBUG
#include <algorithm>
#include <cassert>
#include <cstdint>
using gint64 = int64_t;
using gint32 = int32_t;
using gboolean = bool;
constexpr int SW_RENDERING_MAX_WIDTH=1280, SW_RENDERING_MAX_HEIGHT=720;
constexpr bool FALSE=false;
#define CLAMP(x,a,b) std::clamp<int64_t>(x,a,b)
#define FL_TEXTURE(x) (x)
enum { MPV_RENDER_PARAM_SW_SIZE, MPV_RENDER_PARAM_SW_FORMAT,
       MPV_RENDER_PARAM_SW_STRIDE, MPV_RENDER_PARAM_SW_POINTER,
       MPV_RENDER_PARAM_INVALID };
struct mpv_render_param { int type; void* data; };
struct VideoOutput {
  bool destroyed=false;
  int mutex=0;
  void* render_context=this;
  void* texture_gl=nullptr;
  void* texture_sw=nullptr;
  void* texture_registrar=this;
  uint8_t pixel_buffer[4]{};
  gint64 width=0, height=0;
};
static int renders=0, notifications=0, rendered_width=0, rendered_height=0;
static void g_mutex_lock(int* m) { assert(*m==0); ++*m; }
static void g_mutex_unlock(int* m) { assert(*m==1); --*m; }
static gint64 video_output_get_width(VideoOutput* o) { return o->width; }
static gint64 video_output_get_height(VideoOutput* o) { return o->height; }
static void mpv_render_context_render(void*, mpv_render_param* p) {
  ++renders;
  auto* size=static_cast<int32_t*>(p[0].data);
  rendered_width=size[0]; rendered_height=size[1];
}
static void fl_texture_registrar_mark_texture_frame_available(void*, void*) { ++notifications; }
'''
CHECKS = r'''
int main() {
  VideoOutput gl;
  gl.texture_gl=&gl;
  video_output_set_size(&gl,480,270);
  assert(gl.width==480 && gl.height==270 && renders==0 && notifications==1);
#ifdef MPV_RENDER_API_TYPE_SW
  VideoOutput sw;
  sw.texture_sw=&sw;
  video_output_set_size(&sw,480,270);
  assert(renders==1 && notifications==2 && rendered_width==480 && rendered_height==270);
  video_output_set_size(&sw,5000,5000);
  assert(renders==2 && notifications==3 && rendered_width==1280 && rendered_height==720);
  video_output_set_size(&sw,0,0);
  assert(renders==2 && notifications==3 && sw.mutex==0);
#endif
  int before=notifications;
  gl.destroyed=true;
  video_output_set_size(&gl,300,450);
  assert(notifications==before);
  gl.destroyed=false; gl.render_context=nullptr;
  video_output_set_size(&gl,400,400);
  assert(notifications==before);
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cmake', default='cmake')
    args = parser.parse_args()
    client = Path(__file__).resolve().parents[1]
    config = client / '.dart_tool/package_config.json'
    packages = json.loads(config.read_text())['packages']
    uri = urlparse(next(p for p in packages if p['name'] == 'media_kit_video')['rootUri'])
    path = unquote(uri.path)
    if os.name == 'nt' and uri.scheme == 'file' and path.startswith('/'):
        path = path[1:]
    dependency = Path(path) if uri.scheme == 'file' else config.parent / path
    original = (dependency / 'linux/video_output.cc').read_text(encoding='utf-8')
    build = client / 'build'
    build.mkdir(exist_ok=True)
    sandbox = Path(tempfile.mkdtemp(prefix='reelnest-viewport-patch-', dir=build))
    try:
        upstream = sandbox / 'upstream'
        upstream.mkdir()
        (upstream / 'video_output.cc').write_text(original, encoding='utf-8')
        (upstream / 'other.cc').write_text('int unrelated_input = 0;')
        (upstream / 'CMakeLists.txt').write_text(
            'add_library(media_kit_video_plugin STATIC EXCLUDE_FROM_ALL video_output.cc other.cc)\n')
        (sandbox / 'CMakeLists.txt').write_text(
            'cmake_minimum_required(VERSION 3.13)\nproject(viewport_probe LANGUAGES CXX)\n'
            'set(CMAKE_CXX_STANDARD 17)\nadd_subdirectory(upstream)\n'
            f'include("{(client / "linux/media_kit_viewport.cmake").as_posix()}")\n'
            'get_target_property(inputs media_kit_video_plugin SOURCES)\n'
            'file(WRITE "${CMAKE_BINARY_DIR}/inputs.txt" "${inputs}")\n'
            'add_executable(viewport_probe probe.cc)\n'
            'target_compile_definitions(viewport_probe PRIVATE MPV_RENDER_API_TYPE_SW="sw")\n'
            'add_executable(viewport_gl_probe probe.cc)\n')
        (sandbox / 'probe.cc').write_text('int main() {}')
        output = sandbox / 'output'

        def run(*command):
            result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace')
            if result.returncode:
                print(result.stdout, result.stderr)
                result.check_returncode()

        run(args.cmake, '-S', str(sandbox), '-B', str(output))
        generated = (output / 'reelnest_media_kit/video_output.cc').read_text(encoding='utf-8')
        assert (upstream / 'video_output.cc').read_text(encoding='utf-8') == original
        inputs = (output / 'inputs.txt').read_text()
        assert 'reelnest_media_kit/video_output.cc' in inputs and '/upstream/other.cc' in inputs
        helper = function(generated, 'static void reelnest_render_software(')
        setter = function(generated, 'void video_output_set_size(')
        (sandbox / 'probe.cc').write_text(
            STUB + '\n#ifdef MPV_RENDER_API_TYPE_SW\n' + helper + '\n#endif\n' + setter + CHECKS)
        run(args.cmake, '--build', str(output), '--config', 'Release', '--target', 'viewport_probe', 'viewport_gl_probe')
        for target in ['viewport_probe', 'viewport_gl_probe']:
            executable = output / 'Release' / f'{target}.exe' if os.name == 'nt' else output / target
            run(str(executable))
        (upstream / 'video_output.cc').write_text(
            original.replace('g_mutex_unlock(&self->mutex);', '/* fixture: upstream callback changed */'), encoding='utf-8')
        drift = subprocess.run([args.cmake, '-S', str(sandbox), '-B', str(output)], capture_output=True)
        assert drift.returncode != 0 and b'review the Linux viewport patch' in drift.stderr
        print('Linux generated patch: GPU notification, software render/clamp and close guards passed (test doubles).')
    finally:
        resolved = sandbox.resolve()
        if not resolved.is_relative_to(build.resolve()) or not resolved.name.startswith('reelnest-viewport-patch-'):
            raise RuntimeError('Unexpected test sandbox; refusing cleanup')
        shutil.rmtree(resolved)


if __name__ == '__main__':
    main()
