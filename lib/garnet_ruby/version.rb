# frozening_literal: true

module GarnetRuby
  GARNET_VERSION_MAJOR = 0
  GARNET_VERSION_MINOR = 1
  GARNET_VERSION_TEENY = 0

  GARNET_VERSION = "#{GARNET_VERSION_MAJOR}.#{GARNET_VERSION_MINOR}.#{GARNET_VERSION_TEENY}"
  VERSION = GARNET_VERSION
  GARNET_ENGINE = 'garnet'
  GARNET_RUBY_VERSION = '2.6.5'
  GARNET_PLATFORM = "#{RUBY_ENGINE}_#{RUBY_VERSION}-#{RUBY_PLATFORM}"
  
  GARNET_RELEASE_YEAR = 2020
  GARNET_RELEASE_MONTH = 2
  GARNET_RELEASE_DAY = 6
  GARNET_RELEASE_DATE = "#{GARNET_RELEASE_YEAR}-#{GARNET_RELEASE_MONTH.to_s.rjust(2, '0')}-#{GARNET_RELEASE_DAY.to_s.rjust(2, '0')}"

  GARNET_BIRTH_YEAR = "2019"
  GARNET_AUTHOR = "Daniel Smith"

  GARNET_DESCRIPTION = "garnet #{GARNET_VERSION} (#{GARNET_RELEASE_DATE}) [#{GARNET_PLATFORM}]"
  GARNET_COPYRIGHT = "garnet - Copyright (C) #{GARNET_BIRTH_YEAR}-#{GARNET_RELEASE_YEAR} #{GARNET_AUTHOR}"
end
