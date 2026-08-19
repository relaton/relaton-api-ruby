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
    end
  end
end
