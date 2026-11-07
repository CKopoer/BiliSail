require 'json'
lock = JSON.parse(File.read(File.join(__dir__, 'assets.lock.json')))
Pod::Spec.new do |s|
  s.name = 'FSPlayer'
  s.version = lock.fetch('version')
  s.summary = 'FSPlayer, the FFmpeg-based native media player.'
  s.homepage = lock.fetch('source')
  s.author = { 'debugly' => 'debugly@icloud.com' }
  s.license = { :type => 'LGPL-2.1-or-later', :file => 'FSPlayer/LICENSE' }
  s.source = { :http => "#{lock.fetch('baseUrl')}/#{lock.fetch('apple').fetch('archive')}",
               :sha256 => lock.fetch('apple').fetch('sha256') }
  s.vendored_frameworks = 'FSPlayer.xcframework'
  s.preserve_paths = 'FSPlayer/README.md', 'FSPlayer/CHANGELOG.md', 'FSPlayer/LICENSE'
  s.libraries = 'z', 'iconv', 'xml2', 'bz2', 'c++', 'lzma'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreMedia', 'CoreVideo', 'VideoToolbox', 'Metal'
  s.osx.frameworks = 'Cocoa', 'AudioUnit', 'OpenGL', 'GLKit', 'CoreImage'
  s.ios.frameworks = 'UIKit', 'OpenGLES'
  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'
end
