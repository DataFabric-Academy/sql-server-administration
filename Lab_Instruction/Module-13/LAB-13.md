# Module 13: Monitoring SQL Server
## Lab: Using Query Store for Performance Monitoring

### Exercise 1: Enable and Configure Query Store

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab13\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** แล้วรอให้สคริปต์ทำงานเสร็จ

#### Task 2: Enable Query Store for AdventureWorks Database
1. เริ่ม SQL Server Management Studio แล้วเชื่อมต่อกับ database engine instance `DATAFABRIC-SQL-x` โดยใช้
   Windows authentication
2. ใน Object Explorer ขยาย **Databases** คลิกขวาที่ `AdventureWorks` แล้วคลิก **Properties**
3. ในกล่องโต้ตอบ Database Properties - AdventureWorks ในบานหน้าต่างด้านซ้าย คลิก **Query Store**
4. ในส่วน **Operation Mode (Requested)** ตรวจสอบว่าค่าเป็น **Off** (Query Store ยังไม่ได้เปิดใช้งาน)
5. ในรายการ **Operation Mode (Requested)** คลิก **Read Write**
6. ในส่วน **Data Flush Interval (Minutes)** ตรวจสอบว่าค่าคือ `15` (ค่าเริ่มต้น)
7. ในส่วน **Statistics Collection Interval** ตรวจสอบว่าค่าคือ `60` (ค่าเริ่มต้น)
8. ในส่วน **Max Size (MB)** ตรวจสอบว่าค่าคือ `100` (ค่าเริ่มต้น)
9. ในส่วน **Query Store Capture Mode** ตรวจสอบว่าค่าคือ **All** (ค่าเริ่มต้น)
10. ในส่วน **Size Based Cleanup Mode** ตรวจสอบว่าค่าคือ **Auto** (ค่าเริ่มต้น)
11. ในส่วน **Stale Query Threshold (Days)** ตรวจสอบว่าค่าคือ `30` (ค่าเริ่มต้น)
12. คลิก **OK** เพื่อเปิดใช้งาน Query Store
13. รอสักครู่แล้วคลิกขวาที่ `AdventureWorks` อีกครั้ง แล้วคลิก **Properties**
14. ในกล่องโต้ตอบ Database Properties - AdventureWorks คลิก **Query Store**
15. ตรวจสอบว่า **Operation Mode (Actual)** แสดงเป็น **Read Write** ซึ่งหมายความว่า Query Store เปิดใช้งานแล้ว
16. คลิก **Cancel** เพื่อปิดกล่องโต้ตอบ

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะได้เปิดใช้งาน Query Store สำหรับ database AdventureWorks

---

### Exercise 2: Analyze Query Performance with Query Store

#### Task 1: Run Sample Workload
1. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
2. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อรัน workload ที่จะสร้างข้อมูลใน Query Store:
   ```sql
   USE AdventureWorks;
   GO
   
   -- Run multiple queries to generate Query Store data
   SELECT TOP 10 * FROM Sales.SalesOrderHeader 
   WHERE OrderDate BETWEEN '2011-01-01' AND '2011-12-31';
   GO
   
   SELECT COUNT(*) FROM Sales.SalesOrderDetail 
   WHERE UnitPrice > 100;
   GO
   
   SELECT p.Name, SUM(sod.LineTotal) AS TotalSales
   FROM Production.Product p
   INNER JOIN Sales.SalesOrderDetail sod ON p.ProductID = sod.ProductID
   GROUP BY p.Name
   ORDER BY TotalSales DESC;
   GO
   
   SELECT c.FirstName, c.LastName, COUNT(soh.SalesOrderID) AS OrderCount
   FROM Person.Person c
   INNER JOIN Sales.Customer cu ON c.BusinessEntityID = cu.PersonID
   INNER JOIN Sales.SalesOrderHeader soh ON cu.CustomerID = soh.CustomerID
   GROUP BY c.FirstName, c.LastName
   HAVING COUNT(soh.SalesOrderID) > 10;
   GO
   ```
