# frozen_string_literal: true

require "base64"
require "tmpdir"
require "fileutils"
require "json"
require "rack/mock"
require "relaton/api"

# The v3 surface (TODO.api/03 on the Ruby reference stack): Accept
# negotiation, strong ETags with immutable caching, If-None-Match 304s,
# HEAD, cursor-paginated collection with Link headers, RFC 9457 errors.
RSpec.describe "the /v3 surface" do
  let(:dir) { Dir.mktmpdir }
  let(:app) { Relaton::Api::App.new(Relaton::Api::Config.new(name: "test-api", data_dir: dir)) }

  around do |ex|
    FileUtils.mkdir_p(File.join(dir, "rfcs"))
    write_doc("rfc3986.yaml", "RFC 3986", "Uniform Resource Identifier (URI): Generic Syntax", "2005-01-01")
    write_doc("rfc8446.yaml", "RFC 8446", "The Transport Layer Security (TLS) Protocol Version 1.3", "2018-08-01")
    write_doc("rfc9110.yaml", "RFC 9110", "HTTP Semantics", "2022-06-01")
    ex.run
    FileUtils.remove_entry(dir)
  end

  def write_doc(name, id, title, date)
    File.write(File.join(dir, "rfcs", name), <<~YAML)
      ---
      schema_version: v1.5.6
      type: standard
      title:
      - content: '#{title}'
        type: main
        language:
        - en
      docidentifier:
      - content: #{id}
        type: IETF
        primary: true
      date:
      - type: published
        on: '#{date}'
    YAML
  end

  describe "GET /v3/documents/{key}" do
    it "serves the model JSON by default" do
      res = Rack::MockRequest.new(app).get("/v3/documents/RFC%208446")
      expect(res.status).to eq(200)
      expect(res["content-type"]).to eq("application/json")
      body = JSON.parse(res.body)
      expect(body.dig("docidentifier", 0, "content")).to eq("RFC 8446")
    end

    it "negotiates yaml and xml via Accept, with format as the override" do
      get = ->(path, headers = nil) { Rack::MockRequest.new(app).get(path, headers || {}) }
      expect(get.call("/v3/documents/RFC%208446", "HTTP_ACCEPT" => "application/yaml")["content-type"])
        .to eq("application/yaml")
      expect(get.call("/v3/documents/RFC%208446", "HTTP_ACCEPT" => "application/relaton+xml")["content-type"])
        .to eq("application/relaton+xml")
      expect(get.call("/v3/documents/RFC%208446?format=yaml")["content-type"]).to eq("application/yaml")
      # An Accept naming nothing relaton stays JSON.
      expect(get.call("/v3/documents/RFC%208446", "HTTP_ACCEPT" => "text/html")["content-type"])
        .to eq("application/json")
    end

    it "stamps a strong ETag with immutable caching and answers 304" do
      res = Rack::MockRequest.new(app).get("/v3/documents/RFC%208446")
      etag = res["etag"]
      expect(etag).to match(/\A"[0-9a-f]{64}"\z/)
      expect(res["cache-control"]).to eq("public, max-age=31536000, immutable")

      again = Rack::MockRequest.new(app).get("/v3/documents/RFC%208446", "HTTP_IF_NONE_MATCH" => etag)
      expect(again.status).to eq(304)
      expect(again.body).to be_empty
    end

    it "answers HEAD with the headers and no body" do
      res = Rack::MockRequest.new(app).head("/v3/documents/RFC%208446")
      expect(res.status).to eq(200)
      expect(res["etag"]).to be_truthy
      expect(res.body).to eq("")
    end

    it "404s as problem+json for an unknown key" do
      res = Rack::MockRequest.new(app).get("/v3/documents/RFC%20NOTHING")
      expect(res.status).to eq(404)
      expect(res["content-type"]).to eq("application/problem+json")
      expect(JSON.parse(res.body)["title"]).to eq("Not Found")
    end
  end

  describe "GET /v3/documents" do
    it "pages docid-ordered with a next Link header and follows the cursor" do
      first = Rack::MockRequest.new(app).get("/v3/documents?limit=2")
      expect(first.status).to eq(200)
      body = JSON.parse(first.body)
      expect(body["items"].map { |i| i["key"] }).to eq(["RFC 3986", "RFC 8446"])
      expect(body["next_cursor"]).to eq(Base64.urlsafe_encode64("RFC 8446"))
      expect(first["link"]).to include('rel="next"')

      second = Rack::MockRequest.new(app).get("/v3/documents?limit=2&cursor=#{body['next_cursor']}")
      page2 = JSON.parse(second.body)
      expect(page2["items"].map { |i| i["key"] }).to eq(["RFC 9110"])
      expect(page2["next_cursor"]).to be_nil
    end

    it "points item api links at the v3 document route" do
      body = JSON.parse(Rack::MockRequest.new(app).get("/v3/documents").body)
      expect(body["items"].first["api"]).to eq("/v3/documents/RFC%203986")
    end

    it "filters by title query" do
      body = JSON.parse(Rack::MockRequest.new(app).get("/v3/documents?q=tls").body)
      expect(body["items"].map { |i| i["key"] }).to eq(["RFC 8446"])
    end

    it "422s an invalid cursor as problem+json" do
      res = Rack::MockRequest.new(app).get("/v3/documents?cursor=%21%21not-base64%21%21")
      expect(res.status).to eq(422)
      expect(res["content-type"]).to eq("application/problem+json")
      expect(JSON.parse(res.body)["title"]).to eq("Unprocessable Content")
    end
  end
end
