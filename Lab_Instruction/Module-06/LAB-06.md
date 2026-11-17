# Module 6: Backing Up SQL Server Databases
## Lab: Performing Database Backups

### Exercise 1: Performing Full, Differential, and Log Backups

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab06\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** และรอให้สคริปต์ทำงานเสร็จ
   (สคริปต์จะ restore ฐานข้อมูล **AdventureWorks** จาก `D:\SetupFiles\AdventureWorks2016.bak`
   ซึ่งอาจใช้เวลา 2–3 นาที)

#### Task 2: Configure Recovery Model and Perform a Full Backup
1. เริ่ม SQL Server Management Studio และเชื่อมต่อกับ database engine `DATAFABRIC-SQL-x`
   โดยใช้ **Windows authentication**
2. คลิก **New Query** แล้วรันคำสั่งต่อไปนี้เพื่อสลับเป็น FULL recovery model สร้างโฟลเดอร์
   เก็บ backup และทำ full backup:

   ```sql
   USE master;
   GO
   ALTER DATABASE AdventureWorks SET RECOVERY FULL;
   GO
   EXEC sys.xp_create_subdir N'D:\Labfiles\Lab06\Starter\Backups';
   GO
   BACKUP DATABASE AdventureWorks
   TO DISK = N'D:\Labfiles\Lab06\Starter\Backups\AdventureWorks.bak'
   WITH FORMAT, INIT,
        MEDIANAME = N'AdventureWorks Backup',
        NAME = N'AdventureWorks-Full Database Backup',
        COMPRESSION;
   GO
   ```

3. ในหน้าต่าง Messages สังเกตจำนวน pages ที่ประมวลผล และขนาด backup ที่ได้

#### Task 3: Perform a Differential Backup
1. เปิดไฟล์ `D:\Labfiles\Lab06\Starter\Setupfiles\AdventureWorks.sql` ใน SSMS
   (File → Open → File) แล้วคลิก **Execute** — สคริปต์นี้เพิ่ม VacationHours ของพนักงาน
   ซึ่งเป็นการเปลี่ยนแปลงข้อมูลหลัง full backup
2. กลับไปที่หน้าต่าง query เดิม แล้วทำ differential backup:

   ```sql
   BACKUP DATABASE AdventureWorks
   TO DISK = N'D:\Labfiles\Lab06\Starter\Backups\AdventureWorks.bak'
   WITH DIFFERENTIAL,
        NAME = N'AdventureWorks-Differential Database Backup',
        COMPRESSION;
   GO
   ```

3. สังเกตว่า differential backup ใช้เวลาและขนาดเล็กกว่า full backup อย่างมาก
   เพราะบันทึกเฉพาะ extents ที่เปลี่ยนแปลงตั้งแต่ full backup ล่าสุด

#### Task 4: Perform a Transaction Log Backup
1. ทำ transaction log backup:

   ```sql
   BACKUP LOG AdventureWorks
   TO DISK = N'D:\Labfiles\Lab06\Starter\Backups\AdventureWorks.bak'
   WITH NAME = N'AdventureWorks-Transaction Log Backup', COMPRESSION;
   GO
   ```

2. ตรวจสอบ backup ทั้งหมดที่บันทึกใน media set เดียวกัน:

   ```sql
   RESTORE HEADERONLY
   FROM DISK = N'D:\Labfiles\Lab06\Starter\Backups\AdventureWorks.bak';
   GO
   ```

3. สังเกตคอลัมน์ **BackupType** (1 = Full, 5 = Differential, 2 = Log) และ **Position**
   ซึ่งเป็นหมายเลข backup set ที่จะใช้อ้างอิงตอน restore ใน Module 7

**Results:** หลังจาก exercise นี้ คุณควรมี backup chain ครบทั้ง full, differential และ
transaction log ของ AdventureWorks ในไฟล์เดียว และตรวจสอบ backup sets ได้ด้วย
RESTORE HEADERONLY

---

### Exercise 2: Backing Up Read-Only Filegroups

#### Task 1: Create a Read-Only Filegroup
1. เปิดไฟล์ `D:\Labfiles\Lab06\Starter\Setupfiles\CreateReadOnly.sql` ใน SSMS แล้วคลิก **Execute**
   สคริปต์นี้จะ:
   - เพิ่ม filegroup ใหม่ชื่อ **ReadOnlyFG** พร้อมไฟล์ข้อมูล `ReadOnlyFile.ndf`
     ในโฟลเดอร์ `D:\Labfiles\Lab06\Starter\Data`
   - สร้างตาราง `demoTable` บน filegroup นั้น
   - เปลี่ยน filegroup ให้เป็น **READ_ONLY**
2. ตรวจสอบ filegroups ปัจจุบัน:

   ```sql
   USE AdventureWorks;
   GO
   SELECT name, type_desc, is_read_only
   FROM sys.filegroups;
   GO
   ```

3. สังเกตว่า ReadOnlyFG มีสถานะ is_read_only = 1

#### Task 2: Back Up the Database with a Read-Only Filegroup
1. ทำ full backup ใหม่ (เพื่อให้ diff base รวมถึง read-only filegroup):

   ```sql
   BACKUP DATABASE AdventureWorks
   TO DISK = N'D:\Labfiles\Lab06\Starter\Backups\AdventureWorks.bak'
   WITH NAME = N'AdventureWorks-Full Database Backup 2', COMPRESSION;
   GO
   ```

