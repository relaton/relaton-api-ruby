# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "relaton/api"

run Relaton::Api::App.new(
  Relaton::Api::Config.new(name: "my-sdo-api", data_dir: ENV.fetch("RELATON_DATA_DIR")),
)
