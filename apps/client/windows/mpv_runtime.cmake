# media-kit's 2023 Windows binary omits the FFmpeg mirror filters. Keep its
# import library/headers and ANGLE, but ship one pinned LGPL libmpv DLL for both
# the Dart API and the C++ texture plugin (never load a second copy by path).
if(NOT FLUTTER_TARGET_PLATFORM STREQUAL "windows-x64")
  message(FATAL_ERROR "The pinned libmpv runtime currently supports Windows x64 only")
endif()

set(reelnest_mpv_tag "2026-10-16-a2cd83c56d")
set(reelnest_mpv_name "mpv-dev-lgpl-x86_64-20261016-git-a2cd83c56d.7z")
set(reelnest_mpv_sha256 "63baee08e7a242952aa9a78a6bd172aaf3a2654cdb64361687c9d139e46fefcf")
set(reelnest_mpv_dll_sha256 "22a7cb13ded0a6e80137661f5321de9a43c586780e798e46c39d3395488ece5f")
set(reelnest_mpv_dir "${CMAKE_BINARY_DIR}/reelnest_mpv/${reelnest_mpv_tag}")
set(reelnest_mpv_archive "${reelnest_mpv_dir}/${reelnest_mpv_name}")
set(reelnest_mpv_dll "${reelnest_mpv_dir}/libmpv-2.dll")
file(MAKE_DIRECTORY "${reelnest_mpv_dir}")

set(reelnest_mpv_valid FALSE)
if(EXISTS "${reelnest_mpv_dll}")
  file(SHA256 "${reelnest_mpv_dll}" reelnest_mpv_actual)
  if(reelnest_mpv_actual STREQUAL reelnest_mpv_dll_sha256)
    set(reelnest_mpv_valid TRUE)
  endif()
endif()
if(NOT reelnest_mpv_valid)
  set(reelnest_mpv_archive_valid FALSE)
  if(EXISTS "${reelnest_mpv_archive}")
    file(SHA256 "${reelnest_mpv_archive}" reelnest_mpv_actual)
    if(reelnest_mpv_actual STREQUAL reelnest_mpv_sha256)
      set(reelnest_mpv_archive_valid TRUE)
    endif()
  endif()
  if(NOT reelnest_mpv_archive_valid)
    message(STATUS "Downloading pinned LGPL libmpv ${reelnest_mpv_tag}")
    foreach(reelnest_mpv_attempt RANGE 1 3)
      file(DOWNLOAD
        "https://github.com/zhongfly/mpv-winbuild/releases/download/${reelnest_mpv_tag}/${reelnest_mpv_name}"
        "${reelnest_mpv_archive}"
        TLS_VERIFY ON TIMEOUT 180 INACTIVITY_TIMEOUT 30
        STATUS reelnest_mpv_download
      )
      list(GET reelnest_mpv_download 0 reelnest_mpv_download_status)
      if(reelnest_mpv_download_status EQUAL 0)
        file(SHA256 "${reelnest_mpv_archive}" reelnest_mpv_actual)
        if(reelnest_mpv_actual STREQUAL reelnest_mpv_sha256)
          set(reelnest_mpv_archive_valid TRUE)
          break()
        endif()
      endif()
    endforeach()
    if(NOT reelnest_mpv_archive_valid)
      message(FATAL_ERROR "Pinned LGPL libmpv download/hash verification failed: ${reelnest_mpv_download}")
    endif()
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${reelnest_mpv_archive}" libmpv-2.dll
    WORKING_DIRECTORY "${reelnest_mpv_dir}"
    RESULT_VARIABLE reelnest_mpv_extract_status
  )
  if(NOT reelnest_mpv_extract_status EQUAL 0)
    message(FATAL_ERROR "Pinned LGPL libmpv extraction failed")
  endif()
  file(SHA256 "${reelnest_mpv_dll}" reelnest_mpv_actual)
  if(NOT reelnest_mpv_actual STREQUAL reelnest_mpv_dll_sha256)
    message(FATAL_ERROR "Pinned LGPL libmpv DLL hash does not match")
  endif()
endif()

set(reelnest_mpv_replaced FALSE)
foreach(library IN LISTS PLUGIN_BUNDLED_LIBRARIES)
  get_filename_component(library_name "${library}" NAME)
  if(library_name STREQUAL "libmpv-2.dll")
    list(REMOVE_ITEM PLUGIN_BUNDLED_LIBRARIES "${library}")
    set(reelnest_mpv_replaced TRUE)
  endif()
endforeach()
if(NOT reelnest_mpv_replaced)
  message(FATAL_ERROR "media-kit libmpv bundle changed; review the runtime replacement")
endif()
list(APPEND PLUGIN_BUNDLED_LIBRARIES "${reelnest_mpv_dll}")
