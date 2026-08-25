# Tài liệu phân tích & thiết kế — Web App Phòng khám đa khoa

**Stack**: Ruby on Rails + PostgreSQL + Solid Queue

---

## 1. Tổng quan

Web app production cho 1 phòng khám đa khoa, hỗ trợ bệnh nhân tự đặt lịch khám online, đồng thời hỗ trợ đặt lịch trực tiếp tại quầy cho bệnh nhân walk-in. Không tích hợp BHYT, không liên kết nhà thuốc ngoài.

## 2. Actors & phân quyền

| Actor         | Quyền chính                                                                                                                                                                                                           |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Bệnh nhân** | Đăng ký/đăng nhập, đặt lịch online, thanh toán online, xem hồ sơ/lịch sử/đơn thuốc của mình, hủy lịch (theo chính sách)                                                                                               |
| **Bác sĩ**    | Xem lịch khám của mình, đặt lịch hộ walk-in **vào lịch của chính mình**, xem/cập nhật hồ sơ bệnh nhân đã từng khám, kê đơn thuốc, đánh dấu no-show                                                                    |
| **Admin**     | Quản lý tài khoản/chuyên khoa/lịch làm việc bác sĩ, đặt lịch hộ walk-in cho bất kỳ bác sĩ nào, tạo hồ sơ bệnh nhân walk-in, xác nhận thanh toán tiền mặt, cấu hình chính sách hủy lịch, quản lý kho, đánh dấu no-show |

Phân quyền triển khai bằng **Pundit**.

## 3. Phạm vi nghiệp vụ (MVP)

1. Đặt lịch khám (online tự đặt + walk-in đặt hộ)
2. Hồ sơ bệnh nhân & lịch sử khám
3. Kê đơn thuốc điện tử (draft → issued)
4. Quản lý kho vật tư/thuốc nội bộ
5. Thanh toán online (VNPay) và tiền mặt tại quầy, kèm hủy/hoàn phí
6. Quản lý chuyên khoa & lịch làm việc bác sĩ

**Ngoài phạm vi**: BHYT, tích hợp nhà thuốc ngoài, vai trò lễ tân riêng, mobile app.

## 4. State & Transition

### 4.0 `users.status`

| Từ                | Sang     | Điều kiện / trigger                                                                                                                                                                    |
| ----------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `inactive`        | `active` | Bệnh nhân walk-in tự kích hoạt: cung cấp SĐT + CCCD khớp với record cũ, set email + password                                                                                           |
| `pending_profile` | `active` | Đăng nhập Google lần đầu tạo `users` với `status: pending_profile` (có email từ Google, chưa có phone/national_id) — sau khi điền đủ SĐT + CCCD ở form hoàn tất hồ sơ, chuyển `active` |

Bác sĩ/Admin luôn được tạo với `status: active` ngay từ đầu (Admin tạo tài khoản kèm email/password), không đi qua `inactive`.

### 4.1 `appointment_slots.status`

| Từ          | Sang        | Điều kiện / trigger                                                                                       |
| ----------- | ----------- | --------------------------------------------------------------------------------------------------------- |
| `available` | `held`      | Bệnh nhân/Admin/Bác sĩ chọn slot để đặt                                                                   |
| `held`      | `booked`    | Thanh toán thành công (online) hoặc Admin xác nhận tiền mặt                                               |
| `held`      | `available` | Hết 15 phút chưa thanh toán (job nền `ReleaseExpiredHoldsJob`) hoặc bệnh nhân chủ động hủy trong lúc held |
| `booked`    | `available` | Appointment bị hủy trong hạn miễn phí (trước X ngày)                                                      |

### 4.2 `appointments.status`

| Từ                | Sang        | Điều kiện / trigger                                                             |
| ----------------- | ----------- | ------------------------------------------------------------------------------- |
| `pending_payment` | `confirmed` | Payment `success`                                                               |
| `pending_payment` | `cancelled` | Hết hạn held không thanh toán, hoặc bệnh nhân chủ động hủy trước khi thanh toán |
| `confirmed`       | `cancelled` | Bệnh nhân/Admin hủy — áp dụng chính sách phí hủy theo mốc thời gian             |
| `confirmed`       | `completed` | Bác sĩ đóng ca khám (đã tạo `medical_record`)                                   |
| `confirmed`       | `no_show`   | Admin/Bác sĩ đánh dấu thủ công sau giờ hẹn                                      |

### 4.3 `payments.status`

