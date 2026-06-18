require "tmpdir"

RSpec.describe RailsSync::OpenAPIDocument do
  it "seeds an OpenAPI 3.1 skeleton" do
    doc = described_class.new.to_h
    expect(doc["openapi"]).to eq("3.1.0")
    expect(doc["paths"]).to eq({})
    expect(doc["info"]).to include("title", "version")
  end

  it "sets and reads operations (verb stored lower-case)" do
    doc = described_class.new
    doc.set_operation("/users", "POST", { "responses" => {} })
    expect(doc.operation("/users", "post")).to eq("responses" => {})
    expect(doc.paths.keys).to eq(["/users"])
  end

  it "to_h sorts hashes recursively for stable output" do
    doc = described_class.new({ "openapi" => "3.1.0", "paths" => { "/b" => {}, "/a" => {} } })
    expect(doc.to_h["paths"].keys).to eq(["/a", "/b"])
  end

  it "round-trips through a file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "openapi.yml")
      doc = described_class.new
      doc.set_operation("/ping", "get", { "responses" => { "200" => { "description" => "ok" } } })
      doc.write(path)
      loaded = described_class.load_file(path)
      expect(loaded.operation("/ping", "get")).to eq("responses" => { "200" => { "description" => "ok" } })
    end
  end

  it "load_file on a missing path returns an empty skeleton" do
    expect(described_class.load_file("/no/such/file.yml").paths).to eq({})
  end

  it "deep-sorts nested hashes at every level" do
    doc = described_class.new({ "paths" => { "/b" => { "post" => {}, "get" => {} }, "/a" => {} } })
    sorted = doc.to_h
    expect(sorted["paths"].keys).to eq(["/a", "/b"])
    expect(sorted["paths"]["/b"].keys).to eq(["get", "post"])
  end
end
