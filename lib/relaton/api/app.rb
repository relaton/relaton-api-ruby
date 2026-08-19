# frozen_string_literal: true

require "json"

module Relaton
  module Api
    # Rack application. Routes are a registry — adding one is a new
    # autoloaded class plus one entry here (open/closed).
    class App
      ROUTES = [Routes::Version, Routes::Flavors, Routes::Documents].freeze

      attr_reader :config, :store

      def initialize(config)
        @config = config
        @store = Store::FileSystem.new(config.data_dir)
      end

      def call(env)
        route = ROUTES.map(&:new).find { |r| r.matches?(env["PATH_INFO"]) }
        return route.call(env, self) if route

        [404, { "content-type" => "application/problem+json" },
         [{ type: "about:blank", title: "Not Found" }.to_json]]
      end
    end
  end
end
