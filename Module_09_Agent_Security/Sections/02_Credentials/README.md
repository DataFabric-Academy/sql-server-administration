# Section 2 — Credentials: ห่อ Windows Account ไว้ใช้จาก SQL Server

หลายงานของ SQL Server ต้องพิสูจน์ตัวตน **ออกไปข้างนอก** — backup ไปที่ blob storage, เขียนไฟล์เครือข่ายด้วย account พิเศษ, หรือรัน job step ในบริบท Windows account ใด account หนึ่ง SQL Server ไม่สามารถ "ยืมรหัสผ่านของใคร" ได้เอง จึงมี object ชื่อ **Credential** ระดับ server ทำหน้าที่ห่อชื่อ account (Windows account หรือ S3 access key) กับ secret ไว้ให้ระบบภายในเรียกใช้

Section นี้สอนสร้าง/จัดการ credential และชี้ชัดว่ามันถูกใช้ที่ไหนบ้าง — โดยเฉพาะสองจุดที่จะเจอบ่อย: เป็นฐานของ **Proxy** (Section 3) และเป็นตัวพิสูจน์ตัวตนของ **backup to URL/S3** (ย้อนกลับไปดูตัวอย่างใน [Module 6](../../../Module_06_Backing_Up_Databases/README.md))

## 2.1 Credential คืออะไร ทำงานอยู่ชั้นไหน

```mermaid
flowchart LR
    subgraph SQLServer["SQL Server (ระดับ server)"]
        C[Credential<br/>name = FileOperation<br/>IDENTITY = MACHINE\\FileOps<br/>SECRET = ********]
        P[Proxy FileOp<br/>อ้าง credential]
    end
    C -- "ใช้โดยตรง: BACKUP TO URL (S3/Azure)" --> EXT[ภายนอก: OS/Storage]
    C -- "อ้างโดย proxy เท่านั้น" --> P
    P -- "job step CMDEXEC<br/>รันในบริบท FileOps" --> EXT2[OS command]
```

- **Credential** อยู่ระดับ server เก็บใน `master` (catalog: `sys.credentials`) — ประกอบด้วย **IDENTITY** (ชื่อ account/key ที่จะใช้พิสูจน์ตัวตน) และ **SECRET** (รหัสผ่าน/secret — เข้ารหัสเก็บด้วย Service Master Key)
- Credential **เองไม่ใช้ได้โดย user ทั่วไป** — ผู้ใช้มันคือระบบภายใน (Agent proxy, BACKUP TO URL, EXECUTE AS บน assemblies ฯลฯ) — จึงเป็นวิธีให้ระบบ "มีตัวตนเพิ่ม" โดยไม่ต้องเก็บรหัสผ่านใน T-SQL script
- เรียกมาแล้วใน Module 1: สิทธิ์ `ALTER ANY CREDENTIAL` เป็นของ sysadmin; สร้าง/ลบ credential ต้องเป็น sysadmin (หรือได้สิทธิ์เฉพาะ)

## 2.2 สร้าง Credential — CREATE CREDENTIAL

สคริปต์เดโมฉบับเต็ม: [Scripts/01_Create_Credential.sql](Scripts/01_Create_Credential.sql)

```sql
USE master;
GO
-- หากเคยสร้างไว้ ให้ลบก่อน (idempotent)
IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'FileOperation')
    DROP CREDENTIAL FileOperation;

CREATE CREDENTIAL FileOperation
    WITH IDENTITY = N'MACHINE\FileOps',      -- Windows account ที่จะ "สวม"
         SECRET   = N'Pa$$w0rd2025';         -- รหัสผ่านของ account นั้น
GO

SELECT name, credential_id, identity_desc  -- identity_desc แสดง IDENTITY
FROM sys.credentials
WHERE name = N'FileOperation';
```

จุดที่ต้องเข้าใจถูก:

| พารามิเตอร์ | ความหมาย | ข้อควรระวัง |
|:------------|:---------|:------------|
| `IDENTITY` | ชื่อ account ที่จะใช้ — Windows ใส่รูปแบบ `DOMAIN\user` หรือ `MACHINE\user` (local account — **ไม่ต้องมี domain** สำหรับแล็บ); บางกรณีเป็นคำพิเศษเช่น `S3 Access Key` | account นี้ต้องมีอยู่จริงใน OS และมีสิทธิ์พอกับงานที่จะทำ (เช่นเขียนโฟลเดอร์ที่ job แตะ) |
| `SECRET` | รหัสผ่านของ account หรือ secret ของ access key | ถูกเข้ารหัสเก็บ (ด้วย Service Master Key ของ instance); ห้ามใส่ secret จริงของ production ในสคริปต์ที่ commit |
| ชื่อ credential | ชื่อตรรกะที่ proxy/BACKUP อ้าง | ตั้งตามจุดประสงค์ (FileOperation, S3Backup ฯลฯ) |

