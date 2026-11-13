# Module 00 — เริ่มต้นใช้งาน (Getting Started)

โมดูลนี้ไม่ใช่หัวข้อสอน แต่เป็นคู่มือเตรียม environment ให้พร้อมสำหรับแล็บทั้ง 14 โมดูล ทำให้จบก่อนเริ่มบทที่ 1

หลังจบโมดูลนี้คุณจะมี:

1. SQL Server 2025 (17.x) Developer Edition ที่รันอยู่ (หรือ SQL Server 2019/2022 ด้วยข้อจำกัดที่ระบุไว้)
2. SSMS 21 และ PowerShell 7 พร้อม `SqlServer` module
3. ฐานข้อมูล **AdventureWorks2025** restore เรียบร้อย
4. ตรวจสอบความพร้อมผ่าน `01_Verify_Environment.sql` ผ่านทุกรายการ

---

## 1. ติดตั้ง SQL Server 2025

### ทางเลือก A — ติดตั้งบน Windows (แนะนำสำหรับคอร์ส)

1. ดาวน์โหลด SQL Server 2025 Developer Edition ฟรีจาก [หน้า Get SQL Server 2025](https://www.microsoft.com/sql-server/sql-server-2025)
2. รัน installer เลือก **Developer** edition (มีความสามารถเท่า Enterprise ใช้เพื่อการศึกษาได้ฟรี)
3. ระหว่างติดตั้ง:
   - เลือก **Database Engine Services** + **SQL Server Agent** (จำเป็นสำหรับ Module 8–9)
   - Authentication mode: เลือก **Mixed Mode** และตั้งรหัสผ่าน `sa` (ใช้ `Pa$$w0rd2025` สำหรับห้องเรียน) — คอร์สนี้จะสร้าง SQL Authentication login ใน Module 1
   - เพิ่ม user ปัจจุบันเป็น administrator ของ instance
4. เปิด port 1433 ใน Windows Firewall ถ้าจะเชื่อมต่อจากเครื่องอื่น

> **ข้อแตกต่างที่ควรรู้จาก SQL Server 2025** ([What's new](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17)): Developer edition แบ่งเป็น Standard Developer และ Enterprise Developer; Resource Governor มีใน Standard แล้ว; Web edition ถูกถอด; Express ใหญ่ขึ้นเป็น 50 GB ต่อฐานข้อมูล

### ทางเลือก B — Docker (สำหรับ Linux/macOS หรือ VM แยกเครื่อง)

```bash
docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Pa$$w0rd2025" \
  -p 1433:1433 --name sql2025 \
  -v sql2025data:/var/opt/mssql \
  -d mcr.microsoft.com/mssql/server:2025-latest
```

> แล็บบางโมดูล (Multiserver Jobs ใน Module 8, PowerShell remote ใน Module 11) ออกแบบให้ทำบน instance เดียวได้ แต่ถ้าต้องการสองเครื่องจริง สร้าง container ที่สอง ที่ port 1434 ได้:
>
> ```bash
> docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Pa$$w0rd2025" \
>   -p 1434:1433 --name sql2025b -d mcr.microsoft.com/mssql/server:2025-latest
> ```

---

## 2. ติดตั้ง Tools

| Tool | เวอร์ชันที่แนะนำ | ใช้ทำอะไร |
|:-----|:----------------|:----------|
| [SQL Server Management Studio (SSMS)](https://learn.microsoft.com/sql/ssms/download-sql-server-management-studio-ssms?view=sql-server-ver17) | 21 (ล่าสุด) | เครื่องมือหลักของทุกโมดูล |
| [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) | 7.4+ | Module 11, 14 |
| [SqlServer PowerShell module](https://learn.microsoft.com/powershell/module/sqlserver/) | ล่าสุด | Module 11, 14 |
| [SqlPackage](https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage?view=sql-server-ver17) | ล่าสุด | Module 14 (dacpac) |
| sqlcmd / bcp รุ่นใหม่ | go-sqlcmd + bcp จาก mssql-tools18 | Module 14 |

ติดตั้ง PowerShell module ให้เรียบร้อยก่อนเริ่ม Module 11:

```powershell
Install-Module -Name SqlServer -Scope CurrentUser -Force
Install-Module -Name dbatools -Scope CurrentUser -Force   # optional, ใช้เสริม
```

> **SQLPS เก่าอย่าใช้แล้ว** — โมดูล `SQLPS` ที่มากับ SQL Server 2016 และ `SQLPS` ใน SSMS 18 ลงหรือเก่ากว่า ถูกแทนด้วย `SqlServer` module อย่างเป็นทางการ

---

## 3. Restore AdventureWorks2025

1. ดาวน์โหลด [AdventureWorks2025.bak](https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2025.bak) ไปที่ `D:\SetupFiles\` (หรือโฟลเดอร์ที่ SQL Server service อ่านได้)
2. Restore ด้วยสคริปต์ [`Scripts/00_Restore_AdventureWorks2025.sql`](Scripts/00_Restore_AdventureWorks2025.sql) — แก้ path ให้ตรงเครื่องของคุณ
3. วิธีทำละเอียด (SSMS / T-SQL / command line) ดูที่ [Microsoft Learn — AdventureWorks install](https://learn.microsoft.com/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms)

> ใช้ SQL Server 2019/2022 อยู่ใช้ AdventureWorks2022.bak และแก้ชื่อ DB เป็น `AdventureWorks2022` ในสคริปต์ทุกโมดูล

---

## 4. ตรวจความพร้อม

รัน [`Scripts/01_Verify_Environment.sql`](Scripts/01_Verify_Environment.sql) ใน SSMS:

- ✅ `@@VERSION` ระบุ 17.x (SQL Server 2025)
- ✅ AdventureWorks2025 พร้อมตาราง `Sales.SalesOrderHeader`
- ✅ SQL Server Agent service กำลังรัน (ตรวจจาก `sys.dm_server_services`)
- ✅ Database Mail feature พร้อมเปิดใช้ (Module 10)
- ✅ Query Store / XE พร้อมใช้

ข้อไหน fail ให้กลับไปแก้ก่อนเข้า Module 1

---

## 5. โครงสร้างการเรียน

แต่ละโมดูลมีโครงเหมือนกัน:

```
Module_XX_Topic/
├── README.md          # บทนำ + สารบัญ Sections + Quiz ท้ายบท
├── Sections/
│   └── NN_Topic/
│       ├── README.md  # เนื้อหาบทเรียน (อ่านเป็นลำดับ)
│       └── Scripts/   # demo scripts ของหัวข้อนั้น
└── Labs/
    └── README.md      # แล็บปฏิบัติ ทำจบหลังเรียนจบโมดูล
```

คำศัพท์ที่เจอบ่อยรวมอยู่ที่ [Glossary.md](../Glossary.md)

> ⚠️ **คำเตือนด้านความปลอดภัยของข้อมูลจริง**: สคริปต์หลายตัวสร้าง/ลบ login, ตั้ง server config, backup/restore และเขียนไฟล์ — ให้รันบน VM/instance ทดลองเท่านั้น และ**อ่านสคริปต์ทุกตัวก่อนรันบน production**