| Từ        | Sang       | Điều kiện / trigger                                                                         |
| --------- | ---------- | ------------------------------------------------------------------------------------------- |
| `pending` | `success`  | Webhook VNPay/Momo báo thành công, hoặc Admin xác nhận tiền mặt                             |
| `pending` | `failed`   | Webhook báo lỗi/hết hạn phiên thanh toán cổng                                               |
| `failed`  | `pending`  | Bệnh nhân thử thanh toán lại (tạo attempt mới) — chỉ khi `appointment` còn trong hạn `held` |
| `success` | `refunded` | Hủy lịch có tính phí — hoàn phần còn lại sau khi trừ phí hủy                                |

### 4.4 `prescriptions.status`

| Từ      | Sang        | Điều kiện / trigger                                                         |
| ------- | ----------- | --------------------------------------------------------------------------- |
| `draft` | `issued`    | Bác sĩ xác nhận đơn — **trigger trừ kho tại đây**, không phải lúc tạo draft |
| `draft` | `cancelled` | Bác sĩ hủy đơn nháp                                                         |

## 5. Business Rules

- Một `appointment_slot` chỉ gắn với tối đa 1 `appointment` đang active (`pending_payment`/`confirmed`) tại một thời điểm — ràng buộc ở tầng DB (unique index), không chỉ tin vào application logic.
- Slot ở trạng thái `held` quá 15 phút mà appointment chưa `confirmed` → job nền tự động chuyển slot về `available` và appointment về `cancelled` (lý do: `expired`).
- Trừ kho (`inventory_transactions`) chỉ xảy ra khi `prescription: draft → issued`, không xảy ra lúc tạo draft hoặc lúc sửa draft.
- Hủy appointment:
  - Bệnh nhân tự hủy được (không cần Admin) khi appointment ở `pending_payment` hoặc `confirmed`.
  - Nếu hủy trước mốc `cancellation_free_days` (Admin cấu hình) → miễn phí, hoàn 100% nếu đã thanh toán.
  - Nếu hủy sau mốc đó → thu phí `cancellation_fee_percent` (Admin cấu hình), phần còn lại hoàn về cho bệnh nhân (`payments.status: refunded`).
- No-show chỉ được đánh dấu thủ công bởi Admin/Bác sĩ, không có job tự động ở MVP.
- Thanh toán thất bại: bệnh nhân được thử lại nếu appointment còn trong hạn `held`; hết hạn thì hệ thống tự hủy, không cho thử lại nữa (phải đặt slot mới).
- Webhook thanh toán phải **idempotent** — dùng `transaction_id` từ cổng làm khóa chống xử lý trùng (nếu webhook gọi lại nhiều lần với cùng `transaction_id`, chỉ xử lý 1 lần, các lần sau trả `200 OK` nhưng không đổi state).
- Bác sĩ chỉ được tạo lịch walk-in vào slot của chính mình; Admin được tạo cho bất kỳ bác sĩ nào.
- Bệnh nhân walk-in luôn có `users` record (`status: inactive`) được tạo cùng lúc với `patients` — không tồn tại `patients` mà thiếu `users`.
- Kích hoạt tài khoản `inactive`: bệnh nhân phải cung cấp **cả** SĐT và CCCD khớp với record cũ (không chỉ 1 trong 2), sau đó set email + password → `status: active`.
- Mọi `users` record (bất kể role, bất kể `status`) bắt buộc có `phone` và `national_id` ngay lúc tạo — kể cả bệnh nhân tự đăng ký online phải nhập CCCD ngay ở bước đăng ký, không để trống bổ sung sau. Mục đích: chống 1 người thật tạo nhiều tài khoản qua `national_id` (unique).
- 1 `users` (tài khoản) được quản lý nhiều `patients` (hồ sơ bệnh nhân) — hỗ trợ trường hợp phụ huynh đặt lịch cho con, hoặc 1 người đặt hộ nhiều thành viên gia đình. `patients.national_id` chỉ bắt buộc khi bệnh nhân đó có CCCD riêng (người lớn); trẻ em để trống.
- `patients`, `doctors`, `inventory_items` dùng **soft delete** (`deleted_at`) — không xóa cứng, vì `medical_records`/`appointments`/`prescription_items` cũ vẫn cần tham chiếu tới. Query mặc định luôn lọc `deleted_at IS NULL` qua scope tường minh, không dùng `default_scope`.
- Khi hủy appointment có phí, số tiền phí (`cancellation_fee_amount`) tính xong phải **lưu lại (snapshot)** ngay trên `appointments`, không tính lại từ `clinic_settings` mỗi lần xem — vì `clinic_settings` có thể đổi theo thời gian, làm sai lệch báo cáo tài chính của các lịch hẹn cũ.

