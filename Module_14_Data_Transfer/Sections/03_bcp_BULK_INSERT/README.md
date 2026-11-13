# Section 3 — bcp, BULK INSERT, Linked Servers และ OPENROWSET

เมื่อข้อมูลมาในรูป "ไฟล์" (CSV/ข้อความ/plain data file) เครื่องมือหลักของ SQL Server คือสามตัวนี้: **bcp** (bulk copy program — command line ที่เร็วที่สุดและทำ export ได้), **BULK INSERT** (T-SQL นำเข้าไฟล์โดยตรง — ใส่ Agent job ได้สวย) และ **OPENROWSET(BULK ...)** (อ่านไฟล์เป็น rowset แล้วกรอง/แปลงก่อนลงตาราง) ส่วน **Linked Server** ครอบเคส "query ข้อมูลบน server อื่น" โดยไม่ต้องย้ายไฟล์เลย

ไฟล์ข้อมูลตัวอย่างอยู่ที่ [`Scripts/Data/`](Scripts/Data/):
- [`currency_codes.csv`](Scripts/Data/currency_codes.csv) — รหัสสกุลเงิน 105 แถว (คัดลอกจากข้อมูลตัวอย่างเดิมของหลักสูตร, comma-delimited, CRLF)
- [`top_level_domains.csv`](Scripts/Data/top_level_domains.csv) — ชื่อ TLD 1,252 แถว + header (ใช้ฝึกตัวเลือก `FIRSTROW`)
- [`currency_codes.fmt`](Scripts/Data/currency_codes.fmt) — format file แบบ non-XML สำหรับอ่าน CSV ด้วย bcp/OPENROWSET

> ⚠️ **เรื่อง path**: `BULK INSERT`/`OPENROWSET(BULK)` อ่านไฟล์ด้วย **process ของ SQL Server** ดังนั้น path ต้องเป็น path ที่เครื่อง **server** มองเห็น (local disk หรือ UNC) — ไม่ใช่เครื่องที่คุณนั่ง สคริปต์ทุกไฟล์ใน Section นี้ใช้ตัวแปร `@SetupDir` ต้นไฟล์ **ให้แก้ path ให้ตรงเครื่องคุณก่อนรัน**

## 1. bcp — bulk copy program

**bcp** คือ utility บน command line (มากับ client tools / `mssql-tools18`) ทำสองทิศ: `out`/`queryout` (ออกจาก SQL Server เป็นไฟล์) และ `in` (จากไฟล์เข้าตาราง) เร็วเพราะทำงานเป็นโปรแกรมล้วน ๆ ไม่มี UI overhead

รูปแบบพื้นฐาน:

```console
:: export ทั้งตารางเป็นไฟล์ character format (CSV ประมาณ)
bcp AdventureWorks2025.Production.Currency out D:\bcp\Currency.csv -c -t, -S localhost -T

:: export ผลของ query (queryout)
bcp "SELECT CurrencyCode, Name FROM Production.Currency" queryout D:\bcp\Currency_Query.csv -t, -c -S localhost -T

:: import ไฟล์เข้าตาราง
bcp Lab.CurrencyImport in D:\bcp\Currency.csv -c -t, -S localhost -T

:: สร้าง format file แบบ XML จากโครงตาราง (ไม่อ่านข้อมูล — target เป็น nul)
bcp AdventureWorks2025.Production.Currency format nul -x -f D:\bcp\Currency_Fmt.xml -S localhost -T
```

ตัวเลือกที่ใช้บ่อย:

| Option | ความหมาย |
|:--------|:----------|
| `-T` | ใช้ Windows integrated (trusted) connection |
| `-U` / `-P` | SQL authentication (login/password) |
| `-S` / `-d` | server (และ instance) / database |
| `-c` | character mode (ทุกคอลัมน์เป็นข้อความ) |
| `-n` | native mode (โครงไบนารีตามชนิดคอลัมน์ — เร็วสุด ใช้ SQL ต่อ SQL) |
| `-t` / `-r` | field terminator / row terminator (เช่น `-t,` `-r\n`) |
| `-f` | ใช้ format file (non-XML หรือ XML ถ้าเพิ่ม `-x` ตอนสร้าง) |
| `-F` / `-L` | first row / last row — ตัดช่วงแถว (ใช้แบ่งไฟล์ทำ parallel load) |
| `-E` | คงค่า identity จากไฟล์ |
| `-b` | batch size (แถวต่อ batch) |
| `-e` | error file เก็บแถวที่ fail |