> **บน Linux/container**: ไม่มี Windows account ให้ห่อ — ใช้ credential กับงานที่ไม่ต้องพึ่ง OS ได้ เช่น backup to S3 (`IDENTITY = N'S3 Access Key'`) ส่วน proxy-based CmdExec ต้อง Windows เท่านั้น (หมายเหตุเพิ่มใน Section 3)

## 2.3 จัดการ Credential — ALTER / DROP / ตรวจสอบ

```sql
-- เปลี่ยนรหัสผ่าน (เมื่อ account ถูกหมุนรหัสผ่าน — ต้องทำตาม ไม่งั้นงานที่ใช้พังทันที)
ALTER CREDENTIAL FileOperation
    WITH IDENTITY = N'MACHINE\FileOps',
         SECRET   = N'Pa$$w0rd';      -- รหัสผ่านใหม่หลังหมุน

-- เปลี่ยนเฉพาะชื่อ account:
ALTER CREDENTIAL FileOperation
    WITH IDENTITY = N'MACHINE\FileOps_v2',
         SECRET   = N'Pa$$w0rd2025';

-- ลบเมื่อไม่ใช้ — แต่ระวัง: proxy ที่อ้าง credential นี้จะพัง (Agent จะลบ proxy ให้อัตโนมัติ?)
-- ตามหลัก: ลบ proxy ก่อน (Section 3) แล้วจึงลบ credential
DROP CREDENTIAL FileOperation;

-- ตรวจว่า credential ไหนถูก proxy อ้างอยู่ (มีจริงเมื่อทำ Section 3):
SELECT c.name AS credential_name, c.identity_desc,
       p.name AS proxy_name, p.enabled
FROM sys.credentials AS c
LEFT JOIN msdb.dbo.sysproxies AS p ON p.credential_id = c.credential_id;
```

**Expected:** ตรงนี้เห็นความสัมพันธ์ credential ↔ proxy 1:1 ของแต่ละคู่ — เป็น query ที่ดีให้รันก่อนจะ DROP credential อะไรก็ตาม

## 2.4 Credential ใช้ที่ไหน — สามจุดที่เจอจริง

### จุดที่ 1: เป็นฐานของ Proxy (เจาะลึกใน Section 3)

Agent job steps ชนิด CmdExec/PowerShell/SSIS ที่เจ้าขอนไม่ใช่ sysadmin ต้องรันผ่าน proxy — proxy จะอ้าง credential เพื่อหา Windows account ให้สวม โครงงานแล็บของโมดูลนี้คือ: credential `FileOperation` → proxy `FileOp` → job step copy ไฟล์รันด้วย account `MACHINE\FileOps`

### จุดที่ 2: Backup to URL — S3-compatible storage (cross-ref Module 6)

Backup ไป S3 ใช้ **server-level credential** อย่างตรงไปตรงมา — IDENTITY เป็นคำพิเศษ `S3 Access Key` และ SECRET เป็น `accessKey:secretKey`:

```sql
USE master;
GO
CREATE CREDENTIAL [s3://s3.amazonaws.com:443/backups-fabrikam]
    WITH IDENTITY  = N'S3 Access Key',
         SECRET    = N'AKIAIOSFODNN7EXAMPLE:wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
-- (ค่าในตัวอย่างเป็น key ตัวอย่างทางการของ AWS — ห้ามใช้ของจริงใน script)
```

รูปแบบชื่อ credential ต้องตรงกับ URL ที่ใช้ใน `BACKUP ... TO URL = 's3://...'` แบบเป๊ะ (protocol + endpoint + bucket) — ลึกและครบที่ [Module 6](../../../Module_06_Backing_Up_Databases/README.md) ในหัวข้อ backup to S3

### จุดที่ 3: Backup to Azure Blob — credential แบบ Shared Access Signature

