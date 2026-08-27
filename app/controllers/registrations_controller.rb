class RegistrationsController < ApplicationController
  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    @user.role = "patient"
    @user.status = "active"

    if @user.save
      sign_in(@user)
      redirect_to root_path, notice: "Đăng ký thành công"
    else
      flash.now[:alert] = "Có lỗi khi thực hiện đăng ký"
      render "new", status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(
      :email,
      :password,
      :phone,
      :national_id
    )
  end
end
