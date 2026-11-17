# Module 7: Restoring SQL Server Databases
## Lab: Performing Database Restores

> **แล็บนี้จงใจทำลายไฟล์ฐานข้อมูล** — Setup.cmd ของแล็บนี้จะ restore ฐานข้อมูล
> HumanResources และ InternetSales สร้าง backup จำลองไว้ใน `D:\Labfiles\Lab07\Backups`
> แล้ว **ลบไฟล์ข้อมูลของ HumanResources และทำให้ไฟล์ข้อมูลของ InternetSales เสียหาย**
> เพื่อจำลองเหตุการณ์ disk failure จริง ให้คุณได้ฝึกกู้คืน

### Exercise 1: Restoring a Database with a Missing Data File

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab07\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** และรอให้สคริปต์ทำงานเสร็จ
   (สังเกตข้อความ "Sabotaging databases..." ในหน้าต่าง command prompt — นั่นคือขั้นตอน
   จำลองเหตุขัดข้อง หากคุณเปิด SSMS ค้างไว้ให้ปิดก่อนรัน Setup.cmd)

#### Task 2: Diagnose the Damaged Databases
1. เริ่ม SQL Server Management Studio และเชื่อมต่อกับ database engine `DATAFABRIC-SQL-x`
   โดยใช้ **Windows authentication**
2. คลิก **New Query** แล้วตรวจสอบสถานะของฐานข้อมูล:

   ```sql
   SELECT name, state_desc
   FROM sys.databases
   WHERE name IN (N'HumanResources', N'InternetSales');
   GO
   ```

3. สังเกตว่าทั้งสองฐานข้อมูลอยู่ในสถานะ **RECOVERY_PENDING** —
   HumanResources เพราะไฟล์ข้อมูล (.mdf) ถูกลบไป และ InternetSales เพราะไฟล์ข้อมูล
   ถูกเขียนทับด้วยไฟล์เสีย
4. ตรวจสอบ backup ที่ Setup จัดเตรียมไว้:

   ```sql
   RESTORE HEADERONLY
   FROM DISK = N'D:\Labfiles\Lab07\Backups\HumanResources.bak';
   GO
   ```

5. สังเกตว่าไฟล์มี 2 backup sets (Position 1 และ 2 คือ full backup สองรอบ โดยรอบที่ 2
   มีการแก้ไขข้อมูลเพิ่ม) — เราจะกู้คืนถึงรอบล่าสุด

#### Task 3: Restore the HumanResources Database
1. เนื่องจากไฟล์ข้อมูลหายไป ให้ restore ทับฐานข้อมูลเดิมจาก backup set ล่าสุด (FILE = 2):

   ```sql
   USE master;
   GO
   RESTORE DATABASE HumanResources
   FROM DISK = N'D:\Labfiles\Lab07\Backups\HumanResources.bak'
   WITH FILE = 2, REPLACE, RECOVERY;
   GO
   ```

   > **หมายเหตุ**: ไม่ต้องระบุ MOVE เพราะ backup บันทึกตำแหน่งไฟล์เดิมไว้ และไฟล์เหล่านั้น
   > (รวมถึงไฟล์ที่ถูกลบ) จะถูกสร้างขึ้นใหม่ในตำแหน่งเดิมคือ
   > `D:\Labfiles\Lab07\Starter\SetupFiles`

2. ตรวจสอบผลการกู้คืน:

   ```sql
   SELECT name, state_desc FROM sys.databases
   WHERE name = N'HumanResources';
   GO
   USE HumanResources;
   GO
   SELECT BusinessEntityID, PhoneNumber
   FROM dbo.Employee
   WHERE BusinessEntityID = 259;
   GO
   ```

3. สังเกตว่า PhoneNumber เป็น `151-555-1234` — คือค่าที่ถูกแก้ไขในรอบ backup ที่ 2
   ยืนยันว่าเรากู้คืนมาถึงจุดล่าสุดของข้อมูลแล้ว

**Results:** หลังจาก exercise นี้ HumanResources ควรกลับมา ONLINE พร้อมข้อมูลล่าสุด
จาก backup set ที่ 2 และคุณได้ฝึกวินิจฉัยสถานะ RECOVERY_PENDING จากไฟล์ข้อมูลที่หาย

---

### Exercise 2: Performing a Restore with a Tail-Log Backup

#### Task 1: Investigate the InternetSales Backup Chain
1. ตรวจสอบ backup sets ในไฟล์ backup ของ InternetSales:

   ```sql
   RESTORE HEADERONLY
   FROM DISK = N'D:\Labfiles\Lab07\Backups\InternetSales.bak';
   GO
   ```

