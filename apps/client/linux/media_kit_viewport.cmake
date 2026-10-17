# media_kit_video 2.0.1 SetSize stores dimensions without requesting a frame.
# Generate a project-owned source; never change the shared Pub cache.
if(TARGET media_kit_video_plugin)
  get_target_property(viewport_source_dir media_kit_video_plugin SOURCE_DIR)
  get_target_property(viewport_sources media_kit_video_plugin SOURCES)
  set(viewport_source "${viewport_source_dir}/video_output.cc")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${viewport_source}")
  file(READ "${viewport_source}" viewport_code)

  # Reuse the existing software rendering body for normal frames and resize.
  # Both execute on the GTK platform thread, while the GL path schedules the
  # texture populate callback on Flutter's raster thread (where its EGL lives).
  set(viewport_sw_begin [=[                    VideoOutput* self = (VideoOutput*)data;
                    if (self->destroyed) {]=])
  set(viewport_sw_end [=[                    g_mutex_unlock(&self->mutex);
                    return FALSE;]=])
  string(FIND "${viewport_code}" "${viewport_sw_begin}" viewport_sw_begin_offset)
  string(FIND "${viewport_code}" "${viewport_sw_end}" viewport_sw_end_offset)
  if(viewport_sw_begin_offset EQUAL -1 OR viewport_sw_end_offset EQUAL -1)
    message(FATAL_ERROR "media_kit_video software callback changed; review the Linux viewport patch")
  endif()
  string(LENGTH "${viewport_sw_end}" viewport_sw_end_length)
  math(EXPR viewport_sw_length "${viewport_sw_end_offset} + ${viewport_sw_end_length} - ${viewport_sw_begin_offset}")
  string(SUBSTRING "${viewport_code}" ${viewport_sw_begin_offset} ${viewport_sw_length} viewport_sw_body)
  # Remove the callback's cast: the helper receives a typed pointer.
  string(REPLACE "                    VideoOutput* self = (VideoOutput*)data;\n" "" viewport_sw_helper "${viewport_sw_body}")
  string(REPLACE "return FALSE;" "return;" viewport_sw_helper "${viewport_sw_helper}")
  set(viewport_helper "#ifdef MPV_RENDER_API_TYPE_SW\nstatic void reelnest_render_software(VideoOutput* self) {\n${viewport_sw_helper}\n}\n#endif\n\n")
  string(REPLACE "${viewport_sw_body}" "                    reelnest_render_software((VideoOutput*)data);\n                    return FALSE;" viewport_code "${viewport_code}")

  set(viewport_init "VideoOutput* video_output_new(")
  string(FIND "${viewport_code}" "${viewport_init}" viewport_init_offset)
  if(viewport_init_offset EQUAL -1)
    message(FATAL_ERROR "media_kit_video constructor changed; review the Linux viewport patch")
  endif()
  string(REPLACE "${viewport_init}" "${viewport_helper}${viewport_init}" viewport_code "${viewport_code}")
  set(viewport_end [=[    self->height = CLAMP(height, 0, SW_RENDERING_MAX_HEIGHT);
  }
}

mpv_render_context* video_output_get_render_context]=])
  set(viewport_end_fixed [=[    self->height = CLAMP(height, 0, SW_RENDERING_MAX_HEIGHT);
  }
  // Method-channel SetSize runs on the GTK platform thread. Do not leave a
  // queued raw self pointer that could outlive VideoOutput on player close.
  if (self->destroyed || self->render_context == nullptr) return;
  if (self->texture_gl) {
    fl_texture_registrar_mark_texture_frame_available(
        self->texture_registrar, FL_TEXTURE(self->texture_gl));
  }
#ifdef MPV_RENDER_API_TYPE_SW
  if (self->texture_sw) reelnest_render_software(self);
#endif
}

mpv_render_context* video_output_get_render_context]=])
  string(FIND "${viewport_code}" "${viewport_end}" viewport_end_offset)
  if(viewport_end_offset EQUAL -1)
    message(FATAL_ERROR "media_kit_video SetSize changed; review the Linux viewport patch")
  endif()
  string(REPLACE "${viewport_end}" "${viewport_end_fixed}" viewport_code "${viewport_code}")
  set(viewport_generated_dir "${CMAKE_CURRENT_BINARY_DIR}/reelnest_media_kit")
  file(MAKE_DIRECTORY "${viewport_generated_dir}")
  set(viewport_generated_source "${viewport_generated_dir}/video_output.cc")
  file(WRITE "${viewport_generated_source}" "${viewport_code}")
  set(viewport_fixed_sources "")
  set(viewport_replaced FALSE)
  foreach(viewport_item IN LISTS viewport_sources)
    if(NOT IS_ABSOLUTE "${viewport_item}")
      set(viewport_item "${viewport_source_dir}/${viewport_item}")
    endif()
    if(viewport_item STREQUAL viewport_source)
      list(APPEND viewport_fixed_sources "${viewport_generated_source}")
      set(viewport_replaced TRUE)
    else()
      list(APPEND viewport_fixed_sources "${viewport_item}")
    endif()
  endforeach()
  if(NOT viewport_replaced)
    message(FATAL_ERROR "media_kit_video has no video output input; review the Linux viewport patch")
  endif()
  set_property(TARGET media_kit_video_plugin PROPERTY SOURCES "${viewport_fixed_sources}")
  target_include_directories(media_kit_video_plugin PRIVATE "${viewport_source_dir}")
endif()
