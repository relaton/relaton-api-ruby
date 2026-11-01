# frozen_string_literal: true

require "json"

module Relaton
  module Api
    module Routes
      # The /api/v1 contract surface — the same paths and shapes the
      # Workers stack serves at api.relaton.org, so the shared contract
      # fixtures pass against this stack unchanged.
      module ApiV1
        PROBLEM = { "content-type" => "application/problem+json" }.freeze

        def self.parse_query(env)
          query = env["QUERY_STRING"].to_s
          ::URI.decode_www_form(query).to_h
        end

        # GET /api/v1/document?code=...&year=&all_parts=&keep_year=
        #   -> text/xml bibdata (the model round-trip of the stored YAML)
        class Document
          PATH = %r{\A/api/v1/document\z}.freeze

          def matches?(path) = PATH.match?(path)

          def call(env, app)
            params = ApiV1.parse_query(env)
            code = params["code"].to_s.strip
            return bad_request("code parameter is required") if code.empty?

            entry = app.store.resolve(
              code,
              year: params["year"]&.to_i,
              all_parts: params["all_parts"] == "true",
            )
            return not_found unless entry

            [200, { "content-type" => "text/xml" },
             [app.store.document_xml(entry)]]
          end

          private

          def bad_request(detail)
            [400, PROBLEM,
             [{ type: "about:blank", title: "Bad Request",
                detail: detail }.to_json]]
          end

          def not_found
            [404, { "content-type" => "text/plain" },
             ["Resource doesn't exist."]]
          end
        end

        # GET /api/v1/search?q=&flavor=&doctype=&year=&status=&page=&size=
        #   -> { total, page, size, items[], facets{} }
        class Search
          PATH = %r{\A/api/v1/search\z}.freeze

          def matches?(path) = PATH.match?(path)

          def call(env, app)
            p = ApiV1.parse_query(env)
            result = app.store.search(
              q: presence(p["q"]), flavor: presence(p["flavor"]),
              doctype: presence(p["doctype"]), year: p["year"]&.to_i,
              status: presence(p["status"]), page: p["page"]&.to_i,
              size: p["size"]&.to_i,
            )
            [200, { "content-type" => "application/json" },
             [JSON.generate(result)]]
          end

          private

          def presence(value)
            v = value.to_s.strip
            v.empty? ? nil : v
          end
        end

        # GET /api/v1/version -> text/plain release banner
        class Version
          PATH = %r{\A/api/v1/version\z}.freeze

          def matches?(path) = PATH.match?(path)

          def call(_env, app)
            [200, { "content-type" => "text/plain" },
             ["Release: #{app.config.release}, " \
              "Relaton version: #{app.config.model_version}"]]
          end
        end
      end
    end
  end
end
