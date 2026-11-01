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

        QUERY_KEYS = %w[format year all_parts keep_year].freeze

        def call(env, app)
          key = URI.decode_www_form_component(KEY_PATTERN.match(env["PATH_INFO"])[:key])
          params = ::URI.decode_www_form(env["QUERY_STRING"].to_s).to_h
          entry = app.store.resolve(
            key, year: params["year"]&.to_i,
                 all_parts: params["all_parts"] == "true",
          )
          return not_found(key) unless entry

          case params["format"]
          when "xml"
            [200, { "content-type" => "text/xml" },
             [app.store.document_xml(entry)]]
          when "yaml"
            [200, { "content-type" => "text/yaml" },
             [app.store.document_yaml(entry)]]
          else
            [200, { "content-type" => "application/json" },
             [JSON.generate(app.store.document_hash(entry))]]
          end
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
