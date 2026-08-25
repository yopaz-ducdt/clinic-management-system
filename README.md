# Clinic Management System

Web app phòng khám đa khoa — đặt lịch khám (online + walk-in), hồ sơ bệnh nhân, kê đơn thuốc, quản lý kho, thanh toán online/tiền mặt.

Tài liệu thiết kế đầy đủ: xem `docs/design-document.md`. `docs/api-contract.md` là tài liệu tham chiếu business logic từng action.

## Stack

- Ruby on Rails 8, full MVC
- PostgreSQL
- Solid Queue (background job)
- Devise (session-based auth)
- Pundit
- RSpec + FactoryBot + Capybara

## Yêu cầu môi trường

- Ruby (xem `.ruby-version`)
- PostgreSQL đang chạy local

## Setup lần đầu

```bash
bundle install
bin/rails db:create db:migrate db:seed
```

## Chạy server

```bash
bin/rails server
```

## Chạy background job (Solid Queue)

```bash
bin/jobs
```

## Chạy test

```bash
bundle exec rspec
```

## Cấu trúc thư mục chính

```
app/
  controllers/     # theo resource: appointments, patients, doctors,
                     medical_records, prescriptions, inventory_items,
                     payments, webhooks/payments_controller.rb (JSON riêng)
  models/
  views/            # ERB, theo từng controller
  policies/         # Pundit — 1 policy/model
  helpers/
  services/          # business logic phức tạp (BookAppointmentService, IssuePrescriptionService...)
  jobs/              # GenerateSlotsJob, ReleaseExpiredHoldsJob
config/
  routes.rb
db/
  migrate/
```
