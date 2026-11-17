# Module 2: Assigning Server and Database Roles
## Lab: Assigning Server and Database Roles

### Exercise 1: Assigning Server Roles

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab02\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** เมื่อถูกถามเพื่อยืนยันว่าคุณต้องการรันไฟล์คำสั่ง
   และรอให้สคริปต์ทำงานเสร็จ

#### Task 2: Create a Server Role
1. เริ่ม SQL Server Management Studio และเชื่อมต่อกับ database engine `DATAFABRIC-SQL-x` โดยใช้
   **Windows authentication**
2. บนเมนู **File** ชี้ไปที่ **Open** แล้วคลิก **Project/Solution**
3. ในกล่องโต้ตอบ Open Project นำทางไปยัง `D:\Labfiles\Lab02\Starter\Project` คลิก
   `Project.ssmssln` แล้วคลิก **Open**
4. ใน Solution Explorer ขยาย **Queries** แล้วดับเบิลคลิก `Lab Exercise 01 - server roles.sql`
5. ภายใต้หัวข้อสำหรับ Task 1 พิมพ์โค้ดต่อไปนี้:
   ```sql
   CREATE SERVER ROLE database_manager;
   ```
6. ไฮไลต์โค้ดที่คุณพิมพ์ แล้วคลิก **Execute**

#### Task 3: Assign Server-Level Permissions
1. แก้ไขโค้ดภายใต้หัวข้อสำหรับ Task 2 ให้อ่านว่า:
   ```sql
   GRANT ALTER ANY LOGIN TO database_manager;
   GRANT VIEW ANY DATABASE TO database_manager;
   ```
2. ไฮไลต์ query ที่คุณแก้ไข แล้วคลิก **Execute**

#### Task 4: Assign Role Membership
1. ภายใต้หัวข้อสำหรับ Task 3 พิมพ์โค้ดต่อไปนี้:
   ```sql
   ALTER SERVER ROLE database_manager ADD MEMBER [DATAFABRIC\Database_Managers];
   ```
2. ไฮไลต์โค้ดที่คุณพิมพ์ แล้วคลิก **Execute**
3. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** ในตอนท้ายของ exercise นี้ คุณจะได้สร้าง server role `database_manager` มอบสิทธิ์ให้สมาชิก
เพื่อ alter any login และ alter any database และมอบสมาชิกภาพให้กับสมาชิกของ login
`Database_Managers`

---

### Exercise 2: Assigning Fixed Database Roles

#### Task 1: Create a Database User and Assign Fixed Database Roles
1. ใน SQL Server Management Studio ใน Object Explorer ขยาย **Security** ขยาย **Logins** คลิกขวาที่
   `DATAFABRIC\Database_Managers` แล้วคลิก **Properties**
2. ในกล่องโต้ตอบ Login Properties - DATAFABRIC\Database_Managers บนหน้า **User Mapping**
   ในตาราง Users mapped to this login ในแถว database salesapp1 เลือกช่องทำเครื่องหมาย **Map**
3. ในรายการ **Database role membership for: salesapp1** เลือกช่องทำเครื่องหมาย `db_accessadmin` และ
   `db_backupoperator` แล้วคลิก **OK**
4. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** ในตอนท้ายของ exercise นี้ คุณจะได้ map login `Database_Managers` ไปยัง database
`salesapp1` และเพิ่มพวกเขาไปยัง roles `db_backupoperator` และ `db_accessadmin`

---

### Exercise 3: Assigning User-Defined Database Roles

#### Task 1: Create a Database Principal in SSMS
1. ใน SQL Server Management Studio ใน Object Explorer ขยาย **Databases** ขยาย `salesapp1` แล้ว
   ขยาย **Security**
2. คลิกขวาที่ **Users** แล้วคลิก **New User**
3. ในกล่องโต้ตอบ Database User - New บนหน้า General ตรวจสอบว่าช่อง **User type** มีค่า
   **SQL user with login**
4. ในช่อง **User name** พิมพ์ `internetsales_user` ในช่อง **Login name** พิมพ์
   `DATAFABRIC\InternetSales_Users` แล้วคลิก **OK**

#### Task 2: Create a User-Defined Database Role in SSMS
1. ใน Object Explorer ภายใต้ `salesapp1` ภายใต้ **Security** คลิกขวาที่ **Roles** ชี้ไปที่ **New** แล้วคลิก
   **New Database Role**
2. ในกล่องโต้ตอบ Database Role - New บนหน้า General ในช่อง **Role name** พิมพ์ `sales_reader`
   แล้วคลิก **Add**
