# Module 1: SQL Server Security
## Lab: Authenticating Users

### Exercise 1: Create Logins

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab01\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** และรอให้สคริปต์ทำงานเสร็จ

#### Task 2: Verify the Authentication Mode
1. เริ่ม SQL Server Management Studio และเชื่อมต่อกับ database engine `DATAFABRIC-SQL-x` โดยใช้
   **Windows authentication**
2. ใน Object Explorer คลิกขวาที่ instance `DATAFABRIC-SQL-x` แล้วคลิก **Properties**
3. ในกล่องโต้ตอบ Server Properties - DATAFABRIC-SQL-x บนหน้า **Security** ตรวจสอบว่าเลือก
   **SQL Server and Windows Authentication mode** แล้วคลิก **OK**

#### Task 3: Create Logins Based on Windows Authentication
1. ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ขยาย **Security** และขยาย **Logins** เพื่อดู
   logins ที่มีอยู่ใน instance
2. คลิกขวาที่ **Logins** แล้วคลิก **New Login**
3. ในกล่องโต้ตอบ Login - New บนหน้า General ในช่อง **Login name** พิมพ์
   `DATAFABRIC\WebApplicationSvc`
4. ตรวจสอบว่าเลือก **Windows authentication**
5. ในรายการ **Default database** คลิก **AdventureWorks** แล้วคลิก **OK**
6. ใน Object Explorer คลิกขวาที่ **Logins** แล้วคลิก **New Login**
7. ในกล่องโต้ตอบ Login - New บนหน้า General คลิก **Search**
8. ในกล่องโต้ตอบ Select User or Group คลิก **Object Types**
9. ในกล่องโต้ตอบ Object Types เลือก **Groups** แล้วคลิก **OK**
10. ในกล่องโต้ตอบ Select User or Group คลิก **Locations**
11. ในกล่องโต้ตอบ Locations ขยาย **Entire Directory** คลิก **datafabric.local** แล้วคลิก **OK**
12. ในกล่องโต้ตอบ Select User, Service Account, or Group ในช่อง **Enter the object name to select**
    พิมพ์ `IT_Support` คลิก **Check Names** แล้วคลิก **OK**
13. ในกล่องโต้ตอบ Login - New ตรวจสอบว่าเลือก **Windows authentication**
14. ในรายการ **Default database** คลิก **AdventureWorks** แล้วคลิก **OK**

#### Task 4: Create Logins Based on SQL Server Authentication
1. คลิกขวาที่ **Logins** แล้วคลิก **New Login**
2. ในกล่องโต้ตอบ Login - New บนหน้า General ในช่อง **Login name** พิมพ์ `SalesSupport`
3. คลิก **SQL Server authentication** และในช่อง **Password** และ **Confirm Password** พิมพ์
   `Pa$$w0rd`
4. ยืนยันว่าเลือก **Enforce password policy** ล้างช่องทำเครื่องหมาย **Enforce password expiration**
    ช่องทำเครื่องหมาย **User must change password at next login** จะถูกล้างโดยอัตโนมัติ
5. ในรายการ **Default database** คลิก **AdventureWorks** แล้วคลิก **OK**
6. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจาก exercise นี้ คุณควรได้ตรวจสอบ authentication modes ที่รองรับโดย instance
DATAFABRIC-SQL-x และสร้าง logins สามรายการ

---

### Exercise 2: Create Database Users

#### Task 1: Use Automatic User Creation and Mapping
1. ใน SQL Server Management Studio ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ภายใต้ **Security**
   ภายใต้ **Logins** คลิกขวาที่ `DATAFABRIC\WebApplicationSvc` แล้วคลิก **Properties**
2. ในกล่องโต้ตอบ Login Properties - DATAFABRIC\WebApplicationSvc บนหน้า **User Mapping** ใน
   ส่วน **Users mapped to this login** ในแถว database AdventureWorks เลือกช่องทำเครื่องหมาย **Map**
   แล้วคลิก **OK**
3. ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ขยาย **Databases** ขยาย **AdventureWorks** ขยาย
   **Security** แล้วขยาย **Users** สังเกตว่ามี user ชื่อ `DATAFABRIC\WebApplicationSvc` ถูกสร้างใน database

#### Task 2: Create a User and Map It to a Login
1. ใน database AdventureWorks ภายใต้ **Security** คลิกขวาที่ **Users** แล้วคลิก **New User**
2. ในกล่องโต้ตอบ Database User - New บนหน้า General ตรวจสอบว่าเลือก **SQL user with login**
3. ในช่อง **User name** พิมพ์ `ServiceUser`
4. ในช่อง **Login name** พิมพ์ `SalesSupport` แล้วคลิก **OK**
5. ภายใต้ `DATAFABRIC-SQL-x` ภายใต้ **Security** ภายใต้ **Logins** คลิกขวาที่ `SalesSupport` แล้วคลิก
   **Properties**
