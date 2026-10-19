"""Compile the generated Linux resize code against a renderer test double.

Requires pub get, Python, CMake and a C++ compiler. This validates generation,
GPU notification, software frame dimensions and guards, not GTK/EGL rendering.
"""
import argparse
import json
import os
from pathlib import Path
import re
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
#include <cstring>
using gint64 = int64_t;
using gint32 = int32_t;
using gboolean = bool;
constexpr bool FALSE=false;
#define CLAMP(x,a,b) std::clamp<int64_t>(x,a,b)
#define FL_TEXTURE(x) (x)
enum { MPV_RENDER_PARAM_SW_SIZE, MPV_RENDER_PARAM_SW_FORMAT,
       MPV_RENDER_PARAM_SW_STRIDE, MPV_RENDER_PARAM_SW_POINTER,
       MPV_RENDER_PARAM_INVALID };
struct mpv_render_param { int type; void* data; };
enum { MPV_FORMAT_NODE_MAP=10, MPV_FORMAT_NODE=6, MPV_FORMAT_INT64=4 };
struct mpv_node_list;
struct mpv_node {
  int format=0;
  union { int64_t int64; mpv_node_list* list; } u{};
};
struct mpv_node_list { int num; char** keys; mpv_node* values; };
struct FakeHandle { gint64 width=0, height=0, rotate=0; };
static void mpv_get_property(FakeHandle* handle, const char*, int, mpv_node* result) {
  static char dw[]="dw", dh[]="dh", rotate[]="rotate";
  static char* keys[]{dw,dh,rotate};
  static mpv_node values[3];
  static mpv_node_list list{3,keys,values};
  for (auto& value : values) value.format=MPV_FORMAT_INT64;
  values[0].u.int64=handle->width;
  values[1].u.int64=handle->height;
  values[2].u.int64=handle->rotate;
  result->format=MPV_FORMAT_NODE_MAP; result->u.list=&list;
}
static void mpv_free_node_contents(mpv_node*) {}
struct VideoOutput {
  bool destroyed=false;
  int mutex=0;
  void* render_context=this;
  void* texture_gl=nullptr;
  void* texture_sw=nullptr;
  void* texture_registrar=this;
  uint8_t pixel_buffer[4]{};
  gint64 width=0, height=0;
  FakeHandle source;
  FakeHandle* handle=&source;
};
static int renders=0, notifications=0, rendered_width=0, rendered_height=0;
static void g_mutex_lock(int* m) { assert(*m==0); ++*m; }
static void g_mutex_unlock(int* m) { assert(*m==1); --*m; }
static void mpv_render_context_render(void*, mpv_render_param* p) {
  ++renders;
  auto* size=static_cast<int32_t*>(p[0].data);
  rendered_width=size[0]; rendered_height=size[1];
}
static void fl_texture_registrar_mark_texture_frame_available(void*, void*) { ++notifications; }
'''
CHECKS = r'''
static void expect_dimensions(VideoOutput* output, gint64 width, gint64 height) {
  assert(video_output_get_width(output)==width);
  assert(video_output_get_height(output)==height);
}
#ifdef MPV_RENDER_API_TYPE_SW
static void expect_resize(VideoOutput* output, gint64 width, gint64 height,
                          gint64 expected_width, gint64 expected_height) {
  const int before_renders=renders, before_notifications=notifications;
  video_output_set_size(output,width,height);
  expect_dimensions(output,expected_width,expected_height);
  assert(renders==before_renders+1 && notifications==before_notifications+1);
  assert(rendered_width==expected_width && rendered_height==expected_height);
  assert(rendered_width>0 && rendered_width<=SW_RENDERING_MAX_WIDTH);
  assert(rendered_height>0 && rendered_height<=SW_RENDERING_MAX_HEIGHT);
}
#endif
int main() {
  // These are the pinned dependency's limits, read from its actual header.
  static_assert(SW_RENDERING_MAX_WIDTH==1920 && SW_RENDERING_MAX_HEIGHT==1080);
  VideoOutput gl;
  gl.texture_gl=&gl;
  video_output_set_size(&gl,480,270);
  assert(gl.width==480 && gl.height==270 && renders==0 && notifications==1);
  video_output_set_size(&gl,5000,5000);
  expect_dimensions(&gl,5000,5000);
  assert(renders==0 && notifications==2);
  video_output_set_size(&gl,0,0);
  gl.source={3840,2160,90};
  expect_dimensions(&gl,2160,3840);
#ifdef MPV_RENDER_API_TYPE_SW
  VideoOutput sw;
  sw.texture_sw=&sw;
  expect_resize(&sw,480,270,480,270);
  expect_resize(&sw,1440,1440,1080,1080);
  expect_resize(&sw,5000,5000,1080,1080);
  expect_resize(&sw,2880,2880,1080,1080);
  expect_resize(&sw,7680,4320,1920,1080);
  expect_resize(&sw,4000,3000,1440,1080);
  expect_resize(&sw,1080,1920,608,1080);
  expect_resize(&sw,1440,900,1440,900);
  expect_resize(&sw,8192,1,1920,1);
  expect_resize(&sw,1,8192,1,1080);
  const int before_reset=renders, before_reset_notifications=notifications;
  video_output_set_size(&sw,0,0);
  assert(renders==before_reset && notifications==before_reset_notifications && sw.mutex==0);
  // Automatic source dimensions, including rotation and the old integer divide
  // path, must use exactly the same fit as explicit viewport requests.
  sw.source={3840,2160,0}; expect_dimensions(&sw,1920,1080);
  sw.source.rotate=90; expect_dimensions(&sw,608,1080);
  sw.source.rotate=270; expect_dimensions(&sw,608,1080);
  sw.source={5000,5000,0}; expect_dimensions(&sw,1080,1080);
  sw.source={1600,1440,0}; expect_dimensions(&sw,1200,1080);
  sw.source={4000,3000,180}; expect_dimensions(&sw,1440,1080);
  sw.source={480,960,0}; expect_dimensions(&sw,480,960);
  // Constructor-supplied fixed dimensions bypass SetSize initially.
  sw.width=5000; sw.height=5000; expect_dimensions(&sw,1080,1080);
  sw.destroyed=true;
  video_output_set_size(&sw,300,450);
  assert(renders==before_reset && notifications==before_reset_notifications);
  sw.destroyed=false; sw.render_context=nullptr;
  video_output_set_size(&sw,400,400);
  assert(renders==before_reset && notifications==before_reset_notifications);
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
    header = (dependency / 'linux/include/media_kit_video/texture_sw.h').read_text(encoding='utf-8')
    limits = '\n'.join(re.findall(
        r'^#define SW_RENDERING_MAX_(?:WIDTH|HEIGHT)\s+\d+\s*$', header, re.MULTILINE))
    assert len(limits.splitlines()) == 2, 'Review software pixel-buffer limits'
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
            f'include("{(client / "native/media_kit_color.cmake").as_posix()}")\n'
            'reelnest_patch_media_kit_colors(linux)\n'
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
        assert generated.count('"user-data/reelnest/render-api", "opengl"') == 1
        assert generated.count('"user-data/reelnest/render-api", "sw"') == 1
        assert (upstream / 'video_output.cc').read_text(encoding='utf-8') == original
        inputs = (output / 'inputs.txt').read_text()
        assert 'reelnest_media_kit/video_output.cc' in inputs and '/upstream/other.cc' in inputs
        helper = function(generated, 'static void reelnest_render_software(')
        fit = function(generated, 'static gint64 reelnest_software_dimension(')
        getters = '\n'.join(function(generated, f'gint64 video_output_get_{axis}(')
                            for axis in ['width', 'height'])
        setter = function(generated, 'void video_output_set_size(')
        (sandbox / 'probe.cc').write_text(
            limits + '\n' + STUB + fit + getters + '\n#ifdef MPV_RENDER_API_TYPE_SW\n'
            + helper + '\n#endif\n' + setter + CHECKS)
        run(args.cmake, '--build', str(output), '--config', 'Release', '--target', 'viewport_probe', 'viewport_gl_probe')
        for target in ['viewport_probe', 'viewport_gl_probe']:
            executable = output / 'Release' / f'{target}.exe' if os.name == 'nt' else output / target
            run(str(executable))
        (upstream / 'video_output.cc').write_text(
            original.replace('g_mutex_unlock(&self->mutex);', '/* fixture: upstream callback changed */'), encoding='utf-8')
        drift = subprocess.run([args.cmake, '-S', str(sandbox), '-B', str(output)], capture_output=True)
        assert drift.returncode != 0 and b'review the Linux viewport patch' in b' '.join(drift.stderr.split()), drift.stderr
        # The sizing patch must also fail closed if a dependency getter changes.
        (upstream / 'video_output.cc').write_text(
            original.replace('return width / height * SW_RENDERING_MAX_HEIGHT;',
                             'return /* fixture: sizing changed */ 0;'), encoding='utf-8')
        drift = subprocess.run([args.cmake, '-S', str(sandbox), '-B', str(output)], capture_output=True)
        assert drift.returncode != 0 and b'review the Linux viewport patch' in b' '.join(drift.stderr.split()), drift.stderr
        print('Linux generated patch: proportional software sizing (requested/automatic/rotated), '
              'GPU notification, paused redraw and close guards passed (test doubles).')
    finally:
        resolved = sandbox.resolve()
        if not resolved.is_relative_to(build.resolve()) or not resolved.name.startswith('reelnest-viewport-patch-'):
            raise RuntimeError('Unexpected test sandbox; refusing cleanup')
        shutil.rmtree(resolved)


if __name__ == '__main__':
    main()
