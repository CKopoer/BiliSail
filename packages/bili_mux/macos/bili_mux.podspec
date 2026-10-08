Pod::Spec.new do |s|
  s.name = 'bili_mux'
  s.version = '0.1.0'
  s.summary = 'Local MP4 stream-copy muxing.'
  s.homepage = 'https://github.com/CKopoer/BiliSail'
  s.license = { :type => 'LGPL-2.1-or-later', :file => '../LICENSE-FFmpeg.txt' }
  s.author = { 'BiliSail' => '' }
  s.source = { :path => '.' }
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.vendored_frameworks = 'Frameworks/BiliMux.framework'
end