3. คลิก **Execute** เพื่อรัน queries
4. รอให้ queries เสร็จสิ้น
5. รัน queries เหล่านี้อีกครั้ง 2-3 ครั้งเพื่อสร้างข้อมูลเพิ่มเติมใน Query Store

#### Task 2: View Top Resource Consuming Queries
1. ใน Object Explorer ขยาย **Databases** ขยาย **AdventureWorks** ขยาย **Query Store**
2. คลิกขวาที่ **Top Resource Consuming Queries** แล้วคลิก **View Top Resource Consuming Queries**
3. ในกล่องโต้ตอบ Top Resource Consuming Queries ตรวจสอบข้อมูลที่แสดง:
   - **Duration** (ms) - เวลาที่ใช้ในการรัน query
   - **Execution Count** - จำนวนครั้งที่ query ถูก execute
   - **Logical Reads** - จำนวน logical reads
   - **Logical Writes** - จำนวน logical writes
   - **Physical Reads** - จำนวน physical reads
4. ในส่วน **Metric** เลือกเมตริกต่างๆ เช่น **Duration**, **Execution Count**, **Logical Reads** เพื่อดู queries ที่ใช้ทรัพยากรมากที่สุดในแต่ละเมตริก
5. คลิกที่ query ในรายการเพื่อดูรายละเอียดเพิ่มเติมในบานหน้าต่างด้านล่าง
6. ตรวจสอบ **Query Plan** ที่แสดงในบานหน้าต่างด้านล่าง
7. ปิดกล่องโต้ตอบ Top Resource Consuming Queries

#### Task 3: Use Query Store Reports
1. ใน Object Explorer ภายใต้ **Query Store** คลิกขวาที่ **Regressed Queries** แล้วคลิก **View Regressed Queries**
2. ในกล่องโต้ตอบ Regressed Queries ตรวจสอบ queries ที่มี performance แย่ลงเมื่อเทียบกับช่วงเวลาก่อนหน้า
3. ในส่วน **Metric** เลือกเมตริกที่ต้องการ เช่น **Duration**, **CPU Time**
4. ในส่วน **Time Period** เลือกช่วงเวลาที่ต้องการเปรียบเทียบ
5. คลิกที่ query ในรายการเพื่อดูรายละเอียดและ execution plans
6. ปิดกล่องโต้ตอบ Regressed Queries
7. ใน Object Explorer ภายใต้ **Query Store** คลิกขวาที่ **Overall Resource Consumption** แล้วคลิก **View Overall Resource Consumption**
8. ตรวจสอบกราฟที่แสดงการใช้ทรัพยากรโดยรวมของ database
9. ปิดกล่องโต้ตอบ Overall Resource Consumption

#### Task 4: Query Query Store Using T-SQL
1. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
2. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อดู queries ที่เก็บไว้ใน Query Store:
   ```sql
   USE AdventureWorks;
   GO
   
   -- View queries in Query Store
   SELECT 
       qsq.query_id,
       qsq.query_sql_text,
       qsrs.avg_duration,
       qsrs.avg_cpu_time,
       qsrs.avg_logical_io_reads,
       qsrs.count_executions,
       qsrs.last_execution_time
   FROM sys.query_store_query qsq
   INNER JOIN sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
   INNER JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
   ORDER BY qsrs.avg_duration DESC;
   GO
   ```
3. คลิก **Execute** เพื่อดูผลลัพธ์
4. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อดู execution plans ที่เก็บไว้:
   ```sql
   -- View execution plans in Query Store
   SELECT 
       qsp.plan_id,
       qsq.query_id,
       CAST(qsp.query_plan AS XML) AS query_plan,
       qsp.engine_version,
       qsp.compatibility_level,
       qsp.is_forced_plan
   FROM sys.query_store_plan qsp
   INNER JOIN sys.query_store_query qsq ON qsp.query_id = qsq.query_id
   ORDER BY qsp.last_execution_time DESC;
   GO
   ```
