# API Contract — Clinic Webapp

> **Đã chuyển sang Rails full MVC** (xem `design-document.md` mục 8) — không còn dùng JSON API + JWT như mô tả gốc dưới đây. Giữ lại file này làm tài liệu tham chiếu **business logic từng action** (field nào, validate gì, side-effect gì xảy ra) khi viết controller/view thật. Khi đọc, tự dịch:
>
> - `GET/POST/PATCH /resource` → route + controller action tương ứng (`resources :appointments` trong `routes.rb`)
> - Request JSON body → tham số form (`params[:appointment]`)
> - Response JSON → dữ liệu instance variable dùng trong view (`@appointment`), hoặc Turbo Stream nếu cập nhật từng phần
> - Response lỗi (`422`, `error.code`...) → `flash[:alert]` + hiển thị lỗi validate ngay trên form
> - Riêng webhook thanh toán (mục 5) **vẫn là JSON thật** — đây là API duy nhất còn lại trong hệ thống, giữ nguyên như mô tả

## Error Response Format (thống nhất toàn bộ API)

```json
{
  "error": {
    "code": "SLOT_ALREADY_HELD",
    "message": "Slot này đang được giữ bởi người khác"
  }
}
```

Validation lỗi (422) có thêm `details`:

```json
{
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Dữ liệu không hợp lệ",
    "details": { "email": ["đã tồn tại"] }
  }
}
```

| Status | Ý nghĩa                              |
| ------ | ------------------------------------ |
| 400    | Request format sai                   |
| 401    | Chưa đăng nhập / token invalid       |
| 403    | Không đủ quyền                       |
| 404    | Không tìm thấy resource              |
| 409    | Conflict (VD slot đã bị held/booked) |
| 422    | Validation fail theo field           |
| 500    | Lỗi hệ thống                         |

---

## 1. Auth

### POST /auth/register

`national_id` bắt buộc ngay lúc đăng ký (chống tạo nhiều tài khoản) — nếu đã tồn tại `national_id` trùng, trả `422 NATIONAL_ID_TAKEN`.

```json
// Request
{ "user": { "email": "a@b.com", "password": "123456", "full_name": "Nguyen Van A", "phone": "0900000000", "national_id": "001099005678" } }
// Response 201
{ "token": "eyJ...", "user": { "id": "uuid", "email": "a@b.com", "role": "patient" } }
```

### POST /auth/login

```json
{ "email": "a@b.com", "password": "123456" }
// Response 200
{ "token": "eyJ...", "user": { "id": "uuid", "role": "patient" } }
```

### DELETE /auth/logout

Response 204.

### POST /auth/activate

Kích hoạt tài khoản `users.status: inactive → active` cho bệnh nhân walk-in đã có hồ sơ sẵn. Match hồ sơ bằng SĐT + CCCD (cả 2 phải khớp).

```json
// Request
{ "activation": { "phone": "0911111111", "national_id": "001099001234", "email": "new@b.com", "password": "123456" } }

// Response 200
{ "token": "eyJ...", "user": { "id": "uuid", "role": "patient", "status": "active" } }

// Response 404 nếu không tìm thấy hồ sơ khớp cả SĐT lẫn CCCD
{ "error": { "code": "PROFILE_NOT_FOUND", "message": "Không tìm thấy hồ sơ khớp với thông tin cung cấp" } }
```

---

## 2. Specialties

### GET /specialties

```json
{
  "specialties": [
    { "id": "uuid", "name": "Nội tổng quát", "description": "..." }
  ]
}
```

### POST /specialties _(admin)_

```json
{ "specialty": { "name": "Nhi khoa", "description": "..." } }
```

---

## 3. Doctors

### GET /doctors?specialty_id=uuid

```json
{
  "doctors": [
    {
      "id": "uuid",
      "full_name": "BS. Tran B",
      "specialty": { "id": "uuid", "name": "Nội tổng quát" }
    }
  ]
}
```

### GET /doctors/:id/available_slots?date=2026-08-25

Chỉ trả slot `status: available`.

```json
{
  "slots": [
    {
      "id": "uuid",
      "start_time": "08:00",
      "end_time": "08:30",
      "status": "available"
    }
  ]
}
```

### POST /doctors _(admin)_

### POST /doctors/:id/schedules _(admin)_