2. เปลี่ยนแปลงข้อมูลบน read-write filegroup แล้วทำ differential backup:

   ```sql
   UPDATE HumanResources.Employee
   SET VacationHours = VacationHours + 5
   WHERE SickLeaveHours < 40;
   GO
   BACKUP DATABASE AdventureWorks
   TO DISK = N'D:\Labfiles\Lab06\Starter\Backups\AdventureWorks.bak'
   WITH DIFFERENTIAL,
        NAME = N'AdventureWorks-Differential Database Backup 2',
        COMPRESSION;
   GO
   ```

3. เปรียบเทียบขนาด (คอลัมน์ CompressedBackupSize ใน msdb) ระหว่าง differential ก่อนหน้า
   กับ differential นี้ — ข้อมูลใน read-only filegroup ไม่ถูกเขียนซ้ำใน differential เพราะ
   ไม่มีการเปลี่ยนแปลง

#### Task 3: Perform a Partial (Read-Write Filegroups) Backup
1. ทำ partial backup เฉพาะ read-write filegroups:

   ```sql
   BACKUP DATABASE AdventureWorks READ_WRITE_FILEGROUPS
   TO DISK = N'D:\Labfiles\Lab06\Starter\Backups\AdventureWorks_RW.bak'
   WITH FORMAT, INIT,
        NAME = N'AdventureWorks-Partial (Read-Write) Backup', COMPRESSION;
   GO
   ```

2. ตรวจสอบด้วย msdb ว่าเป็น partial backup และดูขนาดที่ประหยัดได้:

   ```sql
   SELECT backup_set_id, name, is_partial,
          backup_size/1024/1024 AS backup_mb,
          compressed_backup_size/1024/1024 AS compressed_mb
   FROM msdb.dbo.backupset
   WHERE database_name = N'AdventureWorks'
   ORDER BY backup_set_id DESC;
   GO
   ```

3. สังเกตคอลัมน์ **is_partial = 1** ของ backup ล่าสุด — partial backup มีประโยชน์เมื่อ
   ฐานข้อมูลมี filegroup ข้อมูลจำนวนมากแบบ read-only ที่ backup ครั้งเดียวแล้วไม่ต้อง
   backup ซ้ำ (จะได้ใช้จริงใน Module 7)

**Results:** หลังจาก exercise นี้ คุณควรเข้าใจพฤติกรรมของ backup ต่อ read-only filegroup
และสร้าง partial backup ด้วย READ_WRITE_FILEGROUPS ได้

---

### Exercise 3: Encrypting Backups

#### Task 1: Create a Backup Encryption Certificate
1. สร้างโฟลเดอร์ `D:\Backups` ด้วย File Explorer (คลิกขวาที่ drive D: → New → Folder)
   — สคริปต์ถัดไปจะบันทึก master key และ certificate ไว้ที่นี่
2. เปิดไฟล์ `D:\Labfiles\Lab06\Starter\Setupfiles\EncryptionKeys.sql` ใน SSMS แล้วคลิก
   **Execute** — สคริปต์นี้จะ:
   - สร้าง database master key ของ master database
   - backup master key ไปยัง `D:\Backups\master.key`
   - สร้าง certificate ชื่อ **AdventureWorksCert**
   - backup certificate และ private key ไปยัง `D:\Backups\AdventureWorksCert.cer` และ
     `D:\Backups\AdventureWorksCert.pvk`
3. ตรวจสอบว่า certificate ถูกสร้างแล้ว:

   ```sql
   USE master;
   GO
   SELECT name, pvt_key_encryption_type_desc, expiry_date
   FROM sys.certificates;
   GO
   ```

   > **สำคัญ**: เก็บไฟล์ .cer, .pvk และ master.key ให้ปลอดภัย — หากต้องกู้คืน encrypted
   > backup บนเซิร์ฟเวอร์อื่นจะต้องใช้ certificate นี้ (และควรตั้ง expiry date จริงในการใช้งาน)

#### Task 2: Create an Encrypted Backup
1. ทำ encrypted backup ของ AdventureWorks:

   ```sql
   BACKUP DATABASE AdventureWorks
   TO DISK = N'D:\Backups\AdventureWorks_Encrypted.bak'
   WITH FORMAT, INIT,
        NAME = N'AdventureWorks-Encrypted Backup',
        ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = AdventureWorksCert),
        COMPRESSION;
   GO
   ```

2. ตรวจสอบว่าไฟล์ backup ถูกเข้ารหัส:

   ```sql
   RESTORE HEADERONLY
   FROM DISK = N'D:\Backups\AdventureWorks_Encrypted.bak';
   GO
   ```

3. สังเกตคอลัมน์ **EncryptorThumbprint** / **EncryptorType** ที่ระบุ certificate ที่ใช้เข้ารหัส
   — ไฟล์ .bak นี้ไม่สามารถ restore ได้เลยหากไม่มี certificate และ private key ที่ตรงกัน

**Results:** หลังจาก exercise นี้ คุณควรสร้าง backup ที่เข้ารหัสด้วย certificate ได้ และทราบ
ว่าต้องสำรอง (และกู้คืน) certificate พร้อมกับ backup ด้วยเสมอ ใน Module 7 คุณจะได้ฝึก
restore ฐานข้อมูลที่ถูก sabotage ไฟล์ข้อมูลจริง ๆ

> **หมายเหตุ**: Setup.cmd ของ Lab07 จะลบ certificate และ master key ชุดนี้ทิ้งเมื่อเตรียม
> สภาพแวดล้อมถัดไป หากต้องการทดลองต่อให้รีวิวไฟล์ .cer/.pvk ที่ backup ไว้แล้ว
