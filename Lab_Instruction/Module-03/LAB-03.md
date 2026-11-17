# Module 3: Authorizing Users to Access Resources
## Lab: Authorizing Users to Access Resources

### Exercise 1: Granting, Denying, and Revoking Permissions on Objects

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab03\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** เมื่อถูกถามเพื่อยืนยันว่าคุณต้องการรันไฟล์คำสั่ง
   และรอให้สคริปต์ทำงานเสร็จ

#### Task 2: Grant Permissions on Objects
1. ตรวจสอบความต้องการด้านความปลอดภัยที่ให้มาใน scenario สำหรับ lab นี้
2. กำหนดสิทธิ์ที่ควรกำหนดในระดับ object
3. เริ่ม SQL Server Management Studio และเชื่อมต่อกับ database engine `DATAFABRIC-SQL-x` โดยใช้
   **Windows authentication**
4. บนเมนู **File** ชี้ไปที่ **New** แล้วคลิก **Query with Current Connection**
5. ในหน้าต่าง query ใหม่ พิมพ์โค้ดต่อไปนี้เพื่อมอบสิทธิ์สำหรับ e-commerce application เพื่ออ่าน
   ข้อมูลจาก view `Products.vProductCatalog` และแทรกแถวในตาราง `Sales.SalesOrderHeader` และ
   `Sales.SalesOrderDetail`:
   ```sql
   USE InternetSales;
   GO
   GRANT SELECT ON Products.vProductCatalog TO WebApplicationSvc;
   GRANT INSERT ON Sales.SalesOrderHeader TO WebApplicationSvc;
   GRANT INSERT ON Sales.SalesOrderDetail TO WebApplicationSvc;
   GO
   ```
6. ด้านล่างโค้ดที่คุณเพิ่งป้อน พิมพ์โค้ดต่อไปนี้เพื่อมอบสิทธิ์สำหรับพนักงานขายและผู้จัดการทั้งหมดเพื่ออ่าน
   ข้อมูลจากตาราง `Customer`:
   ```sql
   GRANT SELECT ON Customers.Customer TO Database_Managers;
   GRANT SELECT ON Customers.Customer TO InternetSales_Managers;
   GRANT SELECT ON Customers.Customer TO InternetSales_Users;
   GO
   ```
7. บนแถบเครื่องมือ คลิก **Execute**
8. ย่อ SQL Server Management Studio
9. บน taskbar คลิกขวาที่ไอคอน **SQL Server Management Studio** แล้วคลิก **Run as different user**
10. ในกล่องโต้ตอบ Windows Security:
    - **User name:** `DATAFABRIC\anthonyfrizzell`
    - **Password:** `Pa$$w0rd`
    แล้วคลิก **OK**
    ผู้ใช้รายนี้เป็นสมาชิกของกลุ่ม IT_Support
11. รอให้ SQL Server Management Studio เปิดขึ้นมา
12. ในกล่องโต้ตอบ Connect to Server:
    - **Server name:** `DATAFABRIC-SQL-x`
    - **Authentication:** เลือก **Windows Authentication**
    แล้วคลิก **Connect**
13. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
14. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อยืนยันตัวตนของคุณ แล้วคลิก **Execute**:
    ```sql
    SELECT suser_name();
    ```
15. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อตรวจสอบว่า Anthony สามารถเข้าถึง
    ตาราง `Customer` ผ่านการเป็นสมาชิกของ global group IT_Support และด้วยเหตุนี้ local group
    Database Managers และ SQL Server login แล้วคลิก **Execute**:
    ```sql
    USE InternetSales;
    SELECT TOP 5 FirstName, LastName FROM Customers.Customer;
    ```

#### Task 3: Deny Permissions on Objects
1. คุณตระหนักว่า Database_Managers ไม่จำเป็นต้องเข้าถึงข้อมูลลูกค้า ดังนั้นตัดสินใจ deny การเข้าถึง
2. ใน SQL Server Management Studio ในหน้าต่าง query ด้านล่างโค้ดที่มีอยู่ พิมพ์โค้ดต่อไปนี้เพื่อ deny
   ผู้ใช้ Database_Managers สิทธิ์ SELECT บนตาราง `Customer`:
   ```sql
   DENY SELECT ON Customers.Customer TO Database_Managers;
   GO
   ```
