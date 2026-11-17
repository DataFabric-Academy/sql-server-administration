# Module 8: Automating SQL Server Management
## Lab: Automating SQL Server Management

### Exercise 1: Create a SQL Server Agent Job

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab08\Starter` คลิกขวาที่ไฟล์ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** และรอให้สคริปต์ทำงานเสร็จ

#### Task 2: Create a Backup Job
1. เริ่ม SQL Server Management Studio และเชื่อมต่อกับ database engine `DATAFABRIC-SQL-x` โดยใช้
   **Windows authentication**
2. ใน Object Explorer ขยาย **SQL Server Agent** แล้วขยาย **Jobs** เพื่อดู jobs ที่มีอยู่
3. คลิกขวาที่ **Jobs** แล้วคลิก **New Job**
4. ในกล่องโต้ตอบ New Job บนหน้า **General** ในช่อง **Name** พิมพ์ `Backup HumanResources`
5. บนหน้า **Steps** คลิก **New**
6. ในกล่องโต้ตอบ New Job Step บนหน้า **General** ในช่อง **Step name** พิมพ์ `Back Up Database`
7. ในรายการ **Database** คลิก **HumanResources** และในช่อง **Command** พิมพ์คำสั่งต่อไปนี้:
   ```sql
   BACKUP DATABASE HumanResources TO DISK = 'D:\HumanResources.bak';
   ```
8. ในกล่องโต้ตอบ New Job Step บนหน้า **Advanced** ในช่อง **Output file** พิมพ์
   `D:\Labfiles\Lab08\Starter\BackupLog.txt` แล้วคลิก **OK**
9. ในกล่องโต้ตอบ New Job บนหน้า **Steps** คลิก **New**
10. ในกล่องโต้ตอบ New Job Step บนหน้า **General** ในช่อง **Step name** พิมพ์ `Move Backup File`
11. ในรายการ **Type** คลิก **Operating system (CmdExec)** และในช่อง **Command** พิมพ์คำสั่งต่อไปนี้
    ซึ่งย้ายไฟล์ backup ไปยังโฟลเดอร์ `D:\Labfiles\Lab08\Starter`:
    ```
    Move /Y D:\HumanResources.bak D:\Labfiles\Lab08\Starter\HumanResources.bak
    ```
12. ในกล่องโต้ตอบ New Job Step คลิก **OK**
13. ในกล่องโต้ตอบ New Job บนหน้า **Steps** ตรวจสอบว่า **Start step** ตั้งเป็น `1:Back Up Database`
    และในตาราง **Job step list** สังเกตการกระทำ **On Success** และ **On Failure** สำหรับ steps ใน job
14. ในกล่องโต้ตอบ New Job คลิก **OK**
15. ใน Object Explorer ในโฟลเดอร์ **Jobs** ตรวจสอบว่า job ปรากฏขึ้น
16. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** ในตอนท้ายของ exercise นี้ คุณจะได้สร้าง job ชื่อ `Backup HumanResources`

---

### Exercise 2: Test a Job

#### Task 1: Test the Backup Job
1. ใน Object Explorer ภายใต้ **Jobs** คลิกขวาที่ `Backup HumanResources` แล้วคลิก **Start Job at Step**
2. ในกล่องโต้ตอบ Start Job on 'DATAFABRIC-SQL-x' คลิก **Start**
3. สังเกตว่ากล่องโต้ตอบ Start Jobs - DATAFABRIC-SQL-x แสดง error แล้วคลิก **Close**

#### Task 2: Investigate the Error
1. ใน Object Explorer คลิกขวาที่ `Backup HumanResources` แล้วคลิก **View History**
2. ในกล่องโต้ตอบ Log File Viewer - DATAFABRIC-SQL-x ขยายแถวแรกโดยคลิกที่เซลล์วันที่
3. สังเกตว่า Step ID 1 สำเร็จ
4. คลิกเซลล์ Step ID 2 ปรับขนาดบานหน้าต่างล่างที่มีข้อความ "Selected row details:" และเลื่อนไป
   ด้านล่าง
5. ข้อความ error ควรอ่านว่า:
   ```
   Executed as user: DATAFABRIC\ServiceAcct. The syntax of the command is incorrect.
   Process Exit Code 1. The step failed.
   ```
6. คำสั่ง move ใน Step 2 ของ job มี syntax error
7. ในกล่องโต้ตอบ Log File Viewer - DATAFABRIC-SQL-x คลิก **Close**

#### Task 3: Resolve the Error and Retest
1. ใน Object Explorer คลิกขวาที่ `Backup HumanResources` แล้วคลิก **Properties**
2. ในกล่องโต้ตอบ Job Properties - Backup HumanResources บนหน้า **Steps** คลิก `Move Backup
   File` แล้วคลิก **Edit**
3. ในกล่องโต้ตอบ Job Step Properties - Move Backup File ในช่อง **Command** ลบข้อความที่มีอยู่
   แทนที่ด้วยคำสั่งต่อไปนี้ แล้วคลิก **OK**:
   ```
   Move /Y D:\HumanResources.bak D:\Labfiles\Lab08\Starter\HumanResources.bak
   ```
4. ในกล่องโต้ตอบ Job Properties - Backup HumanResources คลิก **OK**
5. ใน Object Explorer คลิกขวาที่ `Backup HumanResources` แล้วคลิก **Start Job at Step**
6. ในกล่องโต้ตอบ Start Job on 'DATAFABRIC-SQL-x' คลิก **Start**
7. สังเกตว่าในกล่องโต้ตอบ Start Jobs - DATAFABRIC-SQL-x job เสร็จด้วยความสำเร็จ แล้วคลิก **Close**
8. ใน File Explorer นำทางไปยัง `D:\Labfiles\Lab08\Starter` และสังเกตว่าไฟล์ `HumanResources.bak`
   มีอยู่
9. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** ในตอนท้ายของ exercise นี้ คุณจะได้ทดสอบ SQL Server Agent job และยืนยันว่ามัน
execute สำเร็จ

---

### Exercise 3: Schedule a Job

#### Task 1: Add a Schedule to the Job
1. คลิกขวาที่ taskbar แล้วคลิก **Properties**
2. ในกล่องโต้ตอบ Taskbar and Navigation properties ในส่วน **Notification area** คลิก **Customize**
3. ในกล่องโต้ตอบ Notification Area Icons คลิก **Turn system icons on or off**
4. ในกล่องโต้ตอบ System Icons ในแถว **Clock** ในรายการ **Behaviors** คลิก **On** แล้วคลิก **OK**
5. ในกล่องโต้ตอบ Notification Area Icons คลิก **OK**
6. ในกล่องโต้ตอบ Taskbar and Navigation properties คลิก **OK**
7. สังเกตว่าตอนนี้นาฬิกาปรากฏใน taskbar
8. ใน Microsoft SQL Server Management Studio ใน Object Explorer ดับเบิลคลิก `Backup HumanResources`
9. ในกล่องโต้ตอบ Job properties - Backup HumanResources บนหน้า **Schedules** คลิก **New**
10. ในกล่องโต้ตอบ New Job Schedule ในช่อง **Name** พิมพ์ `Daily Backup` แล้วในส่วน **Frequency**
    ในรายการ **Occurs** คลิก **Daily**
11. ในส่วน **Daily frequency** ในส่วน **Occurs once at** ตั้งเวลาสองนาทีจากเวลาระบบปัจจุบันตามที่แสดง
    ในนาฬิกาใน notification area แล้วคลิก **OK**
12. ในกล่องโต้ตอบ Job properties - Backup HumanResources คลิก **OK** และรอจนนาฬิการะบบแสดง
    เวลาที่กำหนด

#### Task 2: Verify Scheduled Job Execution
1. ใน Object Explorer ดับเบิลคลิก **Job Activity Monitor** และสังเกต **Status** ของ job
   `Backup HumanResources`
2. ถ้า job ยังทำงานอยู่ คลิก **Refresh** จนกว่า **Status** เปลี่ยนเป็น **Idle**
3. ตรวจสอบว่า **Last Run Outcome** สำหรับ job คือ **Succeeded** และ **Last Run** time คือเวลาที่คุณ
    กำหนดไว้ก่อนหน้านี้ แล้วคลิก **Close**
4. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** ในตอนท้ายของ exercise นี้ คุณจะได้สร้าง schedule สำหรับ job `Backup HumanResources`

---

### Exercise 4: Configure Master and Target Servers

#### Task 1: Configure the Master and Target Servers
1. ใน Object Explorer คลิกขวาที่ **SQL Server Agent** ชี้ไปที่ **Multi Server Administration** แล้วคลิก
   **Make this a Master**
2. ในกล่องโต้ตอบ Master Server Wizard - DATAFABRIC-SQL-x คลิก **Next**
3. บนหน้า Master Server Operator คลิก **Next**
4. บนหน้า Target Servers ในส่วน **Registered servers** ขยาย **Database Engine** และขยาย **Local
   Server Groups**
5. คลิก `DATAFABRIC-SQL-x\sql2` แล้วคลิก `>` คลิก `DATAFABRIC-SQL-x\sql3` แล้วคลิก `>` แล้วคลิก **Next**
6. ในกล่องโต้ตอบ Checking Server Compatibility คลิก **Close**
7. บนหน้า Master Server Login Credentials คลิก **Next**
8. บนหน้า Complete the Wizard คลิก **Finish**
9. บนหน้า Enlist TSX Progress คลิก **Close**

#### Task 2: Create a Maintenance Plan
1. ใน Object Explorer ขยาย **Management** คลิกขวาที่ **Maintenance Plans** แล้วคลิก **Maintenance Plan
   Wizard**
2. ในกล่องโต้ตอบ Maintenance Plan Wizard คลิก **Next**
3. บนหน้า Select Plan Properties ในช่อง **Name** พิมพ์ `System Database Backups`
4. ในส่วน **Schedule** คลิก **Change**
5. ในกล่องโต้ตอบ New Job Schedule ในส่วน **Frequency** ในรายการ **Occurs** คลิก **Daily**
6. ในส่วน **Daily frequency** ในช่อง **Occurs once at** ตั้งเวลาห้านาทีจากเวลาระบบปัจจุบันตามที่แสดง
    ในนาฬิกาใน notification area แล้วคลิก **OK**
7. บนหน้า Select Plan Properties คลิก **Next**
8. บนหน้า Select Target Servers เลือกช่องทำเครื่องหมายถัดจาก `DATAFABRIC-SQL-x\SQL2` และ `DATAFABRIC-SQL-x\SQL3`
    แล้วคลิก **Next**
9. บนหน้า Select Maintenance Tasks เลือก **Back Up Database (Full)** แล้วคลิก **Next**
10. บนหน้า Select Maintenance Task Order คลิก **Next**
11. บนหน้า Define Backup Database (Full) Task บนแท็บ **General** ในรายการ **Database(s)** คลิก
    **System databases** แล้วคลิก **OK**
12. บนแท็บ **Destination** เลือกช่องทำเครื่องหมาย **Create a sub-directory for each database** ในช่อง
    **Folder** พิมพ์ `D:\` แล้วคลิก **Next**
13. บนหน้า Select Report Options ในช่อง **Folder location** พิมพ์ `D:\` แล้วคลิก **Next**
14. บนหน้า Complete the Wizard คลิก **Finish**
15. บนหน้า Maintenance Plan Wizard Progress รอให้การดำเนินการเสร็จสิ้น แล้วคลิก **Close**
16. ใน Object Explorer คลิกขวาที่ **SQL Server Agent** ชี้ไปที่ **Multi Server Administration** แล้วคลิก
    **Manage Target Servers**
17. ในรายการ **Target Server** คลิก `DATAFABRIC-SQL-x\SQL2` แล้วคลิก **Force Poll**
18. ในกล่องโต้ตอบ Force Target Server to Poll MSX Immediately คลิก **OK**
19. ในรายการ **Target Server** คลิก `DATAFABRIC-SQL-x\SQL3` แล้วคลิก **Force Poll**
20. ในกล่องโต้ตอบ Force Target Server to Poll MSX Immediately คลิก **OK**
    **Note:** โดยการบังคับ target servers ให้ poll master server พวกเขาจะได้รับสำเนาของ jobs
    System Database Backup
21. ในกล่องโต้ตอบ Target Server Status - DATAFABRIC-SQL-x คลิก **Close**
22. ใน File Explorer ดูโฟลเดอร์ `D:\` ไฟล์ log ควรถูกสร้างจากแต่ละ server และสำหรับแต่ละ system
    database ควรมีโฟลเดอร์ถูกสร้าง เก็บไฟล์ backup จากแต่ละ SQL Server instance

#### Task 3: Monitor the Job History
1. ใน SQL Server Management Studio ใน Object Explorer ภายใต้ **SQL Server Agent** ดับเบิลคลิก
   **Job Activity Monitor**
2. ในหน้าต่าง Job Activity Monitor - DATAFABRIC-SQL-x สังเกตแถวในตาราง **Agent Job Activity** สำหรับ:
   - `System Database Backups.Subplan_1`
   - `System Database Backups.Subplan_1 (Multi-Server)`
3. คลิกขวาที่ `System Database Backups.Subplan_1` แล้วคลิก **View history**
4. ในกล่องโต้ตอบ Log File Viewer - DATAFABRIC-SQL-x ตรวจสอบข้อมูลประวัติ แล้วคลิก **Close**
5. คลิกขวาที่ `System Database Backups.Subplan_1 (Multi-Server)` แล้วคลิก **View history**
6. สังเกตว่ามีรายละเอียดน้อยกว่าใน Log File Viewer สำหรับ multiserver jobs สำหรับข้อมูลรายละเอียด
    เพิ่มเติม ใช้ Job Activity Monitor บน target server
7. ในกล่องโต้ตอบ Log File Viewer - DATAFABRIC-SQL-x คลิก **Close**
8. ในกล่องโต้ตอบ Job Activity Monitor - DATAFABRIC-SQL-x คลิก **Close**
9. ใน Object Explorer คลิก **Connect** แล้วคลิก **Database Engine**
10. ในกล่องโต้ตอบ Connect to Server ในช่อง **Server name** พิมพ์ `DATAFABRIC-SQL-x\SQL2` แล้วคลิก
    **Connect**
11. ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x\SQL2` ขยาย **SQL Server Agent** แล้วดับเบิลคลิก
    **Job Activity Monitor**
12. ในกล่องโต้ตอบ Job Activity Monitor - DATAFABRIC-SQL-x\SQL2 คลิกขวาที่ `System Database
    Backups.Subplan_1 (Multi-Server)` แล้วคลิก **View history**
13. สังเกตว่ามีข้อมูลแสดงมากขึ้นบน target server
14. ในกล่องโต้ตอบ Log File Viewer - DATAFABRIC-SQL-x\SQL2 คลิก **Close**
15. ในกล่องโต้ตอบ Job Activity Monitor - DATAFABRIC-SQL-x\SQL2 คลิก **Close**
16. ปิด SQL Server Management Studio

**Results:** ในตอนท้ายของ exercise นี้ คุณจะได้สร้างและ execute maintenance plan ข้ามหลาย servers


