# frozen_string_literal: true

require "yaml"

module Relaton
  module Api
    module Store
      # Reads documents from a dataset directory (Relaton YAML, any stream
      # layout). Builds a lookup map at boot from every docidentifier
      # variant; keys are uppercased, whitespace-stripped (the corpus
      # doctrine — datasets own richer variants via the #109 index).
      class FileSystem
        KeyEntry = Struct.new(:file, :docid)

        def initialize(data_dir)
          @data_dir = data_dir
          @keys = {}
          @counts = Hash.new(0)
          build_index
        end

        def fetch(key)
          entry = @keys[key.to_s.upcase.delete(" ")]
          return nil unless entry

          document(entry)
        end

        # [{ stream:, count: }] per top-level stream directory
        def streams
          @counts.sort.map { |stream, count| { stream: stream, count: count } }
        end

        private

        def build_index
          Dir[File.join(@data_dir, "**", "*.yaml")].sort.each do |path|
            doc = YAML.safe_load(File.read(path), aliases: true) || {}
            ids = (doc["docidentifier"] || doc["docid"] || [])
                  .filter_map { |d| d["content"] || d["id"] }
            next if ids.empty?

            @counts[stream_of(path)] += 1
            entry = KeyEntry.new(path, ids.first)
            ids.each { |id| @keys[key_of(id)] ||= entry }
          end
        end

        def stream_of(path)
          rel = path.delete_prefix("#{@data_dir}/")
          rel.include?("/") ? rel.split("/").first : "data"
        end

        def key_of(id)
          id.to_s.upcase.delete(" ")
        end

        # The dataset YAML is already the model serialization; serving it
        # as JSON is a passthrough, not a re-serialization.
        def document(entry)
          YAML.safe_load(File.read(entry.file), aliases: true)
        end
      end
    end
  end
end
