# frozen_string_literal: true

module Relaton
  module Api
    # Immutable deployment configuration.
    class Config
      attr_reader :name, :data_dir

      def initialize(name:, data_dir:)
        @name = name
        @data_dir = data_dir
      end

      # The release banner's release half: the API's own version.
      def release
        VERSION
      end

      # The release banner's model half: the Relaton model line the
      # stored documents serialize against (lazy — only the version
      # file, never the full registry).
      def model_version
        require "relaton/version"
        ::Relaton::VERSION
      end
    end
  end
end
