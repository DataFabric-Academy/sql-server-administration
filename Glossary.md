# Glossary — คำศัพท์เทคนิค SQL Server Administration

คำศัพท์ที่ใช้บ่อยในคอร์สนี้ พร้อมคำอธิบายสั้น ๆ ภาษาไทย เรียงตามหมวด

---

## 🔐 Security & Authentication

| คำศัพท์ | ความหมาย |
|:--------|:---------|
| **Authentication** | การพิสูจน์ตัวตน — ยืนยันว่า "คุณคือใคร" (Windows Authentication หรือ SQL Server Authentication) |
| **Authorization** | การอนุญาต — กำหนดว่าตัวตนนั้น "ทำอะไรได้" (ผ่าน Permissions/Roles) |
| **Securable** | ทรัพยากรที่กำหนดสิทธิ์ได้ เช่น Server, Database, Schema, Table, Procedure |
| **Principal** | ตัวตนที่ขอเข้าถึง Securable เช่น Login, User, Role |
| **Permission** | สิทธิ์ที่ให้ Principal เข้าถึง Securable ผ่าน `GRANT` / `DENY` / `REVOKE` |
| **Login** | ตัวตนระดับ server ที่ใช้เชื่อมต่อ (หรือระดับ Azure SQL DB ที่ใช้เข้าถึง database) |
| **User** | ตัวตนระดับ database ที่ Login ถูกแมปมา (`CREATE USER ... FOR LOGIN`) |
| **SID** | Security Identifier — รหัสเฉพาะของ principal; SID ไม่ตรงกัน (orphaned user) ทำให้ mapping login↔user พัง |
| **Fixed Server Role** | Role ระดับ server ที่ระบบสร้างมาให้ (sysadmin, serveradmin, ...) — SQL Server 2022 เพิ่มชุด `##MS_*##` แบบ least-privilege |
| **Database Role** | Role ระดับ database (db_owner, db_datareader, หรือ role ที่ผู้ใช้สร้างเอง) |
| **Application Role** | Role ที่แอปพลิเคชันเปิดใช้ด้วยรหัสผ่าน (`sp_setapprole`) เพื่อกำหนดสิทธิ์ให้แอป ไม่ใช่ให้คน |
| **Contained Database User** | User ที่พิสูจน์ตัวตนกับ database โดยตรง ไม่ต้องมี login ระดับ server — ง่ายต่อการย้ายฐานข้อมูล |
| **Impersonation** | การสวมสิทธิ์อีก principal หนึ่ง (`EXECUTE AS LOGIN`) |
| **Delegation** | การส่งต่อสิทธิ์ Windows ไปข้ามเครื่องด้วย Kerberos (double-hop) |
| **Double-Hop** | ปัญหาที่ credential จาก client ไม่ถูกส่งต่อไป server ที่สาม (เช่น linked server) |
| **PBKDF2** | อัลกอริทึม hash รหัสผ่านมาตรฐาน NIST SP 800-63b — SQL Server 2025 ใช้เป็น default สำหรับ password hashes |
| **TDS 8.0 / TLS 1.3** | โปรโตคอลการเชื่อมต่อรุ่นใหม่ที่ enforce การเข้ารหัสตั้งแต่ handshake — รองรับใน SQL Server 2025 (Agent, sqlcmd, bcp, linked servers) |
| **Microsoft Entra ID** | บริการ directory ของ Microsoft (ชื่อเดิม Azure AD) ใช้พิสูจน์ตัวตนเข้า SQL Server ได้ตั้งแต่ SQL Server 2022 |
| **Managed Identity** | Identity ที่ Azure จัดการให้ (ไม่ต้องเก็บ secret) — SQL Server 2025 ใช้ได้ผ่าน Azure Arc |

## 🧪 Encryption & Audit

