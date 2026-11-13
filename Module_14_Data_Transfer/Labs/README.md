# Lab 14: การถ่ายโอนข้อมูล (บทที่ 14)

> **ที่มา**: ปรับปรุงจาก Microsoft 20764D **Lab15** (Transferring Data) + [Microsoft Learn — BULK INSERT](https://learn.microsoft.com/sql/t-sql/statements/bulk-insert-transact-sql?view=sql-server-ver17), [bcp utility](https://learn.microsoft.com/sql/tools/bcp/bcp-use-utility?view=sql-server-ver17), [Data-tier applications](https://learn.microsoft.com/sql/tools/sql-database-projects/concepts/data-tier-applications/overview?view=sql-server-ver17)
> รูปแบบ: **Instruction + Code block** — ทุก Step รันได้ทันทีจากเอกสารเดียว

## Prerequisites
- SQL Server 2025 (17.x) แนะนำ (2019/2022 ได้), database **AdventureWorks2025**
- **bcp** จาก mssql-tools18 (Exercise 2) — ตรวจด้วย `bcp -v`
- **SqlPackage** (Exercise 4) — ตรวจด้วย `sqlpackage /Version` หรือ `dotnet tool list -g`
- โฟลเดอร์ที่ **เครื่อง SQL Server** อ่านได้ เช่น `C:\CourseFiles\` (สำหรับไฟล์ข้อมูล/ผล export)
- สิทธิ์ sysadmin บน instance ทดลอง

## Scenario
ฝ่ายการเงินของบริษัทได้ไฟล์ **รหัสสกุลเงิน** และ **อัตราแลกเปลี่ยน** จากผู้ให้บริการข้อมูลมาเป็นประจำ ต้องโหลดเข้า AdventureWorks2025 ทุกเดือน พร้อมกันนั้นทีม infrastructure ขอย้ายโครงสร้างระบบ "ทะเบียนสินทรัพย์" (FixedAssets) จาก dev ไป test แบบมีเวอร์ชัน ในแล็บนี้คุณจะทำงานทั้งสองอย่าง: โหลดไฟล์ด้วย BULK INSERT/bcp/OPENROWSET และย้าย schema ด้วย dacpac — โดยไฟล์ข้อมูลตัวอย่างอยู่ที่ [`../Sections/03_bcp_BULK_INSERT/Scripts/Data/`](../Sections/03_bcp_BULK_INSERT/Scripts/Data/)

> ⚠️ **ก่อนเริ่ม**: copy โฟลเดอร์ `Scripts/Data/` ไปไว้ที่ path ที่เครื่อง SQL Server มองเห็น (เช่น `C:\CourseFiles\Data\`) แล้วใช้ path นั้นในทุก Exercise — `BULK INSERT`/`OPENROWSET` อ่านไฟล์ด้วย process ฝั่ง server เสมอ

## Objectives
1. นำเข้า currency codes ด้วย BULK INSERT (พร้อม ERRORFILE/BATCHSIZE)
2. ใช้ bcp export (queryout) + import ด้วย format file
3. อ่านไฟล์ด้วย OPENROWSET(BULK ...)
4. Deploy dacpac จาก SSMS (หรือ SqlPackage CLI) ด้วย database FixedAssets จำลอง

---

## Exercise 1: นำเข้า Currency Codes ด้วย BULK INSERT

### Step 1 — สร้างตารางปลายทาง

> **ต้องรู้ก่อน**: เดิมหลักสูตรสร้าง schema `Accounts` ใน AdventureWorks — คอร์สนี้ใช้ schema `Lab` ตามข้อตกลงทั้งเล่ม

```sql
USE AdventureWorks2025;
GO
IF SCHEMA_ID('Lab') IS NULL EXEC('CREATE SCHEMA Lab;');
GO
DROP TABLE IF EXISTS Lab.CurrencyCode;
CREATE TABLE Lab.CurrencyCode
(
    currency_code            char(3)      NOT NULL CONSTRAINT PK_CurrencyCode PRIMARY KEY,
    currency_name            nvarchar(100) NOT NULL,
    modified_date            datetime     NULL
);
GO
```

### Step 2 — BULK INSERT (แก้ path ก่อนรัน)

> **ต้องรู้ก่อน**: `BULK INSERT ... FROM` ต้องเป็น **string literal** จึงใช้ dynamic SQL ครอบตัวแปร path — และ `FIRSTROW = 2` ข้าม header (engine จะไม่ validate แถวที่ข้าม)

```sql
DECLARE @DataFile nvarchar(300) = N'C:\CourseFiles\Data\currency_codes.csv';
--  ^^ แก้ให้ตรงเครื่องคุณ

DECLARE @sql nvarchar(max) =
    N'BULK INSERT Lab.CurrencyCode
      FROM ''' + REPLACE(@DataFile, N'''', N'''''') + N'''
      WITH (
          FIELDTERMINATOR = '','',
          ROWTERMINATOR   = ''\r\n'',
          FIRSTROW        = 2,
          CODEPAGE        = ''65001'',
          TABLOCK,
          CHECK_CONSTRAINTS,
          MAXERRORS       = 10,
          ERRORFILE       = ''C:\CourseFiles\Data\currency_errors.log''
      );';

EXEC (@sql);
GO
```

✅ **สังเกต**: ไฟล์ `currency_codes.csv` เป็น comma-delimited แบบ CRLF (Windows) — ถ้าไฟล์มาจาก Linux ให้ `ROWTERMINATOR = '\n'`

**Expected:** `SELECT COUNT(*) FROM Lab.CurrencyCode;` = **105 แถว** (AED ถึง ZWD)

### Step 3 — ทดลอง BATCHSIZE / การไม่ใส่ CHECK_CONSTRAINTS

```sql
TRUNCATE TABLE Lab.CurrencyCode;

-- ลอง import ซ้ำโดยตัด CHECK_CONSTRAINTS ออก และใส่ BATCHSIZE = 50, ROWS_PER_BATCH = 105
-- (แก้บล็อก WITH ใน dynamic SQL ด้านบนแล้วรันซ้ำ)
```

**Expected:** ผลแถวเท่าเดิม แต่ถ้าตารางมี FK ที่ถูกปิดการตรวจ จะเห็น `is_not_trusted = 1` ใน `sys.foreign_keys` — เชื่อมโยงกับ [Section 1](../Sections/01_Data_Transfer_Overview/README.md) หัวข้อ 3.4

---

## Exercise 2: bcp Export + Import (queryout + Format File)

### Step 1 — Export ผล query เป็น CSV (command line / PowerShell)

> **ต้องรู้ก่อน**: `-T` = Windows integrated auth; `-t,` = field terminator เป็น comma; `queryout` = export ผลของ query ไม่ใช่ทั้งตาราง บน SQL Server 2022+/Azure SQL ใช้ `-G` แทน `-T` สำหรับ Entra auth

```console
bcp "SELECT CurrencyCode, Name FROM Production.Currency ORDER BY CurrencyCode" queryout C:\CourseFiles\Data\currency_export.csv -t, -c -S localhost -d AdventureWorks2025 -T
```

**Expected:** ไฟล์ CSV เกิดขึ้นพร้อมข้อความ "N rows copied."

### Step 2 — สร้าง XML format file จากโครงตารางปลายทาง

```console
bcp Lab.CurrencyCode format nul -f C:\CourseFiles\Data\currency_fmt.xml -x -c -t, -r \n -S localhost -d AdventureWorks2025 -T
```

✅ **สังเกต**: `format nul` = ไม่อ่านข้อมูล แค่ "ถาม" โครงตารางมาสร้าง format file (`-x` = เป็น XML)

### Step 3 — Import กลับด้วย format file

```sql
TRUNCATE TABLE Lab.CurrencyCode;
```

```console
bcp Lab.CurrencyCode in C:\CourseFiles\Data\currency_export.csv -f C:\CourseFiles\Data\currency_fmt.xml -b 100 -S localhost -d AdventureWorks2025 -T
```

**Expected:** 105 แถว (ข้อมูลจาก `Production.Currency` ซึ่งมี 105 แถวพอดีกับชุด currency codes ที่คัดลอกมา) — ตรวจด้วย `SELECT COUNT(*) FROM Lab.CurrencyCode;`

> เวอร์ชัน PowerShell เต็ม (เตรียมตาราง + export + format + import + ตรวจ + cleanup) อยู่ที่ [`../Sections/03_bcp_BULK_INSERT/Scripts/02_bcp_Export_Import.ps1`](../Sections/03_bcp_BULK_INSERT/Scripts/02_bcp_Export_Import.ps1)

---

## Exercise 3: อ่านไฟล์ด้วย OPENROWSET(BULK ...)

### Step 1 — อ่านทั้งไฟล์เป็นข้อความเดียว

> **ต้องรู้ก่อน**: `SINGLE_CLOB` อ่านทั้งไฟล์เป็น varchar หนึ่งแถวหนึ่งคอลัมน์ (`SINGLE_BLOB` = ไบต์ดิบ, `SINGLE_NCLOB` = nvarchar)

```sql
SELECT BulkColumn
FROM OPENROWSET(BULK 'C:\CourseFiles\Data\top_level_domains.csv', SINGLE_CLOB) AS f;
```

**Expected:** ข้อความยาวหลายหมื่นตัวอักษร — ลองเอาไปนับบรรทัด: `SELECT COUNT(*) FROM STRING_SPLIT((SELECT BulkColumn FROM OPENROWSET(BULK '...', SINGLE_CLOB) AS f), CHAR(10));`

### Step 2 — อ่านเป็นแถวด้วย format file

```sql
SELECT *
FROM OPENROWSET(
        BULK 'C:\CourseFiles\Data\currency_codes.csv',
        FORMATFILE = 'C:\CourseFiles\Data\currency_codes.fmt'
     ) AS rows;
```

✅ **สังเกต**: ไฟล์ non-XML format file [`currency_codes.fmt`](../Sections/03_bcp_BULK_INSERT/Scripts/Data/currency_codes.fmt) นิยาม 3 ฟิลด์ + delimiter — ผลคือ 105 แถว 3 คอลัมน์ แบบไม่ยุ่งตารางใดเลย

### Step 3 — INSERT ... SELECT กรองก่อนเข้าตาราง

```sql
SELECT CurrencyCode, CurrencyName, ModifiedDate
FROM OPENROWSET(
        BULK 'C:\CourseFiles\Data\currency_codes.csv',
        FORMATFILE = 'C:\CourseFiles\Data\currency_codes.fmt'
     ) AS rows
WHERE CurrencyCode IN ('THB', 'USD', 'EUR', 'JPY');
```

**Expected:** 4 แถว — นี่คือพลังของ OPENROWSET: query ไฟล์ก่อนตัดสินใจว่าจะเก็บอะไร (สคริปต์เต็ม + รูปแบบ Azure Blob/S3 อยู่ที่ [`../Sections/03_bcp_BULK_INSERT/Scripts/03_OPENROWSET_BULK.sql`](../Sections/03_bcp_BULK_INSERT/Scripts/03_OPENROWSET_BULK.sql))

---

## Exercise 4: Deploy dacpac (SSMS หรือ SqlPackage CLI)

### Step 1 — สร้าง database ตัวอย่าง FixedAssets

> **ต้องรู้ก่อน**: หลักสูตรเดิมใช้ไฟล์ `FixedAssets_1.0.9.1.dacpac` สำเร็จรูป — เราสร้าง database จำลองเองให้ครบในตัว

รัน [`../Sections/04_Data_Tier_Applications/Scripts/01_FixedAssets_Create.sql`](../Sections/04_Data_Tier_Applications/Scripts/01_FixedAssets_Create.sql) ทั้งไฟล์ — ได้ database `FixedAssets` (schema Asset, 3 ตาราง, ข้อมูลตัวอย่าง)

### Step 2 (ทาง A) — Extract + Deploy ผ่าน SSMS wizard

1. Right-click database **FixedAssets** > **Tasks** > **Extract Data-tier Application...** — ตั้ง Application Name `FixedAssets`, Version `1.0.0.0`, เซฟเป็น `C:\CourseFiles\Data\fixedassets_1.0.0.dacpac` (ดู validation report ก่อน Finish)
2. Right-click node **Databases** > **Deploy Data-tier Application...** — เลือกไฟล์ที่ extract, ตั้งชื่อ database ปลายทาง `FixedAssets_Deployed`
3. ตรวจ: `SELECT instance_name, type_version FROM msdb.dbo.sysdac_instances;`

**Expected:** database ใหม่มี schema+ข้อมูลเหมือนต้นฉบับ และมีแถว DAC instance ใน msdb

### Step 2 (ทาง B) — Extract + Deploy ผ่าน SqlPackage CLI (สมัยใหม่)

```powershell
sqlpackage /Action:Extract /SourceServerName:localhost /SourceDatabaseName:FixedAssets `
    /TargetFile:"C:\CourseFiles\Data\fixedassets_1.0.0.dacpac" /p:DacVersion=1.0.0

sqlpackage /Action:Publish /SourceFile:"C:\CourseFiles\Data\fixedassets_1.0.0.dacpac" `
    /TargetServerName:localhost /TargetDatabaseName:FixedAssets_Deployed /p:CreateNewDatabase=true
```

> **ต้องรู้ก่อน**: `/Action:Publish` กับ database ที่มีอยู่ = update แบบ **incremental** (เทียบ diff ก่อน apply) — ก่อน publish สำคัญให้รัน `/Action:Script` เพื่อดู deploy script ก่อนเสมอ

### Step 3 — Upgrade in-place (เวอร์ชัน 1.1.0)

```sql
USE FixedAssets;
ALTER TABLE Asset.FixedAsset ADD SerialNumber nvarchar(60) NULL;
```

```powershell
sqlpackage /Action:Extract /SourceServerName:localhost /SourceDatabaseName:FixedAssets `
    /TargetFile:"C:\CourseFiles\Data\fixedassets_1.1.0.dacpac" /p:DacVersion=1.1.0

sqlpackage /Action:Publish /SourceFile:"C:\CourseFiles\Data\fixedassets_1.1.0.dacpac" `
    /TargetServerName:localhost /TargetDatabaseName:FixedAssets_Deployed
```

หรือทาง wizard: right-click **FixedAssets_Deployed** > **Tasks** > **Upgrade Data-tier Application...**

**Expected:** `FixedAssets_Deployed` มีคอลัมน์ `SerialNumber` เพิ่ม — schema ของสอง database ตรงกันแล้ว

### Step 4 — (Bonus) Export/Import bacpac ย้ายทั้ง database

```powershell
sqlpackage /Action:Export /SourceServerName:localhost /SourceDatabaseName:FixedAssets `
    /TargetFile:"C:\CourseFiles\Data\fixedassets.bacpac"

sqlpackage /Action:Import /SourceFile:"C:\CourseFiles\Data\fixedassets.bacpac" `
    /TargetServerName:localhost /TargetDatabaseName:FixedAssets_FromBacpac
```

---

## 🧹 Clean-up

```sql
-- Exercise 1-3
USE AdventureWorks2025;
DROP TABLE IF EXISTS Lab.CurrencyCode;
DROP TABLE IF EXISTS Lab.CurrencyImport;
DROP TABLE IF EXISTS Lab.CurrencyOpenRowset;

-- Linked Server (ถ้ารันสคริปต์ 04 ของ Section 3)
USE master;
IF EXISTS (SELECT 1 FROM sys.servers WHERE name = N'LOOPBACK')
    EXEC sp_dropserver 'LOOPBACK', 'droplogins';

-- Exercise 4
USE master;
IF DB_ID('FixedAssets')            IS NOT NULL DROP DATABASE FixedAssets;
IF DB_ID('FixedAssets_Deployed')   IS NOT NULL DROP DATABASE FixedAssets_Deployed;
IF DB_ID('FixedAssets_FromBacpac') IS NOT NULL DROP DATABASE FixedAssets_FromBacpac;
```

```powershell
# ลบไฟล์ dacpac/bacpac/export ชั่วคราว (ถ้าต้องการ)
Remove-Item C:\CourseFiles\Data\fixedassets_*.dacpac, C:\CourseFiles\Data\fixedassets.bacpac `
            C:\CourseFiles\Data\currency_export.csv, C:\CourseFiles\Data\currency_fmt.xml `
            -ErrorAction SilentlyContinue
```

> หมายเหตุ: ลบ DAC instances ค้างใน msdb ได้ผ่าน SSMS: right-click database ภายใต้ **Management > Data-tier Applications** > Delete Data-tier Application

## Quiz ท้ายแล็บ

1. เหตุใด BULK INSERT ต้องใช้ dynamic SQL เมื่ออยากใส่ path เป็นตัวแปร?
2. ถ้า `SELECT COUNT(*)` ได้ 105 แถว แต่ตารางมี FK ที่ `is_not_trusted = 1` แถวเหล่านั้นผ่านการตรวจ FK หรือไม่ แล้วควรทำอย่างไรต่อ?
3. ทำไม `ERRORFILE` จึงต้องอยู่เครื่อง server และไม่ควรมีไฟล์ชื่อเดียวกันอยู่แล้ว?
4. จุดต่างสำคัญระหว่าง "Publish dacpac" กับ "Import bacpac" คืออะไร และงานไหนใช้อะไร?
