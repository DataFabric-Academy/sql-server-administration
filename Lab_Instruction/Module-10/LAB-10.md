# Module 10: Monitoring SQL Server with Alerts and Notifications
## Lab: Monitoring SQL Server with Alerts and Notifications

### Exercise 1: Configuring Database Mail

#### Task 1: Prepare the Lab Environment

##### การติดตั้ง Papercut SMTP (แนะนำ)

Lab นี้ต้องการ SMTP server สำหรับทดสอบ Database Mail แทนที่จะใช้ SMTP server จริง แนะนำให้ใช้ **Papercut SMTP** ซึ่งเป็นเครื่องมือที่เหมาะสำหรับการทดสอบและพัฒนา

**ขั้นตอนการติดตั้ง:**

1. **ดาวน์โหลด Papercut SMTP:**
   - ไปที่: https://github.com/ChangemakerStudios/Papercut-SMTP/releases
   - ดาวน์โหลดไฟล์ `PapercutSMTP-win-X64-stable-Setup.exe` (สำหรับ 64-bit) หรือ `PapercutSMTP-win-x86-stable-Setup.exe` (สำหรับ 32-bit)

2. **ติดตั้ง Papercut SMTP:**
   - รันไฟล์ติดตั้งที่ดาวน์โหลดมา
   - ทำตามขั้นตอนการติดตั้ง (สามารถเลือกการติดตั้งแบบ silent ด้วย)
   - Papercut SMTP จะเริ่มทำงานทันทีหลังจากติดตั้งเสร็จ

3. **ตั้งค่า SMTP Server สำหรับ Database Mail:**
   - Papercut SMTP จะรันที่ **localhost:25** (default)
   - เมื่อ configure Database Mail ใน Task 2 ใช้ค่า:
     - **Server name:** `localhost` หรือ `127.0.0.1`
     - **Port:** `25` (default) หรือ `2525` (ถ้า port 25 ถูกใช้งาน)
   - Papercut SMTP จะรับอีเมลทั้งหมดที่ส่งจาก Database Mail และแสดงใน UI

4. **ดูอีเมลที่ได้รับ:**
   - เปิด Papercut SMTP application
   - อีเมลที่ส่งจาก Database Mail จะแสดงในรายการด้านซ้าย
   - คลิกที่อีเมลเพื่อดูรายละเอียด: body, HTML, headers, และ attachments

**หมายเหตุ:**
- Papercut SMTP ไม่จำเป็นต้องใช้ SMTP authentication สำหรับการทดสอบ
- ถ้ามี IIS SMTP Virtual Server ทำงานอยู่ อาจต้องปิดหรือเปลี่ยน port ใน Papercut SMTP เป็น 2525
- สำหรับข้อมูลเพิ่มเติมเกี่ยวกับ Papercut SMTP ดูได้ที่: https://github.com/ChangemakerStudios/Papercut-SMTP

---

1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab10\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** และรอให้สคริปต์ทำงานเสร็จ
4. ตรวจสอบให้แน่ใจว่า Papercut SMTP กำลังทำงานอยู่ (ดูใน system tray หรือ Task Manager)

#### Task 2: Configure Database Mail
1. เริ่ม SQL Server Management Studio และเชื่อมต่อกับ Database Engine instance `DATAFABRIC-SQL-x` โดยใช้
   Windows authentication
2. ใน Object Explorer ขยาย **Management** คลิกขวาที่ **Database Mail** แล้วคลิก **Configure Database
   Mail**
3. บนหน้า Welcome to Database Mail Configuration Wizard คลิก **Next**
4. บนหน้า Select Configuration Task คลิก **Set up Database Mail by performing the following tasks:**
   แล้วคลิก **Next**
5. บนหน้า New Profile ในช่อง **Profile name** พิมพ์ `SQL Server Agent Profile` แล้วคลิก **Add**
6. ในกล่องโต้ตอบ Add Account to profile 'SQL Server Agent Profile' คลิก **New Account**
7. ในกล่องโต้ตอบ New Database Mail Account ป้อนรายละเอียดต่อไปนี้ แล้วคลิก **OK**:
   - **Account name:** DataFabric Administrator
   - **Email address:** administrator@datafabric.local
   - **Display name:** Administrator (DataFabric)
   - **Reply email:** administrator@datafabric.local
   - **Server name:** localhost (หรือ 127.0.0.1 หากใช้ Papercut SMTP)
   - **Port:** 25 (default) หรือ 2525 (ถ้า port 25 ถูกใช้งาน)
   - **This server requires a secure connection (SSL):** ไม่ต้องเลือก (Papercut SMTP ไม่จำเป็นต้องใช้ SSL สำหรับการทดสอบ)
