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

  # A texture callback must keep its own registration identity. During a
  # resize the upstream callback looks up the mutable texture_id_ with at(),
  # before the new descriptor is inserted. Offscreen screenshot/readback can
  # overlap that interval and let std::out_of_range escape into Flutter's C
  # callback. Withdraw the old ID and publish the new map entry under the same
  # mutex used by callbacks. Never let an old registration read a new surface.
  set(texture_retire [=[  if (texture_id_) {
    registrar_->texture_registrar()->UnregisterTexture(
        texture_id_, [&, id = texture_id_]() {]=])
  set(texture_retire_fixed [=[  int64_t previous_texture_id;
  {
    std::lock_guard<std::mutex> lock(textures_mutex_);
    previous_texture_id = texture_id_;
    texture_id_ = 0;
  }
  if (previous_texture_id) {
    registrar_->texture_registrar()->UnregisterTexture(
        previous_texture_id, [&, id = previous_texture_id]() {]=])
  set(texture_gpu_callback [=[    auto texture_variant =
        std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
            kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle, [&](auto, auto) {
              std::lock_guard<std::mutex> lock(textures_mutex_);
              if (texture_id_) {
                surface_manager_->Read();
                return textures_.at(texture_id_).get();
              } else {
                return (FlutterDesktopGpuSurfaceDescriptor*)nullptr;
              }
            }));]=])
  set(texture_gpu_callback_fixed [=[    auto owned_texture_id = std::make_shared<int64_t>(0);
    auto texture_variant =
        std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
            kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
            [this, owned_texture_id](auto, auto) {
              std::lock_guard<std::mutex> lock(textures_mutex_);
              const auto found = textures_.find(*owned_texture_id);
              if (destroyed_ || !*owned_texture_id ||
                  *owned_texture_id != texture_id_ || found == textures_.end()) {
                return (FlutterDesktopGpuSurfaceDescriptor*)nullptr;
              }
              surface_manager_->Read();
              return found->second.get();
            }));]=])
  set(texture_sw_callback [=[    auto texture_variant = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture([&](auto, auto) {
          std::lock_guard<std::mutex> lock(textures_mutex_);
          if (texture_id_) {
            return pixel_buffer_textures_.at(texture_id_).get();
          } else {
            return (FlutterDesktopPixelBuffer*)nullptr;
          }
        }));]=])
  set(texture_sw_callback_fixed [=[    auto owned_texture_id = std::make_shared<int64_t>(0);
    auto texture_variant = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture([this, owned_texture_id](auto, auto) {
          std::lock_guard<std::mutex> lock(textures_mutex_);
          const auto found = pixel_buffer_textures_.find(*owned_texture_id);
          if (destroyed_ || !*owned_texture_id ||
              *owned_texture_id != texture_id_ || found == pixel_buffer_textures_.end()) {
            return (FlutterDesktopPixelBuffer*)nullptr;
          }
          return found->second.get();
        }));]=])
  set(texture_register [=[    texture_id_ =
        registrar_->texture_registrar()->RegisterTexture(texture_variant.get());
    std::cout << "media_kit: VideoOutput: Create Texture: " << texture_id_
              << std::endl;
    std::lock_guard<std::mutex> lock(textures_mutex_);]=])
  set(texture_register_fixed [=[    const auto registered_texture_id =
        registrar_->texture_registrar()->RegisterTexture(texture_variant.get());
    std::lock_guard<std::mutex> lock(textures_mutex_);
    texture_id_ = registered_texture_id;
    *owned_texture_id = registered_texture_id;
    std::cout << "media_kit: VideoOutput: Create Texture: " << texture_id_
              << std::endl;]=])
  foreach(texture_patch IN ITEMS texture_retire texture_gpu_callback texture_sw_callback texture_register)
    string(FIND "${viewport_code}" "${${texture_patch}}" texture_offset)
    if(texture_offset EQUAL -1)
      message(FATAL_ERROR "media_kit_video texture callback changed; review ${texture_patch}")
    endif()
    string(REPLACE "${${texture_patch}}" "${${texture_patch}_fixed}" viewport_code "${viewport_code}")
  endforeach()
  # Resize withdrew this ID under the mutex above. Do not retain the upstream
  # unsynchronized second assignment while callbacks are polling it.
  set(texture_zero [=[        });
    texture_id_ = 0;
  }
  // H/W]=])
  set(texture_zero_fixed [=[        });
  }
  // H/W]=])
  string(FIND "${viewport_code}" "${texture_zero}" texture_zero_offset)
  if(texture_zero_offset EQUAL -1)
    message(FATAL_ERROR "media_kit_video resize teardown changed; review texture publication")
  endif()
  string(REPLACE "${texture_zero}" "${texture_zero_fixed}" viewport_code "${viewport_code}")
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
