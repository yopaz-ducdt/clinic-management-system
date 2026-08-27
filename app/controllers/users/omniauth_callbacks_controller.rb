class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    user = User.from_omniauth(request.env["omniauth.auth"])

    if user.persisted?
      sign_in(user)
      if user.status == "pending_profile"
        redirect_to edit_profile_completion_path, notice: "Vui lòng bổ sung thông tin căn cước công dân và số điện thoại"
      else
        redirect_to root_path, notice: "Đăng nhập Google thành công"
      end
    else
      redirect_to new_user_session_path, alert: "Đăng nhập Google thất bại"
    end
  end

  def failure
    redirect_to new_user_session_path, alert: "Đăng nhập Google thất bại"
  end
end
