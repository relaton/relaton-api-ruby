# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "uri"

module Relaton
  module Api
    module Routes
      # The v3 surface (same shape as the Workers stack's /v3/documents):
      # GET /v3/documents searches with cursor paging and Link headers,
      # GET /v3/documents/{key} serves one document with Accept negotiation
      # (application/json default, application/relaton+xml, application/yaml),
      # strong ETags with immutable caching, If-None-Match 304s and HEAD.
      # Errors are RFC 9457 problem+json.
      class Documents
        PATH_PATTERN = %r{\A/v3/documents(?:/(?<key>[^/]+))?\z}.freeze

        XML_TYPE = "application/relaton+xml"
        YAML_TYPE = "application/yaml"
        JSON_TYPE = "application/json"
        IMMUTABLE = "public, max-age=31536000, immutable"

        QUERY_KEYS = %w[cursor limit format q flavor doctype year status all_parts].freeze

        def matches?(path)
          PATH_PATTERN.match?(path)
        end

        def call(env, app)
          key = PATH_PATTERN.match(env["PATH_INFO"])[:key]
          params = query_of(env)
          return collection(env, app, params) unless key

          document(env, app, decode_key(key), params)
        end

        private

        def query_of(env)
          pairs = ::URI.decode_www_form(env["QUERY_STRING"].to_s)
          pairs.select { |k, _| QUERY_KEYS.include?(k) }.to_h
        end

        def decode_key(raw)
          ::URI.decode_www_form_component(raw)
        end

        def document(env, app, key, params)
          entry = app.store.resolve(
            key, year: params["year"]&.to_i,
                 all_parts: params["all_parts"] == "true",
          )
          return not_found(key) unless entry

          type = negotiate(params["format"], env["HTTP_ACCEPT"])
          body = body_of(app, entry, type)
          etag = %("#{Digest::SHA256.hexdigest(body)}")
          return not_modified(etag) if if_none_match?(env, etag)

          headers = { "content-type" => type, "etag" => etag, "cache-control" => IMMUTABLE }
          return [200, headers, []] if env["REQUEST_METHOD"] == "HEAD"

          [200, headers, [body]]
        end

        def body_of(app, entry, type)
          case type
          when JSON_TYPE then JSON.generate(app.store.document_hash(entry))
          when YAML_TYPE then app.store.document_yaml(entry)
          else app.store.document_xml(entry)
          end
        end

        # Explicit format wins; otherwise the first matching Accept token;
        # JSON when nothing names a relaton representation.
        def negotiate(format, accept)
          case format
          when "xml" then XML_TYPE
          when "yaml" then YAML_TYPE
          when "json" then JSON_TYPE
          end || begin
            offered = accept.to_s.split(",").map { |t| t.split(";").first.to_s.strip.downcase }
            offered.each do |type|
              return XML_TYPE if type == XML_TYPE || type == "text/xml"
              return YAML_TYPE if type == YAML_TYPE || type == "text/yaml"
            end
            JSON_TYPE
          end
        end

        def if_none_match?(env, etag)
          env["HTTP_IF_NONE_MATCH"].to_s.split(",").map(&:strip).include?(etag)
        end

        def not_modified(etag)
          [304, { "etag" => etag, "cache-control" => IMMUTABLE }, []]
        end

        # Docid-ordered cursor paging: the cursor is the url-safe base64 of
        # the last docid served; the Link header carries it when more pages
        # remain.
        def collection(env, app, params)
          cursor = params["cursor"] && begin
            Base64.urlsafe_decode64(params["cursor"])
          rescue ArgumentError
            nil
          end
          return unprocessable("cursor is not a valid token") if params["cursor"] && cursor.nil?

          result = app.store.search_cursor(
            cursor: cursor, limit: params["limit"]&.to_i,
            q: params["q"], flavor: params["flavor"],
            doctype: params["doctype"], year: params["year"]&.to_i,
            status: params["status"],
          )

          # The cursor is opaque on the wire: the url-safe base64 of the
          # last docid, the same encoding the Workers stack uses.
          token = result[:next_cursor] && Base64.urlsafe_encode64(result[:next_cursor])
          headers = {}
          if token
            query = { cursor: token, limit: params["limit"] }.compact
            headers["link"] = %(</v3/documents?#{::URI.encode_www_form(query)}>; rel="next")
          end
          [200, { "content-type" => JSON_TYPE }.merge(headers),
           [JSON.generate(items: result[:items], next_cursor: token)]]
        end

        def not_found(key)
          [404, { "content-type" => "application/problem+json" },
           [{ type: "about:blank", title: "Not Found",
              status: 404, detail: "unknown key #{key}" }.to_json]]
        end

        def unprocessable(detail)
          [422, { "content-type" => "application/problem+json" },
           [{ type: "about:blank", title: "Unprocessable Content",
              status: 422, detail: detail }.to_json]]
        end
      end
    end
  end
end
