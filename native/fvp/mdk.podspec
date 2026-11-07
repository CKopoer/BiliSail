require 'json'

lock = JSON.parse(File.read(File.join(__dir__, 'assets.lock.json')))
asset = lock.fetch('assets').fetch('apple')

# Based on wang-bin/mdk-sdk v0.39.0/mdk.podspec. Replace its mutable nightly
# download with the same fixed release and digest used by the other platforms.
Pod::Spec.new do |s|
  s.name = 'mdk'
  s.version = lock.fetch('version')
  s.summary = 'Multimedia Development Kit'
  s.homepage = 'https://github.com/wang-bin/mdk-sdk'
  s.author = { 'Wang Bin' => 'wbsecg1@gmail.com' }
  s.license = { :type => 'Commercial', :text => <<-LICENSE
Copyright 2020-2025 WangBin
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
LICENSE
  }
  s.source = {
    :http => "#{lock.fetch('baseUrl')}/#{asset.fetch('archive')}",
    :sha256 => asset.fetch('sha256'),
  }
  s.vendored_frameworks = 'mdk-sdk/lib/mdk.xcframework'
  s.osx.deployment_target = '10.13'
  s.ios.deployment_target = '12.0'
  s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=*simulator*]' => 'i386' }
  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=*simulator*]' => 'i386' }
end
