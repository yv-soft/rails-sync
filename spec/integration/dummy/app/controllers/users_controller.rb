class UsersController < ActionController::API
  USERS = { 7 => { id: 7, name: "Ada" } }

  def show
    render json: USERS.fetch(params[:id].to_i)
  end

  def create
    attrs = params.require(:user).permit(:name)
    render json: { id: 8, name: attrs[:name] }, status: :created
  end
end