5. คลิก **Execute** เพื่อดูผลลัพธ์
6. คลิกที่ค่าในคอลัมน์ **query_plan** เพื่อดู execution plan ในรูปแบบกราฟิก

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะได้เรียนรู้วิธีวิเคราะห์ query performance โดยใช้ Query Store reports และ T-SQL queries

---

### Exercise 3: Use Query Store for Performance Tuning

#### Task 1: Force a Plan Using Query Store
1. ใน Object Explorer ภายใต้ **Query Store** คลิกขวาที่ **Top Resource Consuming Queries** แล้วคลิก **View Top Resource Consuming Queries**
2. ในกล่องโต้ตอบ Top Resource Consuming Queries เลือก query ที่มีหลาย execution plans
3. ในบานหน้าต่างด้านล่าง ตรวจสอบ execution plans ที่แตกต่างกัน
4. เลือก plan ที่มี performance ดีกว่า (เช่น duration ต่ำกว่า)
5. คลิกขวาที่ plan ที่เลือก แล้วคลิก **Force Plan**
6. ในกล่องโต้ตอบยืนยัน คลิก **Yes** เพื่อบังคับใช้ plan
7. สังเกตว่าไอคอนถูกเปลี่ยนเป็น **Force Plan** (มีลูกศรชี้ลง)
8. ปิดกล่องโต้ตอบ Top Resource Consuming Queries

#### Task 2: Test Forced Plan
1. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
2. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อรัน query ที่ถูก force plan:
   ```sql
   USE AdventureWorks;
   GO
   
   -- Run the query that has a forced plan
   SELECT TOP 10 * FROM Sales.SalesOrderHeader 
   WHERE OrderDate BETWEEN '2011-01-01' AND '2011-12-31';
   GO
   ```
3. คลิก **Execute** เพื่อรัน query
4. ตรวจสอบว่า query ใช้ forced plan โดยดู execution plan
5. ใน Object Explorer ภายใต้ **Query Store** คลิกขวาที่ **Top Resource Consuming Queries** แล้วคลิก **View Top Resource Consuming Queries**
6. ค้นหา query ที่คุณ force plan และตรวจสอบว่า plan ถูก force แล้ว

#### Task 3: Unforce a Plan
1. ในกล่องโต้ตอบ Top Resource Consuming Queries คลิกขวาที่ forced plan แล้วคลิก **Unforce Plan**
2. ในกล่องโต้ตอบยืนยัน คลิก **Yes** เพื่อยกเลิกการบังคับใช้ plan
3. สังเกตว่าไอคอนถูกเปลี่ยนกลับเป็นปกติ
4. ปิดกล่องโต้ตอบ Top Resource Consuming Queries

#### Task 4: Use Query Store Hints (SQL Server 2022+)
1. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
2. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อใช้ Query Store hints:
   ```sql
   USE AdventureWorks;
   GO
   
   -- Use Query Store hint to optimize a query
   -- First, find the query_id from Query Store
   DECLARE @query_id INT;
   
   SELECT TOP 1 @query_id = qsq.query_id
   FROM sys.query_store_query qsq
   INNER JOIN sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
   INNER JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
   WHERE qsq.query_sql_text LIKE '%SalesOrderHeader%'
   ORDER BY qsrs.avg_duration DESC;
   
   -- Apply Query Store hint (SQL Server 2022+)
   EXEC sys.sp_query_store_set_hints @query_id = @query_id,
       @query_hints = N'OPTION(MAXDOP 4)';
   GO
   ```
3. คลิก **Execute** เพื่อใช้ hint
4. **Note:** Query Store hints เป็นฟีเจอร์ใหม่ใน SQL Server 2022 ที่ช่วยให้คุณสามารถปรับแต่ง query behavior โดยไม่ต้องแก้ไข application code

#### Task 5: Monitor Query Store Performance Impact
1. ใน Object Explorer ภายใต้ **Query Store** คลิกขวาที่ **Query Store Statistics** แล้วคลิก **View Query Store Statistics**
2. ตรวจสอบข้อมูลต่อไปนี้:
   - **Total Queries** - จำนวน queries ที่เก็บไว้
   - **Total Plans** - จำนวน execution plans ที่เก็บไว้
   - **Query Store Size (MB)** - ขนาดของ Query Store
   - **Query Store State** - สถานะของ Query Store