## 6. Quan hệ dữ liệu (làm rõ theo góp ý)

- `Patient 1—N Appointment`
- `Appointment 1—1 MedicalRecord`
- ⇒ `Patient 1—N MedicalRecord`: nguồn sự thật là quan hệ **suy diễn** qua `Appointment`, nhưng để tối ưu cho lượng dữ liệu lớn, `medical_records.patient_id` được **denormalize trực tiếp** (có index), ghi 1 lần lúc tạo, không cho sửa qua API — tránh JOIN lặp lại ở query "lịch sử khám của 1 bệnh nhân" (một trong các truy vấn gọi thường xuyên nhất hệ thống).
- `Appointment 1—N Payment` (không phải 1—1 — vì cho phép nhiều lần thử thanh toán khi `failed`, chỉ 1 payment đạt `success`).

## 7. Danh sách thực thể (đầy đủ)

_(Đây là nguồn duy nhất cho cấu trúc từng bảng — không duy trì bảng "thay đổi" riêng để tránh 2 nguồn thông tin lệch nhau khi thiết kế cập nhật.)_

### `users`

| Cột                    | Kiểu      | Ghi chú                                                                                                                                                                                 |
| ---------------------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| id                     | uuid      | PK                                                                                                                                                                                      |
| email                  | string    | unique khi khác NULL — NULL cho tới khi kích hoạt                                                                                                                                       |
| password_digest        | string    | nullable — NULL cho tới khi kích hoạt                                                                                                                                                   |
| role                   | string    | `patient` / `doctor` / `admin`                                                                                                                                                          |
| phone                  | string    | **bắt buộc** với `status: active`/`inactive`, không unique (gia đình có thể dùng chung số); NULL cho phép khi `status: pending_profile` (đăng nhập Google lần đầu, chưa hoàn tất hồ sơ) |
| national_id            | string    | **bắt buộc** với `status: active`/`inactive`, unique — nguồn CCCD duy nhất, chống 1 người tạo nhiều tài khoản; NULL cho phép khi `status: pending_profile`                              |
| status                 | string    | `inactive` (walk-in, chưa đăng nhập được) / `pending_profile` (đăng nhập Google lần đầu, chưa đủ phone+national_id) / `active` (đăng nhập được)                                         |
| provider               | string    | nullable — `google` nếu đăng nhập qua OAuth, NULL nếu đăng ký thường                                                                                                                    |
| uid                    | string    | nullable — ID tài khoản Google, unique khi khác NULL                                                                                                                                    |
| created_at, updated_at | timestamp |                                                                                                                                                                                         |

### `patients`

| Cột                    | Kiểu      | Ghi chú                                                                                                                                                             |
| ---------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| id                     | uuid      | PK                                                                                                                                                                  |
| managed_by_user_id     | uuid      | FK → users, **not null** — tài khoản quản lý hồ sơ này (không nhất thiết là chính bệnh nhân); 1 user quản lý được nhiều `patients` (VD phụ huynh đặt cho nhiều con) |
| relationship           | string    | `self` (chính chủ tài khoản) / `child` / `dependent`                                                                                                                |
| national_id            | string    | **nullable**, unique khi khác NULL — chỉ có khi bệnh nhân đủ điều kiện tự có CCCD riêng (người lớn); để trống với trẻ em                                            |
| full_name              | string    |                                                                                                                                                                     |
| date_of_birth          | date      |                                                                                                                                                                     |
| gender                 | string    |                                                                                                                                                                     |
| address                | string    |                                                                                                                                                                     |
| deleted_at             | timestamp | nullable — soft delete, giữ toàn vẹn tham chiếu từ `medical_records`/`appointments` cũ                                                                              |
| created_at, updated_at | timestamp |                                                                                                                                                                     |

### `specialties`

| Cột         | Kiểu   | Ghi chú |
| ----------- | ------ | ------- |
| id          | uuid   | PK      |
| name        | string |         |
| description | text   |         |

### `doctors`

| Cột          | Kiểu      | Ghi chú                                                                                                  |
| ------------ | --------- | -------------------------------------------------------------------------------------------------------- |
| id           | uuid      | PK                                                                                                       |
| user_id      | uuid      | FK → users                                                                                               |
| specialty_id | uuid      | FK → specialties (1 bác sĩ = 1 chuyên khoa)                                                              |
| full_name    | string    |                                                                                                          |
| bio          | text      |                                                                                                          |
| deleted_at   | timestamp | nullable — soft delete khi bác sĩ nghỉ việc, giữ lịch sử `schedules`/`appointments`/`medical_records` cũ |