กับ Azure Blob Storage (ต่างจาก S3) ตัวพิสูจน์ตัวตนมาตรฐานคือ **Shared Access Signature (SAS)** — IDENTITY เป็นคำพิเศษ `SHARED ACCESS SIGNATURE` และ SECRET เป็น SAS token ที่ขึ้นต้นด้วย `?sv=...`:

```sql
CREATE CREDENTIAL [https://fabrikambackups.blob.core.windows.net/backups]
    WITH IDENTITY = N'SHARED ACCESS SIGNATURE',
         SECRET   = N'?sv=2024-01-01&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2027-01-01T00:00:00Z&st=2026-01-01T00:00:00Z&spr=https&sig=EXAMPLE';
-- (ค่าในตัวอย่างเป็นรูปแบบเท่านั้น — SAS จริงได้จาก Azure Portal ของ storage account)
```

จุดที่คนพลาดบ่อยกับ credential แบบนี้: SAS token ต้องประกาศ **สิทธิ์ service container ทั้งชุดที่ backup ต้องใช้** (`rwdlacup` — read/write/delete/list/create/add/update/path ตามเอกสาร) และชื่อ credential ต้องเป็น URL ของ container **พอดี** (ไม่รวมชื่อไฟล์ .bak) ผิดที่ใดที่หนึ่งจะเจอ error "operating system error 50" ตอน BACKUP ซึ่งหาสาเหตุยากถ้าไม่รู้ว่ามันมาจาก credential

### จุดที่ 4: Managed Identity — ทางเลือกที่ไม่มี secret (SQL Server 2025)

เมื่อ SQL Server onboard ผ่าน **Azure Arc** (SQL Server 2025) การเชื่อมต่อขาออกไป Azure resources ใช้ **managed identity** — identity ที่ Azure จัดการรหัสผ่านให้ ไม่ต้องสร้าง credential ที่ฝัง secret เลย ลดงาน "หมุนรหัสผ่าน" ทิ้งได้ ฟีเจอร์นี้ครอบคลุมทั้ง backup to URL (Blob) และ outbound connections อื่น ๆ (ดูกล่อง 2025 ด้านล่าง)

## 2.5 เทียบสาม object — Credential, Proxy และ Login คนละเลเยอร์กัน

เพราะชื่อพวกนี้คลุมเครือเมื่ออ่านเร็ว สรุปแยกให้ชัด:

| Object | อยู่ที่ไหน | ห่ออะไร | ใครใช้ | ตัวอย่างในโมดูลนี้ |
|:-------|:-----------|:--------|:-------|:-------------------|
| **Credential** | `master` (server scope) | Windows account หรือ key/secret | ระบบภายใน: proxy, BACKUP TO URL | `FileOperation` |
| **Proxy** | `msdb` (Agent scope) | ชี้ไปที่ credential + จำกัดด้วย subsystem | Job steps นอก T-SQL ของเจ้าขอนที่ไม่ใช่ sysadmin | `FileOp` (Section 3) |
| **SQL login ที่มี Agent role** | `master` + user ใน `msdb` | ตัวตนคนสร้าง/รัน job | คน (ไม่ใช่ระบบ) | `Lab09JobUser` |

จำไว้ว่า credential **ไม่ใช่ login** — มันไม่ให้ใคร "เข้าถึง SQL Server" เลย ให้ "SQL Server ออกไปข้างนอก" ในฐานะใครคนหนึ่งเท่านั้น

## 2.6 ข้อควรปฏิบัติเกี่ยวกับ Credential ในงานจริง

