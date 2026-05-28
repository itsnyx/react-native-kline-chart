
Pod::Spec.new do |s|
  s.name         = "RNKLineView"
  s.version      = "0.1.0"
  s.summary      = "High-performance candlestick chart component for React Native"
  s.description  = <<-DESC
                  A professional K-Line (candlestick) chart library for React Native
                  with interactive drawing tools, technical indicators, and real-time
                  data support for iOS and Android.
                   DESC
  s.homepage     = "https://github.com/itsnyx/react-native-kline-chart"
  s.license      = { :type => "Apache-2.0", :file => "LICENSE" }
  s.author             = { "itsnyx" => "xitsnyx@gmail.com" }
  s.platform     = :ios, "13.0"
  s.source       = { :git => "https://github.com/itsnyx/react-native-kline-chart.git", :tag => s.version }
  s.source_files  = "ios/Classes/**/*"
  s.requires_arc = true
  s.swift_version = "5.0"

  s.dependency "React-Core"
  s.dependency "lottie-ios", ">= 4.0"
end
