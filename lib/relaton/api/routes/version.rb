# frozen_string_literal: true

require "json"

module Relaton
  module Api
    module Routes
      # GET /v3/version
      class Version
        def matches?(path) = path == "/v3/version"

        def call(_env, app)
          [200, { "content-type" => "application/json" },
           [{ name: app.config.name, version: VERSION, model: "relaton" }.to_json]]
        end
      end
    end
  end
end
