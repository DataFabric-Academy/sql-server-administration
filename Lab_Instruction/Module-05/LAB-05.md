# Module 5: Recovery Models and Backup Strategies
## Lab: Planning a Backup Strategy

### Exercise 1: Investigating Recovery Models

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab05\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** และรอให้สคริปต์ทำงานเสร็จ
   (สคริปต์จะสร้างฐานข้อมูลว่าง 2 ฐานข้อมูล ได้แก่ **MarketDev** และ **Research**)

#### Task 2: Review the Current Recovery Models
1. เริ่ม SQL Server Management Studio และเชื่อมต่อกับ database engine `DATAFABRIC-SQL-x`
   โดยใช้ **Windows authentication**
2. คลิก **New Query** แล้วรันคำสั่งต่อไปนี้เพื่อดู recovery model ปัจจุบัน:

   ```sql
   SELECT name, recovery_model_desc
   FROM sys.databases
   WHERE name IN (N'MarketDev', N'Research');
   ```

3. สังเกตว่าทั้งสองฐานข้อมูลถูกสร้างด้วย recovery model **SIMPLE**

#### Task 3: Observe Log Truncation in the SIMPLE Recovery Model
1. สร้างตารางและใส่ข้อมูลจำลองใน **MarketDev** เพื่อให้ transaction log มีการใช้งาน:

   ```sql
   USE MarketDev;
   GO
   CREATE TABLE dbo.MarketingSessions (
       SessionID     INT IDENTITY PRIMARY KEY,
       CampaignName  NVARCHAR(100),
       SessionData   NVARCHAR(4000),
       LoggedAt      DATETIME2 DEFAULT SYSDATETIME()
   );
   GO
   INSERT INTO dbo.MarketingSessions (CampaignName, SessionData)
   SELECT TOP 20000 c.name, REPLICATE(N'x', 2000)
   FROM sys.all_columns AS c CROSS JOIN sys.objects AS o;
   GO 5
   ```

2. ตรวจสอบการใช้งาน transaction log ด้วยคำสั่งต่อไปนี้:

   ```sql
   DBCC SQLPERF(LOGSPACE);
   GO
   ```

3. จดค่า **Log Size Used (%)** ของ MarketDev แล้วบังคับ checkpoint ด้วยคำสั่ง:

   ```sql
   USE MarketDev;
   CHECKPOINT;
   GO
   DBCC SQLPERF(LOGSPACE);
   GO
   ```

4. สังเกตว่าหลัง checkpoint พื้นที่ log ที่ใช้ลดลงเหลือใกล้ 0% — ใน SIMPLE recovery model
   log ถูก truncate โดยอัตโนมัติหลังการ checkpoint

#### Task 4: Switch to the FULL Recovery Model and Compare
1. เปลี่ยน **Research** เป็น FULL recovery model และสร้างตารางเดียวกัน:

   ```sql
   USE master;
   GO
   ALTER DATABASE Research SET RECOVERY FULL;
   GO
   USE Research;
   GO
   CREATE TABLE dbo.ExperimentLog (
       ExperimentID  INT IDENTITY PRIMARY KEY,
       Scientist     NVARCHAR(100),
       ResultData    NVARCHAR(4000),
       RecordedAt    DATETIME2 DEFAULT SYSDATETIME()
   );
   GO
   INSERT INTO dbo.ExperimentLog (Scientist, ResultData)
   SELECT TOP 20000 c.name, REPLICATE(N'y', 2000)
   FROM sys.all_columns AS c CROSS JOIN sys.objects AS o;
   GO 5
   ```

2. รัน `DBCC SQLPERF(LOGSPACE);` อีกครั้ง แล้วบันทึก **Log Size Used (%)** ของ Research
3. รัน `CHECKPOINT;` ใน Research แล้วตรวจ `DBCC SQLPERF(LOGSPACE);` อีกครั้ง —
   สังเกตว่าพื้นที่ log **ยังถูกใช้อยู่เท่าเดิม** เพราะ FULL recovery model จะ truncate log
   เฉพาะเมื่อมีการสำรอง log เท่านั้น (หมายเหตุ: หลังเปลี่ยนเป็น FULL จนกว่าจะทำ full backup
   ครั้งแรก ฐานข้อมูลยังทำงานตาม effective recovery model แบบ SIMPLE)
