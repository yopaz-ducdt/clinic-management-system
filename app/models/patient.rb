class Patient < ApplicationRecord
  belongs_to :managed_by_user, class_name: "User"
end
