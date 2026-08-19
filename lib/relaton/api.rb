# frozen_string_literal: true

require "relaton/api/version"

module Relaton
  # Relaton API reference implementation. All constants load lazily via
  # autoloads declared here (the immediate parent namespace file).
  module Api
    autoload :Config, "relaton/api/config"
    autoload :App, "relaton/api/app"
    autoload :Routes, "relaton/api/routes"
    autoload :Store, "relaton/api/store"
  end
end