8. บนหน้า New Profile คลิก **Next**
9. บนหน้า Manage Profile Security เลือก **Public** สำหรับ profile SQL Server Agent Profile ตั้งค่า
   **Default Profile** เป็น **Yes** แล้วคลิก **Next**
10. บนหน้า Configure System Parameters คลิก **Next**
11. บนหน้า Complete the Wizard คลิก **Finish** และเมื่อการกำหนดค่าเสร็จสิ้น คลิก **Close**

#### Task 3: Test Database Mail
1. ใน Object Explorer คลิกขวาที่ **Database Mail** แล้วคลิก **Sent Test E-Mail**
2. ในกล่องโต้ตอบ Send Test E-Mail from DATAFABRIC-SQL-x ตรวจสอบว่า database mail profile **SQL Server
   Agent Profile** ถูกเลือก
3. ในช่อง **To** พิมพ์ `student@datafabric.local` แล้วคลิก **Send Test Email**
4. เปิด **Papercut SMTP** application (ดูใน system tray หรือ Start menu)
5. ตรวจสอบว่ามีอีเมลใหม่ปรากฏในรายการด้านซ้ายของ Papercut SMTP (อาจต้องคลิก Refresh)
6. คลิกที่อีเมลที่ส่งมาเพื่อดูรายละเอียด: body, HTML, headers, และ attachments
7. ในกล่องโต้ตอบ Database Mail Test E-Mail (ซึ่งอาจอยู่หลัง SQL Server Management Studio) คลิก
   **OK**
7. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
8. ใน query pane พิมพ์ Transact-SQL code ต่อไปนี้ แล้วคลิก **Execute**:
   ```sql
   SELECT * FROM msdb.dbo.sysmail_event_log;
   SELECT * FROM msdb.dbo.sysmail_mailitems;
   ```
9. ตรวจสอบผลลัพธ์ ผลลัพธ์แรกแสดง system events สำหรับ Database Mail และผลลัพธ์ที่สองแสดง
    บันทึกของข้อความ email ที่ถูกส่ง
10. ปิด query pane โดยไม่บันทึกการเปลี่ยนแปลง
11. ปล่อยให้ SSMS เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจาก exercise นี้ คุณควรได้กำหนดค่า Database Mail ด้วย profile ใหม่ชื่อ `SQL
Server Agent Profile`

---

### Exercise 2: Configuring Operators

#### Task 1: Create the Student Operator
1. ใน Object Explorer ขยาย **SQL Server Agent** คลิกขวาที่ **Operators** แล้วคลิก **New Operator**
2. ในกล่องโต้ตอบ New Operator ในช่อง **Name** พิมพ์ `Student` ในช่อง **E-mail name** พิมพ์
   `student@datafabric.local` แล้วคลิก **OK**

#### Task 2: Create the DBA Team Operator
1. ใน Object Explorer ภายใต้ **SQL Server Agent** คลิกขวาที่ **Operators** แล้วคลิก **New Operator**
2. ในกล่องโต้ตอบ New Operator ในช่อง **Name** พิมพ์ `DBA Team` ในช่อง **E-mail name** พิมพ์
   `dba@datafabric.local` แล้วคลิก **OK**

