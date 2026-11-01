# frozen_string_literal: true

module Relaton
  module Api
    # Route namespace; children declared here.
    module Routes
      # The /api/v1 contract surface (same paths as api.relaton.org).
      module ApiV1
        autoload :Document, "relaton/api/routes/api_v1"
        autoload :Search, "relaton/api/routes/api_v1"
        autoload :Version, "relaton/api/routes/api_v1"
      end

      autoload :Version, "relaton/api/routes/version"
      autoload :Documents, "relaton/api/routes/documents"
      autoload :Flavors, "relaton/api/routes/flavors"
    end
  end
end