3. ในกล่องโต้ตอบ Select Database User or Role คลิก **Browse**
4. ในกล่องโต้ตอบ Browse for Objects เลือกช่องทำเครื่องหมาย `[internetsales_user]` แล้วคลิก **OK**
5. ในกล่องโต้ตอบ Select Database User or Role คลิก **OK**
6. ในกล่องโต้ตอบ Database Role - New บนหน้า **Securables** คลิก **Search**
7. ในกล่องโต้ตอบ Add Objects คลิก **Specific objects** แล้วคลิก **OK**
8. ในกล่องโต้ตอบ Select Objects คลิก **Object Types**
9. ในกล่องโต้ตอบ Select Object Types เลือกช่องทำเครื่องหมาย **Schemas** แล้วคลิก **OK**
10. ในกล่องโต้ตอบ Select Objects คลิก **Browse**
11. ในกล่องโต้ตอบ Browse for Objects เลือกช่องทำเครื่องหมาย `[Sales]` แล้วคลิก **OK**
12. ในกล่องโต้ตอบ Select Objects คลิก **OK**
13. ในกล่องโต้ตอบ Database Role - New ในส่วน **Permissions for Sales** บนแท็บ **Explicit** ใน
    แถว **Select** เลือกช่องทำเครื่องหมาย **Grant** แล้วคลิก **OK**

#### Task 3: Create a Database Principal by Using Transact-SQL
1. ใน Solution Explorer ดับเบิลคลิก query `Lab Exercise 03 - database roles.sql`
2. ไฮไลต์โค้ดภายใต้หัวข้อสำหรับ Task 3 แล้วคลิก **Execute**

#### Task 4: Create User-Defined Database Roles by Using Transact-SQL
1. ภายใต้หัวข้อสำหรับ Task 4 พิมพ์โค้ดต่อไปนี้:
   ```sql
   CREATE ROLE production_reader;
   CREATE ROLE sales_order_writer;
   GO
   ```
2. ไฮไลต์โค้ดที่คุณเพิ่งพิมพ์ แล้วคลิก **Execute**

#### Task 5: Grant Permissions to User-Defined Database Roles Using Transact-SQL
1. ภายใต้หัวข้อสำหรับ Task 5 พิมพ์โค้ดต่อไปนี้:
   ```sql
   GRANT SELECT ON SCHEMA::Production TO production_reader;
   GO
   GRANT UPDATE ON Sales.OrderDetails TO sales_order_writer;
   GO
   GRANT UPDATE ON Sales.Orders TO sales_order_writer;
   GO
   ```
2. ไฮไลต์ query ที่คุณพิมพ์ แล้วคลิก **Execute**

#### Task 6: Add a Database Principal to a Role Using Transact-SQL
1. ภายใต้หัวข้อสำหรับ Task 6 แก้ไข query ให้อ่านว่า:
   ```sql
   ALTER ROLE sales_reader ADD MEMBER internetsales_manager;
   ALTER ROLE production_reader ADD MEMBER internetsales_manager;
   ALTER ROLE sales_order_writer ADD MEMBER internetsales_manager;
   GO
   ```
2. ไฮไลต์ query ที่คุณพิมพ์ แล้วคลิก **Execute**
3. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** ในตอนท้ายของ exercise นี้ คุณจะได้สร้าง user-defined database roles และกำหนดให้กับ
database principals

---

### Exercise 4: Verifying Security

#### Task 1: Test IT Support Permissions
1. ย่อ SQL Server Management Studio
2. บน taskbar คลิกขวาที่ไอคอน **SQL Server Management Studio** แล้วคลิก **Run as different user**
3. ในกล่องโต้ตอบ Windows Security:
   - **User name:** `DATAFABRIC\anthonyfrizzell`
   - **Password:** `Pa$$w0rd`
   แล้วคลิก **OK**
4. รอให้ SQL Server Management Studio เปิดขึ้นมา
5. ในกล่องโต้ตอบ Connect to Server:
   - **Server name:** `DATAFABRIC-SQL-x`
   - **Authentication:** เลือก **Windows Authentication**
   แล้วคลิก **Connect**
6. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
7. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อยืนยันตัวตนของคุณ แล้วคลิก **Execute**:
   ```sql
   SELECT SUSER_NAME();
   ```
   สังเกตว่า SQL Server ระบุ Windows group logins โดยใช้บัญชีผู้ใช้แต่ละราย แม้ว่าจะไม่มี
   individual login สำหรับผู้ใช้รายนั้น `DATAFABRIC\AnthonyFrizzell` เป็นสมาชิกของ global
   group `DATAFABRIC\IT_Support` ซึ่งเป็นสมาชิกของ domain local group
   `DATAFABRIC\Database_Managers` ที่คุณสร้าง login
8. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อเปลี่ยนรหัสผ่านของ login
   `Marketing_Application` แล้วคลิก **Execute**:
   ```sql
   ALTER LOGIN Marketing_Application WITH PASSWORD = 'NewPa$$w0rd';
   ```
9. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อปิดใช้งาน login
   `DATAFABRIC\WebAplicationSvc` แล้วคลิก **Execute**:
   ```sql
   ALTER LOGIN [DATAFABRIC\WebApplicationSvc] DISABLE;
   ```