3. เลือกโค้ดที่คุณเพิ่งพิมพ์ แล้วคลิก **Execute**
4. ใน SQL Server Management Studio ที่เปิดด้วย `DATAFABRIC\anthonyfrizzell` ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อตรวจสอบว่า Anthony ถูก deny
   การเข้าถึงตาราง `Customer` แล้วคลิก **Execute**:
   ```sql
   SELECT TOP 5 FirstName, LastName FROM Customers.Customer;
   ```

#### Task 4: Revoke Permissions on Objects
1. คุณตระหนักว่าแม้ว่า Database_Managers จะไม่จำเป็นต้องเข้าถึงข้อมูลลูกค้า แต่ Anthony เป็นสมาชิก
   ของกลุ่มอื่นและด้วยเหตุนี้จึงจำเป็นต้องเข้าถึงตาราง คุณตัดสินใจ revoke สิทธิ์ deny ที่คุณได้
   implement ไว้ ทำให้ Anthony สืบทอดสิทธิ์จากการเป็นสมาชิกของกลุ่มอื่น
2. ใน SQL Server Management Studio ในหน้าต่าง query ด้านล่างโค้ดที่มีอยู่ พิมพ์โค้ดต่อไปนี้เพื่อ revoke
   ผู้ใช้ Database_Managers สิทธิ์ SELECT บนตาราง `Customer`:
   ```sql
   REVOKE SELECT ON Customers.Customer TO Database_Managers;
   GO
   ```
3. เลือกโค้ดที่คุณเพิ่งพิมพ์ แล้วคลิก **Execute**
4. ใน SQL Server Management Studio ที่เปิดด้วย `DATAFABRIC\anthonyfrizzell` ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อตรวจสอบว่า Anthony สามารถเข้าถึง
   ตาราง `Customer` ผ่านการเป็นสมาชิกของ global group Sales_Managers และด้วยเหตุนี้ local group
   InternetSales_Managers และ SQL Server login แล้วคลิก **Execute**:
   ```sql
   SELECT TOP 5 FirstName, LastName FROM Customers.Customer;
   ```
5. ปิดหน้าต่าง SQL Server Management Studio ที่เปิดด้วย `DATAFABRIC\anthonyfrizzell`
6. ใน SQL Server Management Studio เดิม (ที่เปิดด้วย `DATAFABRIC\Student`) บนเมนู **File** คลิก **Close**
7. ในกล่องโต้ตอบ Microsoft SQL Server Management Studio คลิก **No**
8. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะได้กำหนดสิทธิ์ระดับ object ที่ต้องการ

---

### Exercise 2: Granting EXECUTE Permissions on Code

#### Task 1: Grant EXECUTE Permission
1. ตรวจสอบความต้องการด้านความปลอดภัยที่ให้มาใน scenario สำหรับ lab นี้
2. กำหนดสิทธิ์ที่ควรกำหนดบน code
3. บนเมนู **File** ชี้ไปที่ **New** แล้วคลิก **Query with Current Connection**
4. ในหน้าต่าง query ใหม่ พิมพ์โค้ดต่อไปนี้เพื่อมอบสิทธิ์สำหรับผู้จัดการขายเพื่อรัน stored procedure
   `ChangeProductPrice` แล้วคลิก **Execute**:
   ```sql
   USE InternetSales;
   GO
   GRANT EXECUTE ON Products.ChangeProductPrice TO InternetSales_Managers;
   GO
   ```

#### Task 2: Test the Permission
1. บน taskbar คลิกขวาที่ไอคอน **SQL Server Management Studio** แล้วคลิก **Run as different user**
2. ในกล่องโต้ตอบ Windows Security:
   - **User name:** `DATAFABRIC\deannaball`
   - **Password:** `Pa$$w0rd`
   แล้วคลิก **OK**
   ผู้ใช้รายนี้เป็นสมาชิกของกลุ่ม IT_Support
3. รอให้ SQL Server Management Studio เปิดขึ้นมา
4. ในกล่องโต้ตอบ Connect to Server:
   - **Server name:** `DATAFABRIC-SQL-x`
   - **Authentication:** เลือก **Windows Authentication**
   แล้วคลิก **Connect**
5. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
6. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อตรวจสอบว่า Deanna สามารถรัน
   stored procedure ได้ แล้วคลิก **Execute**:
   ```sql
   USE InternetSales;
   EXECUTE Products.ChangeProductPrice 1, 2;
   ```
7. ปิดหน้าต่าง SQL Server Management Studio ที่เปิดด้วย `DATAFABRIC\deannaball`
8. ใน SQL Server Management Studio เดิม (ที่เปิดด้วย `DATAFABRIC\Student`) ในหน้าต่าง query ด้านล่างโค้ดที่มีอยู่ พิมพ์โค้ดต่อไปนี้เพื่อตรวจสอบว่า
   stored procedure อัปเดตราคา:
   ```sql
   SELECT ListPrice from Products.Product WHERE ProductID<10;
   ```
9. เลือกโค้ดที่คุณเพิ่งพิมพ์ แล้วคลิก **Execute**
10. บนเมนู **File** คลิก **Close**
8. ในกล่องโต้ตอบ Microsoft SQL Server Management Studio คลิก **No**
9. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะได้กำหนดสิทธิ์ EXECUTE ที่ต้องการบน stored procedures

---

### Exercise 3: Granting Permissions at the Schema Level

#### Task 1: Grant Permission on a Schema
1. ตรวจสอบความต้องการด้านความปลอดภัยที่ให้มาใน scenario สำหรับ lab นี้
2. กำหนดสิทธิ์ที่ควรกำหนดในระดับ schema
3. บนเมนู **File** ชี้ไปที่ **New** แล้วคลิก **Query with Current Connection**
4. ในหน้าต่าง query ใหม่ พิมพ์โค้ดต่อไปนี้เพื่อมอบสิทธิ์สำหรับผู้จัดการขายเพื่อ insert และ update ข้อมูลใน
   schema `Sales` และสำหรับพนักงานขายและผู้จัดการเพื่ออ่านข้อมูลใน schema `Sales`:
   ```sql
   USE InternetSales;
   GO
   GRANT INSERT, UPDATE ON SCHEMA::Sales TO InternetSales_Managers;
   GRANT SELECT ON Schema::Sales TO InternetSales_Managers;
   GRANT SELECT ON Schema::Sales TO InternetSales_Users;
   GO
   ```
5. บนแถบเครื่องมือ คลิก **Execute**

#### Task 2: Test the Permission
1. บน taskbar คลิกขวาที่ไอคอน **SQL Server Management Studio** แล้วคลิก **Run as different user**
2. ในกล่องโต้ตอบ Windows Security:
   - **User name:** `DATAFABRIC\anthonyfrizzell`
   - **Password:** `Pa$$w0rd`
   แล้วคลิก **OK**
   ผู้ใช้รายนี้เป็นสมาชิกของกลุ่ม Sales_Managers
3. รอให้ SQL Server Management Studio เปิดขึ้นมา
4. ในกล่องโต้ตอบ Connect to Server:
   - **Server name:** `DATAFABRIC-SQL-x`
   - **Authentication:** เลือก **Windows Authentication**
   แล้วคลิก **Connect**
5. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
6. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อตรวจสอบว่า Anthony สามารถเข้าถึง
   และอัปเดตข้อมูลขาย แล้วคลิก **Execute**:
   ```sql
   USE InternetSales;
   SELECT TOP 5 SalesOrderID, CustomerID FROM Sales.SalesOrderHeader;
   UPDATE Sales.SalesOrderHeader SET CustomerID=28389 WHERE SalesOrderID=43697;
   SELECT TOP 5 SalesOrderID, CustomerID FROM Sales.SalesOrderHeader;
   ```
7. ปิดหน้าต่าง SQL Server Management Studio ที่เปิดด้วย `DATAFABRIC\anthonyfrizzell`
8. ใน SQL Server Management Studio เดิม (ที่เปิดด้วย `DATAFABRIC\Student`) บนเมนู **File** คลิก **Close**
9. ในกล่องโต้ตอบ Microsoft SQL Server Management Studio คลิก **No**
10. บนเมนู **File** คลิก **Exit**
11. ในกล่องโต้ตอบ Microsoft SQL Server Management Studio คลิก **No**

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะได้กำหนดสิทธิ์ระดับ schema ที่ต้องการ


