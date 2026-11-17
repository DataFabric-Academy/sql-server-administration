# Module 4: Protecting Data with Encryption and Auditing
## Lab: Using Auditing and Encryption

### Exercise 1: Working with SQL Server Audit

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่
2. เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
3. ในโฟลเดอร์ `D:\Labfiles\Lab04\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
4. ในกล่องโต้ตอบ User Account Control คลิก **Yes** แล้วรอให้สคริปต์ทำงานเสร็จ

#### Task 2: Create a Server Audit
1. เริ่ม SQL Server Management Studio และเชื่อมต่อกับ database engine `DATAFABRIC-SQL-x` โดยใช้
   **Windows authentication**
2. ใน Object Explorer ขยายโหนด **Security** คลิกขวาที่โหนด **Audits** แล้วคลิก **New Audit**
3. ในกล่องโต้ตอบ Create Audit ในช่อง **Audit name** พิมพ์ `activity_audit`
4. ในช่อง **File path** พิมพ์ `D:\Labfiles\Lab04\Starter\Audit` แล้วคลิก **OK**
5. ใน Object Explorer ขยายโหนด **Audits** คลิกขวาที่โหนด `activity_audit` แล้วคลิก **Enable Audit**
6. ในกล่องโต้ตอบ Enable Audit คลิก **Close**

#### Task 3: Create a Server Audit Specification
1. ใน Object Explorer คลิกขวาที่โหนด **Server Audit Specifications** แล้วคลิก **New Server Audit Specification**
2. ในกล่องโต้ตอบ Create Server Audit Specification ในช่อง **Name** พิมพ์ `audit_logins`
3. ในช่อง **Audit** พิมพ์ `activity_audit`
4. ในช่อง **Actions** ในรายการ **Audit Action Type** เลือกค่า **SUCCESSFUL_LOGIN_GROUP** แล้วคลิก **OK**
5. ใน Object Explorer ขยายโหนด **Server Audit Specifications** คลิกขวาที่โหนด `audit_logins` แล้วคลิก
   **Enable Server Audit Specification**
6. ในกล่องโต้ตอบ Enable Server Audit Specification คลิก **Close**
7. ใน Object Explorer ยุบโหนด **Security**

#### Task 4: Create a Database Audit Specification
1. ใน Object Explorer ขยายโหนด **Databases** ขยายโหนด `salesapp1` แล้วขยายโหนด **Security**
2. คลิกขวาที่โหนด **Database Audit Specifications** แล้วคลิก **New Database Audit Specification**
3. ในกล่องโต้ตอบ Create Database Audit Specification ในช่อง **Name** พิมพ์ `employees_change_audit`
   และในช่อง **Audit** พิมพ์ `activity_audit`
4. ในช่อง **Actions** ในรายการ **Audit Action Type** คลิกค่า **INSERT**
5. ในรายการ **Object Class** ในแถวแรก คลิก **OBJECT**
6. ในคอลัมน์ **Object Name** ในแถวแรก คลิกจุดไข่ปลา (…)
7. ในกล่องโต้ตอบ Select Objects ในช่อง **Enter the object names to select (examples)** พิมพ์
   `HR.Employees` แล้วคลิก **OK**
8. ในคอลัมน์ **Principal Name** ในแถวแรก คลิกจุดไข่ปลา (…)
9. ในกล่องโต้ตอบ Select Objects ในช่อง **Enter the object names to select (examples)** พิมพ์ `public`
   แล้วคลิก **OK**
10. ในแถวที่สอง ในรายการ **Audit Action Type** คลิกค่า **UPDATE**
11. ในรายการ **Object Class** ในแถวที่สอง คลิก **OBJECT**
12. ในคอลัมน์ **Object Name** ในแถวที่สอง คลิกจุดไข่ปลา (…)
13. ในหน้าต่าง Select Objects ในช่อง **Enter the object names to select (examples)** พิมพ์
    `HR.Employees` แล้วคลิก **OK**
14. ในคอลัมน์ **Principal Name** ในแถวที่สอง คลิกจุดไข่ปลา (…)
15. ในหน้าต่าง Select Objects ในช่อง **Enter the object names to select (examples)** พิมพ์ `public`
    แล้วคลิก **OK**
16. ในกล่องโต้ตอบ Create Database Audit Specification คลิก **OK**
17. ใน Object Explorer ขยายโหนด **Database Audit Specifications** คลิกขวาที่โหนด
    `employees_change_audit` แล้วคลิก **Enable Database Audit Specification**
18. ในกล่องโต้ตอบ Enable Database Audit Specification คลิก **Close**

#### Task 5: Generate Audited Activity
1. ใน SQL Server Management Studio บนเมนู **File** ชี้ไปที่ **Open** แล้วคลิก **Project/Solution**
2. ในหน้าต่าง Open Project เรียกดูไปยัง `D:\Labfiles\Lab04\Starter\Project` แล้วดับเบิลคลิก
   `Project.ssmssln`
3. ใน Solution Explorer ขยาย **Queries** แล้วดับเบิลคลิก query `Lab Exercise 01 - audit activity.sql`
4. ไฮไลต์โค้ดภายใต้หัวข้อ Task 1 แล้วคลิก **Execute**

#### Task 6: Review Audit Data
1. ภายใต้หัวข้อ Task 2 พิมพ์:
   ```sql
   SELECT * 
   FROM sys.fn_get_audit_file('D:\Labfiles\Lab04\Starter\Audit\*', default, default) 
   WHERE session_id = @@SPID;
   ```
2. ไฮไลต์โค้ดที่คุณพิมพ์ แล้วคลิก **Execute**

#### Task 7: Disable the Audit
1. ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ขยายโหนด **Security** ขยายโหนด **Audits** คลิกขวาที่
   `activity_audit` แล้วคลิก **Disable Audit**
2. ในกล่องโต้ตอบ Disable Audit คลิก **Close**

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะสามารถ:
- สร้าง server audit
- สร้าง server audit specification
- สร้าง database audit specification
- ดึงข้อมูล audit

---

### Exercise 2: Encrypt a Column with Always Encrypted

#### Task 1: Encrypt a Column
1. ใน SQL Server Management Studio ภายใต้ `DATAFABRIC-SQL-x` ภายใต้ **Databases** ภายใต้ `salesapp1`
   ขยายโหนด **Tables** ขยายโหนด **Sales.Customers** แล้วขยายโหนด **Columns**
2. คลิกขวาที่ `phone (nvarchar(24), not null)` แล้วคลิก **Encrypt Column**
3. ในกล่องโต้ตอบ Always Encrypted บนหน้า Introduction คลิก **Next**
4. บนหน้า Column Selection ภายใต้ Sales.Customers เลือกคอลัมน์ `phone`
5. เปลี่ยนค่าของช่อง **Encryption Type** เป็น **Randomized** แล้วคลิก **Next**
6. บนหน้า Master Key Configuration คลิก **Next**
7. บนหน้า Run Settings คลิก **Next**
8. บนหน้า Summary คลิก **Finish**
9. เมื่อกระบวนการเข้ารหัสเสร็จสิ้น คลิก **Close**
10. ใน Object Explorer ภายใต้โหนด `salesapp1.Tables` คลิกขวาที่ `Sales.Customers` แล้วคลิก
    **Select top 1000 rows** สังเกตว่าค่าในคอลัมน์ phone ถูกเข้ารหัส

#### Task 2: View Always Encrypted Data from an Application
1. ใน File Explorer นำทางไปยัง `D:\Labfiles\Lab04\Starter` คลิกขวาที่ `query_encrypted_columns.ps1`
   แล้วคลิก **Run with PowerShell**
2. ตรวจสอบผลลัพธ์ของสคริปต์ สคริปต์แสดงให้เห็นว่าการเปลี่ยนแปลงใน connection string เพื่อเปิดใช้งาน
   property **Column Encryption Setting** ทำให้สามารถถอดรหัสคอลัมน์ Always Encrypted ได้
   สิ่งนี้เป็นไปได้เพราะสคริปต์มีการเข้าถึง column master key ใน local Windows keystore
3. เมื่อคุณตรวจสอบผลลัพธ์เสร็จแล้ว กด Enter เพื่อปิดหน้าต่าง PowerShell

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะสามารถ:
- Implement Always Encrypted

---

### Exercise 3: Encrypt a Database Using TDE

#### Task 1: Create a Service Master Key
1. ใน SQL Server Management Studio ใน Solution Explorer ดับเบิลคลิก query `Lab Exercise 03 - TDE.sql`
2. ไฮไลต์โค้ดภายใต้หัวข้อสำหรับ Task 1 แล้วคลิก **Execute**

#### Task 2: Back Up the Service Master Key
1. แก้ไข query ภายใต้หัวข้อสำหรับ Task 2 ให้อ่านว่า:
   ```sql
   BACKUP MASTER KEY TO FILE = 'D:\Labfiles\Lab04\Starter\Audit\smk.bak' 
       ENCRYPTION BY PASSWORD = 'iD2Z1i85saFyAiK7auzn$';
   ```
2. ไฮไลต์ query ที่คุณแก้ไข แล้วคลิก **Execute**

#### Task 3: Create and Back Up a Server Certificate
1. ไฮไลต์โค้ดภายใต้หัวข้อสำหรับ Task 3 แล้วคลิก **Execute**
2. แก้ไข query ภายใต้หัวข้อสำหรับ Task 4 ให้อ่านว่า:
   ```sql
   BACKUP CERTIFICATE TDE_cert  
   TO FILE = 'D:\Labfiles\Lab04\Starter\Audit\TDE_cert.bak' 
   WITH PRIVATE KEY 
   ( 
       FILE = 'D:\Labfiles\Lab04\Starter\Audit\TDE_cert_pk.bak', 
       ENCRYPTION BY PASSWORD = '*R8vkULA5aKhp3ekGg1o3' 
   );
   GO
   ```
3. ไฮไลต์ query ที่คุณแก้ไข แล้วคลิก **Execute**

#### Task 4: Create a Database Encryption Key and Encrypt the salesapp1 Database
1. แก้ไข query ภายใต้หัวข้อสำหรับ Task 5 ให้อ่านว่า:
   ```sql
   USE salesapp1;
   GO
   CREATE DATABASE ENCRYPTION KEY 
   WITH ALGORITHM = AES_256 
   ENCRYPTION BY SERVER CERTIFICATE TDE_cert;
   GO
   ```
2. ไฮไลต์ query ที่คุณแก้ไข แล้วคลิก **Execute**
3. ไฮไลต์โค้ดภายใต้หัวข้อสำหรับ Task 6 แล้วคลิก **Execute**
4. ไฮไลต์โค้ดภายใต้หัวข้อสำหรับ Task 7 คลิก **Execute** แล้วตรวจสอบผลลัพธ์

#### Task 5: Move the salesapp1 Database
1. ใน Object Explorer ภายใต้โหนด **Databases** คลิกขวาที่ `salesapp1` ชี้ไปที่ **Tasks** แล้วคลิก
   **Detach**
2. ในกล่องโต้ตอบ Detach Database เลือกช่องทำเครื่องหมาย **Drop Connections** แล้วคลิก **OK**
3. ใน Object Explorer ในรายการ **Connect** คลิก **Database Engine**
4. เชื่อมต่อกับ `DATAFABRIC-SQL-x\SQL2` โดยใช้ Windows authentication
5. ใน Object Explorer ภายใต้ instance `DATAFABRIC-SQL-x\SQL2` คลิกขวาที่ **Databases** แล้วคลิก **Attach**
6. ในกล่องโต้ตอบ Attach Databases คลิก **Add**
7. ในกล่องโต้ตอบ Attach Databases นำทางไปยังโฟลเดอร์ `D:\Labfiles\Lab04\Starter\Setupfiles`
   คลิกไฟล์ `salesapp1.mdf` แล้วคลิก **OK**
8. ในกล่องโต้ตอบ Microsoft SQL Server Management Studio สังเกตว่ามีข้อความ error แสดงเพราะ
   certificate ที่ database encryption key ถูกป้องกันด้วยไม่มีอยู่ใน instance `DATAFABRIC-SQL-x\SQL2`
   เนื่องจากสิ่งนี้ ไฟล์ข้อมูลไม่สามารถ attach ได้ คลิก **OK**
9. ในกล่องโต้ตอบ Attach Databases คลิก **Cancel**
10. ใน Solution Explorer ดับเบิลคลิก query `Lab Exercise 03 - move DB.sql`
11. บนเมนู **Query** ชี้ไปที่ **Connection** แล้วคลิก **Change Connection**
12. ในกล่องโต้ตอบ Connect to Database Engine เชื่อมต่อกับ database engine `DATAFABRIC-SQL-x\SQL2`
    โดยใช้ Windows authentication
13. ไฮไลต์โค้ดภายใต้หัวข้อสำหรับ Task 10 แล้วคลิก **Execute** สิ่งนี้สร้าง server master key บน
    `DATAFABRIC-SQL-x\SQL2`
14. ไฮไลต์โค้ดภายใต้หัวข้อสำหรับ Task 11 แล้วคลิก **Execute** สิ่งนี้สร้าง certificate ใน database
    master บน `DATAFABRIC-SQL-x\SQL2` จากไฟล์ backup ที่คุณสร้างไว้ก่อนหน้านี้
15. ใน Object Explorer ภายใต้ instance `DATAFABRIC-SQL-x\SQL2` คลิกขวาที่ **Databases** แล้วคลิก **Attach**
16. ในกล่องโต้ตอบ Attach Databases คลิก **Add**
17. ในกล่องโต้ตอบ Attach Databases นำทางไปยังโฟลเดอร์ `D:\Labfiles\Lab04\Starter\Setupfiles`
    คลิกไฟล์ `salesapp1.mdf` แล้วคลิก **OK**
18. ในกล่องโต้ตอบ Attach Databases คลิก **OK**
19. ไฮไลต์โค้ดภายใต้หัวข้อสำหรับ Task 12 แล้วคลิก **Execute** สิ่งนี้ query ตาราง `Sales.Customers`
    ใน database `salesapp1`
20. ตรวจสอบผลลัพธ์ของ query แล้วปิด SQL Server Management Studio โดยไม่บันทึกไฟล์ใดๆ

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะสามารถ:
- เข้ารหัส database โดยใช้ TDE
- ย้าย database ที่เข้ารหัสไปยัง SQL Server instance อื่น


