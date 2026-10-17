require 'json'
require 'uri'
require 'tmpdir'
require 'pathname'
require 'minitest/autorun'
require_relative '../media_kit_viewport'

# Run after flutter pub get. Exercise the real pinned dependency input and a
# minimal Pods project double; this is not macOS rendering/Swift compilation.
class MediaKitViewportTest < Minitest::Test
  Reference = Struct.new(:path, :source_tree)
  BuildFile = Struct.new(:file_ref)
  Phase = Struct.new(:files)
  Script = Struct.new(:name, :input_paths, :output_paths, :shell_script)
  Target = Struct.new(:name, :source_build_phase, :build_phases) do
    def shell_script_build_phases
      build_phases.grep(Script)
    end

    def new_shell_script_build_phase(name)
      script = Script.new(name)
      build_phases << script
      script
    end
  end
  Project = Struct.new(:targets)
  Installer = Struct.new(:pods_project)

  def upstream_source
    config = File.expand_path('../../.dart_tool/package_config.json', __dir__)
    entry = JSON.parse(File.read(config))['packages'].find { |item| item['name'] == 'media_kit_video' }
    uri = URI.parse(entry.fetch('rootUri'))
    path = URI::DEFAULT_PARSER.unescape(uri.path)
    root = uri.scheme == 'file' ? path : File.expand_path(path, File.dirname(config))
    File.read(File.join(root, 'macos/Classes/plugin/common/VideoOutput.swift'))
  end

  def test_rejects_dependency_drift
    assert_raises(RuntimeError) { ReelNestMediaKitViewport.patch('changed upstream') }
  end

  def test_pods_compiles_generated_copy_and_preserves_shared_source
    Dir.mktmpdir('reelnest-viewport-pod-') do |macos_root|
      source = File.join(macos_root, 'Flutter/ephemeral/.symlinks/plugins/media_kit_video/macos/Classes/plugin/common/VideoOutput.swift')
      FileUtils.mkdir_p(File.dirname(source))
      original = upstream_source
      File.write(source, original)
      reference = Reference.new('common/VideoOutput.swift', '<group>')
      target = Target.new('media_kit_video', Phase.new([BuildFile.new(reference)]), [])
      installer = Installer.new(Project.new([target]))
      2.times { ReelNestMediaKitViewport.apply(installer, macos_root: macos_root) }
      assert_equal original, File.read(source)
      assert_equal '<absolute>', reference.source_tree
      assert_includes reference.path, 'ephemeral/reelnest_media_kit/'
      generated = File.read(reference.path)
      assert_includes generated, 'worker.enqueue { [weak self] in'
      assert_includes generated, 'guard let self = self, !self.disposed, self.texture != nil'
      assert_includes generated, "self.height = height\n      // ReelNest:"
      assert_includes generated, "      self._updateCallback()\n"
      assert_equal 1, generated.scan('ReelNest: a paused decoder').length
      assert_equal 1, target.shell_script_build_phases.length
      phase = target.build_phases.first
      assert_equal [reference.path], phase.output_paths
      assert_includes phase.input_paths, source
      assert_includes phase.shell_script, '--generate-source'
    end
  end
end