### `schedules`

Lịch làm việc định kỳ theo tuần — nguồn để job nền sinh `appointment_slots`.
| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | uuid | PK |
| doctor_id | uuid | FK → doctors |
| day_of_week | integer | 0–6 |
| start_time | time | |
| end_time | time | |

### `appointment_slots`

Slot cụ thể theo ngày, sinh tự động từ `schedules`.
| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | uuid | PK |
| doctor_id | uuid | FK → doctors |
| slot_date | date | |
| start_time | time | |
| end_time | time | |
| status | string | `available` / `held` / `booked` |
| held_until | timestamp | nullable, hết hạn giữ chỗ |

### `appointments`

| Cột                     | Kiểu    | Ghi chú                                                                                                                                                  |
| ----------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| id                      | uuid    | PK                                                                                                                                                       |
| patient_id              | uuid    | FK → patients                                                                                                                                            |
| doctor_id               | uuid    | FK → doctors                                                                                                                                             |
| slot_id                 | uuid    | FK → appointment_slots, **unique** trong các appointment active                                                                                          |
| created_by_user_id      | uuid    | FK → users — ai tạo lịch (bệnh nhân/Admin/Bác sĩ)                                                                                                        |
| booking_channel         | string  | `online` / `walk_in`                                                                                                                                     |
| status                  | string  | `pending_payment` / `confirmed` / `completed` / `cancelled` / `no_show`                                                                                  |
| notes                   | text    |                                                                                                                                                          |
| cancellation_fee_amount | decimal | nullable — snapshot số tiền phí hủy thực tế tại thời điểm hủy (không lưu %, vì `clinic_settings` có thể đổi sau đó, phải giữ đúng số đã áp dụng lúc hủy) |

### `medical_records`

| Cột            | Kiểu | Ghi chú                                                                                                                                                                                                                                 |
| -------------- | ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| id             | uuid | PK                                                                                                                                                                                                                                      |
| appointment_id | uuid | FK → appointments                                                                                                                                                                                                                       |
| doctor_id      | uuid | FK → doctors                                                                                                                                                                                                                            |
| diagnosis      | text |                                                                                                                                                                                                                                         |
| notes          | text |                                                                                                                                                                                                                                         |
| patient_id     | uuid | denormalize từ `appointments.patient_id` để query nhanh (tránh JOIN khi data lớn) — **có index**, chỉ ghi 1 lần lúc tạo record, không cho sửa qua API, không phải nguồn sự thật (đối chiếu `appointments.patient_id` khi nghi ngờ lệch) |

### `prescriptions`

| Cột               | Kiểu   | Ghi chú                          |
| ----------------- | ------ | -------------------------------- |
| id                | uuid   | PK                               |
| medical_record_id | uuid   | FK → medical_records             |
| status            | string | `draft` / `issued` / `cancelled` |
| notes             | text   |                                  |

### `prescription_items`

| Cột               | Kiểu    | Ghi chú              |
| ----------------- | ------- | -------------------- |
| id                | uuid    | PK                   |
| prescription_id   | uuid    | FK → prescriptions   |
| inventory_item_id | uuid    | FK → inventory_items |
| quantity          | decimal |                      |
| dosage            | string  |                      |
| instructions      | string  |                      |

### `inventory_items`

| Cột               | Kiểu      | Ghi chú                                                                                          |
| ----------------- | --------- | ------------------------------------------------------------------------------------------------ |
| id                | uuid      | PK                                                                                               |
| name              | string    |                                                                                                  |
| item_type         | string    | `medicine` / `supply`                                                                            |
| unit              | string    |                                                                                                  |
| quantity_in_stock | decimal   |                                                                                                  |
| reorder_threshold | decimal   |                                                                                                  |
| unit_price        | decimal   |                                                                                                  |
| deleted_at        | timestamp | nullable — soft delete khi ngừng sử dụng thuốc/vật tư, giữ tham chiếu từ `prescription_items` cũ |

### `inventory_transactions`

