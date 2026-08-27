class SessionsController < ApplicationController
  def new
  end

  def create
    login = params.dig(:user, :login)
    user = User.find_for_database_authentication(login: login)

    if user&.valid_password?(params.dig(:user, :password))
      sign_in(user)
      redirect_to root_path, notice: "Đăng nhập thành công"
    else
      flash.now[:alert] = "Thông tin đăng nhập không đúng"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out(current_user)
    redirect_to root_path, notice: "Đã đăng xuất"
  end
end
