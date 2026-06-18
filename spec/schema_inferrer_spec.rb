RSpec.describe RailsContractSync::SchemaInferrer do
  describe ".infer" do
    it "types scalars" do
      expect(described_class.infer(1)).to eq("type" => "integer")
      expect(described_class.infer(1.5)).to eq("type" => "number")
      expect(described_class.infer("x")).to eq("type" => "string")
      expect(described_class.infer(true)).to eq("type" => "boolean")
      expect(described_class.infer(nil)).to eq("type" => "null")
    end

    it "infers objects with required = keys present" do
      expect(described_class.infer({ "a" => 1, "b" => "x" })).to eq(
        "type" => "object",
        "properties" => { "a" => { "type" => "integer" }, "b" => { "type" => "string" } },
        "required" => %w[a b]
      )
    end

    it "infers arrays by merging element schemas" do
      expect(described_class.infer([1, 2])).to eq(
        "type" => "array", "items" => { "type" => "integer" }
      )
    end

    it "treats empty arrays as items: any" do
      expect(described_class.infer([])).to eq("type" => "array", "items" => {})
    end
  end

  describe ".merge" do
    it "widens integer + number to number" do
      expect(described_class.merge({ "type" => "integer" }, { "type" => "number" }))
        .to eq("type" => "number")
    end

    it "makes a field nullable via type array" do
      expect(described_class.merge({ "type" => "string" }, { "type" => "null" }))
        .to eq("type" => %w[null string])
    end

    it "treats {} as any (identity)" do
      expect(described_class.merge({}, { "type" => "string" })).to eq("type" => "string")
    end

    it "unions object properties and intersects required" do
      a = described_class.infer({ "id" => 1, "name" => "x" })
      b = described_class.infer({ "id" => 2 })
      merged = described_class.merge(a, b)
      expect(merged["properties"].keys).to contain_exactly("id", "name")
      expect(merged["required"]).to eq(["id"]) # name absent in b -> optional
    end

    it "keeps required as an empty array when objects share no required keys" do
      a = described_class.infer({ "a" => 1 })
      b = described_class.infer({ "b" => 2 })
      merged = described_class.merge(a, b)
      expect(merged["properties"].keys).to contain_exactly("a", "b")
      expect(merged["required"]).to eq([])
    end
  end

  describe ".infer_all" do
    it "reduces multiple observations" do
      expect(described_class.infer_all([{ "a" => 1 }, { "a" => 2, "b" => 3 }]))
        .to eq(
          "type" => "object",
          "properties" => { "a" => { "type" => "integer" }, "b" => { "type" => "integer" } },
          "required" => ["a"]
        )
    end

    it "returns {} for no observations" do
      expect(described_class.infer_all([])).to eq({})
    end
  end
end
