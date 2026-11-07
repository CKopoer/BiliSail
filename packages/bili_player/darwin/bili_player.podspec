Pod::Spec.new do |s|
  s.name = 'bili_player'
  s.version = '0.1.0'
  s.summary = 'BiliSail native FSPlayer bridge.'
  s.homepage = 'https://github.com/CKopoer/BiliSail'
  s.license = { :type => 'See accompanying notices', :file => '../native/NOTICE.md' }
  s.author = { 'BiliSail' => '' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/BiliPlayerPlugin.h'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.dependency 'FSPlayer', '= 1.1.2'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '13.0'
  s.frameworks = 'CoreVideo'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
