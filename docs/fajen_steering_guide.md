# Fajen & Warren Dynamical Steering — Hướng dẫn Fine‑tune

## 1. Công thức tổng quát

```
φ̈ = -b·φ̇  -  kg·(φ - ψg)·(e^(-c1·dg) + c2)  +  Σ [ ko·(φ - ψo)·e^(-c3·|φ-ψo|)·e^(-c4·do) ]
  ─────────   ──────────────────────────────     ────────────────────────────────────────────
    Damping            Goal Attraction                       Obstacle Repellers
```

| Ký hiệu | Ý nghĩa |
|----------|---------|
| φ̈ | Gia tốc góc đầu ra (rad/s²) — dùng để tích lũy thành vận tốc xoay |
| φ̇ | Vận tốc góc hiện tại (rad/s) — fajen_angular_velocity nội bộ |
| φ | Góc heading hiện tại của ship (rad) |
| ψg | Góc từ ship đến target (rad) |
| ψo | Góc từ ship đến obstacle (rad) |
| dg | Khoảng cách đến target (m) |
| do | Khoảng cách đến obstacle (m) |

---

## 2. Kiến trúc code

```
Steering_Fajen_Warrent (Node3D)
├── fajen_angular_velocity (Vector2)   ← Momentum nội bộ (x=pitch, y=yaw)
├── compute_fajen_angular_acceleration()
│   ├── Tính raw φ̈ từ công thức
│   ├── Clamp theo max_engine_accel (từ ship)
│   ├── Tích lũy: vel += accel * delta
│   ├── Damping: vel = lerp(ZERO, damping * delta)
│   └── Clamp max speed
└── get_fajen_angular_velocity()       ← Ship gọi để lấy vel đã sẵn sàng

Ship (RigidBody3D)
├── Gọi steering.compute(..., delta, max_engine_accel)
├── vel = steering.get_fajen_angular_velocity()
└── state.angular_velocity = yaw*vel.y + pitch*vel.x
```

---

## 3. Các tham số & cách fine‑tune

### 3.1 `fajen_kg` — Goal Attraction Strength

> **Mặc định: 20 | Draff: 12 | Range: 5–50**

Lực kéo mũi ship về phía target. 

| Giá trị | Hiệu quả |
|----------|----------|
| **Thấp (5–12)** | Ship ưu tiên tránh obstacle hơn là đến đích. Phù hợp map nhiều chướng ngại. |
| **Cao (20–50)** | Ship bám target mạnh, có thể bỏ qua obstacle nhỏ. Phù hợp không gian trống. |

> **Mẹo**: Nếu ship cứ bay vòng quanh obstacle mà không chịu đến target → giảm kg. Nếu ship đâm thẳng vào obstacle → tăng ko, không tăng kg.

---

### 3.2 `fajen_ko` — Obstacle Repulsion Strength

> **Mặc định: 400 | Draff: 200 | Range: 50–800**

Lực đẩy ship ra xa obstacle. Đây là tham số **quan trọng nhất** cho tránh vật cản.

| Giá trị | Hiệu quả |
|----------|----------|
| **Thấp (50–150)** | Phản ứng yếu, ship có thể va chạm. Phù hợp obstacle nhỏ, thưa. |
| **Trung bình (200–400)** | Cân bằng. Tránh tốt mà không giật. |
| **Cao (500–800)** | Tránh rất mạnh, nhưng dễ oscillation nếu c3 quá cao. |

> **Mẹo**: Tăng ko trước khi đụng đến bất kỳ tham số nào khác.

---

### 3.3 `fajen_b` — Angular Damping

> **Mặc định: 4.2 | Range: 1.0–10.0**

Hãm vô-lăng. Giá trị càng cao → ship càng "nặng" khi xoay, ít oscillation nhưng phản ứng chậm.