| คำศัพท์ | ความหมาย |
|:--------|:---------|
| **TDE (Transparent Data Encryption)** | เข้ารหัสไฟล์ฐานข้อมูลทั้งหมด "ขณะพัก" (at rest) — โปร่งใสต่อแอป, กัน copy ไฟล์ .mdf ไปเปิดที่อื่น |
| **Database Master Key (DMK)** | คีย์รากของลำดับการเข้ารหัสระดับ database (`CREATE MASTER KEY`) |
| **Extensible Key Management (EKM)** | ส่งงานจัดเก็บคีย์ไปที่ HSM/Key Vault ภายนอก (SQL Server 2025 รองรับ Managed Identity กับ Azure Key Vault) |
| **Always Encrypted** | เข้ารหัสระดับ column โดย SQL Server ไม่เห็นข้อมูลจริง — ถอดรหัสที่ client เท่านั้น |
| **Secure Enclave** | พื้นที่ memory ปลอดภัยบน server ที่ให้ Always Encrypted ทำงาน (query/comparison) ได้โดยไม่ต้องส่ง plaintext ออก |
| **Dynamic Data Masking (DDM)** | ปกปิดข้อมูล "หน้าตา" ของ user ที่ไม่มีสิทธิ์ (UNMASK) โดยข้อมูลใน disk ยังเป็นของจริง |
| **Ledger** | ตารางแบบ tamper-evident (SQL Server 2022+) — พิสูจน์ได้ว่าใครแก้ข้อมูล ใช้เป็นทางเลือก audit ที่แก้ไม่ได้ |
| **Temporal Table** | ตาราง system-versioned เก็บประวัติแถวเก่าอัตโนมัติ (FROM TO / FOR SYSTEM_TIME) |
| **SQL Server Audit** | กลไก audit ทางการ — Server Audit (ปลายทาง) + Server/Database Audit Specification (สิ่งที่จับ) |
| **Audit Action Group** | กลุ่มเหตุการณ์ audit ระดับ server เช่น `FAILED_LOGIN_GROUP` |
| **Common Criteria Compliance** | โหมดเข้มงวดที่บันทึก failed logins ทุกครั้ง (`common criteria compliance enabled`) |
| **ALTER TRACE** | สิทธิ์ระดับ server ที่ใช้สร้าง SQL Trace — เมื่อ SQL Trace ถูก deprecate ให้ใช้ `VIEW SERVER STATE` + XE แทน |

## 💾 Backup & Recovery

| คำศัพท์ | ความหมาย |
|:--------|:---------|
| **Recovery Model** | โหมดของฐานข้อมูลที่กำหนดพฤติกรรม transaction log และความสามารถ restore: FULL / BULK_LOGGED / SIMPLE |
| **Full Backup** | สำรองข้อมูลทั้งหมด + ลำดับ log ที่จำเป็น — เป็นฐานของ restore chain |
| **Differential Backup** | สำรองเฉพาะ extent ที่เปลี่ยนหลัง full ล่าสุด (ดูจาก Differential Changed Map) |
| **Transaction Log Backup** | สำรอง log ตั้งแต่ LSN สุดท้าย — เปิดใช้ point-in-time recovery (ต้อง FULL recovery model) |
| **Copy-only Backup** | Backup ที่ไม่ทำลาย LSN chain (ไม่ reset differential base, ไม่ truncate log) |
| **LSN (Log Sequence Number)** | ลำดับที่ของทุก record ใน log — ใช้อ้างอิงลำดับ restore |
| **VLF (Virtual Log File)** | หน่วยย่อยภายในไฟล์ transaction log — VLF จำนวนมากทำให้ recovery/restore ช้า |
| **Checkpoint** | จุดที่ SQL Server เขียน dirty pages ลง disk และบันทึกลง log — กำหนดขอบเขต recovery |
| **Backup Media Set** | ชุดสื่อสำรอง (ไฟล์ .bak/.trn หลายไฟล์) — มี header จำลองเป็น families |
| **Backup Set** | หนึ่งการ backup ภายใน media set หนึ่งอาจมีหลาย backup sets |
| **CHECKSUM** | การตรวจความสมบูรณ์ระหว่าง backup (`WITH CHECKSUM`) — ป้องกันสำรองข้อมูลเสียเงียบ ๆ |
| **Tail-Log Backup** | สำรอง log ส่วนท้ายก่อน restore เพื่อกู้คืนข้อมูลถึงวินาทีสุดท้าย (`WITH NO_TRUNCATE`) |
| **STOPAT** | ออปชัน restore log ที่ระบุเวลา (`RESTORE LOG ... WITH STOPAT='...'`) |
| **STOPATMARK** | Restore จนถึง "mark" ที่สร้างด้วย `BEGIN TRAN ... WITH MARK` — ใช้จุดตัดที่แม่นยำกว่าเวลานาฬิกา |
| **ZSTD** | อัลกอริทึมบีบอัดรุ่นใหม่สำหรับ backup — SQL Server 2025 เพิ่ม ZSTD ให้เร็วกว่า MS_XPRESS |
| **Backup to URL** | สำรองตรงไปที่ Azure Blob Storage หรือ S3-compatible object storage (SQL Server 2022+) |
| **Immutable Storage** | Blob storage ที่เขียนแล้วแก้/ลบไม่ได้ตามกำหนดเวลา — SQL Server 2025 รองรับ backup ตรงไปยัง storage ประเภทนี้ |
| **Page Restore** | กู้คืนเฉพาะ page ที่เสีย (`RESTORE DATABASE ... PAGE='...'`) — ต้องมี full/log backups ครบ |
| **Recovery Phases** | สามขั้นของ restore: Copy → Redo (Roll Forward) → Undo (Roll Back) |

