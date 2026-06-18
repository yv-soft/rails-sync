RSpec.describe RailsSync do
  it "has a semantic version string" do
    expect(RailsSync::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