| Cột               | Kiểu    | Ghi chú                                                                                                                                                                                                             |
| ----------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| id                | uuid    | PK                                                                                                                                                                                                                  |
| inventory_item_id | uuid    | FK → inventory_items                                                                                                                                                                                                |
| transaction_type  | string  | `restock` / `dispense`                                                                                                                                                                                              |
| quantity          | decimal |                                                                                                                                                                                                                     |
| reference_type    | string  | polymorphic — VD `Prescription`                                                                                                                                                                                     |
| reference_id      | uuid    | polymorphic                                                                                                                                                                                                         |
| created_by        | uuid    | FK → users                                                                                                                                                                                                          |
| balance_after     | decimal | số dư tồn kho ngay sau giao dịch này — tránh phải `SUM()` lại toàn bộ lịch sử khi đối soát; **bắt buộc ghi trong cùng transaction có lock** với việc trừ/cộng `quantity_in_stock` để tránh sai số khi ghi đồng thời |

### `payments`

| Cột                     | Kiểu    | Ghi chú                                                                                               |
| ----------------------- | ------- | ----------------------------------------------------------------------------------------------------- |
| id                      | uuid    | PK                                                                                                    |
| appointment_id          | uuid    | FK → appointments (1—N)                                                                               |
| patient_id              | uuid    | FK → patients                                                                                         |
| amount                  | decimal |                                                                                                       |
| method                  | string  | `vnpay` / `momo` / `cash`                                                                             |
| status                  | string  | `pending` / `success` / `failed` / `refunded`                                                         |
| provider_transaction_id | string  | unique, dùng cho idempotency webhook                                                                  |
| confirmed_by_user_id    | uuid    | FK → users, nullable — Admin xác nhận tiền mặt                                                        |
| refunded_amount         | decimal | nullable — số tiền thực tế đã hoàn (có thể lệch nhẹ so với tính toán do phí cổng thanh toán/làm tròn) |

### `clinic_settings`

| Cột   | Kiểu   | Ghi chú                             |
| ----- | ------ | ----------------------------------- |
| id    | uuid   | PK                                  |
| key   | string | unique, VD `cancellation_free_days` |
| value | string |                                     |

---

## 8. Kiến trúc hệ thống

- **Rails 8 full MVC** (server-rendered) — không tách Frontend riêng, không có API JSON layer. Controller render view (ERB) trực tiếp, có thể dùng Hotwire/Turbo (đi kèm mặc định từ Rails 7+) để tăng tính tương tác (submit form không reload trang, cập nhật từng phần) mà không cần viết JavaScript framework riêng.
- **Auth**: Devise session-based (cookie), **không dùng JWT** — vì không còn nhu cầu API stateless cho SPA riêng biệt. Session là lựa chọn mặc định và đơn giản nhất cho MVC, ít bề mặt lỗi hơn (không cần quản lý token, không cần CORS). Bổ sung **đăng nhập Google** (`omniauth-google-oauth2` + `omniauth-rails_csrf_protection`) — vì Google chỉ cung cấp email, không có phone/CCCD, tài khoản tạo qua Google vào state trung gian `pending_profile` cho tới khi người dùng điền đủ thông tin bắt buộc.
- Pundit cho phân quyền, **Solid Queue** cho job nền (sinh slot, giải phóng hold hết hạn) — chạy trên chính PostgreSQL, không cần thêm service Redis.
- **Thanh toán**: VNPay/Momo qua redirect + webhook (idempotent theo `provider_transaction_id`) — webhook vẫn là 1 controller action riêng, trả JSON tối giản cho cổng thanh toán gọi vào (đây là ngoại lệ duy nhất còn "giống API" trong hệ thống).
- **Database**: PostgreSQL.

### Cấu trúc thư mục

```
app/
  controllers/     # theo resource: appointments, patients, doctors,
                    # medical_records, prescriptions, inventory_items,
                    # payments, webhooks/payments_controller.rb (JSON riêng)
  models/
  views/            # ERB, theo từng controller — form đặt lịch, hồ sơ bệnh nhân...
  policies/         # Pundit — 1 policy/model
  helpers/
  services/          # BookAppointmentService, IssuePrescriptionService,
                     # CancelAppointmentService (tính phí hủy), RefundService
  jobs/              # GenerateSlotsJob, ReleaseExpiredHoldsJob
config/routes.rb
db/migrate/
```

## 9. Chuẩn hóa Error Response

_(Chỉ còn áp dụng cho endpoint webhook thanh toán — nơi duy nhất còn trả JSON. Các action khác trong MVC trả lỗi qua `flash`/validation errors hiển thị trực tiếp trên form, theo cách chuẩn của Rails.)_

