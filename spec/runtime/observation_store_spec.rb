require "tmpdir"

RSpec.describe RailsContractSync::Runtime::ObservationStore do
  it "appends and reads back JSONL, creating parent dirs" do
    Dir.mktmpdir do |dir|
      store = described_class.new(File.join(dir, "nested", "obs.jsonl"))
      store.append("verb" => "GET", "path_template" => "/a")
      store.append("verb" => "POST", "path_template" => "/b")
      expect(store.all).to eq([
        { "verb" => "GET", "path_template" => "/a" },
        { "verb" => "POST", "path_template" => "/b" }
      ])
    end
  end

  it "clear empties the store" do
    Dir.mktmpdir do |dir|
      store = described_class.new(File.join(dir, "obs.jsonl"))
      store.append("verb" => "GET")
      store.clear
      expect(store.all).to eq([])
    end
  end
end