2. สังเกตว่าไฟล์ประกอบด้วย 2 backup sets: **Position 1 = full backup** (BackupType 1)
   และ **Position 2 = transaction log backup** (BackupType 2) ซึ่งถูกบันทึกหลังการปรับ
   ListPrice ของสินค้า — เราจะใช้ทั้งสองชุดในการกู้คืน พร้อม tail-log ที่จะสำรองเพิ่มใน Task ถัดไป
3. ตรวจสอบว่า InternetSales ถูกตั้ง recovery model อะไร:

   ```sql
   SELECT name, recovery_model_desc FROM sys.databases
   WHERE name = N'InternetSales';
   GO
   ```

#### Task 2: Back Up the Tail of the Log
1. แม้ไฟล์ข้อมูลจะเสียหาย (RECOVERY_PENDING) เรายังสามารถสำรอง log ท้ายสุด
   (tail-log) ได้ด้วย WITH NO_TRUNCATE เพื่อไม่ให้ธุรกรรมหลัง log backup ล่าสุดสูญหาย:

   ```sql
   USE master;
   GO
   BACKUP LOG InternetSales
   TO DISK = N'D:\Labfiles\Lab07\Backups\IS-TailLog.bak'
   WITH NO_TRUNCATE;
   GO
   ```

#### Task 3: Restore the InternetSales Database
1. Restore ตามลำดับ — full backup (NORECOVERY), ตามด้วย log backup ในไฟล์เดิม
   (NORECOVERY), และจบด้วย tail-log (RECOVERY):

   ```sql
   RESTORE DATABASE InternetSales
   FROM DISK = N'D:\Labfiles\Lab07\Backups\InternetSales.bak'
   WITH FILE = 1, NORECOVERY, REPLACE;
   GO
   RESTORE LOG InternetSales
   FROM DISK = N'D:\Labfiles\Lab07\Backups\InternetSales.bak'
   WITH FILE = 2, NORECOVERY;
   GO
   RESTORE LOG InternetSales
   FROM DISK = N'D:\Labfiles\Lab07\Backups\IS-TailLog.bak'
   WITH FILE = 1, RECOVERY;
   GO
   ```

2. ตรวจสอบผลการกู้คืน:

   ```sql
   SELECT name, state_desc FROM sys.databases
   WHERE name = N'InternetSales';
   GO
   USE InternetSales;
   GO
   SELECT TOP 10 ProductID, ListPrice
   FROM dbo.Product
   WHERE ProductSubcategoryID = 1;
   GO
   ```

3. สังเกตว่า ListPrice ถูกปรับเพิ่มขึ้น 10% (การคูณ 1.1 จาก Setup) — ข้อมูลหลังการแก้ไข
   ถูกกู้คืนครบถ้วนด้วย log ท้ายสุด

**Results:** หลังจาก exercise นี้ InternetSales ควรกลับมา ONLINE ด้วยลำดับ restore
full → log → tail-log และคุณได้ฝึกขั้นตอน tail-log backup ของฐานข้อมูลที่ไฟล์เสียหาย

---

### Exercise 3: Performing a Piecemeal Restore

#### Task 1: Restore the AWDataWarehouse Database
1. Restore ฐานข้อมูลคลังข้อมูลจากไฟล์ที่ trainer เตรียมไว้:

   ```sql
   USE master;
   GO
   RESTORE DATABASE AWDataWarehouse
   FROM DISK = N'D:\SetupFiles\AWDataWarehouse_07.bak'
   WITH REPLACE;
   GO
   ```

2. ตรวจสอบ filegroups ของฐานข้อมูล:

   ```sql
   USE AWDataWarehouse;
   GO
   SELECT name, type_desc, is_read_only
   FROM sys.filegroups;
   GO
   ```

3. สังเกตว่ามี filegroup **Current** (read-write) สำหรับข้อมูลปัจจุบัน
   และ **Archive** (read-only) สำหรับข้อมูลย้อนหลัง:

   ```sql
   SELECT TOP 5 ProductKey, OrderDateKey, SalesAmount FROM dbo.FactInternetSales;
   GO
   SELECT TOP 5 ProductKey, OrderDateKey, SalesAmount FROM dbo.FactInternetSalesArchive;
   GO
   ```

#### Task 2: Create Filegroup Backups
1. สำรองข้อมูลแยกตามกลุ่ม — read-write กับ read-only:

   ```sql
   BACKUP DATABASE AWDataWarehouse FILEGROUP = N'Current'
   TO DISK = N'D:\Labfiles\Lab07\Backups\AWDataWarehouse_Read-Write.bak'
   WITH FORMAT, INIT, NAME = N'AWDataWarehouse-Read-Write Filegroup Backup', COMPRESSION;
   GO
   BACKUP DATABASE AWDataWarehouse FILEGROUP = N'Archive'
   TO DISK = N'D:\Labfiles\Lab07\Backups\AWDataWarehouse_Read-Only.bak'
   WITH FORMAT, INIT, NAME = N'AWDataWarehouse-Read-Only Filegroup Backup', COMPRESSION;
   GO
   ```