1. **หนึ่ง credential ต่อจุดประสงค์** — อย่าแชร์ credential งาน backup กับงาน file copy พอกันทำหมด ให้จำกัด scope ต่องานจะควบคุมง่ายกว่า
2. **Account ขั้นต่ำ** — Windows account ที่ห่อควรมีสิทธิ์เฉพาะโฟลเดอร์/งานที่จำเป็น (เขียนได้เฉพาะ `D:\Backups\`) ไม่ใช่ account ใหญ่ที่แตะทุกอย่าง
3. **หมุนรหัสผ่าน = แก้ credential ทันที** — ใส่งานนี้ไว้ใน runbook หมุนรหัสผ่าน ไม่งั้น job จะเริ่มพังแบบ error "Access is denied" ที่หายากเมื่อมองแค่ job history
4. **อย่า commit SECRET จริง** — สคริปต์ใน source control ให้ใช้ placeholder + ตั้งค่าจริงด้วย deployment pipeline หรือ SSMS เท่านั้น

## 2.7 Troubleshoot ที่พบบ่อยของ Credential

อาการที่หลายทีมเจอและจุดแรกที่ควรมอง (ก่อนเดาว่า network มีปัญหา):

| อาการ | ต้นเหตุที่พบบ่อย | ตรวจอย่างไร |
|:------|:------------------|:-------------|
| Job step นอก T-SQL ล้มตอนรัน (สร้างได้) | credential หมายถึง account ที่ไม่มีอยู่/รหัสผ่านถูกหมุน | `sys.credentials` + `ALTER CREDENTIAL` ให้ตรง |
| BACKUP TO URL error "operating system error 50" | ชื่อ credential ไม่ตรง URL หรือ SAS ผิดรูป/ขาดสิทธิ์ | เทียบชื่อ credential กับ URL แบบตัวอักษร, อ่าน SAS ใหม่ |
| Backup ขึ้น "Backup to URL received an exception from remote" | สิทธิ์ของ storage/key ไม่พอ (เช่น SAS หมดอายุ) | ต่ออายุ SAS (`ALTER CREDENTIAL` ด้วย token ใหม่) |
| เมลแจ้ง "Access is denied" จาก OS | Windows account ใน credential ไม่มีสิทธิ์ NTFS โฟลเดอร์ที่ job เขียน | จัดสิทธิ์โฟลเดอร์ให้ account นั้นเท่าที่จำเป็น |
| ลบ credential แล้ว job บางตัวพังแบบเงียบ ๆ | proxy ที่อ้าง credential นั้นพังตอน execute | query `sys.credentials × msdb.dbo.sysproxies` (ข้อ 4 ในสคริปต์เดโม) ก่อนลบเสมอ |

รูปแบบการ audit ที่แนะนำ: เก็บ query คู่ `sys.credentials`/`sysproxies` ไว้ใน job ตรวจสอบรายสัปดาห์ — เห็น credential ที่ "ไม่มีใครอ้าง" (ขยะที่ควรลบ) และ credential ที่มี secret ตั้งแต่ก่อนปีที่แล้ว (candidate สำหรับหมุนรหัสผ่าน) ได้พร้อมกัน

### 🚀 SQL Server 2025 & Modern Notes

- **Managed identity ผ่าน Azure Arc (SQL Server 2025)** — outbound connection ไป Azure ทำได้โดยไม่ต้องมี credential ที่ฝังรหัสผ่าน; inbound ก็รับด้วย identity เดียวกันได้ — ทางเลือกอันดับแรกเมื่อสภาพแวดล้อมอยู่บน Arc ([What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17))
- **PBKDF2 (2025)** — รหัสผ่าน SQL logins/application roles hash ด้วย PBKDF2+SHA512 default ทั้งกระบวนการพิสูจน์ตัวตนของ account ที่ใช้ใน automation ปลอดภัยขึ้นโดยอัตโนมัติ; สำหรับ application role เดิมที่ตั้งรหัสผ่านก่อน 2025 ควร ALTER ใหม่ให้ได้ hash รุ่นใหม่
- **TDS 8.0 / TLS 1.3 (2025)** — งานที่ credential สนับสนุน (เช่น Agent เชื่อม engine, backup ข้ามเครือข่าย) รองรับการเข้ารหัสรุ่นใหม่แบบ strict
- **Credential ต่อ S3 มีมาตั้งแต่ SQL Server 2022** — ยังใช้งานแบบเดิมทุกอย่างบน 2025; บีบอัด ZSTD ใหม่ของ 2025 ทำงานร่วมกับ backup to S3 ได้ตามปกติ

> อ้างอิง: [CREATE CREDENTIAL](https://learn.microsoft.com/sql/t-sql/statements/create-credential-transact-sql?view=sql-server-ver17), [ALTER CREDENTIAL](https://learn.microsoft.com/sql/t-sql/statements/alter-credential-transact-sql?view=sql-server-ver17), [DROP CREDENTIAL](https://learn.microsoft.com/sql/t-sql/statements/drop-credential-transact-sql?view=sql-server-ver17), [sys.credentials](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-credentials-transact-sql?view=sql-server-ver17), [SQL Server backup to URL (S3)](https://learn.microsoft.com/sql/relational-databases/backup-restore/sql-server-backup-to-url?view=sql-server-ver17)
