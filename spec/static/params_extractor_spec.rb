RSpec.describe RailsSync::Static::ParamsExtractor do
  it "reads require + scalar permits, wrapping under the required key" do
    source = <<~RUBY
      class UsersController < ApplicationController
        def create
          user = User.create(params.require(:user).permit(:name, :email))
        end
      end
    RUBY
    expect(described_class.extract(source)).to eq(
      "create" => { "user" => { "name" => nil, "email" => nil } }
    )
  end

  it "reads top-level scalar permits with no require" do
    source = <<~RUBY
      class SearchController < ApplicationController
        def index
          render json: search(params.permit(:q, :page))
        end
      end
    RUBY
    expect(described_class.extract(source)).to eq(
      "index" => { "q" => nil, "page" => nil }
    )
  end

  it "treats empty-array permits as arrays of scalars and key-lists as nested objects" do
    source = <<~RUBY
      class PostsController < ApplicationController
        def update
          params.require(:post).permit(:title, tags: [], author: [:name, :id])
        end
      end
    RUBY
    expect(described_class.extract(source)).to eq(
      "update" => { "post" => { "title" => nil, "tags" => [nil], "author" => { "name" => nil, "id" => nil } } }
    )
  end

  it "returns no entry for actions without a permit" do
    source = <<~RUBY
      class PingController < ApplicationController
        def show
          render json: { ok: true }
        end
      end
    RUBY
    expect(described_class.extract(source)).to eq({})
  end
end
