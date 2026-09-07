Pod::Spec.new do |s|
  s.name = 'google_mlkit_text_recognition'
  s.version = '0.16.0'
  s.summary = 'No-op ML Kit text recognition plugin for iOS simulator builds.'
  s.homepage = 'https://github.com/flutter-ml/google_ml_kit_flutter'
  s.license = { :type => 'MIT' }
  s.author = 'Kando'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m}'
  s.dependency 'Flutter'
  s.platform = :ios, '15.5'
  s.static_framework = true
end