#### Task 3: Configure the SQL Server Agent Mail Profile
1. ใน Object Explorer คลิกขวาที่ **SQL Server Agent** แล้วคลิก **Properties**
2. ในกล่องโต้ตอบ SQL Server Agent Properties บนหน้า **Alert System** เลือก **Enable mail profile**
3. ในรายการ **Mail profile** คลิก **SQL Server Agent Profile**
4. เลือก **Enable fail-safe operator** ในรายการ **Operator** คลิก **DBA Team**
5. ในส่วน **Notify using** เลือก **E-mail** แล้วคลิก **OK**
6. ใน Object Explorer คลิกขวาที่ **SQL Server Agent** แล้วคลิก **Restart**
7. ในกล่องโต้ตอบ User Account Control คลิก **Yes**
8. ในกล่องโต้ตอบ Microsoft SQL Server Management Studio คลิก **Yes**
9. ปล่อยให้ SSMS เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจาก exercise นี้ คุณควรได้สร้าง operators ชื่อ `Student` และ `DBA Team` และ
กำหนดค่า SQL Server Agent service เพื่อใช้ Database Mail profile `SQL Server Agent Profile`

---

### Exercise 3: Configuring Alerts and Notifications

#### Task 1: Create an Alert
1. ใน Object Explorer ขยาย **SQL Server Agent** คลิกขวาที่ **Alerts** แล้วคลิก **New Alert**
2. ในกล่องโต้ตอบ New Alert บนหน้า **General** ในช่อง **Name** พิมพ์ `InternetSales Log Full Alert`
3. ในรายการ **Database name** คลิก **InternetSales**
4. คลิก **Error number** และพิมพ์ error number `9002`
5. บนหน้า **Response** เลือก **Execute job** และในรายการ drop-down คลิก `Back Up Log -
   InternetSales ([Uncategorized (Local)])`
6. เลือก **Notify operators** แล้วเลือก **E-mail** สำหรับ operator **Student**
7. บนหน้า **Options** ภายใต้ **Include alert error text in** เลือก **E-mail** แล้วคลิก **OK**

#### Task 2: Configure Job Notifications
1. ใน Object Explorer ภายใต้ **SQL Server Agent** ขยาย **Jobs** และดู jobs ที่มีอยู่
2. คลิกขวาที่ `Back Up Database - AWDataWarehouse` แล้วคลิก **Properties**
3. ในกล่องโต้ตอบ Job Properties - Back Up Database - AWDataWarehouse บนหน้า **Notifications**
   เลือก **E-mail**
4. ในรายการ drop-down แรก คลิก **Student**
5. ในรายการ drop-down ที่สอง คลิก **When the job fails** แล้วคลิก **OK**
6. คลิกขวาที่ `Back Up Database - HumanResources` แล้วคลิก **Properties**
7. ในกล่องโต้ตอบ Job Properties - Back Up Database - HumanResources บนหน้า **Notifications**
   เลือก **E-mail**
8. ในรายการ drop-down แรก คลิก **Student**
9. ในรายการ drop-down ที่สอง คลิก **When the job fails** แล้วคลิก **OK**
10. คลิกขวาที่ `Back Up Database - InternetSales` แล้วคลิก **Properties**
11. ในกล่องโต้ตอบ Job Properties - Back Up Database - InternetSales บนหน้า **Notifications**
    เลือก **E-mail**
12. ในรายการ drop-down แรก คลิก **Student**
13. ในรายการ drop-down ที่สอง คลิก **When the job completes** แล้วคลิก **OK**
14. คลิกขวาที่ job `Back Up Log - InternetSales` แล้วคลิก **Properties**
15. ในกล่องโต้ตอบ Job Properties - Back Up Log - InternetSales บนหน้า **Notifications** เลือก
    **E-mail**
16. ในรายการ drop-down แรก คลิก **Student**
17. ในรายการ drop-down ที่สอง คลิก **When the job completes** แล้วคลิก **OK**
18. ขยายโฟลเดอร์ **Operators** คลิกขวาที่ `Student` แล้วคลิก **Properties**
19. ในกล่องโต้ตอบ Student Properties บนหน้า **Notifications** คลิก **Jobs** ตรวจสอบ job
    notifications ที่ได้กำหนดไว้สำหรับ operator นี้ แล้วคลิก **Cancel**
20. ปล่อยให้ SSMS เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจาก exercise นี้ คุณควรได้สร้าง alert ชื่อ `InternetSales Log Full Alert` และ
คุณควรได้กำหนดค่า jobs `Back Up Database - AWDataWarehouse`, `Back Up Database - HumanResources`,
`Back Up Database - InternetSales`, และ `Back Up Log - InternetSales` เพื่อส่ง notifications

---

