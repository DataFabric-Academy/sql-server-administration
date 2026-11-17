# Module 12: Tracing Access to SQL Server with Extended Events
## Lab: Extended Events

### Exercise 1: Using the system_health Extended Events Session

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab12\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** แล้วรอให้สคริปต์ทำงานเสร็จ

#### Task 2: Run a Workload
1. ใน File Explorer นำทางไปยังโฟลเดอร์ `D:\Labfiles\Lab12\Starter`
2. คลิกขวาที่ `start_load_1.ps1` แล้วคลิก **Run with PowerShell**
3. ถ้ามีข้อความแสดงเพื่อยืนยันการเปลี่ยนแปลงใน execution policy พิมพ์ `Y` แล้วกด Enter
4. รอให้ workload เสร็จสิ้น ซึ่งควรใช้เวลาประมาณหนึ่งนาที แล้วกด Enter เพื่อปิดหน้าต่าง Windows
   PowerShell

#### Task 3: Query the system_health Extended Events Session
1. เริ่ม SQL Server Management Studio และเชื่อมต่อกับ database engine `DATAFABRIC-SQL-x` โดยใช้
   **Windows authentication**
2. บนเมนู **File** ชี้ไปที่ **Open** แล้วคลิก **Project/Solution**
3. ในกล่องโต้ตอบ Open Project นำทางไปยังโฟลเดอร์ `D:\Labfiles\Lab12\Starter\Project` คลิก
   `Project.sln` แล้วคลิก **Open**
4. ใน Solution Explorer ขยาย **Queries** แล้วดับเบิลคลิก `Exercise 01 - system_health.sql`
5. แก้ไขโค้ดภายใต้ comment ที่ขึ้นต้นด้วย Task 2 ให้อ่านดังนี้:
   ```sql
   SELECT CAST(event_data AS xml) AS xe_data 
   FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL);
   ```
6. เลือก query ที่คุณแก้ไขในขั้นตอนก่อนหน้า แล้วคลิก **Execute**

#### Task 4: Extract Deadlock Data
1. แก้ไข query ภายใต้ comment ที่ขึ้นต้นด้วย Task 3 ให้อ่านดังนี้:
   ```sql
   SELECT xe_event.c.value('@timestamp', 'datetime2(3)') AS event_time, 
   xe_event.c.query('/event/data/value/deadlock') AS deadlock_data 
   FROM ( 
   SELECT CAST(event_data AS xml) AS xe_data 
   FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL) 
   ) AS xe_data 
   CROSS APPLY xe_data.nodes('/event') AS xe_event(c) 
   WHERE xe_event.c.value('@name', 'varchar(100)') = 'xml_deadlock_report' 
   ORDER BY event_time;
   ```
2. เลือก query ที่คุณแก้ไขในขั้นตอนก่อนหน้า แล้วคลิก **Execute**
3. ในบานหน้าต่าง **Results** คลิกค่าแถวใดๆ ในคอลัมน์ deadlock_data เพื่อดู deadlock XML
   รายละเอียด
4. บนเมนู **File** คลิก **Close**
5. ปล่อยให้ SSMS เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะได้ดึงข้อมูล deadlock จาก SQL Server

---

### Exercise 2: Tracking Page Splits Using Extended Events

#### Task 1: Create an Extended Events Session to Track Page Splits
1. ใน Solution Explorer ดับเบิลคลิก `Exercise 02 - page splits.sql`
2. ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ขยาย **Management** ขยาย **Extended Events** คลิกขวาที่
   **Sessions** แล้วคลิก **New Session Wizard**
3. ใน New Session Wizard บนหน้า Introduction คลิก **Next**
4. บนหน้า Set Session Properties ในช่อง **Session name** พิมพ์ `track page splits` แล้วคลิก **Next**
5. บนหน้า Choose Template คลิก **Next**
6. บนหน้า Select Events To Capture ในส่วน **Event library** ในส่วนหัวคอลัมน์ **Channel** คลิกปุ่ม
   drop-down แล้วเลือกช่องทำเครื่องหมาย **Debug**
7. ในช่อง **Search Events** พิมพ์ `transaction_log` ดับเบิลคลิกแถว transaction_log ในรายการ Event
   Library ซึ่งจะเพิ่มมันไปยังรายการ Selected events แล้วคลิก **Next**
8. บนหน้า Capture Global Fields คลิก **Next**
9. บนหน้า Set Session Event Filters คลิก **Click here to add a clause**
10. ในรายการ drop-down **Field** คลิก `sqlserver.database_name`
11. ในช่อง **Value** พิมพ์ `AdventureWorks` แล้วคลิก **Finish**
12. บนหน้า Create Event Session คลิก **Close**
13. ใน Object Explorer ขยาย **Sessions** คลิกขวาที่ `track page splits` แล้วคลิก **Properties**
14. ในกล่องโต้ตอบ Session Properties บนหน้า **Events** คลิก **Configure**
15. ในรายการ **Selected events** คลิก `transaction_log`
16. บนแท็บ **Filter (Predicate)** คลิก **Click here to add a clause**
17. ในช่อง **And/Or** ตรวจสอบว่าค่าคือ **And**
18. ในรายการ **Field** คลิก `operation`
19. ในรายการ **Operator** คลิก `=`
20. ในรายการ **Value** คลิก `LOP_DELETE_SPLIT`
21. บนหน้า **Data Storage** คลิก **Click here to add a target**
22. ในรายการ **Type** คลิก `histogram`
23. ในรายการ **Event to filter on** คลิก `transaction_log`
24. ในส่วน **Base buckets on** คลิก **Field** ในรายการ **Field** คลิก `alloc_unit_id` แล้วคลิก **OK**
25. ใน Object Explorer คลิกขวาที่ `track page splits` แล้วคลิก **Start Session**

