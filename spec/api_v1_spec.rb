# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"
require "rack/mock"
require "relaton/api"

RSpec.describe "the /api/v1 contract surface" do
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

  it "serves a document as bibdata XML by code" do
    res = Rack::MockRequest.new(app).get("/api/v1/document?code=RFC%203986")
    expect(res.status).to eq(200)
    expect(res["content-type"]).to eq("text/xml")
    expect(res.body).to include("<bibdata")
    expect(res.body).to include("Uniform Resource Identifier")
  end

  it "answers 404 text/plain for an unknown code" do
    res = Rack::MockRequest.new(app).get("/api/v1/document?code=NOSUCH99")
    expect(res.status).to eq(404)
    expect(res["content-type"]).to eq("text/plain")
  end

  it "answers 400 problem+json for a missing code" do
    res = Rack::MockRequest.new(app).get("/api/v1/document")
    expect(res.status).to eq(400)
    expect(res["content-type"]).to include("application/problem+json")
  end

  it "searches with filters and facets" do
    res = Rack::MockRequest.new(app).get("/api/v1/search?q=transport&flavor=rfcs")
    expect(res.status).to eq(200)
    body = JSON.parse(res.body)
    expect(body["total"]).to eq(1)
    expect(body["size"]).to eq(25)
    item = body["items"].first
    expect(item["docid"]).to eq("RFC 8446")
    expect(item["flavor"]).to eq("rfcs")
    expect(item["title"]).to include("Transport Layer Security")
    expect(item["api"]).to start_with("/api/v1/document?code=")
    expect(body["facets"]["flavor"]).to eq([{ "value" => "rfcs", "count" => 1 }])
  end

  it "serves the release banner as text/plain" do
    res = Rack::MockRequest.new(app).get("/api/v1/version")
    expect(res.status).to eq(200)
    expect(res["content-type"]).to eq("text/plain")
    expect(res.body).to include("Release:")
  end

  it "serves a v3 document as XML on format=xml" do
    res = Rack::MockRequest.new(app).get("/v3/documents/RFC%203986?format=xml")
    expect(res.status).to eq(200)
    expect(res["content-type"]).to eq("text/xml")
    expect(res.body).to include("<bibdata")
  end

  it "serves a v3 document as raw YAML on format=yaml" do
    res = Rack::MockRequest.new(app).get("/v3/documents/RFC%203986?format=yaml")
    expect(res.status).to eq(200)
    expect(res["content-type"]).to eq("text/yaml")
    expect(res.body).to include("Uniform Resource Identifier")
  end
end
