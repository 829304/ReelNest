require 'fileutils'
require 'shellwords'

# Generate a local compilation input, leaving the shared Pub cache unchanged.
# Keep heavy resize/render work on media_kit_video's existing serial worker.
module ReelNestMediaKitViewport
  ORIGINAL = <<'SWIFT'.freeze
  public func setSize(width: Int64?, height: Int64?) {
    worker.enqueue {
      self.width = width
      self.height = height
    }
  }
SWIFT

  REPLACEMENT = <<'SWIFT'.freeze
  public func setSize(width: Int64?, height: Int64?) {
    worker.enqueue { [weak self] in
      guard let self = self, !self.disposed, self.texture != nil, self.textureId >= 0 else { return }
      self.width = width
      self.height = height
      // ReelNest: a paused decoder may never issue another update callback.
      // Resize, render the current frame and notify Flutter on the same worker.
      self._updateCallback()
    }
  }
SWIFT

  def self.patch(source)
    source = source.gsub("\r\n", "\n")
    unless source.scan(ORIGINAL).length == 1
      raise 'media_kit_video SetSize changed; review the macOS paused viewport patch'
    end
    source.sub(ORIGINAL, REPLACEMENT)
  end

  def self.apply(installer, macos_root:)
    targets = installer.pods_project.targets.select { |target| target.name == 'media_kit_video' }
    raise 'Expected one media_kit_video CocoaPods target' unless targets.length == 1
    target = targets.first
    files = target.source_build_phase.files.select do |file|
      file.file_ref && file.file_ref.path && File.basename(file.file_ref.path) == 'VideoOutput.swift'
    end
    raise 'Expected one media_kit_video VideoOutput.swift input' unless files.length == 1

    generated = generate_source(macos_root)
    # CocoaPods resolves the plugin via a symlink into PubCache. Change only
    # this generated Pods project's compilation reference, not that source.
    files.first.file_ref.source_tree = '<absolute>'
    files.first.file_ref.path = generated

    # Also regenerate before Swift compilation when this helper or upstream
    # source changes. An unchanged Podfile does not otherwise rerun post_install.
    phase_name = 'ReelNest paused viewport source'
    phase = target.shell_script_build_phases.find { |item| item.name == phase_name }
    phase ||= target.new_shell_script_build_phase(phase_name)
    helper = File.expand_path(__FILE__)
    phase.input_paths = [helper, source_path(macos_root)]
    phase.output_paths = [generated]
    phase.shell_script = "/usr/bin/ruby #{Shellwords.escape(helper)} --generate-source #{Shellwords.escape(File.expand_path(macos_root))}\n"
    target.build_phases.delete(phase)
    target.build_phases.unshift(phase)
  end

  def self.source_path(macos_root)
    File.expand_path(File.join(macos_root, 'Flutter', 'ephemeral', '.symlinks', 'plugins',
                              'media_kit_video', 'macos', 'Classes', 'plugin', 'common', 'VideoOutput.swift'))
  end

  def self.generate_source(macos_root)
    generated = File.expand_path(File.join(macos_root, 'Flutter', 'ephemeral',
                                           'reelnest_media_kit', 'VideoOutput.swift'))
    contents = patch(File.read(source_path(macos_root), encoding: 'UTF-8'))
    FileUtils.mkdir_p(File.dirname(generated))
    File.write(generated, contents) unless File.exist?(generated) && File.read(generated) == contents
    generated
  end
end

if $PROGRAM_NAME == __FILE__
  raise 'Usage: media_kit_viewport.rb --generate-source MACOS_ROOT' unless ARGV.length == 2 && ARGV[0] == '--generate-source'
  ReelNestMediaKitViewport.generate_source(File.expand_path(ARGV[1]))
end