#### Task 3: Perform the Piecemeal Restore Sequence
1. จำลองเหตุขัดข้องด้วยการ restore ใหม่ทั้งฐานข้อมูล แต่ทำแบบ **piecemeal** —
   เริ่มจากเรียกคืนเฉพาะ primary กับ filegroup ที่กำลังใช้งาน (WITH PARTIAL):

   ```sql
   USE master;
   GO
   RESTORE DATABASE AWDataWarehouse FILEGROUP = N'Current'
   FROM DISK = N'D:\Labfiles\Lab07\Backups\AWDataWarehouse_Read-Write.bak'
   WITH PARTIAL, REPLACE, NORECOVERY;
   GO
   RESTORE DATABASE AWDataWarehouse
   FROM DISK = N'D:\Labfiles\Lab07\Backups\AWDataWarehouse_Read-Write.bak'
   WITH RECOVERY;
   GO
   ```

2. ตรวจสอบสถานะไฟล์ — ข้อมูลปัจจุบันใช้งานได้ แต่ไฟล์ของ Archive ยัง offline:

   ```sql
   USE AWDataWarehouse;
   GO
   SELECT name, state_desc, type_desc
   FROM sys.database_files;
   GO
   SELECT TOP 5 ProductKey, SalesAmount FROM dbo.FactInternetSales;        -- ใช้งานได้
   GO
   ```

3. เรียกคืน filegroup เก็บถาวรในภายหลัง:

   ```sql
   RESTORE DATABASE AWDataWarehouse FILEGROUP = N'Archive'
   FROM DISK = N'D:\Labfiles\Lab07\Backups\AWDataWarehouse_Read-Only.bak'
   WITH RECOVERY;
   GO
   USE AWDataWarehouse;
   GO
   SELECT TOP 5 ProductKey, SalesAmount FROM dbo.FactInternetSalesArchive; -- ใช้งานได้
   GO
   ```

**Results:** หลังจาก exercise นี้ คุณควรเห็นว่า piecemeal restore ทำให้ธุรกิจกลับมา
ใช้ข้อมูล read-write ได้ก่อน แล้วค่อย restore ข้อมูล read-only ขนาดใหญ่ทีหลัง

---

### Exercise 4: Backing Up and Restoring the master Database

#### Task 1: Back Up the System Databases
1. สำรอง master และ msdb:

   ```sql
   BACKUP DATABASE master
   TO DISK = N'D:\Labfiles\Lab07\Backups\master.bak'
   WITH FORMAT, INIT, NAME = N'master-Full Database Backup';
   GO
   BACKUP DATABASE msdb
   TO DISK = N'D:\Labfiles\Lab07\Backups\msdb.bak'
   WITH FORMAT, INIT, NAME = N'msdb-Full Database Backup';
   GO
   ```

2. จดจำไว้เสมอ: backup ของ master มี logins, configuration และ metadata ของทุกฐานข้อมูล
   ส่วน msdb เก็บประวัติ backup, SQL Server Agent jobs และ operator/alert —
   ควรสำรองทุกครั้งที่มีการเปลี่ยนแปลงสำคัญ

#### Task 2: Restore the master Database (Instructor-Led Walkthrough)
> ทำร่วมกับ trainer เท่านั้น — การ restore master ทำให้ instance ทุก connection หลุด

1. ที่เครื่อง SQL ในฐานะ administrator เปิด elevated Command Prompt แล้วหยุด
   SQL Server Agent และ database engine:

   ```
   NET STOP SQLSERVERAGENT
   NET STOP MSSQLSERVER
   ```

2. เริ่ม SQL Server ในโหมด single-user:

   ```
   NET START MSSQLSERVER /m
   ```

3. เชื่อมต่อด้วย sqlcmd แล้ว restore master:

   ```
   sqlcmd -S DATAFABRIC-SQL-x -E
   1> RESTORE DATABASE master FROM DISK = N'D:\Labfiles\Lab07\Backups\master.bak' WITH REPLACE;
   2> GO
   ```

   (SQL Server จะหยุดทำงานเองหลัง restore master เสร็จ)

4. เริ่มบริการตามปกติ:

   ```
   NET START MSSQLSERVER
   NET START SQLSERVERAGENT
   ```

5. เชื่อมต่อ SSMS แล้วตรวจว่า login `DATAFABRIC\Student` และฐานข้อมูลทั้งหมดยังอยู่ครบ

**Results:** หลังจาก exercise นี้ คุณควรเข้าใจขั้นตอน recovery ของ system databases
และเหตุผลที่ต้องสำรอง master/msdb ไว้เสมอ
