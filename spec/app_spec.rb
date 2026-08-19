# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"
require "rack/mock"
require "relaton/api"

RSpec.describe Relaton::Api::App do
  let(:dir) { Dir.mktmpdir }
  let(:app) do
    described_class.new(Relaton::Api::Config.new(name: "test-api", data_dir: dir))
  end

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
      - content: 10.17487/RFC3986
        type: DOI
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

  it "serves /v3/version" do
    res = Rack::MockRequest.new(app).get("/v3/version")
    expect(res.status).to eq(200)
    expect(JSON.parse(res.body)["name"]).to eq("test-api")
  end

  it "serves a document by primary key as full model JSON" do
    res = Rack::MockRequest.new(app).get("/v3/documents/RFC%203986")
    expect(res.status).to eq(200)
    body = JSON.parse(res.body)
    expect(body.dig("docidentifier", 0, "content")).to eq("RFC 3986")
    expect(body.dig("title", 0, "content")).to include("Uniform Resource Identifier")
  end

  it "resolves any indexed docid variant (DOI form)" do
    res = Rack::MockRequest.new(app).get("/v3/documents/10.17487%2FRFC3986")
    expect(res.status).to eq(200)
    expect(JSON.parse(res.body).dig("docidentifier", 0, "content")).to eq("RFC 3986")
  end

  it "lists stream coverage" do
    res = Rack::MockRequest.new(app).get("/v3/flavors")
    expect(JSON.parse(res.body)).to eq([{ "stream" => "rfcs", "count" => 2 }])
  end

  it "returns problem+json for unknowns" do
    res = Rack::MockRequest.new(app).get("/v3/documents/nope")
    expect(res.status).to eq(404)
    expect(res["content-type"]).to include("application/problem+json")
  end
end