| Giá trị | Hiệu quả |
|----------|----------|
| **Thấp (1–3)** | Ship linh hoạt, dễ oscillation khi ko cao. |
| **Cao (6–10)** | Ship nặng, mượt, nhưng có thể không kịp tránh obstacle gần. |

---

### 3.4 `fajen_c3` — Obstacle Angular Sensitivity

> **Mặc định: 6.0 | Range: 1.0–10.0**

Mức độ obstacle ảnh hưởng theo **góc lệch**. `exp(-c3 * |φ - ψo|)` — c3 càng lớn, obstacle chỉ đẩy khi **gần như chính diện**.

| c3 | Góc hiệu quả (~50% force) |
|----|---------------------------|
| 1.0 | ~40° (rộng) |
| 2.0 | ~20° |
| 3.0 | ~13° |
| 6.0 | ~7° (rất hẹp — mặc định) |
| 10.0 | ~4° (chỉ chính diện) |

| Giá trị | Hiệu quả |
|----------|----------|
| **Thấp (1–3)** | Obstacle đẩy từ góc rộng. Ship "né" từ xa, bay vòng cung rộng. |
| **Trung bình (4–6)** | Chỉ tránh obstacle phía trước. Bay thẳng hơn. |
| **Cao (8–10)** | Chỉ phản ứng khi sắp đâm trực diện — nguy hiểm! |

> **Mẹo**: Đây là tham số thường bị bỏ qua nhất. Nếu ship không thấy obstacle → giảm c3.

---

### 3.5 `fajen_c4` — Obstacle Distance Decay

> **Mặc định: 0.2 | Range: 0.05–1.0**

Mức độ obstacle ảnh hưởng theo **khoảng cách**. `exp(-c4 * do)`.

| c4 | Khoảng cách còn ~37% force | Khoảng cách còn ~14% force |
|-----|---------------------------|---------------------------|
| 0.05 | 20m | 40m |
| 0.1 | 10m | 20m |
| 0.2 | 5m | 10m |
| 0.5 | 2m | 4m |

| Giá trị | Hiệu quả |
|----------|----------|
| **Thấp (0.05–0.1)** | Phát hiện obstacle từ xa, tránh sớm, mượt. |
| **Cao (0.3–0.5)** | Chỉ tránh obstacle rất gần — phản ứng gấp, giật. |

---

### 3.6 `fajen_c1` & `fajen_c2` — Goal Distance Weight

> **Mặc định: c1=0.4, c2=0.4 | Range: 0.1–1.0**

Trọng số goal theo khoảng cách: `exp(-c1 * dg) + c2`.

| Khoảng cách | c1=0.4, c2=0.4 | Ý nghĩa |
|-------------|-----------------|---------|
| 0m (đến đích) | 1.4 | Lực hút mạnh nhất |
| 5m | 0.54 | Giảm dần |
| 20m | 0.40 | Tiệm cận c2 |

| Điều chỉnh | Hiệu quả |
|-------------|----------|
| Tăng c2 (0.6–1.0) | Ship luôn bị hút mạnh về target ngay cả khi xa. |
| Giảm c2 (0.1–0.2) | Ship thờ ơ với target ở xa, ưu tiên tránh obstacle. |

---

### 3.7 `fajen_angular_damping` — Velocity Damping (mọi frame)

> **Mặc định: 1.0 | Range: 0.5–5.0**

Damping trên `fajen_angular_velocity` sau mỗi frame tích lũy. Giống `angular_damping` của draff.

| Giá trị | Hiệu quả |
|----------|----------|
| **Thấp (0.5)** | Giữ momentum lâu → ship bay mượt, ít giật. |
| **Cao (2–5)** | Momentum tắt nhanh → ship dừng xoay ngay khi hết obstacle. |

---

### 3.8 `max_engine_accel` — Giới hạn gia tốc (từ ship)

> **Công thức: `max_turn_torque / mass`** (truyền từ ship)

Đây là **nút thắt cổ chai** — mọi raw_accel từ Fajen đều bị clamp bởi giá trị này.

