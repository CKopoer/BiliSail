# Verify CocoaPods' actual Xcode project, including what Runner can import from
# the built framework. Source-level includes alone do not verify header export.
def bilisail_verify_media_kit_headers(target)
  return unless target.name == 'media_kit_video'

  public_headers = target.headers_build_phase.files.select do |file|
    (file.settings || {}).fetch('ATTRIBUTES', []).include?('Public')
  end.map { |file| File.basename(file.file_ref.path) }
  required = %w[client.h render.h render_gl.h media_kit_mpv.h]
  missing = required - public_headers
  unless missing.empty?
    raise "media-kit framework Public Headers missing: #{missing.join(', ')}"
  end
  puts "Verified media-kit framework Public Headers: #{required.join(', ')}"
end
