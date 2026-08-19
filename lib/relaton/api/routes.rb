# frozen_string_literal: true

module Relaton
  module Api
    # Route namespace; children declared here.
    module Routes
      autoload :Version, "relaton/api/routes/version"
      autoload :Documents, "relaton/api/routes/documents"
      autoload :Flavors, "relaton/api/routes/flavors"
    end
  end
end
