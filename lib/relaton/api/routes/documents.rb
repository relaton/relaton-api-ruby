# frozen_string_literal: true

require "json"
require "uri"

module Relaton
  module Api
    module Routes
      # GET /v3/documents/{key} — full Relaton JSON by any indexed id
      class Documents
        KEY_PATTERN = %r{\A/v3/documents/(?<key>[^/]+)\z}.freeze

        def matches?(path)
          KEY_PATTERN.match?(path)
        end

        def call(env, app)
          key = URI.decode_www_form_component(KEY_PATTERN.match(env["PATH_INFO"])[:key])
          document = app.store.fetch(key)
          return not_found(key) unless document

          [200, { "content-type" => "application/json" }, [JSON.generate(document)]]
        end

        private

        def not_found(key)
          [404, { "content-type" => "application/problem+json" },
           [{ type: "about:blank", title: "Not Found",
              detail: "unknown key #{key}" }.to_json]]
        end
      end
    end
  end
end
