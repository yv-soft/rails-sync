RSpec.describe RailsContractSync::Merger do
  def doc(paths)
    RailsContractSync::OpenAPIDocument.new({ "openapi" => "3.1.0", "info" => { "title" => "API", "version" => "1.0.0" }, "paths" => paths })
  end

  it "preserves human prose on operations that still exist" do
    existing = doc("/users" => { "get" => { "summary" => "List users", "responses" => {} } })
    fresh = doc("/users" => { "get" => { "responses" => { "200" => {} } } })
    merged = described_class.merge(existing, fresh).to_h
    expect(merged["paths"]["/users"]["get"]["summary"]).to eq("List users")
    expect(merged["paths"]["/users"]["get"]["responses"]).to eq("200" => {})
  end

  it "flags stale operations not present in fresh" do
    existing = doc("/legacy" => { "get" => { "responses" => {} } })
    fresh = doc("/users" => { "get" => { "responses" => {} } })
    merged = described_class.merge(existing, fresh).to_h
    expect(merged["paths"]["/legacy"]["get"]["x-rails-contract-sync-stale"]).to be(true)
    expect(merged["paths"]).to have_key("/users")
  end

  it "prunes stale operations when prune: true" do
    existing = doc("/legacy" => { "get" => { "responses" => {} } })
    fresh = doc("/users" => { "get" => { "responses" => {} } })
    merged = described_class.merge(existing, fresh, prune: true).to_h
    expect(merged["paths"]).not_to have_key("/legacy")
  end

  it "keeps the existing info block verbatim" do
    existing = doc("/users" => { "get" => { "responses" => {} } })
    existing_h = existing.to_h.merge("info" => { "title" => "My Real API", "version" => "2.3.0" })
    merged = described_class.merge(RailsContractSync::OpenAPIDocument.new(existing_h), doc({})).to_h
    expect(merged["info"]).to eq("title" => "My Real API", "version" => "2.3.0")
  end

  it "is idempotent" do
    existing = doc("/legacy" => { "get" => { "responses" => {} } })
    fresh = doc("/users" => { "get" => { "summary" => "x", "responses" => {} } })
    once = described_class.merge(existing, fresh)
    twice = described_class.merge(once, fresh)
    expect(twice.to_h).to eq(once.to_h)
  end
end
