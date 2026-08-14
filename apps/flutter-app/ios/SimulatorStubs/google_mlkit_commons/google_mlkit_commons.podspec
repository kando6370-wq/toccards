Pod::Spec.new do |s|
  s.name = 'google_mlkit_commons'
  s.version = '0.12.0'
  s.summary = 'No-op ML Kit commons plugin for iOS simulator builds.'
  s.homepage = 'https://github.com/flutter-ml/google_ml_kit_flutter'
  s.license = { :type => 'MIT' }
  s.author = 'Kando'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m}'
  s.dependency 'Flutter'
  s.platform = :ios, '15.5'
  s.static_framework = true
end
