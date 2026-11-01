# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"
require "rack/mock"
require "relaton/api"

# The shared contract runner's assertion classes, executed in-process
# against the booted Rack app and the local fixture dataset — the same
# fixtures committed at contract/fixtures-local.json. CI runs the same
# set through contract/run.mjs against a booted app (rake contract:local).
RSpec.describe "local contract fixtures" do
  FIXTURES = JSON.parse(
    File.read(File.expand_path("../contract/fixtures-local.json", __dir__)),
  ).fetch("fixtures")

  let(:dir) { Dir.mktmpdir }
  let(:app) { Relaton::Api::App.new(Relaton::Api::Config.new(name: "test-api", data_dir: dir)) }

  around do |ex|
    FileUtils.mkdir_p(File.join(dir, "rfcs"))
    File.write(File.join(dir, "rfcs", "rfc3986.yaml"), <<~YAML)
      ---
      schema_version: v1.5.6
      type: standard
      title:
      - content: 'Uniform Resource Identifier (URI): Generic Syntax'
        type: main
      docidentifier:
      - content: RFC 3986
        type: IETF
        primary: true
    YAML
    File.write(File.join(dir, "rfcs", "rfc8446.yaml"), <<~YAML)
      ---
      schema_version: v1.5.6
      type: standard
      title:
      - content: The Transport Layer Security (TLS) Protocol Version 1.3
        type: main
      docidentifier:
      - content: RFC 8446
        type: IETF
        primary: true
    YAML
    ex.run
    FileUtils.remove_entry(dir)
  end

  FIXTURES.each do |fixture|
    it fixture["name"] do
      res = Rack::MockRequest.new(app).get(fixture["path"], "HTTP_ACCEPT" => nil)
      want = fixture["expect"]
      expect(res.status).to eq(want["status"]) if want["status"]
      expect(res["content-type"].split(";").first).to eq(want["contentType"]) if want["contentType"]
      Array(want["bodyContains"]).each { |needle| expect(res.body).to include(needle) }
      Array(want["bodyNotContains"]).each { |needle| expect(res.body).not_to include(needle) }
      if want["json"]
        body = JSON.parse(res.body)
        want["json"].each do |path, test|
          value = path.split(".").reduce(body) { |acc, key| acc&.[](key) }
          expect(value.positive?).to be(true) if test == ">0"
        end
      end
    end
  end
end
