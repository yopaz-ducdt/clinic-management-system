class ProfileCompletionsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_pending_profile

  def edit
  end

  def update
    if current_user.update(profile_params.merge(status: "active"))
      redirect_to root_path, notice: "Hoàn tất hồ sơ tài khoản"
    else
      flash.now[:alert] = "Có lỗi xảy ra, vui lòng kiểm tra lại thông tin đã nhập"
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(
      :phone,
      :national_id
    )
  end

  def require_pending_profile
    redirect_to root_path if current_user.status != "pending_profile"
  end
end