```json
{
  "error": {
    "code": "SLOT_ALREADY_HELD",
    "message": "Slot này đang được giữ bởi người khác"
  }
}
```

| HTTP status | Khi nào dùng                                                            |
| ----------- | ----------------------------------------------------------------------- |
| 400         | Request format sai                                                      |
| 401         | Chưa đăng nhập / token invalid                                          |
| 403         | Không đủ quyền (Pundit deny)                                            |
| 404         | Không tìm thấy resource                                                 |
| 409         | Conflict — VD slot đã bị held/booked bởi người khác                     |
| 422         | Validation fail theo field — dùng thêm `details: { field: [messages] }` |
| 500         | Lỗi hệ thống, không lộ chi tiết trong response                          |

## 10. Quyết định thiết kế quan trọng (rationale)

| Quyết định                                                                                 | Lý do                                                                                                                                                                            |
| ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tách `users` khỏi `patients`/`doctors`                                                     | Dùng chung 1 cơ chế auth cho 3 role                                                                                                                                              |
| `schedules` tách khỏi `appointment_slots`                                                  | Tránh xung đột đặt trùng giờ                                                                                                                                                     |
| Cơ chế `held` 15 phút cho cả online lẫn walk-in                                            | Tránh race condition, dùng chung logic                                                                                                                                           |
| Trừ kho ở `issued` thay vì lúc tạo draft                                                   | Tránh trừ kho cho đơn nháp chưa chốt                                                                                                                                             |
| `Appointment 1—N Payment`                                                                  | Cho phép retry khi thanh toán thất bại, giữ lịch sử                                                                                                                              |
| Unique index DB cho slot booking                                                           | Chặn double-booking triệt để, không chỉ dựa vào app logic                                                                                                                        |
| Session-based auth (Devise mặc định) thay vì JWT                                           | Không còn Frontend tách riêng nên không cần API stateless; session đơn giản hơn, ít bề mặt lỗi hơn (không token, không CORS), đúng "con đường chính" của Rails MVC               |
| Rails full MVC thay vì API-only + React SPA                                                | Giảm độ phức tạp cho người mới học Rails — 1 codebase, không cần đồng bộ API contract giữa 2 phía, không cần JWT/CORS                                                            |
| `users.status: pending_profile` cho đăng nhập Google                                       | Google OAuth không cung cấp phone/CCCD — cần state trung gian trước khi tài khoản đủ điều kiện `active`, tránh vi phạm ràng buộc bắt buộc đã chốt                                |
| Giữ Solid Queue, không đổi Sidekiq/Shoryuken+SQS                                           | Sidekiq thêm phụ thuộc Redis, Shoryuken+SQS thêm phụ thuộc AWS — cả 2 đều dư thừa cho quy mô 1 phòng khám, đi ngược hướng gọn gàng đã chọn                                       |
| Tự viết tích hợp VNPay, không dùng gem `vnpay` có sẵn                                      | Gem cộng đồng hiện có không được bảo trì (từ 2020, target Rails 5.1 cũ) — rủi ro tương thích/bảo mật cao hơn tự viết theo tài liệu chính thức VNPay                              |
| `users.national_id`/`phone` bắt buộc + unique                                              | Chống 1 người tạo nhiều tài khoản quản lý                                                                                                                                        |
| `patients.managed_by_user_id` (không unique) thay vì gắn cứng 1 user = 1 patient           | Trẻ em không có CCCD/SĐT riêng nên không thể tự có `users`; tách "tài khoản quản lý" khỏi "người được khám", đồng thời hỗ trợ 1 tài khoản đặt lịch cho nhiều thành viên gia đình |
| Soft delete (`deleted_at`) cho `patients`/`doctors`/`inventory_items`                      | Giữ toàn vẹn tham chiếu từ hồ sơ bệnh án/lịch hẹn/đơn thuốc cũ khi xóa "mềm"                                                                                                     |
| Snapshot `cancellation_fee_amount`/`refunded_amount` thay vì tính lại từ `clinic_settings` | `clinic_settings` đổi theo thời gian — không snapshot sẽ làm sai lệch báo cáo tài chính lịch sử                                                                                  |
| `balance_after` trên `inventory_transactions`                                              | Đối soát tồn kho nhanh không cần `SUM()` lại toàn bộ lịch sử — phù hợp định hướng dữ liệu lớn                                                                                    |

## 11. Roadmap

1. Requirement Analysis
2. System Design
3. Rails migration + models
4. Triển khai từng module
5. Testing (unit/integration/system test với Capybara)
6. CI/CD & Deployment