```json
{ "schedule": { "day_of_week": 1, "start_time": "08:00", "end_time": "12:00" } }
```

---

## 4. Appointments

### POST /appointments

Giữ chỗ slot — chuyển `appointment_slots.status: available → held` (có lock chống race condition), tạo `appointment.status: pending_payment`, `held_until = now + 15min`.

- Caller = `patient` → tự gắn `patient_id` = chính họ, `booking_channel: online`.
- Caller = `admin` → phải truyền `doctor_id` bất kỳ, `patient_id` có sẵn hoặc `new_patient: {full_name, national_id?, relationship}` (tạo dưới `managed_by_user_id` = hồ sơ tài khoản walk-in vừa tạo/có sẵn — xem mục 6), `booking_channel: walk_in`.
- Caller = `doctor` → chỉ được đặt vào slot của **chính mình** (403 nếu `slot.doctor_id != current_user.doctor.id`), tương tự cần `patient_id`/`new_patient`, `booking_channel: walk_in`.

```json
// Request (patient)
{ "appointment": { "slot_id": "uuid" } }

// Request (admin/doctor đặt hộ, bệnh nhân mới - người lớn có CCCD riêng)
{ "appointment": { "slot_id": "uuid", "new_patient": { "full_name": "Le Van C", "national_id": "001099001234", "relationship": "self" } } }

// Request (đặt hộ cho trẻ em, không có CCCD)
{ "appointment": { "slot_id": "uuid", "patient_id": "uuid-cua-tai-khoan-phu-huynh", "new_patient": { "full_name": "Le Van D (con)", "relationship": "child" } } }

// Response 201
{ "appointment": { "id": "uuid", "status": "pending_payment", "held_until": "2026-08-25T08:15:00Z" }, "payment_required": true }

// Response 409 (slot đã bị held/booked)
{ "error": { "code": "SLOT_ALREADY_HELD", "message": "Slot này đang được giữ bởi người khác" } }
```

### GET /appointments

```json
{ "appointments": [{ "id": "uuid", "status": "confirmed", "booking_channel": "online", "patient": {...}, "doctor": {...}, "slot": {...} }] }
```

### PATCH /appointments/:id/cancel

Tính phí hủy theo `clinic_settings` (`cancellation_free_days`, `cancellation_fee_percent`) dựa trên thời điểm hủy so với giờ hẹn — **lưu snapshot** kết quả vào `appointments.cancellation_fee_amount`, không tính lại từ settings sau này.

```json
// Response 200
{
  "appointment": {
    "id": "uuid",
    "status": "cancelled",
    "cancellation_fee_amount": 100000
  },
  "refund_amount": 400000
}
```

### PATCH /appointments/:id/no*show *(admin/doctor)\_

```json
{ "appointment": { "id": "uuid", "status": "no_show" } }
```

### PATCH /appointments/:id/complete _(doctor — thường gọi ngầm khi tạo medical_record)_

---

## 5. Payments

### POST /payments _(patient)_

Chỉ tạo được nếu `appointment.status == pending_payment` và còn trong hạn `held`.

```json
// Request
{ "payment": { "appointment_id": "uuid", "method": "vnpay" } }
// Response 200
{ "payment_url": "https://sandbox.vnpayment.vn/...", "payment": { "id": "uuid", "status": "pending" } }

// Request (cash — walk-in)
{ "payment": { "appointment_id": "uuid", "method": "cash" } }
// Response 200 — không có payment_url, chờ Admin confirm
{ "payment": { "id": "uuid", "status": "pending", "method": "cash" } }
```

### PATCH /payments/:id/confirm _(admin — xác nhận thu tiền mặt)_

```json
{
  "payment": {
    "id": "uuid",
    "status": "success",
    "confirmed_by_user_id": "uuid"
  }
}
```

### POST /webhooks/payments/:provider

Không cần JWT — verify bằng chữ ký của cổng. **Idempotent theo `provider_transaction_id`**: nếu đã xử lý transaction này rồi, trả `200 OK` ngay, không đổi state lần 2.

Khi thành công: `payments.status = success`, `appointments.status = confirmed`, `appointment_slots.status = booked`.
Khi thất bại: `payments.status = failed`. Nếu appointment còn hạn `held`, bệnh nhân có thể gọi lại `POST /payments` để thử thanh toán lần nữa.

