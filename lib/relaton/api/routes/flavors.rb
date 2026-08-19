# frozen_string_literal: true

require "json"

module Relaton
  module Api
    module Routes
      # GET /v3/flavors — stream coverage from the store
      class Flavors
        def matches?(path)
          path == "/v3/flavors"
        end

        def call(_env, app)
          [200, { "content-type" => "application/json" },
           [JSON.generate(app.store.streams)]]
        end
      end
    end
  end
end