| Ship mass ~167 | max_turn_torque | max_engine_accel |
|----------------|-----------------|------------------|
| Nhẹ | 50 | 0.3 |
| Trung bình | 150 | 0.9 |
| Mạnh | 250 | 1.5 |

> **Nếu lực tránh yếu**: tăng `max_turn_torque` trong Inspector của ship trước.

---

## 4. Các kịch bản fine‑tune thường gặp

### A. "Ship đâm thẳng vào obstacle, không thèm tránh"

1. Kiểm tra `obstacle_count` trong debug — nếu = 0 → obstacle không được detect.
2. Tăng `fajen_ko` (400 → 600).
3. Giảm `fajen_c3` (6.0 → 2.5) — mở rộng góc phát hiện.
4. Giảm `fajen_c4` (0.2 → 0.08) — phát hiện từ xa hơn.
5. Tăng `max_turn_torque` trên ship.

### B. "Ship xoay loạn xạ, oscillation"

1. Tăng `fajen_b` (4.2 → 6.0).
2. Tăng `fajen_angular_damping` (1.0 → 2.0).
3. Giảm `fajen_ko` (400 → 200).
4. Tăng `fajen_c3` (6.0 → 8.0) — thu hẹp góc, tránh obstacle không cần thiết.

### C. "Ship tránh quá xa, bay vòng cung lớn"

1. Tăng `fajen_c3` (3.0 → 6.0).
2. Tăng `fajen_c4` (0.1 → 0.25).
3. Giảm `fajen_ko` (400 → 200).

### D. "Ship không đến được target vì cứ né obstacle"

1. Tăng `fajen_kg` (20 → 30).
2. Tăng `fajen_c2` (0.4 → 0.6).
3. Giảm `fajen_ko` (400 → 200).

### E. "Pitch tránh obstacle không hoạt động"

1. Kiểm tra `max_pitch_angle` (10° mặc định) — có thể quá nhỏ.
2. Kiểm tra `apply_pitch_clamp` không zero pitch velocity của Fajen.
3. Obstacle phải có độ cao khác biệt so với ship để pitch hoạt động.

---

## 5. Debug — đọc label 3 (ship) / label 1 (draff)

```
FAJEN FORMULA
─────────────────────────
damping_term (pitch, yaw):  ← -b * φ̇
goal_term   (pitch, yaw):   ← Lực hút target
goal_error  (pitch, yaw):   ← Góc lệch target
goal_weight              :  ← exp(-c1*dg) + c2
distance_to_goal         :  ← Khoảng cách target
noise_added              :  ← Deadlock?

RAW → APPLIED → VELOCITY
─────────────────────────
raw_accel   (pitch, yaw):  ← φ̈ thô từ công thức
max_engine_accel       :   ← Giới hạn từ ship
applied     (pitch, yaw):  ← Đã clamp
fajen_vel   (pitch, yaw):  ← Đã tích lũy + damp + clamp

REPULSION
─────────────────────────
total_repulsion         :   ← Σ||obstacle terms||
obstacle_count          :   ← Số obstacle đang xử lý
danger_throttle_factor  :   ← Hệ số giảm ga

OBSTACLE DETAILS
  #1: err=(pitch, yaw), term=(pitch, yaw), dist=..., r=..., ko=...
```

---

## 6. Bảng tham chiếu nhanh

| Vấn đề | Tham số | Hướng sửa |
|--------|---------|-----------|
| Tránh quá yếu | ko ↑, c3 ↓, c4 ↓, max_turn_torque ↑ |
| Oscillation | b ↑, damping ↑, ko ↓, c3 ↑ |
| Phản ứng chậm | max_engine_accel ↑, b ↓ |
| Né quá xa | c3 ↑, c4 ↑, ko ↓ |
| Không đến đích | kg ↑, c2 ↑ |
| Roll quá mạnh | max_roll_angle ↓, roll_factor ↓ |