## 🤖 Automation & Operations

| คำศัพท์ | ความหมาย |
|:--------|:---------|
| **SQL Server Agent** | บริการ scheduler ของ SQL Server ที่รัน Jobs อัตโนมัติ |
| **Job / Job Step / Schedule** | งานอัตโนมัติ / ขั้นตอนย่อย (T-SQL, CmdExec, SSIS, PowerShell) / กำหนดเวลา |
| **Multiserver Administration** | บริหารหลาย server จากจุดเดียว: Master Server (MSX) กระจาย jobs ไป Target Servers (TSX) |
| **Credential** | ห่อ Windows account ให้ SQL Server เรียกใช้ได้ (ใช้โดย Proxy และ backup to URL) |
| **Proxy Account** | คนกลางที่ map สิทธิ์ sysadmin บางชุดให้ user ใช้รัน job step ข้าม subsystem |
| **SQLAgentUserRole / ReaderRole / OperatorRole** | Fixed database roles ใน msdb ที่คุมสิทธิ์ใช้ Agent โดยไม่ต้องเป็น sysadmin |
| **Database Mail** | ระบบส่งอีเมลจาก SQL Server ผ่าน SMTP (profile + account) |
| **Operator** | ผู้รับ notification (email/pager) เมื่อ job ล้มหรือ alert เกิดขึ้น |
| **Alert** | การตอบสนองอัตโนมัติต่อ error number / severity / performance counter ที่กำหนด |
| **Severity Level** | ระดับความรุนแรงของ error 0–25 (≥19 ต้อง sysadmin กำหนด alert; 20–25 fatal) |
| **Error Log** | ไฟล์บันทึกของ Database Engine (ERRORLOG รวมถึง errorlog.1–.6 แบบหมุนวน) |
| **WMI Alert** | Alert ที่ดักจับ event จาก Windows ผ่าน WQL เช่น "log file เตือน" |

## 📊 Monitoring & Diagnostics

