# Lab Instruction — คู่มือแล็บห้องเรียน

ชุดคำสั่งแล็บแบบ **step-by-step ระดับคลิก GUI** (แปล/ปรับจาก Microsoft course 20764D)
สำหรับการอบรมในห้องเรียนที่ใช้ virtual machine ที่มี Active Directory domain

> **แยกบทบาทกับแล็บหลักของคอร์ส**: แต่ละ module ใน repo นี้มีแล็บ self-study อยู่ที่
> `Module_XX_*/Labs/README.md` (Instruction + Code block รันได้เองบน SQL Server 2025
> โดยไม่ต้องมี domain) — โฟลเดอร์นี้คือฉบับ **ห้องเรียน** ที่ต้องมี VM environment ตามด้านล่าง

## โครงสร้าง

```
Lab_Instruction/
├── Module-01/ … Module-14/
│   ├── LAB-NN.md      คำสั่งแล็บ (Exercise → Task → ขั้นตอน → Results)
│   ├── Starter/       ไฟล์ให้ผู้เรียน (Setup.cmd, Setupfiles/, Project/ ตาม lab)
│   └── Solution/      เฉลย (เฉพาะ lab ที่มีสคริปต์ให้เติม: Module-02/03/04/08/12/14)
```

## Environment ที่ต้องมี (Classroom VM)

