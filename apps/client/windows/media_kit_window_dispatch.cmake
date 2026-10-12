# media_kit_video 2.0.1 subclasses every HWND but dispatches through one global
# plugin pointer. A player overwrites the main window's owner, then clears it
# on destruction. Patch our generated build input, never the shared Pub cache.
if(TARGET media_kit_video_plugin)
  get_target_property(video_source_dir media_kit_video_plugin SOURCE_DIR)
  get_target_property(video_sources media_kit_video_plugin SOURCES)
  set(video_dispatch_source "${video_source_dir}/media_kit_video_plugin.cc")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${video_dispatch_source}")
  file(READ "${video_dispatch_source}" video_dispatch_code)

  function(reelnest_replace_video_dispatch old new)
    string(FIND "${video_dispatch_code}" "${old}" match_offset)
    if(match_offset EQUAL -1)
      message(FATAL_ERROR "media_kit_video window dispatch changed; review the per-window patch")
    endif()
    string(REPLACE "${old}" "${new}" video_dispatch_code "${video_dispatch_code}")
    set(video_dispatch_code "${video_dispatch_code}" PARENT_SCOPE)
  endfunction()

  reelnest_replace_video_dispatch("#include <Windows.h>" "#include <Windows.h>\n#include <unordered_map>")
  reelnest_replace_video_dispatch(
    "MediaKitVideoPlugin* MediaKitVideoPlugin::instance_ = nullptr;"
    "namespace {\n// All registration, dispatch and destruction run on the platform thread.\nstd::unordered_map<HWND, MediaKitVideoPlugin*> window_plugins;\n}")
  reelnest_replace_video_dispatch("  instance_ = this;\n" "")
  reelnest_replace_video_dispatch(
    "  original_window_proc_ = reinterpret_cast<WNDPROC>("
    "  window_plugins[flutter_window_] = this;\n  original_window_proc_ = reinterpret_cast<WNDPROC>(")
  reelnest_replace_video_dispatch([=[  if (instance_ == this) {
    instance_ = nullptr;
  }]=] [=[  window_plugins.erase(flutter_window_);]=])
  reelnest_replace_video_dispatch([=[  if (message == kMainThreadTaskMessage && instance_) {
    instance_->ProcessMainThreadTasks();
    return 0;
  }

  if (instance_ && instance_->original_window_proc_) {
    return ::CallWindowProc(instance_->original_window_proc_, hwnd, message,
                            wParam, lParam);
  }]=] [=[  const auto found = window_plugins.find(hwnd);
  auto* owner = found == window_plugins.end() ? nullptr : found->second;
  if (message == kMainThreadTaskMessage && owner) {
    owner->ProcessMainThreadTasks();
    return 0;
  }

  if (owner && owner->original_window_proc_) {
    // Save before calling: WM_DESTROY may delete owner while forwarding.
    const auto original = owner->original_window_proc_;
    return ::CallWindowProc(original, hwnd, message, wParam, lParam);
  }]=])

  set(video_generated_dir "${CMAKE_CURRENT_BINARY_DIR}/reelnest_media_kit")
  file(MAKE_DIRECTORY "${video_generated_dir}")
  set(video_generated_source "${video_generated_dir}/media_kit_video_plugin.cc")
  file(WRITE "${video_generated_source}" "${video_dispatch_code}")
  set(video_fixed_sources "")
  foreach(video_source IN LISTS video_sources)
    if(NOT IS_ABSOLUTE "${video_source}")
      set(video_source "${video_source_dir}/${video_source}")
    endif()
    if(video_source STREQUAL video_dispatch_source)
      list(APPEND video_fixed_sources "${video_generated_source}")
    else()
      list(APPEND video_fixed_sources "${video_source}")
    endif()
  endforeach()
  set_property(TARGET media_kit_video_plugin PROPERTY SOURCES "${video_fixed_sources}")
  target_include_directories(media_kit_video_plugin PRIVATE "${video_source_dir}")
endif()