6. ในกล่องโต้ตอบ Login Properties - SalesSupport บนหน้า **User Mapping** ตรวจสอบว่า login
   ถูก map ไปยัง user ServiceUser ใน AdventureWorks และ default schema คือ dbo แล้วคลิก **OK**

#### Task 3: Create a User Using Transact-SQL
1. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
2. ในหน้าต่าง query พิมพ์ Transact-SQL statement ต่อไปนี้:
   ```sql
   USE AdventureWorks;
   GO
   CREATE USER [ITSupport] FOR LOGIN [DATAFABRIC\IT_Support] WITH DEFAULT_SCHEMA=[dbo]
   GO
   ```
3. คลิก **Execute**
4. ใน Object Explorer ใน database AdventureWorks ภายใต้ **Security** คลิกขวาที่ **Users** แล้วคลิก
   **Refresh** ตรวจสอบว่า user **ITSupport** ปรากฏขึ้น

**Results:** ในตอนท้ายของ exercise นี้ คุณจะได้สร้าง database users สามรายการและ map พวกเขาไปยัง
logins ที่คุณสร้างใน exercise ก่อนหน้า

---

### Exercise 3: Correct Application Login Issues

#### Task 1: Carry Out an Initial Test
1. ใน SQL Server Management Studio คลิก **File** → **Connect Object Explorer**
2. ในกล่องโต้ตอบ Connect to Server:
   - **Server name:** `DATAFABRIC-SQL-x`
   - **Authentication:** เลือก **SQL Server Authentication**
   - **Login:** `LegacySalesLogin`
   - **Password:** `t0ps3cr3t`
   แล้วคลิก **Connect**
3. สังเกตว่าข้อความ error ที่แสดงเป็นแบบทั่วไป รายงานว่า login ล้มเหลวแต่ไม่ให้
   รายละเอียดเพิ่มเติม
4. ใน SQL Server Management Studio ใน Object Explorer ขยาย **Management** ขยาย **SQL Server
   Logs** แล้วดับเบิลคลิกไฟล์ log ที่ชื่อขึ้นต้นด้วย Current
5. ในกล่องโต้ตอบ Log File Viewer - DATAFABRIC-SQL-x ในบานหน้าต่างด้านขวา มองหา log entry
   ด้านบนสุดที่ขึ้นต้นด้วย `Login failed for user 'LegacySalesLogin'` ข้อความ error ระบุว่ามี
   ปัญหาในการประเมินรหัสผ่านของ login
6. สังเกตว่าในบรรทัดถัดไปในไฟล์ log มี error number ต่อไปนี้:
   `Error: 18456, Severity: 14, State: 7`
   เอกสารสำหรับ error 18456 ระบุว่า State value ของ 7 เกิดจาก:
   Login ถูกปิดใช้งาน และรหัสผ่านไม่ถูกต้อง
7. ในกล่องโต้ตอบ Log File Viewer - DATAFABRIC-SQL-x คลิก **Close**
   Login ไม่สามารถเชื่อมต่อได้เพราะบัญชีถูกปิดใช้งาน และมีการใช้รหัสผ่านผิด

#### Task 2: Enable the Login
1. ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ภายใต้ **Security** ภายใต้ **Logins** คลิกขวาที่
   `LegacySalesLogin` แล้วคลิก **Properties**
2. ในกล่องโต้ตอบ Login Properties - LegacySalesLogin บนหน้า **Status** คลิก **Enabled** แล้วคลิก
   **OK**
3. ใน SQL Server Management Studio คลิก **File** → **Connect Object Explorer**
4. ในกล่องโต้ตอบ Connect to Server:
   - **Server name:** `DATAFABRIC-SQL-x`
   - **Authentication:** เลือก **SQL Server Authentication**
   - **Login:** `LegacySalesLogin`
   - **Password:** `t0ps3cr3t`
   แล้วคลิก **Connect**
5. สังเกตว่าข้อความ error ที่แสดงเป็นแบบทั่วไป รายงานว่า login ล้มเหลวแต่ไม่ให้
   รายละเอียดเพิ่มเติม
6. ใน SQL Server Management Studio ใน Object Explorer ภายใต้ **Management** ภายใต้ **SQL Server
   Logs** ดับเบิลคลิกไฟล์ log ที่ชื่อขึ้นต้นด้วย **Current**
