# Module 14: Importing and Exporting Data
## Lab: Importing and Exporting Data

### Exercise 1: Import Excel Data Using the Import Wizard

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่
2. เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
3. ในโฟลเดอร์ `D:\Labfiles\Lab14\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
4. ในกล่องโต้ตอบ User Account Control คลิก **Yes** แล้วรอให้สคริปต์ทำงานเสร็จ

#### Task 2: Examine the Excel File
1. ใน File Explorer นำทางไปยัง `D:\Labfiles\Lab14\Starter\Import` แล้วดับเบิลคลิกไฟล์
   `currency_codes.xlsx` เพื่อเปิดใน Excel
2. ตรวจสอบเนื้อหาของไฟล์ ปิด Excel เมื่อคุณตรวจสอบเสร็จแล้ว

#### Task 3: Run the Data Import Wizard
1. บนเมนู Start พิมพ์ `SQL Server 2016 Import and Export Data (64-bit)` แล้วกด Enter
2. ในหน้าต่าง SQL Server Import and Export Wizard คลิก **Next**
3. บนหน้า Choose a Data Source ในช่อง **Data Source** คลิก **Microsoft Excel**
4. ในช่อง **Excel file path** พิมพ์ `D:\Labfiles\Lab14\Starter\Import\currency_codes.xlsx`
5. ในรายการ **Excel Version** คลิก **Microsoft Excel 2016** แล้วคลิก **Next**
6. บนหน้า Choose a Destination ในรายการ **Destination** คลิก **SQL Server Native Client 11.0**
7. ตรวจสอบว่าช่อง **Server Name** มีค่า `(local)` และเลือก **Use Windows Authentication**
8. ในช่อง **Database** คลิก **AdventureWorks** แล้วคลิก **Next**
9. บนหน้า Specify Table Copy or Query ตรวจสอบว่าเลือก **Copy data from one or more tables or
   views** แล้วคลิก **Next**
10. บนหน้า Select Source Tables and Views ในรายการ Destination: (local) แรก คลิก
    `[Accounts].[CurrencyCode]` แล้วคลิก **Edit Mappings**
11. ในกล่องโต้ตอบ Column Mappings ตรวจสอบว่าเลือก **Append rows to destination table**
12. ในช่อง **Mappings** ในช่อง Destination แรก คลิก `currency_code`
13. ในช่อง Destination ที่สอง คลิก `currency_numeric_code` แล้วคลิก **OK**
14. บนหน้า Select Source Tables and Views คลิก **Next**
15. บนหน้า Review Data Type Mapping คลิก **Next**
16. บนหน้า Save and Run Package ตรวจสอบว่าเลือก **Run immediately** แล้วคลิก **Finish**
17. บนหน้า Complete the Wizard คลิก **Finish**
18. เมื่อการ execute ของ package เสร็จสิ้น คลิก **Close**
19. บน taskbar คลิก **Microsoft SQL Server Management Studio**
20. ในกล่องโต้ตอบ Connect to Server คลิก **Connect**
21. บนเมนู **File** ชี้ไปที่ **Open** แล้วคลิก **Project/Solution**
22. ในกล่องโต้ตอบ Open Project นำทางไปยัง `D:\Labfiles\Lab14\Starter\Project` แล้วดับเบิลคลิก
    `Project.ssmssln`
23. ใน Solution Explorer ขยาย **Queries** แล้วดับเบิลคลิก `Lab Exercise 01 - currency codes.sql`
24. คลิก **Execute** เพื่อตรวจสอบข้อมูลที่คุณได้โหลด
25. บนเมนู **File** คลิก **Close**
26. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะสามารถ:
- ใช้ Import and Export Wizard เพื่อ import ข้อมูล

---

### Exercise 2: Import a Delimited Text File Using bcp

#### Task 1: Import Data Using bcp
1. บนหน้าจอ Start พิมพ์ `cmd` แล้วคลิก **Command Prompt**
2. ที่ command prompt พิมพ์โค้ดต่อไปนี้ แล้วกด Enter:
   ```
   bcp AdventureWorks.Accounts.ExchangeRate in
   D:\Labfiles\Lab14\Starter\Import\currency_exchange_rates.txt -S DATAFABRIC-SQL-x -T -c -t ,
   ```
3. รอให้การโหลดเสร็จสิ้น

#### Task 2: Trusting Foreign Key Constraints
1. ใน SQL Server Management Studio ใน Solution Explorer ดับเบิลคลิก `Lab Exercise 02 - bcp.sql`
2. ไฮไลต์ query ภายใต้หัวข้อสำหรับ Task 1 แล้วคลิก **Execute** สังเกตว่า foreign key constraints
   ไม่ถูก trust
3. ไฮไลต์ query ภายใต้หัวข้อสำหรับ Task 2 แล้วคลิก **Execute**
4. ไฮไลต์ query ภายใต้หัวข้อสำหรับ Task 1 แล้วคลิก **Execute** สังเกตว่า foreign key constraints
   ตอนนี้ถูก trust แล้ว

**Results:** ในตอนท้ายของ exercise นี้ คุณจะสามารถ:
- Import ไฟล์ข้อความ delimited โดยใช้ bcp

---

### Exercise 3: Import a Delimited Text File Using BULK INSERT

#### Task 1: Clear Down the Accounts.ExchangeRate Table
1. ใน Solution Explorer ดับเบิลคลิก `Lab Exercise 03 - BULK INSERT.sql`
2. ไฮไลต์ query ภายใต้หัวข้อสำหรับ Task 1 แล้วคลิก **Execute**

#### Task 2: Import Data Using BULK INSERT
1. แก้ไข query ภายใต้หัวข้อสำหรับ Task 2 ให้อ่านว่า:
   ```sql
   BULK INSERT AdventureWorks.Accounts.ExchangeRate
   FROM 'D:\Labfiles\Lab14\Starter\Import\currency_exchange_rates.txt'
   WITH ( FIELDTERMINATOR =',',
   ROWTERMINATOR ='\n',
   CHECK_CONSTRAINTS
   );
   GO
   ```
2. ไฮไลต์ query ที่คุณแก้ไข แล้วคลิก **Execute**

#### Task 3: Check Foreign Key Trust Status
- ไฮไลต์ query ภายใต้หัวข้อสำหรับ Task 3 แล้วคลิก **Execute** สังเกตว่า foreign key constraints
  ถูก trust เพราะคุณใช้ option CHECK_CONSTRAINT ใน query BULK INSERT ของคุณ

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะสามารถ:
- Import ไฟล์ข้อความ delimited โดยใช้ BULK INSERT

---

### Exercise 4: Create and Test an SSIS Package to Extract Data

#### Task 1: Create an SSIS Package
1. เริ่ม Visual Studio
2. บนเมนู **File** ชี้ไปที่ **Open** แล้วคลิก **Project/Solution**
3. ในกล่องโต้ตอบ Open Project นำทางไปยัง `D:\Labfiles\Lab14\Starter\prospect_export` แล้วดับเบิลคลิก
   `prospect_export.sln`
4. ใน Solution Explorer คลิกขวาที่ **SSIS Packages** แล้วคลิก **New SSIS Package**
5. คลิกขวาที่ `Package1.dtsx` คลิก **Rename** พิมพ์ `prospects` แล้วกด Enter
6. ในบานหน้าต่าง `prospects.dtsx [Design]` คลิก **Control Flow**
7. ใน SSIS Toolbox ดับเบิลคลิก **Data Flow Task**
8. คลิกขวาที่ **Data Flow Task** คลิก **Rename** พิมพ์ `Export Prospects` แล้วกด Enter
9. ดับเบิลคลิก `Export Prospects` เพื่อเปิดหน้า **Data Flow**

#### Task 2: Add a Data Source
1. ใน SSIS Toolbox ดับเบิลคลิก **Source Assistant**
2. ในกล่องโต้ตอบ Source Assistant - Add New Source ในช่อง **Select source type** คลิก **SQL
   Server**
3. ในช่อง Select connection managers คลิก **New** แล้วคลิก **OK**
4. ในกล่องโต้ตอบ Connection Manager ในช่อง **Server name** พิมพ์ `DATAFABRIC-SQL-x` และตรวจสอบว่าเลือก
   **Use Windows Authentication**
5. ในรายการ **Select or enter a database name** คลิก **AdventureWorks** แล้วคลิก **OK**
6. คลิกขวาที่ OLE DB Source คลิก **Rename** พิมพ์ `usp_prospect_list` แล้วกด Enter
7. ดับเบิลคลิก `usp_prospect_list` เพื่อกำหนดค่า source
8. ในกล่องโต้ตอบ OLE DB Source Editor บนหน้า Connection Manager ในรายการ **Data access mode**
   คลิก **SQL command**
9. ในช่อง **SQL command text** พิมพ์ `EXEC Sales.usp_prospect_list;` แล้วคลิก **OK**

#### Task 3: Add a File Target
1. ใน SSIS Toolbox ขยาย **Other Destinations** คลิกและลาก **Flat File Destination** ไปยังหน้า Data
   Flow
2. คลิกขวาที่ Flat File Destination คลิก **Rename** พิมพ์ `prospects file` แล้วกด Enter
3. คลิก `usp_prospect_list` คลิกที่ลูกศรสีน้ำเงินด้านซ้ายใต้ object `usp_prospect_list` แล้วคลิก
   `prospects file`
4. ดับเบิลคลิก `prospects file` เพื่อกำหนดค่า
5. ในกล่องโต้ตอบ Flat File Destination Editor คลิก **New**
6. ในกล่องโต้ตอบ Flat File Format คลิก **Delimited** แล้วคลิก **OK**
7. ในกล่องโต้ตอบ Flat File Connection Manager Editor บนหน้า General ในช่อง **Connection manager
   name** พิมพ์ `prospect file connection`
8. ในช่อง **File name** พิมพ์ `D:\Labfiles\Lab14\Starter\Export\prospects.txt`
9. เลือกช่องทำเครื่องหมาย **Column names in the first data row**
10. บนหน้า Columns ในช่อง **Row Delimiter** ตรวจสอบว่าเลือก `{CR}{LF}`
11. ในช่อง **Column delimiter** ตรวจสอบว่าเลือก **Comma {,}** แล้วคลิก **OK**
12. ในกล่องโต้ตอบ Flat File Destination Editor บนหน้า **Mappings** สังเกต mappings ระหว่าง Input
    Column และ Destination Column แล้วคลิก **OK**

#### Task 4: Test the Package
1. เพื่อทดสอบ package บนเมนู **Debug** คลิก **Start Debugging** Package จะรันเกือบทันที
2. บนเมนู **Debug** คลิก **Stop Debugging** เพื่อกลับไปยังโหมด design
3. ใน File Explorer นำทางไปยัง `D:\Labfiles\Lab14\Starter\Export` ดับเบิลคลิก `prospects.txt` และ
   ตรวจสอบว่ามีข้อมูล
4. เมื่อคุณตรวจสอบเสร็จแล้ว ปิด Notepad แล้วปิด Visual Studio โดยไม่บันทึกการเปลี่ยนแปลงใดๆ

**Results:** ในตอนท้ายของ exercise นี้ คุณจะสามารถ:
- สร้างและทดสอบ SSIS package

---

### Exercise 5: Deploy a Data-Tier Application

#### Task 1: Review the Contents of a DACPAC
1. ใน File Explorer นำทางไปยัง `D:\Labfiles\Lab14\Starter\FixedAssets` คลิกขวาที่
   `FixedAssets_1.0.9.1.dacpac` แล้วคลิก **Unpack**
2. ในกล่องโต้ตอบ Unpack Microsoft SQL Server DAC Package File ในช่อง **Files will be unpacked to
   this folder** ตรวจสอบว่า location คือ
   `D:\Labfiles\Lab14\Starter\FixedAssets\FixedAssets_1.0.9.1` แล้วคลิก **Unpack**
3. เมื่อการ unpack เสร็จสิ้น ในหน้าต่าง `FixedAssets_1.0.9.1` ดับเบิลคลิกสคริปต์ `model.sql` เพื่อ
   ตรวจสอบว่า DACPAC จะทำงานอย่างไร

#### Task 2: Deploy the Data-Tier Application
1. ใน SQL Server Management Studio ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` คลิกขวาที่ **Databases**
   แล้วคลิก **Deploy Data Tier Application**
2. ในกล่องโต้ตอบ Deploy Data-tier Application บนหน้า Introduction คลิก **Next**
3. บนหน้า Select Package ในช่อง **DAC package (file name with the .dacpac extension)** พิมพ์
   `D:\Labfiles\Lab14\Starter\FixedAssets\FixedAssets_1.0.9.1.dacpac` แล้วคลิก **Next**
4. บนหน้า Update Configuration คลิก **Next**
5. บนหน้า Summary คลิก **Next**
6. บนหน้า Deploy DAC เมื่อ deployment เสร็จสิ้น คลิก **Finish**
7. ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` คลิกขวาที่ **Databases** แล้วคลิก **Refresh**
8. ขยาย **Databases** และตรวจสอบว่า database `FixedAssets_1.0.9.1` ถูกสร้างสำเร็จ

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะสามารถ:
- ตรวจสอบเนื้อหาของ DACPAC
- Deploy data-tier application