4. สำรอง transaction log แล้วตรวจซ้ำ:

   ```sql
   BACKUP LOG Research TO DISK = N'D:\Labfiles\Lab05\Starter\Backups\Research.trn';
   GO
   DBCC SQLPERF(LOGSPACE);
   GO
   ```

5. สังเกตว่า **Log Size Used (%)** ของ Research ลดลงหลัง `BACKUP LOG`

**Results:** หลังจาก exercise นี้ คุณควรได้เห็นความแตกต่างของกลไก log truncation ระหว่าง
SIMPLE (checkpoint อัตโนมัติ) และ FULL (ต้อง BACKUP LOG) ซึ่งเป็นฐาของการวาง backup strategy

---

### Exercise 2: Implementing a Backup Strategy

#### Task 1: Create a Backup Folder
1. ในหน้าต่าง query รันคำสั่งต่อไปนี้เพื่อสร้างโฟลเดอร์เก็บ backup ของแล็บนี้:

   ```sql
   USE master;
   GO
   EXEC sys.xp_create_subdir N'D:\Labfiles\Lab05\Starter\Backups';
   GO
   ```

#### Task 2: Back Up a Database in the SIMPLE Recovery Model
1. ทำ full backup ของ **MarketDev**:

   ```sql
   BACKUP DATABASE MarketDev
   TO DISK = N'D:\Labfiles\Lab05\Starter\Backups\MarketDev.bak'
   WITH FORMAT, INIT, NAME = N'MarketDev-Full Database Backup', COMPRESSION;
   GO
   ```

2. แก้ไขข้อมูลเพิ่มเติมเพื่อให้เกิดการเปลี่ยนแปลงหลัง full backup:

   ```sql
   USE MarketDev;
   GO
   INSERT INTO dbo.MarketingSessions (CampaignName, SessionData)
   VALUES (N'Spring Campaign', REPLICATE(N'z', 2000));
   GO 20
   ```

3. ทำ differential backup:

   ```sql
   BACKUP DATABASE MarketDev
   TO DISK = N'D:\Labfiles\Lab05\Starter\Backups\MarketDev.bak'
   WITH DIFFERENTIAL, NAME = N'MarketDev-Differential Database Backup', COMPRESSION;
   GO
   ```

4. ลองสำรอง log ของ MarketDev:

   ```sql
   BACKUP LOG MarketDev
   TO DISK = N'D:\Labfiles\Lab05\Starter\Backups\MarketDev.trn';
   GO
   ```

5. สังเกตข้อผิดพลาด — ใน SIMPLE recovery model ไม่สามารถสำรอง transaction log ได้
   ดังนั้นจึงกู้คืนได้เฉพาะจุดที่ทำ full/differential backup เท่านั้น

#### Task 3: Back Up a Database in the FULL Recovery Model
1. ทำ full backup ของ **Research**:

   ```sql
   BACKUP DATABASE Research
   TO DISK = N'D:\Labfiles\Lab05\Starter\Backups\Research.bak'
   WITH FORMAT, INIT, NAME = N'Research-Full Database Backup', COMPRESSION;
   GO
   ```

2. แก้ไขข้อมูลและทำ differential backup และ log backup ตามลำดับ:

   ```sql
   USE Research;
   GO
   INSERT INTO dbo.ExperimentLog (Scientist, ResultData)
   VALUES (N'Lab A', REPLICATE(N'w', 2000));
   GO 20
   ```

   ```sql
   BACKUP DATABASE Research
   TO DISK = N'D:\Labfiles\Lab05\Starter\Backups\Research.bak'
   WITH DIFFERENTIAL, NAME = N'Research-Differential Database Backup', COMPRESSION;
   GO
   BACKUP LOG Research
   TO DISK = N'D:\Labfiles\Lab05\Starter\Backups\Research.trn';
   GO
   ```

