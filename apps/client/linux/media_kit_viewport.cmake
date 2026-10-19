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
  # The software pixel buffer has fixed bounds. Fit both axes with one scale;
  # independent clamping stretches square/portrait/high-DPI viewports. Apply
  # the same policy to explicit requests and automatic video dimensions.
  set(viewport_fit_helper [=[static gint64 reelnest_software_dimension(gint64 width, gint64 height,
                                            bool horizontal) {
  double scale = 1.0;
  if (width > SW_RENDERING_MAX_WIDTH) {
    scale = (double)SW_RENDERING_MAX_WIDTH / (double)width;
  }
  if (height > 0 && (double)height * scale > SW_RENDERING_MAX_HEIGHT) {
    scale = (double)SW_RENDERING_MAX_HEIGHT / (double)height;
  }
  const gint64 value = horizontal ? width : height;
  if (value <= 0) return 0;
  const gint64 limit = horizontal ? SW_RENDERING_MAX_WIDTH : SW_RENDERING_MAX_HEIGHT;
  return CLAMP((gint64)((double)value * scale + 0.5), 1, limit);
}

]=])
  set(viewport_helper "${viewport_fit_helper}#ifdef MPV_RENDER_API_TYPE_SW\nstatic void reelnest_render_software(VideoOutput* self) {\n${viewport_sw_helper}\n}\n#endif\n\n")
  string(REPLACE "${viewport_sw_body}" "                    reelnest_render_software((VideoOutput*)data);\n                    return FALSE;" viewport_code "${viewport_code}")

  set(viewport_init "VideoOutput* video_output_new(")
  string(FIND "${viewport_code}" "${viewport_init}" viewport_init_offset)
  if(viewport_init_offset EQUAL -1)
    message(FATAL_ERROR "media_kit_video constructor changed; review the Linux viewport patch")
  endif()
  string(REPLACE "${viewport_init}" "${viewport_helper}${viewport_init}" viewport_code "${viewport_code}")
  set(viewport_fixed_width [=[  if (self->width) {
    return self->width;
  }]=])
  set(viewport_fixed_width_fit [=[  if (self->width) {
    return self->texture_sw
        ? reelnest_software_dimension(self->width, self->height, true)
        : self->width;
  }]=])
  set(viewport_fixed_height [=[  if (self->width) {
    return self->height;
  }]=])
  set(viewport_fixed_height_fit [=[  if (self->width) {
    return self->texture_sw
        ? reelnest_software_dimension(self->width, self->height, false)
        : self->height;
  }]=])
  set(viewport_auto_width [=[    if (width >= SW_RENDERING_MAX_WIDTH) {
      return SW_RENDERING_MAX_WIDTH;
    }
    if (height >= SW_RENDERING_MAX_HEIGHT) {
      return width / height * SW_RENDERING_MAX_HEIGHT;
    }]=])
  set(viewport_auto_width_fit "    return reelnest_software_dimension(width, height, true);")
  set(viewport_auto_height [=[    if (height >= SW_RENDERING_MAX_HEIGHT) {
      return SW_RENDERING_MAX_HEIGHT;
    }
    if (width >= SW_RENDERING_MAX_WIDTH) {
      return height / width * SW_RENDERING_MAX_WIDTH;
    }]=])
  set(viewport_auto_height_fit "    return reelnest_software_dimension(width, height, false);")
  set(viewport_fixed_size [=[    self->width = CLAMP(width, 0, SW_RENDERING_MAX_WIDTH);
    self->height = CLAMP(height, 0, SW_RENDERING_MAX_HEIGHT);]=])
  set(viewport_fixed_size_fit [=[    self->width = reelnest_software_dimension(width, height, true);
    self->height = reelnest_software_dimension(width, height, false);]=])
  # Fail on dependency drift rather than silently retaining a partial fix.
  foreach(viewport_fit_part fixed_width fixed_height auto_width auto_height fixed_size)
    string(FIND "${viewport_code}" "${viewport_${viewport_fit_part}}" viewport_fit_offset)
    if(viewport_fit_offset EQUAL -1)
      message(FATAL_ERROR "media_kit_video software dimensions changed; review the Linux viewport patch")
    endif()
    string(REPLACE "${viewport_${viewport_fit_part}}" "${viewport_${viewport_fit_part}_fit}" viewport_code "${viewport_code}")
  endforeach()
  set(viewport_end [=[    self->height = reelnest_software_dimension(width, height, false);
  }
}

mpv_render_context* video_output_get_render_context]=])
  set(viewport_end_fixed [=[    self->height = reelnest_software_dimension(width, height, false);
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