### Exercise 4: Testing Alerts and Notifications

#### Task 1: Test the Alert
1. บนเมนู **File** ชี้ไปที่ **Open** แล้วคลิก **File**
2. ในกล่องโต้ตอบ Open File นำทางไปยังโฟลเดอร์ `D:\Labfiles\Lab10\Starter` คลิก `TestAlert.sql`
   แล้วคลิก **Open**
3. บนแถบเครื่องมือ คลิก **Execute** และรอให้สคริปต์ทำงานเสร็จ เมื่อ log file สำหรับ database
   InternetSales เต็ม error 9002 เกิดขึ้น
4. ใน Object Explorer ขยาย **Alerts** คลิกขวาที่ `InternetSales Log Full Alert` แล้วคลิก
   **Properties**
5. ในกล่องโต้ตอบ 'InternetSales Log Full Alert' alert properties บนหน้า **History** สังเกตค่า
   **Date of last alert** และ **Date of last response** แล้วคลิก **Cancel**
6. เปิด **Papercut SMTP** application (ดูใน system tray หรือ Start menu)
7. ตรวจสอบว่ามีอีเมลใหม่สี่ข้อความปรากฏในรายการด้านซ้ายของ Papercut SMTP (อาจต้องคลิก Refresh)
8. คลิกที่อีเมลแต่ละข้อความเพื่อดูรายละเอียด ควรรวม notification ว่า transaction log เต็ม
   และ notification ว่า job `Back Up Log - InternetSales` เสร็จสิ้น เมื่อคุณตรวจสอบเสร็จแล้ว ปิด
   Papercut SMTP หรือย่อหน้าต่างไว้

#### Task 2: Test Job Notifications
1. ใน Object Explorer ภายใต้ **Jobs** คลิกขวาที่ `Back Up Database - AWDataWarehouse` แล้วคลิก
   **Start Job at Step**
2. เมื่อ job เสร็จสิ้นแล้ว สังเกตว่ามันล้มเหลว แล้วคลิก **Close**
3. ใน Object Explorer ภายใต้ **Jobs** คลิกขวาที่ `Back Up Database - HumanResources` แล้วคลิก
   **Start Job at Step**
4. เมื่อ job เสร็จสิ้นแล้ว สังเกตว่ามันสำเร็จ แล้วคลิก **Close**
5. ใน Object Explorer ภายใต้ **Jobs** คลิกขวาที่ `Back Up Database - InternetSales` แล้วคลิก **Start
   Job at Step**
6. เมื่อ job เสร็จสิ้นแล้ว สังเกตว่ามันสำเร็จ แล้วคลิก **Close**
7. ภายใต้โฟลเดอร์ **Operators** คลิกขวาที่ `Student` แล้วคลิก **Properties**
8. ในกล่องโต้ตอบ Student Properties บนหน้า **History** สังเกตวันที่และเวลาของ notification ล่าสุด
   โดย email แล้วคลิก **Cancel**
9. เปิด **Papercut SMTP** application (ดูใน system tray หรือ Start menu)
10. ตรวจสอบว่ามีอีเมลใหม่ถูกสร้างขึ้นในรายการด้านซ้ายของ Papercut SMTP (อาจต้องคลิก Refresh)
11. คลิกที่อีเมลแต่ละข้อความเพื่อดูรายละเอียด ตรวจสอบว่าพวกเขารวม failure notification สำหรับ job `Back Up
    Database - AWDataWarehouse` และ completion notification สำหรับ job `Back Up Database -
    InternetSales` แต่ไม่มี notification เกี่ยวกับ job `Back Up Database - HumanResources`
12. เมื่อคุณอ่านข้อความแล้ว ปิด Papercut SMTP หรือย่อหน้าต่างไว้
12. ปิด SQL Server Management Studio โดยไม่บันทึกไฟล์ใดๆ

**Results:** หลังจาก exercise นี้ คุณจะได้ตรวจสอบว่า notifications ที่คุณกำหนดค่าสำหรับ backups
ของ databases AWDataWarehouse, HumanResources, และ InternetSales ทำงานตามที่คาดหวัง คุณยังจะ
ตรวจสอบว่า alert ถูก trigger เมื่อ transaction log ของ database InternetSales เต็ม