| คำศัพท์ | ความหมาย |
|:--------|:---------|
| **DMV / DMF** | Dynamic Management View/Function — มุมมองสถานะ runtime เช่น `sys.dm_exec_requests` |
| **SMO** | SQL Server Management Objects — ไลบรารี .NET ที่ PowerShell module ใช้จัดการ SQL Server |
| **PowerShell Provider (SQLSERVER:)** | Drive จำลอง SQL Server เป็นไฟร์ซิสเทม เดินด้วย `Set-Location SQLSERVER:\SQL\...` |
| **SqlServer Module** | โมดูล PowerShell ทางการแทน SQLPS เก่า (`Install-Module SqlServer`) |
| **dbatools** | โมดูล PowerShell ของชุมชน (150+ command) สำหรับ migration/automation |
| **Extended Events (XE)** | ระบบจับเหตุการณ์ของ engine — ทางการแทน Profiler/SQL Trace (ซึ่ง deprecated) |
| **XE Session** | นิยามว่าจับ event ใด กรองอย่างไร (predicate) บันทึก field ใด (action) และเขียนที่ไหน (target) |
| **system_health** | Session XE ในตัวที่บันทึก deadlock, error 1641+, latch wait ฯลฯ — ดูท้ายก่อนเสมอ |
| **Event File / Ring Buffer Target** | ปลายทางของ XE session: ไฟล์ .xel หรือ memory buffer |
| **Time-bound Session** | ฟีเจอร์ SQL Server 2025 — XE session หยุดเองตามเวลาที่กำหนด กัน session รั่ว |
| **Activity Monitor** | หน้าจอรายงานใน SSMS ที่อ่าน DMVs — เห็น process/resource/data I/O สด |
| **Performance Monitor (PerfMon)** | เครื่องมือของ Windows — SQL Server มี object counters เช่น `SQLServer:Buffer Manager` |
| **Baseline** | ค่าอ้างอิงพฤติกรรมปกติของระบบ ใช้เทียบเวลาเกิดปัญหา |
| **Query Store** | กล่องดำของ query — เก็บ plan/perf ต่อ query, Query Store บน secondary เปิด default ใน SQL Server 2025 |
| **Optimized Locking** | ฟีเจอร์ SQL Server 2025 — ลด blocking/lock memory ด้วย Lock after Qualification (LAQ) |

## 📦 Data Movement

| คำศัพท์ | ความหมาย |
|:--------|:---------|
| **bcp** | Bulk copy utility แบบ command-line (`bcp ... in/out`) |
| **BULK INSERT** | T-SQL คำสั่งนำเข้าไฟล์ข้อความเข้าตารางโดยตรง (เร็วกว่า bcp in บางสถานการณ์) |
| **OPENROWSET(BULK...)** | อ่านไฟล์เป็น table ผ่าน provider (รองรับ S3/Azure path ตั้งแต่ SQL Server 2022+) |
| **SSIS (SQL Server Integration Services)** | เครื่องมือ ETL ของ Microsoft — package (.dtsx) เคลื่อนข้อมูลข้ามแหล่ง |
| **Import/Export Wizard** | ตัวช่วย copy ข้อมูลง่าย ๆ ใน SSMS (สร้าง SSIS package ให้อัตโนมัติ) |
| **DACPAC / Data-Tier Application (DAC)** | ไฟล์ schema ฐานข้อมูล (และข้อมูลบางส่วน) ที่ deploy/upgrade ได้เป็นเวอร์ชัน |
| **SqlPackage** | CLI ที่ใช้ import/export/deploy ไฟล์ dacpac |
| **Partition Switching** | สลับ partition ทั้งก้อนเข้า-ออกตารางแบบ metadata-only — โหลดข้อมูลใหญ่แบบทันที |
| **Minimal Logging** | โหมดเขียน log น้อยมากขณะ bulk load (ต้อง SIMPLE/BULK_LOGGED + TABLOCK) — เร็วขึ้นเยอะแต่กระทบ log backup |
| **Linked Server** | ตัวเชื่อมไปยัง server/แหล่งข้อมูลอื่น ใช้ query แบบ 4-part name |

---

> คำศัพท์เพิ่มเติมเจาะลึกมีในแต่ละโมดูล — ถ้าพบคำที่ไม่รู้จักระหว่างเรียน ค้นหาได้จาก [Microsoft Learn Glossary](https://learn.microsoft.com/sql/sql-server/glossary?view=sql-server-ver17)