### Authentication ยุคใหม่: -T ยังเป็นค่า default ของคอร์ส แต่รู้จัก -G

- `-T` (Windows integrated) ใช้ได้เมื่ออยู่ใน domain/เครื่อง Windows ที่สิทธิ์ผ่าน — ในคอร์สนี้เราใช้ `-T` กับ instance ทดลอง
- กับ Azure SQL หรือ SQL Server 2022+ ที่เปิดใช้ **Microsoft Entra ID** ให้ใช้ **`-G`** (แทน `-T`) ร่วมกับ `-U` กรณี user/password แบบ Entra หรือผ่าน DSN แบบ managed identity — ดู [Authenticate with Microsoft Entra ID in bcp](https://learn.microsoft.com/sql/tools/bcp/bcp-authentication?view=sql-server-ver17)
- SQL Server 2025 เพิ่มการรองรับ **TDS 8.0 (TLS 1.3)** ให้ bcp — การเชื่อมต่อเข้มงวดเรื่องการเข้ารหัสตั้งแต่ handshake ([bcp utility](https://learn.microsoft.com/sql/tools/bcp/bcp-utility?view=sql-server-ver17))

### Format file — เมื่อไฟล์กับตาราง "ไม่ตรงกัน"

Format file (non-XML หรือ XML) บอก bcp/BULK INSERT ว่าแต่ละฟิลด์ในไฟล์ map ไปคอลัมน์ไหน ชนิดอะไร delimiter อะไร — จำเป็นเมื่อไฟล์มีคอลัมน์เกิน/สลับลำดับ/ต้อง skip คอลัมน์ สคริปต์ PowerShell [`Scripts/02_bcp_Export_Import.ps1`](Scripts/02_bcp_Export_Import.ps1) สาธิต: สร้าง format file จากโครงตาราง (`format nul -x`), export ด้วย `queryout`, import กลับด้วย format file และไฟล์ [`currency_codes.fmt`](Scripts/Data/currency_codes.fmt) คือตัวอย่าง non-XML format file ที่เขียนมือ (โครงสร้าง: เวอร์ชัน format file → จำนวนฟิลด์ → หนึ่งบรรทัดต่อฟิลด์)

## 2. BULK INSERT — นำเข้าไฟล์ด้วย T-SQL

`BULK INSERT` ทำงานเทียบเท่า `bcp in` แต่อยู่ใน T-SQL — **server อ่านไฟล์เอง** (จึงไม่ต้องมี client tools ที่เครื่องรัน) และใส่ Agent job / stored procedure ได้ทันที

สคริปต์เต็มอยู่ที่ [`Scripts/01_BULK_INSERT_Currency.sql`](Scripts/01_BULK_INSERT_Currency.sql) — สาระสำคัญ:

```sql
DECLARE @SetupDir nvarchar(260) = N'C:\CourseFiles\sql-server-administration\Module_14_Data_Transfer\Sections\03_bcp_BULK_INSERT\Scripts\Data\';
--  ^^ แก้ path นี้ให้ตรงเครื่องคุณ (ต้องเป็น path ฝั่ง SERVER มองเห็น)

BULK INSERT Lab.CurrencyImport
FROM 'C:\CourseFiles\...\currency_codes.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\r\n',   -- ไฟล์ที่แจกมาเป็น CRLF แบบ Windows
    FIRSTROW        = 2,        -- ข้ามบรรทัด header
    CODEPAGE        = '65001',  -- UTF-8 (ไฟล์จาก Linux/ที่มีภาษาอื่น)
    TABLOCK,                    -- ให้ minimal logging ทำงาน (SIMPLE/BULK_LOGGED)
    CHECK_CONSTRAINTS,          -- ตรวจ FK/CHECK ระหว่างโหลด (ถ้าไม่ใส่ = ไม่ตรวจ!)
    ERRORFILE   = 'C:\CourseFiles\...\currency_errors.log',
    MAXERRORS   = 10
);
```

ตัวเลือกสำคัญของ BULK INSERT:

| Option | ใช้ทำอะไร | หมายเหตุ |
|:--------|:-----------|:----------|
| `FIELDTERMINATOR` / `ROWTERMINATOR` | ตัวคั่นคอลัมน์/แถว | ไฟล์ Windows จริง ๆ ใช้ `'\r\n'`; ไฟล์ที่สร้างบน Linux จะเป็น `'\n'` |
| `FIRSTROW` / `LASTROW` | ข้าม header / เลือกช่วงแถว | `FIRSTROW = 2` เท่ากับเริ่มแถวที่สอง (นับ 1-based) |
| `BATCHSIZE` | แบ่ง import เป็น transaction ย่อย | กัน log บวม + retry ต่อ batch |
| `ROWS_PER_BATCH` | บอกขนาดโดยประมาณของ batch เดียว | ช่วยการจัดสรร ไม่ commit เป็นรอบ (ต่างจาก BATCHSIZE) |
| `DATAFILETYPE` | ชนิดไฟล์: `char`, `native`, `widechar`, `widenative` | `native` ใช้กับไฟล์ที่ bcp `-n` สร้าง |
| `CODEPAGE` | code page ของไฟล์: `'ACP'`, `'RAW'`, `'65001'` (UTF-8) | ไฟล์ UTF-8 ต้องระบุ 65001 |
| `FORMATFILE` | ใช้ format file (non-XML/XML) | เมื่อไฟล์ไม่ตรงโครงตาราง |
| `ERRORFILE` + `MAXERRORS` | เก็บแถวที่ fail และยอมได้กี่แถว | ไฟล์ error อยู่ฝั่ง server เสมอ |
| `TABLOCK` | ล็อกทั้งตารางช่วงโหลด | เปิดประตู minimal logging |
| `CHECK_CONSTRAINTS` | บังคับตรวจ FK/CHECK | **ไม่ใส่ = constraint ไม่ถูกตรวจ** (และหลัง enable จะ untrusted) |
| `FIRE_TRIGGERS` | ยิง trigger ระหว่างโหลด | default คือไม่ยิง |
| `KEEP_IDENTITY` / `KEEP_NULLS` | เก็บค่า identity จากไฟล์ / เก็บ NULL | ทำงานเหมือน `-E` ของ bcp |

> สิทธิ์ที่ต้องมี: `INSERT` บนตาราง + `ADMINISTER BULK OPERATIONS` (หรือ role `bulkadmin`) และถ้าตารางมี constraint/trigger แล้วไม่ใส่ `CHECK_CONSTRAINTS`/`FIRE_TRIGGERS` จะต้องมี `ALTER TABLE` ด้วย ([BULK INSERT](https://learn.microsoft.com/sql/t-sql/statements/bulk-insert-transact-sql?view=sql-server-ver17))

> บน Linux: ตั้งแต่ SQL Server 2022 CU24 และ **2025 CU3** role `bulkadmin`/สิทธิ์ `ADMINISTER BULK OPERATIONS` ใช้ได้แล้ว (เดิม sysadmin เท่านั้น) ร่วมกับการ config approved paths ผ่าน mssql-conf ([Bulk operations on Linux](https://learn.microsoft.com/sql/linux/sql-server-linux-bulk-operations?view=sql-server-ver17))

## 3. Linked Servers — query ข้าม server แบบสด

Linked Server คือ config ระดับ instance ที่ทำให้ query ไปยัง data source อื่น (SQL Server อีกตัว, Oracle, Excel, OLE DB provider อื่น ๆ) ผ่านชื่อเลียนแบบ 4-part: `server.database.schema.table` หรือผ่าน `OPENQUERY`

สคริปต์เต็มที่ [`Scripts/04_Linked_Server.sql`](Scripts/04_Linked_Server.sql) — ตัวอย่างที่รันได้โดยไม่ต้องมี server ที่สอง: สร้าง linked server ชี้ "กลับมาที่ตัวเอง" (loopback):

```sql
-- สร้าง linked server แบบ dynamic เพื่อชี้กลับ instance ตัวเอง
DECLARE @Self nvarchar(128) = CONVERT(nvarchar(128), SERVERPROPERTY('ServerName'));

EXEC sp_addlinkedserver
     @server     = N'LOOPBACK',
     @srvproduct = N'',
     @provider   = N'MSOLEDBSQL',
     @datasrc    = @Self;

EXEC sp_addlinkedsrvlogin
     @rmtsrvname  = N'LOOPBACK',
     @useself     = N'TRUE';   -- ใช้ credential ของผู้เรียก

-- Query แบบ 4-part name
SELECT TOP (5) * FROM LOOPBACK.AdventureWorks2025.Production.Currency;

-- Query ผ่าน OPENQUERY (ส่ง query ไปรันที่ remote แล้วส่งผลกลับ — คุม execution ดีกว่า)
SELECT TOP (5) * FROM OPENQUERY(LOOPBACK,
    N'SELECT CurrencyCode, Name FROM AdventureWorks2025.Production.Currency');
```

ข้อควรรู้:

- **ความปลอดภัย**: `sp_addlinkedsrvlogin @useself = 'TRUE'` ส่ง credential ผู้เรียกไป (บน domain คือ Kerberos double-hop — อาจ fail ถ้าไม่มี delegation) แบบที่ต้องระวังคือ `@useself = 'FALSE'` + ฝัง login/password กลาง (ทุกคนใช้บัญชีเดียวกัน) — จำกัดสิทธิ์บัญชีนั้นให้น้อยที่สุด
- **Performance**: join ตาราง remote ใหญ่กับ local ใหญ่ ๆ มักช้า — กรองด้วย `OPENQUERY` ให้ remote ทำงานก่อนจะดีกว่า 4-part ล้วน
- SQL Server 2025 รองรับ **TDS 8.0 สำหรับ linked servers** (มี breaking changes เรื่อง encryption — ตรวจ [breaking changes](https://learn.microsoft.com/sql/database-engine/breaking-changes-to-database-engine-features-in-sql-server-2025?view=sql-server-ver17) ก่อนอัปเกรด)

## 4. OPENROWSET(BULK ...) — อ่านไฟล์เป็น rowset

`OPENROWSET(BULK ...)` ให้ query **ไฟล์โดยตรง** เหมือนเป็นตาราง — ได้ทั้งอ่านอย่างเดียว หรือผ่าน `INSERT ... SELECT` ลงตารางพร้อมแปลงค่า

### 4.1 อ่านไฟล์ทั้งก้อนเป็นค่าเดียว (SINGLE_BLOB / SINGLE_CLOB / SINGLE_NCLOB)

สคริปต์เต็มที่ [`Scripts/03_OPENROWSET_BULK.sql`](Scripts/03_OPENROWSET_BULK.sql):

```sql
-- อ่านไบต์ดิบทั้งไฟล์ (varbinary) — เช่น เก็บเข้าตาราง document
SELECT BulkColumn
FROM OPENROWSET(BULK 'C:\CourseFiles\...\currency_codes.csv', SINGLE_BLOB) AS f;

-- อ่านเป็นข้อความ (varchar/nvarchar) แล้วนับบรรทัดด้วย STRING_SPLIT
SELECT COUNT(*) AS LineCount
FROM STRING_SPLIT(
    (SELECT BulkColumn FROM OPENROWSET(BULK 'C:\CourseFiles\...\top_level_domains.csv', SINGLE_CLOB) AS f),
    CHAR(10));
```

### 4.2 อ่านเป็นแถวด้วย format file

```sql
-- ใช้ non-XML format file ที่แจกมา (แก้ path ตามเครื่อง)
SELECT *
FROM OPENROWSET(
        BULK 'C:\CourseFiles\...\currency_codes.csv',
        FORMATFILE = 'C:\CourseFiles\...\currency_codes.fmt'
     ) AS rows;
```

✅ **สังเกต**: ผลเป็น 105 แถวสามคอลัมน์ — อ่านไฟล์ "เป็นตาราง" โดยไม่ยุ่งตารางจริงเลย นำไป `INSERT ... SELECT ... WHERE` กรองก่อนเข้าตารางได้

### 4.3 อ่านไฟล์บน Azure Blob / ADLS / S3 (SQL Server 2022+)

ตั้งแต่ SQL Server 2022 `OPENROWSET(BULK ...)` รองรับ object storage โดยตรงผ่าน **EXTERNAL DATA SOURCE** (ต้องมี database scoped credential ตามชนิด storage):

```sql
-- โครงแบบ Azure Blob (abs://) — ร่วมกับ DATABASE SCOPED CREDENTIAL แบบ SAS
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Pa$$w0rd2025';

CREATE DATABASE SCOPED CREDENTIAL BlobCred
    WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
         SECRET   = 'sv=2022-11-02&ss=b&srt=sco&sp=rl&se=2027-01-01T00:00:00Z&sig=...';

CREATE EXTERNAL DATA SOURCE BlobSrc
    WITH (LOCATION = 'abs://mystorageaccount.blob.core.windows.net/imports');

SELECT * FROM OPENROWSET(
    BULK 'currency_codes.csv',
    DATA_SOURCE = 'BlobSrc',
    SINGLE_CLOB) AS f;

-- โครงแบบ S3-compatible (s3://) — SQL Server 2022+, credential ชนิด S3 Access Key
CREATE EXTERNAL DATA SOURCE S3Src
    WITH (LOCATION = 's3://10.0.0.10:9000/imports',
          CREDENTIAL = S3AccessKeyCred);   -- IDENTITY = 'S3 Access Key', SECRET = 'key:secret'

SELECT * FROM OPENROWSET(
    BULK 'currency_codes.csv',
    DATA_SOURCE = 'S3Src',
    SINGLE_CLOB) AS f;
```

> ⚠️ ข้อแตกต่างที่หลายคนพลาด: **BULK INSERT ไม่รองรับ S3** (รองรับ Azure Blob ผ่าน `DATA_SOURCE`, ADLS Gen2 ตั้งแต่ 2019 CU11) ขณะที่ **OPENROWSET(BULK) รองรับทั้ง Blob/ADLS/S3** — อ้าง [Data virtualization guide](https://learn.microsoft.com/sql/relational-databases/polybase/data-virtualization-guide?view=sql-server-ver17) และ [OPENROWSET BULK](https://learn.microsoft.com/sql/t-sql/functions/openrowset-bulk-transact-sql?view=sql-server-ver17)

## 5. Troubleshooting bulk operations — ข้อผิดพลาดที่เจอบ่อย

| อาการ | สาเหตุที่พบบ่อย | ทางแก้ |
|:-------|:------------------|:--------|
| Msg 4861 "Cannot bulk load. The file ... does not exist" | path อยู่เครื่อง client แต่ server อ่าน / service account ไม่มีสิทธิ์โฟลเดอร์ | ใช้ path ฝั่ง server (หรือ UNC) + ให้ SQL Server service account อ่านได้ |
| Msg 4864 "type conversion error" | รูปแบบข้อมูลไม่เข้าคอลัมน์ (วันที่/ตัวเลข) | แก้ไฟล์, ใช้ format file, หรือโหลดเข้า staging คอลัมน์ varchar แล้ว CONVERT ทีหลัง |
| Msg 4861 แบบ security/delegation (UNC ข้ามเครื่อง) | Windows auth ไม่ delegate ได้ | ใช้ SQL auth (ไฟล์ถูกอ่านด้วย service account) หรือตั้ง delegation |
| แถวท้ายมี `\r` ติดค่า | ไฟล์ LF แต่ระบุ `ROWTERMINATOR = '\r\n'` (หรือกลับกัน) | ตรวจ line ending ของไฟล์จริงแล้วเลือกให้ตรง |
| Constraint ไม่บังคับหลังโหลด | โหลดโดยไม่ใส่ `CHECK_CONSTRAINTS` → constraint กลายเป็น untrusted | ตรวจ `is_not_trusted` แล้ว enable ด้วย `WITH CHECK CHECK` ให้ได้เมื่อจบ |
| ERRORFILE "already exists" | ไฟล์ error จากรอบก่อนยังอยู่ | ลบไฟล์ error/error.txt ก่อนรันใหม่ (documented พฤติกรรม) |

และจำเรื่องสิทธิ์ให้ขึ้นใจ: bulk operations ต้องการ `ADMINISTER BULK OPERATIONS` (+ `INSERT` ปลายทาง) และถ้าไม่ใส่ `CHECK_CONSTRAINTS`/`FIRE_TRIGGERS` จะต้องมี `ALTER TABLE` ด้วย — ตารางสิทธิ์เต็มอยู่ที่ [BULK INSERT — Permissions](https://learn.microsoft.com/sql/t-sql/statements/bulk-insert-transact-sql?view=sql-server-ver17#security)

## 6. แบบฝึกหัดท้าย Section — นำเข้า currency codes (จาก Lab 15 เดิม)

โจทย์เดิมของหลักสูตร (Lab15 Exercise 1): นำเข้าไฟล์รหัสสกุลเงินเข้าตาราง `Accounts.CurrencyCode` ด้วย BULK INSERT — เราปรับเป็น schema `Lab` บน AdventureWorks2025:

1. รันส่วน setup ของ [`Scripts/01_BULK_INSERT_Currency.sql`](Scripts/01_BULK_INSERT_Currency.sql) (สร้าง `Lab.CurrencyImport`) และ**แก้ `@SetupDir` ที่หัวไฟล์**
2. รัน BULK INSERT หลัก — ตรวจว่าได้ 105 แถว
3. รันซ้ำโดยเอา `CHECK_CONSTRAINTS` ออกและตั้ง `ERRORFILE` — สังเกตพฤติกรรม
4. ทำตาม [`Scripts/02_bcp_Export_Import.ps1`](Scripts/02_bcp_Export_Import.ps1) — export `Production.Currency` ด้วย `queryout` แล้ว import เข้า `Lab.CurrencyImport` ด้วย format file
5. (Optional) อ่าน `top_level_domains.csv` ด้วย `OPENROWSET(BULK ..., SINGLE_CLOB)` + `FIRSTROW` pattern ใน [`Scripts/03_OPENROWSET_BULK.sql`](Scripts/03_OPENROWSET_BULK.sql)

### 🚀 SQL Server 2025 & Modern Notes
- **bcp + TDS 8.0 (TLS 1.3)** — SQL Server 2025 รองรับการเชื่อมต่อเข้มงวดแบบ strict encryption; ใช้ได้ทั้ง Windows/Linux และตัวเลือก `-G` สำหรับ Entra auth ตั้งแต่ SQL Server 2022 ([bcp utility](https://learn.microsoft.com/sql/tools/bcp/bcp-utility?view=sql-server-ver17), [bcp + Entra ID](https://learn.microsoft.com/sql/tools/bcp/bcp-authentication?view=sql-server-ver17))
- **bulkadmin บน Linux ใช้ได้จริงแล้ว** — SQL Server 2022 CU24 และ 2025 CU3 เปิดสิทธิ์ `ADMINISTER BULK OPERATIONS` ให้บทบาทที่ไม่ใช่ sysadmin (พร้อม approved paths ใน mssql-conf) ([Bulk import on Linux](https://learn.microsoft.com/sql/linux/sql-server-linux-bulk-operations?view=sql-server-ver17))
- **OPENROWSET(BULK) อ่าน Parquet/Delta ได้ตั้งแต่ 2022** (`FORMAT = 'PARQUET'/'DELTA'`) — ทางเข้า data lake โดยตรงจาก T-SQL; BULK INSERT ยังจำกัด CSV/delimited text
- **Managed identity บน SQL Server 2025** (ผ่าน Arc) ใช้กับ database scoped credential ของ BULK INSERT/OPENROWSET ได้ — ลดการฝัง SAS/secret
- **go-sqlcmd** (sqlcmd รุ่นใหม่แบบ open source ของ Microsoft) จับคู่กับ bcp จาก mssql-tools18 — ทางที่ Microsoft ผลักดันสำหรับ scripting ร่วมสมัย (ดู Module 00)
