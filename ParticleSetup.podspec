Pod::Spec.new do |s|
    s.name             = "ParticleSetup"
    s.version          = "0.8.1"
    s.summary          = "Particle iOS Device Setup library for easy integration of setup process for Particle devices in your app"
    s.description      = <<-DESC
                        Particle (formerly Spark) Device Setup library for integrating a customized setup process of Particle Wifi devices in your app
                        This library will allow you to easily invoke a standalone setup wizard UI for setting up
                        Particle devices (photon/P1) from within your app. Setup UI look & feel can be easily customized with custom brand
                        logos/colors/fonts/texts and instructional video. Further customization can be done by directly modifying the setup.storyboard file.
                        DESC
    s.homepage         = "https://github.com/spark/markoImake/particle-setup-ios"
    s.screenshots      = "http://i58.tinypic.com/15yhdeb.jpg"
    s.license          = 'Apache 2.0'
    s.author           = { "Marko Heyns" => "marko.heyns@bevie.co" }
    s.source           = { :git => "https://github.com/markoImake/particle-setup-ios/particle-setup-ios.git", :tag => s.version.to_s }
    s.social_media_url = 'https://twitter.com/particle'

    s.platform     = :ios, '8.0'
    s.requires_arc = true

    s.public_header_files = 'Classes/*.h'
    s.source_files  = 'Classes/*.h'

    s.resource_bundle = {'ParticleSetup' => 'Resources/**/*.{xcassets,storyboard}'}
    s.resources = "Resources/**/*.{xcassets,storyboard}"

    s.subspec 'Core' do |core|
        core.source_files  = 'Classes/User/**/*.{h,m}', 'Classes/UI/**/*'
        core.dependency 'Particle-SDK'
        core.dependency '1PasswordExtension'
        core.dependency 'ParticleSetup/Comm'
        core.ios.frameworks    = 'UIKit'
    end

    s.subspec 'Comm' do |comm|
        comm.source_files  = 'Classes/Comm/**/*'
        comm.ios.frameworks    = 'SystemConfiguration', 'Security'
    end



end
