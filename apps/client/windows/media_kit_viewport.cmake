# media_kit_video 2.0.1 only stores SetSize requests. A paused player may never
# request another mpv frame, so its FBO/aspect/panscan remain at the old size.
# Generate a project-owned source with a redraw on the existing render queue;
# never seek, unpause, change player properties, or edit the shared Pub cache.
if(TARGET media_kit_video_plugin)
  get_target_property(viewport_source_dir media_kit_video_plugin SOURCE_DIR)
  get_target_property(viewport_sources media_kit_video_plugin SOURCES)
  set(viewport_source "${viewport_source_dir}/video_output.cc")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${viewport_source}")
  file(READ "${viewport_source}" viewport_code)
  set(viewport_begin [=[  thread_pool_ref_->Post([&, width, height]() {
    if (width.has_value()) {]=])
  set(viewport_begin_fixed [=[  thread_pool_ref_->Post([&, width, height]() {
    if (destroyed_) return;
    if (width.has_value()) {]=])
  set(viewport_end [=[  });
}

void VideoOutput::CheckAndResize() {]=])
  set(viewport_end_fixed [=[    // Render even while paused: resizing an FBO does not notify mpv itself.
    CheckAndResize();
    Render();
  });
}

void VideoOutput::CheckAndResize() {]=])
  string(FIND "${viewport_code}" "${viewport_begin}" viewport_begin_offset)
  string(FIND "${viewport_code}" "${viewport_end}" viewport_end_offset)
  if(viewport_begin_offset EQUAL -1 OR viewport_end_offset EQUAL -1)
    message(FATAL_ERROR "media_kit_video SetSize changed; review the paused viewport patch")
  endif()
  string(REPLACE "${viewport_begin}" "${viewport_begin_fixed}" viewport_code "${viewport_code}")
  string(REPLACE "${viewport_end}" "${viewport_end_fixed}" viewport_code "${viewport_code}")
  set(viewport_generated_dir "${CMAKE_CURRENT_BINARY_DIR}/reelnest_media_kit")
  file(MAKE_DIRECTORY "${viewport_generated_dir}")
  set(viewport_generated_source "${viewport_generated_dir}/video_output.cc")
  file(WRITE "${viewport_generated_source}" "${viewport_code}")
  set(viewport_fixed_sources "")
  foreach(viewport_item IN LISTS viewport_sources)
    if(NOT IS_ABSOLUTE "${viewport_item}")
      set(viewport_item "${viewport_source_dir}/${viewport_item}")
    endif()
    if(viewport_item STREQUAL viewport_source)
      list(APPEND viewport_fixed_sources "${viewport_generated_source}")
    else()
      list(APPEND viewport_fixed_sources "${viewport_item}")
    endif()
  endforeach()
  set_property(TARGET media_kit_video_plugin PROPERTY SOURCES "${viewport_fixed_sources}")
endif()