7. ในกล่องโต้ตอบ Log File Viewer - DATAFABRIC-SQL-x ในบานหน้าต่างด้านขวา มองหา log entry
   ด้านบนสุดที่ขึ้นต้นด้วย `Login failed for user 'LegacySalesLogin'` อ่านส่วนที่เหลือของ entry
   เพื่อระบุสาเหตุของ login failure สังเกตว่า login ล้มเหลวเพราะรหัสผ่านไม่ถูกต้อง
8. ในกล่องโต้ตอบ Log File Viewer - DATAFABRIC-SQL-x คลิก **Close**

#### Task 3: Change the Login Password
1. ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ภายใต้ **Security** ภายใต้ **Logins** คลิกขวาที่
   `LegacySalesLogin` แล้วคลิก **Properties**
2. ในกล่องโต้ตอบ Login Properties - LegacySalesLogin บนหน้า **General** ในช่อง **Password** และ
   **Confirm password** พิมพ์ `t0ps3cr3t` แล้วคลิก **OK**
3. ใน SQL Server Management Studio คลิก **File** → **Connect Object Explorer**
4. ในกล่องโต้ตอบ Connect to Server:
   - **Server name:** `DATAFABRIC-SQL-x`
   - **Authentication:** เลือก **SQL Server Authentication**
   - **Login:** `LegacySalesLogin`
   - **Password:** `t0ps3cr3t`
   แล้วคลิก **Connect**
5. สังเกตว่าข้อความ error ระบุว่าไม่สามารถเปิด default database ได้

#### Task 4: Change the Default Database
1. ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ภายใต้ **Security** ภายใต้ **Logins** คลิกขวาที่
   `LegacySalesLogin` แล้วคลิก **Properties**
2. ในกล่องโต้ตอบ Login Properties - LegacySalesLogin บนหน้า **General** ในรายการ **Default
   database** คลิก **AdventureWorks**
3. บนหน้า **User Mapping** ในส่วน **Users mapped to this login** บนแถวสำหรับ database
   AdventureWorks เลือกช่องทำเครื่องหมาย **Map** แล้วคลิก **OK**
4. ใน SQL Server Management Studio คลิก **File** → **Connect Object Explorer**
5. ในกล่องโต้ตอบ Connect to Server:
   - **Server name:** `DATAFABRIC-SQL-x`
   - **Authentication:** เลือก **SQL Server Authentication**
   - **Login:** `LegacySalesLogin`
   - **Password:** `t0ps3cr3t`
   แล้วคลิก **Connect**
6. สังเกตว่าการพยายาม login สำเร็จ
7. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจากเสร็จสิ้น lab นี้ คุณจะสามารถ:
- แก้ไขปัญหา application login issues

---

### Exercise 4: Configure Security for Restored Databases

#### Task 1: Verify Database Users
- ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ภายใต้ **Databases** ขยาย **InternetSales** ขยาย **Security**
  ขยาย **Users** และสังเกตว่า database users ที่มีชื่อต่อไปนี้มีอยู่ใน database:
  - `DATAFABRIC\WebApplicationSvc`
  - `InternetSalesApplication`

#### Task 2: Run the Orphaned Users Report
1. บนแถบเครื่องมือ คลิก **New Query**
2. ใน query pane พิมพ์คำสั่งต่อไปนี้:
   ```sql
   USE InternetSales
   EXEC sp_change_users_login 'Report';
   GO
   ```
3. เลือก query ที่คุณพิมพ์ แล้วคลิก **Execute**
4. User `InternetSalesApplication` ถูกรายงานว่าเป็น orphaned

#### Task 3: Repair the Orphaned User
1. บนแถบเครื่องมือ คลิก **New Query**
2. ใน query pane พิมพ์คำสั่งต่อไปนี้:
   ```sql
   USE InternetSales
   EXEC sp_change_users_login 'Auto_Fix', 'InternetSalesApplication', NULL, NULL
   GO
   ```
3. เลือก query ที่คุณพิมพ์ แล้วคลิก **Execute** ในผลลัพธ์ของ query reports สังเกตว่า
   orphaned user หนึ่งรายการถูกแก้ไขโดยการอัปเดต
4. บนแถบเครื่องมือ คลิก **New Query**
5. ใน query pane พิมพ์คำสั่งต่อไปนี้:
   ```sql
   USE InternetSales
   EXEC sp_change_users_login 'Report';
   GO
   ```
6. เลือก query ที่คุณพิมพ์ แล้วคลิก **Execute** สังเกตว่าไม่มี orphaned users ถูกรายงาน
7. ปิด SQL Server Management Studio โดยไม่บันทึกการเปลี่ยนแปลงใดๆ

**Results:** ในตอนท้ายของ exercise นี้ logins `DATAFABRIC\WebApplicationSvc` และ
`InternetSalesApplication` จะสามารถเข้าถึง database InternetSales ได้


