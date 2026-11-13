# Course Guide — SQL Server Administration (SQL-ADM) 4 Days / 24 Hours

> ตารางเวลาสอนรายชั่วโมงสำหรับผู้สอน — จัดจากโครงสไลด์ 9Expert SQL-ADM v1 (2026) 14 บท โดยอบรม 4 วัน วันละ 6 ชั่วโมง

## ข้อมูลหลักสูตร

| รายการ | รายละเอียด |
|:-------|:-----------|
| **ชื่อหลักสูตร** | Microsoft SQL Server Database Administration (SQL-ADM) |
| **ระยะเวลา** | 4 วัน (24 ชั่วโมง) |
| **กลุ่มเป้าหมาย** | Database Administrator, IT Operations, Developer ที่ดูแล SQL Server |
| **พื้นฐานที่ต้องมี** | ใช้ T-SQL เบื้องต้น (SELECT/INSERT/UPDATE) + เข้าใจ Windows Server พื้นฐาน |
| **Environment** | SQL Server 2025 Developer + SSMS 21 + PowerShell 7 + AdventureWorks2025 (ดู Module 00) |
| **โครงหลักสูตร** | 14 Modules + 14 Labs (แล็บท้ายโมดูล 40-60 นาที/โมดูล) |

---

## วันที่ 1 — Security Foundations (บทที่ 1–4)

| เวลา | หัวข้อ | Sections | Lab |
|:-----|:-------|:---------|:----|
| 09:00–09:30 | เปิดคอร์ส + ตรวจ Environment (Module 00) | Verify script | — |
| 09:30–10:30 | บทที่ 1: Authentication — Securable/Principal, Logins (SSMS/T-SQL) | 1.1–1.2 | Demo scripts |
| 10:30–10:45 | ☕ Break | | |
| 10:45–11:45 | บทที่ 1 (ต่อ): User Tokens, สิทธิ์ข้ามเครื่อง, Contained Databases | 1.3–1.4 | Lab 1 (เริ่ม) |
| 11:45–12:30 | Lab 1: Logins/Users/Orphaned/Contained DB | | Lab 1 (จบ) |
| 12:30–13:30 | 🍴 Lunch | | |
| 13:30–14:30 | บทที่ 2: Server Roles + Fixed Database Roles | 2.1–2.2 | Demo |
| 14:30–15:15 | บทที่ 2 (ต่อ): User-defined Roles, Application Roles + `##MS_*##` roles รุ่นใหม่ | 2.3 | Demo |
| 15:15–15:30 | ☕ Break | | |
| 15:30–16:30 | บทที่ 3: GRANT/DENY/REVOKE, Column + RLS, Code Permissions | 3.1–3.2 | Demo |
| 16:30–17:00 | บทที่ 3 (ต่อ): Schema Permissions + Lab 3 | 3.3 | Lab 3 |

## วันที่ 2 — Encryption, Audit & Backup Strategy (บทที่ 4–7 เริ่ม)

| เวลา | หัวข้อ | Sections | Lab |
|:-----|:-------|:---------|:----|
| 09:00–10:15 | บทที่ 4: Audit ทางเลือก (Trigger/Temporal/CC) + SQL Server Audit | 4.1–4.3 | Demo |
| 10:15–10:30 | ☕ Break | | |
| 10:30–11:30 | บทที่ 4 (ต่อ): TDE, Always Encrypted, DDM + Lab 4 | 4.4 | Lab 4 |
| 11:30–12:30 | บทที่ 5: Transaction Log + Recovery Models | 5.1–5.2 | Demo |
| 12:30–13:30 | 🍴 Lunch | | |
| 13:30–14:30 | บทที่ 5 (ต่อ): Backup Types + กลยุทธ์ + Lab 5 | 5.3 | Lab 5 |
| 14:30–15:15 | บทที่ 6: Media Sets, Backup Basics + Verification | 6.1–6.2 | Demo |
| 15:15–15:30 | ☕ Break | | |
| 15:30–16:30 | บทที่ 6 (ต่อ): Compression (ZSTD 2025), Encryption, Backup to URL/S3 | 6.3 | Demo |
| 16:30–17:00 | Lab 6 | | Lab 6 |

## วันที่ 3 — Restore & Automation (บทที่ 7–10)

