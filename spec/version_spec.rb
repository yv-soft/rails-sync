RSpec.describe RailsContractSync do
  it "has a semantic version string" do
    expect(RailsContractSync::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