3. สังเกตว่า log backup ของ FULL recovery model ทำได้สำเร็จ — เป็นเงื่อนไขที่ทำให้
   point-in-time recovery เป็นไปได้ (จะได้ฝึกจริงใน Module 7)

#### Task 4: Review the Backup History
1. ตรวจสอบประวัติ backup ทั้งหมดจาก msdb:

   ```sql
   SELECT database_name, type,
          CASE type WHEN 'D' THEN N'Database (Full/Diff)'
                    WHEN 'I' THEN N'Differential'
                    WHEN 'L' THEN N'Log' END AS backup_type,
          backup_start_date, backup_finish_date, compressed_backup_size
   FROM msdb.dbo.backupset
   WHERE database_name IN (N'MarketDev', N'Research')
   ORDER BY backup_start_date;
   GO
   ```

2. ตรวจสอบ backup sets ที่บันทึกในไฟล์ .bak:

   ```sql
   RESTORE HEADERONLY
   FROM DISK = N'D:\Labfiles\Lab05\Starter\Backups\Research.bak';
   GO
   ```

**Results:** หลังจาก exercise นี้ คุณควรมี backup ครบตาม recovery model — MarketDev (SIMPLE):
full + differential; Research (FULL): full + differential + log และสามารถอ่านประวัติ backup
จาก msdb และ RESTORE HEADERONLY ได้

---

### Exercise 3: Evaluating the BULK_LOGGED Recovery Model

#### Task 1: Observe Minimal Logging
1. เปลี่ยน Research เป็น BULK_LOGGED และวัดขนาด log ก่อน/หลังการโหลดข้อมูลจำนวนมาก:

   ```sql
   USE master;
   GO
   ALTER DATABASE Research SET RECOVERY BULK_LOGGED;
   GO
   USE Research;
   GO
   SELECT total_log_size_in_bytes/1024/1024 AS total_mb,
          used_log_space_in_bytes/1024/1024 AS used_mb
   FROM sys.dm_db_log_space_usage;
   GO
   SELECT TOP 50000 c.name, REPLICATE(N'b', 2000)
   INTO dbo.BulkTest
   FROM sys.all_columns AS c CROSS JOIN sys.objects AS o;
   GO
   SELECT total_log_size_in_bytes/1024/1024 AS total_mb,
          used_log_space_in_bytes/1024/1024 AS used_mb
   FROM sys.dm_db_log_space_usage;
   GO
   ```

2. สังเกตว่า log ที่ถูกใช้เพิ่มขึ้นน้อยกว่าที่ควรจะเป็น เมื่อเทียบกับปริมาณข้อมูลที่โหลด —
   นี่คือผลของ **minimal logging** สำหรับ bulk operations (เช่น SELECT INTO, BULK INSERT)
   ใน BULK_LOGGED recovery model

#### Task 2: Return to FULL and Summarize the Trade-offs
1. ลบตารางทดสอบและคืนค่า recovery model:

   ```sql
   USE Research;
   GO
   DROP TABLE dbo.BulkTest;
   GO
   USE master;
   GO
   ALTER DATABASE Research SET RECOVERY FULL;
   GO
   ```

2. สรุปข้อจำกัด: ใน BULK_LOGGED ช่วงเวลาที่มี bulk operation จะกู้คืนแบบ point-in-time
   ข้ามช่วงนั้นไม่ได้ และ log backup จะใหญ่ขึ้นมากหากมี bulk operation ระหว่างช่วง
   ดังนั้นจึงนิยมใช้ชั่วคราวใน "หน้าต่างโหลดข้อมูล" แล้วสลับกลับเป็น FULL

**Results:** หลังจาก exercise นี้ คุณควรสามารถอธิบายได้ว่าเมื่อใดควรเลือกใช้ SIMPLE,
FULL หรือ BULK_LOGGED รวมถึงผลกระทบต่อขนาด log และตัวเลือกการกู้คืนของแต่ละแบบ
