# Module 14 — การถ่ายโอนข้อมูล (Data Transfer)

ฐานข้อมูลไม่ได้อยู่โดดเดี่ยว — ข้อมูลต้องเข้า (ไฟล์จาก vendor, ระบบเก่า, cloud storage) ออก (รายงานให้ทีม data, ระบบ BI) และโครงสร้างต้องย้ายระหว่าง environment อย่างมีเวอร์ชัน โมดูลนี้รวบเครื่องมือถ่ายโอนข้อมูลของ SQL Server ให้เป็นชุดเดียว: **SSIS/Import-Export Wizard** สำหรับงาน ETL และ copy แบบ UI, **bcp + BULK INSERT + OPENROWSET** สำหรับ bulk load ไฟล์ที่เร็วและควบคุมได้ละเอียด, **Linked Server** สำหรับ query ข้าม server และ **Data-tier Applications (dacpac/bacpac)** สำหรับย้าย schema เป็นเวอร์ชันด้วย SqlPackage

ต่อจาก Module 13 (monitoring) แล้ว โมดูลนี้ปิดท้ายส่วน "จัดการข้อมูล" ของคอร์ส: คุณจะได้เทคนิคเร่ง bulk load (minimal logging, TABLOCK, partition switching) ที่ใช้ได้จริงเมื่อโหลดไฟล์หลายสิบล้านแถว และจะได้เห็นว่าเนื้อหาเก่าตัวไหนยังใช้ได้ ตัวไหน deprecated ใน SQL Server 2025

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)
- **ระดับ 1 – เลือกเครื่องมือถูกงาน**: บอกได้ว่าโจทย์ย้ายข้อมูลแบบไหนใช้ wizard/SSIS/bcp/BULK INSERT/OPENROWSET/dacpac
- **ระดับ 2 – โหลดไฟล์เร็วและปลอดภัย**: เขียน BULK INSERT คุมตัวเลือก (terminator, FIRSTROW, BATCHSIZE, ERRORFILE) และเข้าใจเงื่อนไข minimal logging
- **ระดับ 3 – จัดการ constraint/index ใน bulk load**: ปิด-เปิด index (DISABLE/REBUILD) และ constraint อย่างเข้าใจเรื่อง trusted/untrusted พร้อมทำ partition switching ได้
- **ระดับ 4 – deploy schema เป็นเวอร์ชัน**: extract/deploy/upgrade dacpac ด้วย SSMS wizard และ SqlPackage CLI รวมถึงอ่าน drift

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [ภาพรวมการถ่ายโอนข้อมูล + เทคนิค bulk load (minimal logging, partition switch)](Sections/01_Data_Transfer_Overview/README.md) |
| 2 | [SSIS และ Import/Export Wizard](Sections/02_Import_Export_SSIS/README.md) |
| 3 | [bcp, BULK INSERT, Linked Servers, OPENROWSET](Sections/03_bcp_BULK_INSERT/README.md) |
| 4 | [Data-tier Applications (dacpac/bacpac) และ SqlPackage](Sections/04_Data_Tier_Applications/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ (ไฟล์ข้อมูลตัวอย่างอยู่ที่ `Sections/03_bcp_BULK_INSERT/Scripts/Data/`)

---

## Quiz ทบทวน

<details>
<summary><b>1. เงื่อนไขสำคัญของ minimal logging ระหว่าง bulk load คืออะไร?</b></summary>

สามอย่างต้องพร้อมกัน: (1) database อยู่ recovery model **SIMPLE หรือ BULK_LOGGED** (FULL ไม่มี minimal logging เด็ดขาด) (2) ใส่ hint **`TABLOCK`** ขณะโหลด และ (3) ตารางปลายทางเป็น heap ว่าง หรือมีโครงสร้างที่ engine ทำ bulk optimization ได้ แนวปฏิบัติ: โหลดลง heap ว่าง + TABLOCK แล้วสร้าง clustered index ทีหลัง — อ่านละเอียด: [Section 1](Sections/01_Data_Transfer_Overview/README.md)
</details>

<details>
<summary><b>2. CHECK CONSTRAINT แบบ untrusted กับ trusted ต่างกันอย่างไร และคำสั่ง enable แบบไหนได้ trusted?</b></summary>

untrusted ยัง**บังคับข้อมูลใหม่**เหมือนเดิม แต่ **optimizer ไม่ใช้ข้อมูล constraint มาช่วยวางแผน** (เช่น partition elimination / join elimination) ทำให้บาง query ช้าลง คำสั่ง `ALTER TABLE ... CHECK CONSTRAINT` เปิดใช้แต่ได้ untrusted — ต้องใช้ **`ALTER TABLE ... WITH CHECK CHECK CONSTRAINT`** จึงจะตรวจข้อมูลเก่าและได้ trusted — อ่านละเอียด: [Section 1](Sections/01_Data_Transfer_Overview/README.md)
</details>

<details>
<summary><b>3. BULK INSERT กับ OPENROWSET(BULK...) ต่างกันอย่างไรเรื่อง cloud storage?</b></summary>

`BULK INSERT` นำเข้าไฟล์ **เข้าตารางโดยตรง** รองรับ Azure Blob ผ่าน `DATA_SOURCE` (ตั้งแต่ 2017) แต่**ไม่รองรับ S3** `OPENROWSET(BULK ...)` อ่านไฟล์เป็น **rowset** (กรอง/แปลงก่อนลงตารางได้) รองรับ Azure Blob, ADLS Gen2 และ **S3-compatible storage ตั้งแต่ SQL Server 2022** รวมถึง Parquet/Delta (2022+) — อ่านละเอียด: [Section 3](Sections/03_bcp_BULK_INSERT/README.md)
</details>

<details>
<summary><b>4. ขนาดไฟล์ใหญ่มาก ควรใช้ BATCHSIZE หรือ ROWS_PER_BATCH? ต่างกันอย่างไร?</b></summary>

`BATCHSIZE = n` แบ่งการ import เป็น **transaction ย่อยรอบละ n แถว** (commit จริงเป็นรอบ — ใช้กัน log บวม/ทำ retry) ส่วน `ROWS_PER_BATCH = n` เป็นเพียง**คำใบ้**บอกขนาดของ batch เดียวเพื่อให้ engine จัดสรร/ล็อกได้ดีขึ้น ไม่มีการ commit เป็นรอบเกิดขึ้น — อ่านละเอียด: [Section 3](Sections/03_bcp_BULK_INSERT/README.md)
</details>

<details>
<summary><b>5. dacpac กับ bacpac ต่างกันอย่างไร และงาน "อัปเดตเวอร์ชัน schema บน prod" ใช้อะไร?</b></summary>

`.dacpac` = schema เท่านั้น (deploy/upgrade ด้วย Extract/Publish) — เหมาะเป็น build artifact ใน CI/CD `.bacpac` = schema + ข้อมูล (Export/Import) — เหมาะย้ายทั้ง database งานอัปเดตเวอร์ชันบน prod ใช้ **dacpac เวอร์ชันใหม่ + `/Action:Publish` (SqlPackage) หรือ wizard Upgrade Data-tier Application** — อ่านละเอียด: [Section 4](Sections/04_Data_Tier_Applications/README.md)
</details>

<details>
<summary><b>6. อะไรถูก deprecated ในฝั่ง SSIS ของ SQL Server 2025 และควรทำอย่างไร?</b></summary>

**Legacy SSIS service** (การเก็บ/จัดการ package ผ่านบริการเก่า/ msdb) และโหมด **32-bit runtime** ถูกประกาศ deprecated — ใช้ **project deployment ไปยัง SSISDB catalog** และรันแบบ 64-bit จากนี้ไป Import/Export Wizard ยังใช้ได้ปกติและสร้าง package ให้เก็บเป็น file system แล้วนำเข้า SSISDB ต่อได้ — อ่านละเอียด: [Section 2](Sections/02_Import_Export_SSIS/README.md)
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)
- **SSIS**: legacy SSIS service + 32-bit mode deprecated — project deployment ไป SSISDB เป็นมาตรฐาน
- **bcp**: รองรับ **TDS 8.0 / TLS 1.3** (strict encryption) และ `-G` สำหรับ Microsoft Entra authentication ตั้งแต่ SQL Server 2022
- **Linux**: `bulkadmin` / `ADMINISTER BULK OPERATIONS` ใช้ได้แล้วตั้งแต่ SQL Server 2022 CU24 และ **2025 CU3** (พร้อม approved paths ใน mssql-conf)
- **OPENROWSET(BULK)**: รองรับ S3/Azure Blob/ADLS และ Parquet/Delta (ตั้งแต่ 2022) — ทางเข้า data lake จาก T-SQL; ระวัง **BULK INSERT ไม่รองรับ S3**
- **Managed identity** (2025 ผ่าน Arc) ใช้กับ bulk operations กับ Azure Storage ได้ — ลดการเก็บ SAS/secret
- **DAC**: SqlPackage เป็นทางหลัก (cross-platform, รองรับ server roles ใหม่) — ทางเลือก replication สมัยใหม่ระยะสั้นคือ **Fabric Mirroring**

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [Bulk import/export overview](https://learn.microsoft.com/sql/relational-databases/import-export/import-bulk-data-by-using-bulk-insert-or-openrowset-bulk-sql-server?view=sql-server-ver17), [Data-tier applications](https://learn.microsoft.com/sql/tools/sql-database-projects/concepts/data-tier-applications/overview?view=sql-server-ver17)
