# frozen_string_literal: true

require "yaml"

module Relaton
  module Api
    module Store
      # Reads documents from a dataset directory (Relaton YAML, any stream
      # layout). Builds an in-memory index at boot: one DocEntry per file
      # with the summary fields the API serves, plus a key map over every
      # docidentifier variant (uppercased, whitespace-stripped — the corpus
      # doctrine; datasets own richer variants via the #109 index).
      class FileSystem
        DocEntry = Struct.new(:file, :stream, :docid, :title, :year,
                              :doctype, :status, :ids)

        DEFAULT_SIZE = 25
        MAX_SIZE = 100

        attr_reader :data_dir

        def initialize(data_dir)
          @data_dir = data_dir
          @docs = []
          @keys = {}
          build_index
        end

        # Resolve a code to its DocEntry. Order: exact key; the undated
        # form (trailing ":YYYY" dropped — latest edition wins, or the
        # requested year); with all_parts the trailing "-<part>" also
        # drops before that.
        # -> DocEntry, or nil when nothing matches
        def resolve(key, year: nil, all_parts: false)
          key = key_of(key)
          exact = @keys[key]
          return exact if exact

          base = undated(key)
          base = base.sub(/-\d+\z/, "") if all_parts
          matches = @docs.select do |d|
            d.ids.any? { |i| (i == base) || i.start_with?("#{base}:") }
          end
          return nil if matches.empty?

          best = matches.max_by { |d| d.year.to_i }
          return best unless year

          matches.find { |d| d.year == year.to_i } || best
        end

        # Full-contract search: substring over titles and identifiers,
        # exact-value filters, one page of items in the Workers response
        # shape, and facets computed over the whole filtered set.
        def search(q: nil, flavor: nil, doctype: nil, year: nil,
                   status: nil, page: 0, size: DEFAULT_SIZE)
          size = DEFAULT_SIZE if size.nil? || size < 1
          size = MAX_SIZE if size > MAX_SIZE
          page = 0 if page.nil? || page.negative?

          filtered = @docs.select do |d|
            (flavor.nil? || d.stream == flavor) &&
              (doctype.nil? || d.doctype == doctype) &&
              (year.nil? || d.year == year.to_i) &&
              (status.nil? || d.status == status) &&
              (q.nil? || matches_query?(d, q))
          end

          facets = {
            "flavor" => facet(filtered, :stream),
            "doctype" => facet(filtered, :doctype),
            "status" => facet(filtered, :status),
          }
          items = filtered.sort_by { |d| [d.title.to_s, d.docid.to_s] }
                          .drop(page * size)
                          .first(size)
                          .map { |d| item(d) }
          { "total" => filtered.size, "page" => page, "size" => size,
            "items" => items, "facets" => facets }
        end

        # v3 collection page: the same filters as #search, docid-ordered,
        # paged by cursor (the docid the previous page ended on) instead of
        # page numbers. -> { items:, next_cursor: }
        def search_cursor(cursor: nil, limit: DEFAULT_SIZE, q: nil, flavor: nil,
                          doctype: nil, year: nil, status: nil)
          limit = DEFAULT_SIZE if limit.nil? || limit < 1
          limit = MAX_SIZE if limit > MAX_SIZE

          filtered = @docs.select do |d|
            (flavor.nil? || d.stream == flavor) &&
              (doctype.nil? || d.doctype == doctype) &&
              (year.nil? || d.year == year.to_i) &&
              (status.nil? || d.status == status) &&
              (q.nil? || matches_query?(d, q))
          end.sort_by { |d| d.docid.to_s }
          filtered = filtered.drop_while { |d| d.docid.to_s <= cursor.to_s } if cursor

          page = filtered.first(limit + 1)
          has_more = page.size > limit
          served = page.first(limit)
          { items: served.map { |d| collection_item(d) },
            next_cursor: has_more ? served.last.docid.to_s : nil }
        end

        # [{ stream:, count: }] per top-level stream directory
        def streams
          @docs.group_by(&:stream)
               .map { |stream, docs| { stream: stream, count: docs.size } }
               .sort_by { |s| s[:stream] }
        end

        def document_hash(entry)
          YAML.safe_load(File.read(entry.file), aliases: true)
        end

        def document_xml(entry)
          require "relaton"
          ::Relaton::Bib::Item.from_yaml(File.read(entry.file)).to_xml(bibdata: true)
        end

        def document_yaml(entry)
          File.read(entry.file)
        end

        private

        def matches_query?(doc, q)
          needle = q.downcase
          doc.title.to_s.downcase.include?(needle) ||
            doc.ids.any? { |i| i.downcase.include?(needle) }
        end

        def facet(docs, attr)
          docs.group_by { |d| d.send(attr) }
              .reject { |value, _| value.nil? }
              .map { |value, ds| { "value" => value, "count" => ds.size } }
              .sort_by { |f| -f["count"] }
        end

        def item(doc)
          {
            "docid" => doc.docid,
            "flavor" => doc.stream,
            "year" => doc.year,
            "doctype" => doc.doctype,
            "status" => doc.status,
            "title" => doc.title,
            "api" => "/api/v1/document?code=#{::URI.encode_www_form_component(doc.docid.to_s)}",
          }
        end

        def collection_item(doc)
          {
            "key" => doc.docid,
            "flavor" => doc.stream,
            "docid" => doc.docid,
            "title" => doc.title,
            "year" => doc.year,
            "doctype" => doc.doctype,
            "status" => doc.status,
            # encodeURIComponent's form (spaces as %20, not +).
            "api" => "/v3/documents/#{::URI.encode_www_form_component(doc.docid.to_s).gsub('+', '%20')}",
          }
        end

        def build_index
          Dir[File.join(@data_dir, "**", "*.yaml")].sort.each do |path|
            doc = YAML.safe_load(File.read(path), aliases: true) || {}
            ids = (doc["docidentifier"] || doc["docid"] || [])
                  .filter_map { |d| d.is_a?(Hash) ? (d["content"] || d["id"]) : d }
                  .reject { |i| i.to_s.empty? }
            next if ids.empty?

            entry = DocEntry.new(
              path, stream_of(path), ids.first.to_s, title_of(doc),
              year_of(doc, ids.first), doctype_of(doc), status_of(doc),
              ids.map { |i| key_of(i) },
            )
            @docs << entry
            ids.each { |id| @keys[key_of(id)] ||= entry }
          end
        end

        def title_of(doc)
          titles = Array(doc["title"])
          main = titles.select { |t| t.is_a?(Hash) && t["type"] == "main" }
          pool = main.empty? ? titles : main
          chosen = pool.find { |t| t.is_a?(Hash) && t["language"] == "en" } ||
                   pool.first
          chosen.is_a?(Hash) ? chosen["content"].to_s : chosen.to_s
        end

        def year_of(doc, primary_id)
          dates = Array(doc["date"])
          published = dates.find { |d| d.is_a?(Hash) && d["type"] == "published" }
          value = published && (published["on"] || published["at"] ||
                                published["from"])
          value.to_s[0, 4].to_i.nonzero? ||
            primary_id.to_s[/:(\d{4})/, 1]&.to_i
        end

        def doctype_of(doc)
          (doc.dig("ext", "doctype") || doc["doctype"] || doc["type"])&.to_s
        end

        def status_of(doc)
          st = doc["status"]
          return nil unless st.is_a?(Hash)

          stage = st["stage"]
          stage.is_a?(Hash) ? (stage["value"] || stage["content"]) : stage
        end

        def stream_of(path)
          rel = path.delete_prefix("#{@data_dir}/")
          rel.include?("/") ? rel.split("/").first : "data"
        end

        def undated(key)
          key.sub(/:\d{4}\z/, "")
        end

        def key_of(id)
          id.to_s.upcase.delete(" ")
        end
      end
    end
  end
end