10. ปิดหน้าต่าง SQL Server Management Studio ที่เปิดด้วย `DATAFABRIC\anthonyfrizzell`
11. ใน SQL Server Management Studio เดิม (ที่เปิดด้วย `DATAFABRIC\Student`) ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ภายใต้ **Security**
   คลิกขวาที่ **Logins** แล้วคลิก **Refresh**
12. ภายใต้ **Logins** คลิกขวาที่ `DATAFABRIC\WebApplicationSvc` แล้วคลิก **Properties**
13. ในกล่องโต้ตอบ Login Properties - DATAFABRIC\WebApplicationSvc บนหน้า **Status** คลิก
    **Enabled** แล้วคลิก **OK** เพื่อเปิดใช้งาน login อีกครั้ง

#### Task 2: Test Sales Employee Permissions
1. บน taskbar คลิกขวาที่ไอคอน **SQL Server Management Studio** แล้วคลิก **Run as different user**
2. ในกล่องโต้ตอบ Windows Security:
   - **User name:** `DATAFABRIC\dandrayton`
   - **Password:** `Pa$$w0rd`
   แล้วคลิก **OK**
   ผู้ใช้รายนี้เป็นสมาชิกของ global group `DATAFABRIC\Sales_NorthAmerica` ซึ่งเป็นสมาชิกของ
   domain group `DATAFABRIC\InternetSales_Users`
3. รอให้ SQL Server Management Studio เปิดขึ้นมา
4. ในกล่องโต้ตอบ Connect to Server:
   - **Server name:** `DATAFABRIC-SQL-x`
   - **Authentication:** เลือก **Windows Authentication**
   แล้วคลิก **Connect**
5. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
6. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อ query ตาราง `Sales.Orders` ใน
   database `salesapp1` แล้วคลิก **Execute**:
   ```sql
   SELECT TOP (10) * FROM salesapp1.Sales.Orders;
   ```
7. ตรวจสอบว่าผู้ใช้สามารถ query ตาราง `Sales.Orders` ได้
8. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่ออัปเดตตาราง `Sales.Orders` ใน
   database `salesapp1` แล้วคลิก **Execute**:
   ```sql
   UPDATE salesapp1.Sales.Orders SET shippeddate = getdate() WHERE orderid = 10257;
   ```
9. ตรวจสอบว่าผู้ใช้ไม่มีสิทธิ์ UPDATE บนตาราง `Sales.Orders`
10. ปิดหน้าต่าง SQL Server Management Studio ที่เปิดด้วย `DATAFABRIC\dandrayton`

#### Task 3: Test Sales Manager Permissions
1. บน taskbar คลิกขวาที่ไอคอน **SQL Server Management Studio** แล้วคลิก **Run as different user**
2. ในกล่องโต้ตอบ Windows Security:
   - **User name:** `DATAFABRIC\deannaball`
   - **Password:** `Pa$$w0rd`
   แล้วคลิก **OK**
   ผู้ใช้รายนี้เป็นสมาชิกของ global group `DATAFABRIC\Sales_Managers`
   ซึ่งเป็นสมาชิกของ domain group `DATAFABRIC\InternetSales_Managers`
3. รอให้ SQL Server Management Studio เปิดขึ้นมา
4. ในกล่องโต้ตอบ Connect to Server:
   - **Server name:** `DATAFABRIC-SQL-x`
   - **Authentication:** เลือก **Windows Authentication**
   แล้วคลิก **Connect**
5. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
6. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อ query ตาราง `Sales.Orders` ใน
   database `salesapp1` แล้วคลิก **Execute**:
   ```sql
   SELECT TOP (10) * FROM salesapp1.Sales.Orders;
   ```
7. ตรวจสอบว่าผู้ใช้สามารถ query ตาราง `Sales.Orders` ได้
8. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อ query ตาราง
   `Production.Suppliers` ใน database `salesapp1` แล้วคลิก **Execute**:
   ```sql
   SELECT TOP (10) * FROM salesapp1.Production.Suppliers;
   ```
9. ตรวจสอบว่าผู้ใช้สามารถ query ตาราง `Production.Suppliers` ได้
10. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่ออัปเดตตาราง `Sales.Orders` ใน
   database `salesapp1` แล้วคลิก **Execute**:
   ```sql
   UPDATE salesapp1.Sales.Orders SET shippeddate = getdate() WHERE orderid = 10257;
   ```
11. ตรวจสอบว่าผู้ใช้มีสิทธิ์ UPDATE บนตาราง `Sales.Orders`
12. ปิดหน้าต่าง SQL Server Management Studio ที่เปิดด้วย `DATAFABRIC\deannaball`
13. ปิด SQL Server Management Studio เดิม (ที่เปิดด้วย `DATAFABRIC\Student`) โดยไม่บันทึกการเปลี่ยนแปลงใดๆ

**Results:** ในตอนท้ายของ exercise นี้ คุณจะได้ตรวจสอบการตั้งค่าความปลอดภัยใหม่ของคุณ