3. ใน SQL Server Management Studio บนแถบเครื่องมือ คลิก **New Query**
4. ใน query pane พิมพ์คำสั่งต่อไปนี้เพื่อดู Query Store configuration:
   ```sql
   USE AdventureWorks;
   GO
   
   -- View Query Store configuration
   SELECT 
       actual_state_desc,
       readonly_reason,
       current_storage_size_mb,
       max_storage_size_mb,
       stale_query_threshold_days,
       max_plans_per_query
   FROM sys.database_query_store_options;
   GO
   ```
5. คลิก **Execute** เพื่อดูผลลัพธ์

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะได้เรียนรู้วิธีใช้ Query Store สำหรับ performance tuning รวมถึงการ force plans และใช้ Query Store hints (SQL Server 2022+)

---

### Exercise 4: Configure Query Store Settings

#### Task 1: Modify Query Store Configuration
1. ใน Object Explorer ขยาย **Databases** คลิกขวาที่ `AdventureWorks` แล้วคลิก **Properties**
2. ในกล่องโต้ตอบ Database Properties - AdventureWorks คลิก **Query Store**
3. ในส่วน **Max Size (MB)** เปลี่ยนค่าเป็น `200` เพื่อเพิ่มขนาดของ Query Store
4. ในส่วน **Query Store Capture Mode** เปลี่ยนเป็น **Auto** เพื่อให้ Query Store capture queries อัตโนมัติตามเกณฑ์ที่กำหนด
5. ในส่วน **Stale Query Threshold (Days)** เปลี่ยนค่าเป็น `60` เพื่อเก็บข้อมูล queries ไว้เป็นเวลา 60 วัน
6. คลิก **OK** เพื่อบันทึกการเปลี่ยนแปลง
7. รอสักครู่แล้วคลิกขวาที่ `AdventureWorks` อีกครั้ง แล้วคลิก **Properties**
8. คลิก **Query Store** และตรวจสอบว่าการตั้งค่าถูกบันทึกแล้ว

#### Task 2: Pause Query Store
1. ในกล่องโต้ตอบ Database Properties - AdventureWorks ในส่วน **Operation Mode (Requested)** เปลี่ยนเป็น **Read Only**
2. คลิก **OK** เพื่อหยุดการเก็บข้อมูลใหม่ (แต่ยังคงข้อมูลเดิมไว้)
3. รอสักครู่แล้วคลิกขวาที่ `AdventureWorks` อีกครั้ง แล้วคลิก **Properties**
4. คลิก **Query Store** และตรวจสอบว่า **Operation Mode (Actual)** แสดงเป็น **Read Only**

#### Task 3: Clear Query Store Data
1. ใน Object Explorer ภายใต้ **Query Store** คลิกขวาที่ **Query Store** แล้วคลิก **Clear Query Store Data**
2. ในกล่องโต้ตอบ Clear Query Store Data คลิก **OK** เพื่อยืนยันการลบข้อมูล
3. **Note:** การลบข้อมูล Query Store จะลบข้อมูลทั้งหมดที่เก็บไว้ แต่จะไม่ปิดการใช้งาน Query Store

#### Task 4: Re-enable Query Store
1. ใน Object Explorer คลิกขวาที่ `AdventureWorks` แล้วคลิก **Properties**
2. ในกล่องโต้ตอบ Database Properties - AdventureWorks คลิก **Query Store**
3. ในส่วน **Operation Mode (Requested)** เปลี่ยนกลับเป็น **Read Write**
4. คลิก **OK** เพื่อเปิดใช้งาน Query Store อีกครั้ง
5. ปิด SQL Server Management Studio โดยไม่บันทึกการเปลี่ยนแปลงใดๆ

**Results:** ในตอนท้ายของ exercise นี้ คุณจะได้เรียนรู้วิธีกำหนดค่า Query Store settings ต่างๆ รวมถึงการหยุดชั่วคราวและล้างข้อมูล Query Store