### POST /payments/:id/refund _(admin/system — trigger khi hủy lịch có phí)_

Ghi kết quả vào `payments.refunded_amount`.

```json
{ "refund": { "amount": 400000, "reason": "cancellation" } }
```

---

## 6. Patients & Medical Records

### GET /patients

Danh sách hồ sơ bệnh nhân do `current_user` quản lý (`managed_by_user_id`) — bao gồm cả hồ sơ `self` lẫn các `dependent`/`child` (VD phụ huynh xem danh sách các con đã thêm).

```json
{
  "patients": [
    { "id": "uuid", "full_name": "Le Van C", "relationship": "self" },
    { "id": "uuid", "full_name": "Le Van D (con)", "relationship": "child" }
  ]
}
```

### POST /patients _(patient — tự thêm hồ sơ phụ thuộc, VD thêm con)_

```json
// Request
{ "patient": { "full_name": "Le Van D (con)", "date_of_birth": "2020-05-01", "relationship": "child" } }
// Response 201 — national_id không bắt buộc khi relationship khác "self"
{ "patient": { "id": "uuid", "full_name": "Le Van D (con)", "relationship": "child" } }
```

### GET /patients/:id

_(patient: hồ sơ do mình quản lý / doctor: đã từng khám / admin: tất cả — Pundit)_

```json
{
  "patient": {
    "id": "uuid",
    "full_name": "...",
    "date_of_birth": "1990-01-01",
    "relationship": "self"
  }
}
```

### GET /patients/:id/medical_records

Query trực tiếp `WHERE patient_id = :id` (denormalized, có index) — không cần JOIN qua `appointments`.

```json
{
  "medical_records": [
    {
      "id": "uuid",
      "diagnosis": "...",
      "appointment_id": "uuid",
      "created_at": "..."
    }
  ]
}
```

### POST /medical*records *(doctor only)\_

Tạo record → tự động chuyển `appointment.status: confirmed → completed`.

```json
{
  "medical_record": {
    "appointment_id": "uuid",
    "diagnosis": "...",
    "notes": "..."
  }
}
```

---

## 7. Prescriptions

### POST /prescriptions _(doctor only)_

Tạo với `status: draft`. **Không** trừ kho ở bước này.

```json
{
  "prescription": {
    "medical_record_id": "uuid",
    "items": [{ "inventory_item_id": "uuid", "quantity": 10, "dosage": "2 viên/ngày", "instructions": "Sau ăn" }]
  }
}
// Response 201
{ "prescription": { "id": "uuid", "status": "draft" } }
```

### PATCH /prescriptions/:id/issue _(doctor only)_

Chuyển `draft → issued`. Trigger tạo `inventory_transactions` (type: `dispense`) và trừ `quantity_in_stock` — có lock để tránh race condition khi tồn kho gần hết.

```json
// Response 200
{ "prescription": { "id": "uuid", "status": "issued" } }
// Response 422 nếu không đủ tồn kho
{ "error": { "code": "INSUFFICIENT_STOCK", "message": "Không đủ tồn kho cho Paracetamol 500mg" } }
```

### PATCH /prescriptions/:id/cancel _(doctor only, chỉ khi còn draft)_

---

## 8. Inventory _(admin write, doctor read)_

### GET /inventory_items

```json
{
  "items": [
    {
      "id": "uuid",
      "name": "Paracetamol 500mg",
      "quantity_in_stock": 200,
      "reorder_threshold": 50
    }
  ]
}
```

### POST /inventory*items *(admin)\_

### POST /inventory*items/:id/transactions *(admin — nhập kho thủ công)\_

```json
{ "transaction": { "transaction_type": "restock", "quantity": 100 } }
```

---

## 9. Clinic Settings _(admin only)_

### GET /clinic_settings

```json
{ "settings": { "cancellation_free_days": 2, "cancellation_fee_percent": 20 } }
```

### PATCH /clinic_settings

```json
{ "settings": { "cancellation_free_days": 3, "cancellation_fee_percent": 30 } }
```

---

## Quy ước chung

- List endpoint hỗ trợ `page`, `per_page`.
- Timestamp: ISO 8601, UTC.
- Response bọc theo key số nhiều/số ít đúng resource.
- Authorization theo Pundit — deny trả `403` theo format lỗi thống nhất ở đầu tài liệu.