| เวลา | หัวข้อ | Sections | Lab |
|:-----|:-------|:---------|:----|
| 09:00–10:15 | บทที่ 7: Restore Mechanics + Restore Scenarios | 7.1–7.2 | Demo |
| 10:15–10:30 | ☕ Break | | |
| 10:30–11:30 | บทที่ 7 (ต่อ): Special Restores (Page/System DBs) + Point-in-time | 7.3–7.4 | Lab 7 |
| 11:30–12:30 | บทที่ 8: SQL Server Agent — Jobs/Steps/Schedules | 8.1–8.2 | Demo |
| 12:30–13:30 | 🍴 Lunch | | |
| 13:30–14:30 | บทที่ 8 (ต่อ): Job Management + Multiserver + Lab 8 | 8.3–8.4 | Lab 8 |
| 14:30–15:30 | บทที่ 9: Agent Security — Context, Credentials, Proxies | 9.1–9.3 | Lab 9 |
| 15:30–15:45 | ☕ Break | | |
| 15:45–16:45 | บทที่ 10: Error Log, Database Mail | 10.1–10.2 | Demo |
| 16:45–17:00 | บทที่ 10 (ต่อ): Operators + Alerts (เริ่ม) | 10.3 | Demo |

## วันที่ 4 — Operations Toolkit (บทที่ 10 จบ – 14)

| เวลา | หัวข้อ | Sections | Lab |
|:-----|:-------|:---------|:----|
| 09:00–09:45 | บทที่ 10 (จบ): Alerts + Azure Alerts + Lab 10 | 10.3–10.4 | Lab 10 |
| 09:45–10:45 | บทที่ 11: PowerShell — SMO, SQLSERVER: drive, ตั้งค่า/บำรุงรักษา | 11.1–11.3 | Demo |
| 10:45–11:00 | ☕ Break | | |
| 11:00–12:00 | บทที่ 11 (ต่อ): Azure SQL ด้วย PowerShell + Lab 11 | 11.4 | Lab 11 |
| 12:00–13:00 | 🍴 Lunch | | |
| 13:00–14:15 | บทที่ 12: Extended Events — Concepts + Sessions + system_health | 12.1–12.2 | Lab 12 |
| 14:15–15:30 | บทที่ 13: DMVs, Activity Monitor, PerfMon + Baseline | 13.1–13.2 | Lab 13 |
| 15:30–15:45 | ☕ Break | | |
| 15:45–16:45 | บทที่ 14: Data Transfer — bcp/BULK INSERT/OPENROWSET/dacpac | 14.1–14.4 | Lab 14 |
| 16:45–17:00 | สรุปคอร์ส + Roadmap การเรียนต่อ (Roadmap slide) | — | — |

---

## แนวทางการสอน (Trainer Notes)

1. **Demo-first**: ทุกหัวข้อมี demo script ใน `Sections/*/Scripts/` — สาธิตก่อน แล้วให้ผู้เรียนทำซ้ำ
2. **Labs ท้ายโมดูล** เป็นแบบ "Instruction + Code block" — ผู้เรียนก๊อปรันได้จากเอกสาร
3. **สไลด์เดิมมีข้อผิดพลาดที่ควรแก้ตอนสอน**:
   - SQL Trace/Profiler → ย้ำว่า **deprecated** ให้สอน Extended Events เป็นหลัก (บทที่ 12)
   - SQLPS/ISE → ใช้ **SqlServer module + PowerShell 7 + VS Code** (บทที่ 11)
   - sp_change_users_login → ใช้ `ALTER USER ... WITH LOGIN` (บทที่ 1)
   - Purview access policies → **discontinued ใน SQL Server 2025** ใช้ fixed server roles `##MS_*##` (บทที่ 2)
4. **เตรียมอุปกรณ์เสริม**: smtp4dev (ทดสอบ Database Mail), container ที่สอง `sql2025b` สำหรับ MSX/TSX (optional)
5. **เวลาบั้นท้ายแต่ละบท** ให้ทำ Quiz ในหน้า README ของโมดูล (แบบถาม-ตอบปากเปล่า)

## Sign-off ท้ายคอร์ส

- [ ] ผู้เรียนทำ Lab 1–14 ครบ
- [ ] ผู้เรียนตอบ Quiz ทุกโมดูลได้
- [ ] สอบปลายคอร์ส (Case study: สร้าง runbook ประจำวัน — backup/restore drill + alert + baseline)