| ส่วนประกอบ | ค่า |
|---|---|
| Domain (AD DS) | `datafabric.local` — DC ชื่อ `datafabric-dc` |
| SQL VM | `DATAFABRIC-SQL-x` (x = หมายเลขเครื่องผู้เรียน) + named instances `\SQL2`, `\SQL3` (ใช้ใน LAB-04, 07, 08) |
| บัญชีเข้าใช้ SQL VM | `DATAFABRIC\Student` / `Pa$$w0rd` |
| SQL Server | 2016/2017 (ตาม courseware ต้นฉบับ) พร้อม SSMS |
| โฟลเดอร์ courseware | `D:\Labfiles\` (deploy จากโฟลเดอร์นี้) และ `D:\SetupFiles\` (ไฟล์ .bak ด้านล่าง) |

> ชื่อ domain/เครื่องปรับมาจาก courseware ต้นฉบับ (`9expert.training` / `9EXPERT-SQL-x`
> และ domain เก่า `ADVENTUREWORKS\`) ให้เป็น `datafabric.*` ทั้งชุดแล้ว — หากสร้าง VM
> ใหม่ให้ตั้งชื่อตามตารางข้างบนเพื่อให้ตรงกับคำสั่งใน LAB-NN.md และสคริปต์ Setup ทั้งหมด

## วิธี Deploy ก่อนคลาส

1. คัดลอก `Module-NN/Starter` ทั้งโฟลเดอร์ไปที่ `D:\Labfiles\LabNN\Starter` บน SQL VM
   เช่น `Module-04/Starter` → `D:\Labfiles\Lab04\Starter` (**Module-14 → Lab14** เช่นกัน —
   ต้นฉบับ MOC เดิมคือ Lab15 เพราะคอร์สใหม่ตัดบท Troubleshooting ออก)
2. คัดลอกไฟล์ `.bak` ที่ lab นั้นต้องใช้ (ตารางด้านล่าง) ไปยัง `D:\SetupFiles\`
3. ผู้เรียนเริ่มแต่ละ lab ด้วยการคลิกขวา `Setup.cmd` → **Run as administrator**
   (สคริปต์จะ restart SQL services, รัน `invoke_dc_commands.ps1` เพื่อสร้าง AD users/groups
   และ restore/สร้างฐานข้อมูลจาก `D:\SetupFiles` อัตโนมัติ — ไฟล์ `*.ps1.txt` จะถูกเปลี่ยน
   ชื่อเป็น `*.ps1` ให้เองระหว่างรัน)

## ตารางสรุปแต่ละ Lab

| Lab | หัวข้อ | ฐานข้อมูลที่ใช้ | ต้องมี .bak ใน D:\SetupFiles | Solution |
|---|---|---|---|---|
| [LAB-01](Module-01/LAB-01.md) | Authentication & logins/users | AdventureWorks, InternetSales | AdventureWorks.bak, InternetSales.bak | — (ทำใน SSMS) |
| [LAB-02](Module-02/LAB-02.md) | Server & database roles | salesapp1 | salesapp1.bak | ✅ |
| [LAB-03](Module-03/LAB-03.md) | Permissions บน objects/code/schema | InternetSales | InternetSales_03.bak | ✅ |
| [LAB-04](Module-04/LAB-04.md) | SQL Audit, Always Encrypted, TDE | salesapp1 (+ SQL2) | salesapp1.bak | ✅ |
| [LAB-05](Module-05/LAB-05.md) | Recovery models & log behavior | MarketDev, Research (สร้างโดย Setup) | — | — |
| [LAB-06](Module-06/LAB-06.md) | Full/Diff/Log, read-only FG, encrypted backup | AdventureWorks | AdventureWorks2016.bak | — |
| [LAB-07](Module-07/LAB-07.md) | Restore, tail-log, piecemeal, master | HumanResources, InternetSales, AWDataWarehouse | HumanResources_07.bak, InternetSales_07.bak, AWDataWarehouse_07.bak* | — |
| [LAB-08](Module-08/LAB-08.md) | Agent jobs, multiserver (MSX/TSX) | HumanResources (+ SQL2, SQL3) | HumanResources_08.bak | ✅ |
| [LAB-09](Module-09/LAB-09.md) | Agent security, credential, proxy | InternetSales (SSIS job) | InternetSales.bak | — |
| [LAB-10](Module-10/LAB-10.md) | Database Mail, operators, alerts | InternetSales, AWDataWarehouse, HumanResources | InternetSales_10.bak, AWDataWarehouse.bak, HumanResources.bak | — |
| [LAB-11](Module-11/LAB-11.md) | PowerShell + SMO | AdventureWorks2016 | AdventureWorks2016.bak | — |
| [LAB-12](Module-12/LAB-12.md) | Extended Events | AdventureWorks | AdventureWorks2016.bak | ✅ |
| [LAB-13](Module-13/LAB-13.md) | Query Store (เนื้อหาใหม่ แทน DMV lab เดิม) | AdventureWorks | AdventureWorks2016.bak | — |
| [LAB-14](Module-14/LAB-14.md) | Import/Export: wizard, bcp, BULK INSERT, SSIS, dacpac | AdventureWorks | AdventureWorks2016.bak | ✅ |

\* LAB-07 Exercise 3 restore จาก `D:\SetupFiles\AWDataWarehouse_07.bak` โดยตรง (ไม่ผ่าน Setup.cmd)

## ข้อจำกัดที่ควรทราบ

- **ไฟล์ `.bak` ทั้งหมด (~557 MB) ไม่ถูก track ใน git** (ดู `.gitignore`) — trainer ต้องเตรียม
  `D:\SetupFiles` จาก image ของ courseware เดิม ไฟล์สาธารณะเช่น `AdventureWorks2016.bak`
  ดาวน์โหลดแทนได้จาก [Microsoft — AdventureWorks sample databases](https://learn.microsoft.com/sql/samples/adventureworks-install-configure)
  แต่ฐานข้อมูลเฉพาะของ courseware (`salesapp1`, `InternetSales_*`, `HumanResources_*`,
  `AWDataWarehouse`, `MarketDev`) ต้องมีจาก image เดิมเท่านั้น
- **`Old/` เป็นวัสดุต้นฉบับแบบ local-only** (ไม่ถูก track): `Old/Labfiles` คือต้นทางของ
  Starter/Solution ในโฟลเดอร์นี้ (คัดลอกมาแล้วพร้อมแก้ชื่อ domain), `Old/Setupfiles` คือคลัง
  `.bak`, ส่วน `Old/Demofiles` **เลิกใช้แล้ว** — demo script ประจำบทเรียนอยู่ที่
  `Module_XX_*/Sections/*/Scripts/` ของคอร์สหลัก
- LAB-05/06/07 เป็นฉบับเขียนใหม่ให้สมบูรณ์ (ต้นฉบับเดิมเป็นหน้าเปล่าที่ชี้ไปลิงก์เสีย)
  โดยยึดสถานการณ์และไฟล์ Setup ของ MOC เดิม และออกแบบให้ backup ที่ใช้ในแล็บ
  **ถูกสร้างระหว่างรันแล็บเอง** ลดการพึ่งพาไฟล์สำเร็จรูป
- แล็บนี้อ้างอิง SQL Server 2016/2017 ตาม courseware ต้นฉบับ — สำหรับเวอร์ชัน
  SQL Server 2025 ให้ใช้แล็บ self-study ที่ `Module_XX_*/Labs/README.md`
