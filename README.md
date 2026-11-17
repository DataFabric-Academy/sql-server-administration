# Microsoft SQL Server Database Administration

<div align="center">

![SQL Server](https://img.shields.io/badge/SQL%20Server-2019%20%7C%202022%20%7C%202025-CC2927?style=for-the-badge&logo=microsoft-sql-server&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Active-success?style=for-the-badge)

**คอร์ส SQL Server Administration ฉบับภาษาไทย (SQL-ADM)**
*เนื้อหาเรียบเรียงจาก Microsoft Course 20764D (Administering a SQL Database Infrastructure) และสไลด์ 9Expert Training SQL-ADM Version 1 (2026) โดยปรับปรุงเนื้อหา สคริปต์ และแล็บให้ทันสมัยถึง SQL Server 2025*

[📖 เริ่มต้นใช้งาน](#-การใช้งาน-usage) • [📚 โครงสร้างบทเรียน](#-โครงสร้างบทเรียน-course-structure) • [🗓️ ตารางอบรม 4 วัน](#️-ผังการอบรม-4-วัน) • [🤝 Credits](#-credits)

</div>

---

## 📋 ภาพรวม (Overview)

คอร์สนี้ครอบคลุมการบริหารจัดการ SQL Server แบบครบวงจร ตั้งแต่ความปลอดภัย (Authentication / Authorization / Encryption / Audit) การสำรองและกู้คืนข้อมูล (Backup / Restore) ระบบอัตโนมัติ (SQL Server Agent / Database Mail / Alerts) เครื่องมือติดตาม (PowerShell / Extended Events / DMVs) จนถึงการถ่ายโอนข้อมูล (bcp / BULK INSERT / SSIS / dacpac)

> **จุดเด่นของฉบับนี้**: เนื้อหาและแล็บทุกโมดูลอัปเดตตาม **SQL Server 2025 (17.x)** — ZSTD Backup Compression, PBKDF2 Password Hash, Fixed Server Roles รุ่นใหม่ (`##MS_*##`), Managed Identity ผ่าน Azure Arc, TLS 1.3 + TDS 8.0, Time-bound Extended Events และการเปลี่ยนผ่านจาก Profiler/SQL Trace ไปสู่ Extended Events เต็มรูปแบบ

### ✨ คุณสมบัติหลัก

- ✅ **14 Modules** ตรงตามโครงหลักสูตร (บทที่ 1–14) ครอบคลุมทุกมิติของงาน SQL Server DBA
- ✅ **Modern Scripts** อัปเดตตาม SQL Server 2025 — ทุกฟีเจอร์เก่าที่ถูก deprecated/removed มีหมายเหตุและทางเลือกทันสมัยกำกับ
- ✅ **Hands-on Labs** รูปแบบ *Instruction + Code block* — ทุก Step รันได้ทันทีจากเอกสารเดียว
- ✅ **Demo Scripts** คู่กับหัวข้อที่เกี่ยวข้อง (`Sections/*/Scripts/`)
- ✅ **Quiz Bank** ทบทวนความเข้าใจท้ายโมดูล
- ✅ **Best Practices** จาก Microsoft Learn, Microsoft Course 20764D และสไลด์ผู้สอน 9Expert Training (2026)

---

## 📚 โครงสร้างบทเรียน (Course Structure)

| Module | หัวข้อ | คำอธิบาย | ระดับ |
|:------:|:------|:---------|:-----:|
| **[00](./Module_00_Getting_Started/README.md)** | เริ่มต้นใช้งาน (Getting Started) | เตรียม SQL Server 2025, SSMS และ AdventureWorks2025 ให้พร้อมสำหรับแล็บทุกโมดูล | ⭐ |
| **[01](./Module_01_SQL_Server_Security/README.md)** | ความปลอดภัยของ SQL Server | Authentication, Logins/Users, Linked Servers, Double-Hop และ Contained Databases | ⭐⭐⭐ |
| **[02](./Module_02_Server_Roles_Database_Roles/README.md)** | Server Roles และ Database Roles | Fixed Server Roles (รุ่นใหม่ 2022/2025), Fixed Database Roles, User-defined และ Application Roles | ⭐⭐⭐ |
| **[03](./Module_03_User_Resource_Permissions/README.md)** | อนุญาตให้ผู้ใช้เข้าถึงทรัพยากร | GRANT/DENY/REVOKE, Row-Level Security, Column Permissions, Ownership Chaining และ Schema Permissions | ⭐⭐⭐ |
| **[04](./Module_04_Encryption_Auditing/README.md)** | การเข้ารหัสและการ Audit | SQL Server Audit, Temporal Tables, TDE, Always Encrypted, Dynamic Data Masking | ⭐⭐⭐⭐ |
| **[05](./Module_05_Recovery_Model_Backup_Strategy/README.md)** | Recovery Model และกลยุทธ์การ Backup | Transaction Log Internals, Recovery Models, การวางแผน Backup Strategy | ⭐⭐⭐ |
| **[06](./Module_06_Backing_Up_Databases/README.md)** | การ Backup ฐานข้อมูล | Media Sets, Backup Verification, Backup Compression (ZSTD), Encryption และ Backup to URL/S3 | ⭐⭐⭐ |
| **[07](./Module_07_Restoring_Databases/README.md)** | การ Restore ฐานข้อมูล | Restore Phases, Point-in-time Recovery, Page Restore, กู้คืน System Databases | ⭐⭐⭐⭐ |
| **[08](./Module_08_Automation/README.md)** | การจัดการ SQL Server โดยอัตโนมัติ | SQL Server Agent, Jobs/Steps/Schedules, Multiserver Administration | ⭐⭐⭐ |
| **[09](./Module_09_Agent_Security/README.md)** | ความปลอดภัยของ SQL Server Agent | Security Context ของ Job Steps, Credentials และ Proxy Accounts | ⭐⭐⭐ |
| **[10](./Module_10_Alerts_Notifications/README.md)** | Alerts และ Notifications | Error Log, Severity Levels, Database Mail, Operators, Alerts | ⭐⭐ |
| **[11](./Module_11_PowerShell/README.md)** | การจัดการ SQL Server ด้วย PowerShell | SMO, SqlServer Module, การตั้งค่า/บำรุงรักษาด้วย PowerShell 7 | ⭐⭐⭐ |
| **[12](./Module_12_Extended_Events/README.md)** | Extended Events | สถาปัตยกรรม XE, Sessions, Targets และ system_health — เครื่องมือแทน Profiler อย่างเป็นทางการ | ⭐⭐⭐ |
| **[13](./Module_13_Performance_Monitoring/README.md)** | การติดตามค่าประสิทธิภาพ | DMVs/DMFs, Activity Monitor, Performance Monitor Counters และการทำ Baseline | ⭐⭐⭐ |
| **[14](./Module_14_Data_Transfer/README.md)** | การถ่ายโอนข้อมูล | SSIS, Import/Export Wizard, bcp, BULK INSERT, OPENROWSET และ Data-Tier Applications (dacpac) | ⭐⭐ |

### 🗓️ ผังการอบรม 4 วัน (24 ชั่วโมง)

| วัน | หัวข้อ | บทที่ |
|:---:|:-------|:------|
| **วันที่ 1** | Security Foundations | 1–4 |
| **วันที่ 2** | Backup & Recovery | 5–7 |
| **วันที่ 3** | Automation & Operations | 8–10 |
| **วันที่ 4** | PowerShell, Monitoring & Data Movement | 11–14 |

---

## 🚀 การใช้งาน (Usage)

### โครงสร้างโฟลเดอร์

อ่านเป็นลำดับเหมือนหนังสือ — แต่ละโมดูลแบ่งเป็น Sections ย่อย สคริปต์อยู่คู่กับหัวข้อที่เกี่ยวข้อง:

```
Module_XX_Topic/
├── README.md                     # 📖 สารบัญโมดูล: บทนำ + สารบัญ Sections + Quiz
├── Sections/
│   ├── 01_Topic_Name/
│   │   ├── README.md             # 📖 เนื้อหาบทเรียนแบบหนังสือ
│   │   └── Scripts/              # 🧪 สคริปต์ที่เกี่ยวข้องกับ section นี้
│   └── 02_Topic_Name/ ...
└── Labs/
    └── README.md                 # 🧪 แล็บรวมประจำโมดูล (Instruction + Code block)
```

### แหล่งข้อมูลแล็บ (Lab Resources)

| แหล่ง | รูปแบบ | เหมาะกับ |
|:------|:-------|:---------|
| `Module_XX_*/Labs/README.md` | แล็บ self-study ครบในไฟล์เดียว (SQL Server 2025, ไม่ต้องมี domain) | ผู้เรียนด้วยตนเอง / ทุกคน |
| [`Lab_Instruction/`](./Lab_Instruction/README.md) | คู่มือแล็บห้องเรียนแบบ step-by-step ระดับคลิก GUI (ต้องมี VM domain `datafabric.local` + `D:\Labfiles`) | การอบรมที่ใช้ courseware VM |
| `Old/` | วัสดุต้นฉบับ 20764D แบบ local-only (ไม่ถูก track ใน git — `.gitignore`) | trainer ผู้ดูแล image เท่านั้น |

### Prerequisites

| ข้อกำหนด | รายละเอียด |
|:--------|:----------|
| **SQL Server** | 2025 (17.x) (แนะนำ) หรือ 2019/2022 — ฟีเจอร์เฉพาะรุ่นมีหมายเหตุกำกับ |
| **Database** | **AdventureWorks2025** (แนะนำ) — บน SQL Server 2019/2022 ใช้ AdventureWorks2022 |
| **Permissions** | `sysadmin` (งาน admin ส่วนใหญ่ต้องการ) และ `VIEW SERVER STATE` |
| **Tools** | SSMS 21, PowerShell 7 + `SqlServer` module, sqlcmd/bcp รุ่นใหม่ |

### ขั้นตอนการเริ่มต้น

1. **Clone Repository**
   ```bash
   git clone https://github.com/DataFabric-Academy/sql-server-administration.git
   cd sql-server-administration
   ```

2. **เตรียม Environment** — ทำตามคู่มือฉบับเต็มที่ [Module_00_Getting_Started/README.md](./Module_00_Getting_Started/README.md)
   - ติดตั้ง SQL Server 2025 Developer Edition (ฟรี — มีความสามารถเท่า Enterprise)
   - ดาวน์โหลดและ Restore [AdventureWorks2025.bak](https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2025.bak) (วิธีทำจาก [Microsoft Learn](https://learn.microsoft.com/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms))
   - ตรวจความพร้อมด้วย `Module_00_Getting_Started/Scripts/01_Verify_Environment.sql`

3. **เริ่มเรียน**
   - เริ่มจาก Module 01 เพื่อวางรากฐานด้านความปลอดภัย
   - ทำตาม Demo Scripts (`Sections/*/Scripts/`) ระหว่างเรียน แล้วปิดท้ายด้วย Labs (`Labs/README.md`) ท้ายโมดูล

---

## 📖 แนวทางการเรียนรู้ (Learning Path)

### 🎯 สำหรับผู้เริ่มต้น (มีพื้นฐาน T-SQL แต่ยังไม่เคยดูแล server)
1. Module 00 → 01 → 02 → 03 (ความปลอดภัยพื้นฐาน)
2. Module 05 → 06 → 07 (Backup/Restore ซึ่งเป็นหัวใจของงาน DBA)

### 🎯 สำหรับผู้ดูแลระบบที่มีประสบการณ์
1. Module 08 → 09 → 10 (Automation, Agent Security, Alerts)
2. Module 12 → 13 (XE และ Monitoring — เครื่องมือวินิจฉัยสมัยใหม่)

### 🎯 สำหรับผู้เชี่ยวชาญ / ผู้ย้ายจากรุ่นเก่า
1. Module 04 (TDE/Always Encrypted/Audit แบบละเอียด)
2. Module 11 → 14 (PowerShell สมัยใหม่ + Data Transfer บน S3/URL)
3. ดูหมวด "SQL Server 2025" ท้ายแต่ละ Section เพื่อจับของใหม่เทียบกับเวอร์ชันเดิม

---

## 🛠️ สคริปต์ที่ใช้ (Scripts Overview)

### Section Scripts (`Sections/*/Scripts/`)
สคริปต์อยู่คู่กับหัวข้อที่เกี่ยวข้อง — เปิด section ไหนก็เจอสคริปต์ของหัวข้อนั้น

- **Demo Scripts** (`NN_*.sql`): ใช้ตอนสาธิตในห้องเรียน รันได้ทีละไฟล์
- **Workload Scripts**: สร้างโหลดจำลอง เพื่อให้แล็บด้าน monitoring/audit เห็นเหตุการณ์จริง
- **คู่มือแล็บรวมต่อโมดูล**: `Labs/README.md` แบบ Instruction + Code block
- **คำศัพท์เทคนิค**: รวมอยู่ที่ [Glossary.md](Glossary.md)

---

## 📊 สถิติ Repository

- **Total Modules**: 14 (+ Module 00 Getting Started)
- **Total Sections**: 47 Sections
- **Total Scripts**: 120+ (SQL + PowerShell)
- **Lab Exercises**: 14 Labs (Exercise รวม 46)

---

## 🤝 Credits

### Original Course
- **Microsoft Course 20764D**: Administering a SQL Database Infrastructure — โครงหลักสูตร 15 โมดูล ที่ปรับเป็น 14 โมดูลในสไลด์ผู้สอน
- **9Expert Training**: SQL-ADM Version 1 (2026) — สไลด์ผู้สอนภาษาไทยโดย Aj. Phakkhaphong K.

### Additional Resources
- **[Microsoft Learn — SQL Server Technical Documentation](https://learn.microsoft.com/sql/)**: แหล่งอ้างอิงหลักของทุกหัวข้อ [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17)
- **[AdventureWorks sample databases](https://github.com/microsoft/sql-server-samples/releases)**: ฐานข้อมูลตัวอย่างทางการของ Microsoft
- **[dbatools](https://dbatools.io/)**: โมดูล PowerShell ชุมชนสำหรับ automation ระดับมืออาชีพ (อ้างอิงใน Module 11)
- **[First Responder Kit](https://www.firstresponderkit.org/)**: sp_Blitz* maintenance/health scripts ที่วงการใช้แพร่หลาย (อ้างอิงใน Module 08)

### License
This repository is for educational purposes. Scripts are provided as-is with attribution to original authors.

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## ⚠️ Disclaimer

สคริปต์ใน Repository นี้จัดทำขึ้นเพื่อวัตถุประสงค์ทางการศึกษาเท่านั้น
**กรุณาใช้ความระมัดระวัง** เมื่อรันสคริปต์บน Production Environment — โดยเฉพาะสคริปต์กลุ่ม BACKUP/RESTORE/ALTER SERVER CONFIGURATION

---

<div align="center">

**⭐ ถ้าคุณพบว่าคอร์สนี้มีประโยชน์ กรุณา Star Repository นี้ ⭐**

Made with ❤️ for the SQL Server Community

</div>