#### Task 2: Run a Workload
1. ใน File Explorer นำทางไปยังโฟลเดอร์ `D:\Labfiles\Lab12\Starter` คลิกขวาที่ `start_load_2.ps1` แล้ว
   คลิก **Run with PowerShell**
2. ถ้ามีข้อความแสดงเพื่อยืนยันการเปลี่ยนแปลงใน execution policy พิมพ์ `Y` แล้วกด Enter
3. รอให้ workload เสร็จสิ้น ควรใช้เวลาประมาณ 60 วินาที

#### Task 3: Query the Session
1. ใน SQL Server Management Studio ในหน้าต่าง query สำหรับ `Exercise 02 - page splits.sql` แก้ไข
   โค้ดภายใต้ comment ที่ขึ้นต้นด้วย Task 3 ให้อ่านดังนี้:
   ```sql
   USE AdventureWorks;
   SELECT CAST(target_data AS XML) AS target_data 
   FROM sys.dm_xe_sessions AS xs  
   JOIN sys.dm_xe_session_targets xt 
   ON xs.address = xt.event_session_address 
   WHERE xs.name = 'track page splits' 
   AND xt.target_name = 'histogram';
   ```
2. เลือก query ที่คุณแก้ไขในขั้นตอนก่อนหน้า แล้วคลิก **Execute**
3. ในบานหน้าต่าง results คลิก XML ที่ส่งกลับมาเพื่อตรวจสอบข้อมูล

#### Task 4: Extract alloc_unit_id and Count Values
1. ในบานหน้าต่าง `Exercise 02 - page splits.sql` แก้ไขโค้ดภายใต้ comment ที่ขึ้นต้นด้วย Task 4 ให้
   อ่านดังนี้:
   ```sql
   SELECT xe_node.value('(value)[1]', 'bigint') AS alloc_unit_id, 
   xe_node.value('(@count)[1]', 'bigint') AS split_count 
   FROM ( SELECT CAST(target_data AS XML) AS target_data 
   FROM sys.dm_xe_sessions AS xs  
   JOIN sys.dm_xe_session_targets xt 
   ON xs.address = xt.event_session_address 
   WHERE xs.name = 'track page splits' 
   AND xt.target_name = 'histogram') AS xe_data 
   CROSS APPLY target_data.nodes('HistogramTarget/Slot') AS xe_xml (xe_node);
   ```
2. เลือก query ที่คุณแก้ไขในขั้นตอนก่อนหน้า แล้วคลิก **Execute**
3. ตรวจสอบจำนวน splits ในแต่ละ node

#### Task 5: Return Object Names
1. แก้ไขโค้ดภายใต้ comment ที่ขึ้นต้นด้วย Task 5 ให้อ่านดังนี้:
   ```sql
   SELECT OBJECT_SCHEMA_NAME(sp.object_id) AS object_schema, 
     OBJECT_NAME(sp.object_id) AS object_name,  
     si.name AS index_name, 
     xe.split_count 
   FROM ( SELECT xe_node.value('(value)[1]', 'bigint') AS alloc_unit_id, 
       xe_node.value('(@count)[1]', 'bigint') AS split_count 
     FROM ( SELECT CAST(target_data AS XML) AS target_data 
       FROM sys.dm_xe_sessions AS xs  
       JOIN sys.dm_xe_session_targets xt 
       ON xs.address = xt.event_session_address 
       WHERE xs.name = 'track page splits' 
       AND xt.target_name = 'histogram') AS xe_data 
     CROSS APPLY target_data.nodes('HistogramTarget/Slot') AS xe_xml (xe_node)) 
   AS xe 
   JOIN sys.allocation_units AS sau 
   ON sau.allocation_unit_id = xe.alloc_unit_id 
   JOIN sys.partitions AS sp 
   ON sp.partition_id = sau.container_id 
   JOIN sys.indexes AS si 
   ON si.object_id = sp.object_id 
   AND si.index_id = sp.index_id;
   ```
2. เลือก query ที่คุณแก้ไขในขั้นตอนก่อนหน้า แล้วคลิก **Execute**
3. ตรวจสอบ objects ที่ได้รับผลกระทบจาก page splits

#### Task 6: Delete the Session
1. ใน Object Explorer ภายใต้ **Sessions** คลิกขวาที่ `track page splits` แล้วคลิก **Delete**
2. ในกล่องโต้ตอบ Delete Object คลิก **OK**
3. ปิด SSMS โดยไม่บันทึกการเปลี่ยนแปลง

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะได้ดึงข้อมูล page split จาก SQL Server


