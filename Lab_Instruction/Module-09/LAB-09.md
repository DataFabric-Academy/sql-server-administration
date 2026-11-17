# Module 9: Configuring Security for SQL Server Agent
## Lab: Configuring Security for SQL Server Agent

### Exercise 1: Analyzing Security Problems in SQL Server Agent

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab09\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** แล้วรอให้สคริปต์ทำงานเสร็จ
4. กดคีย์ใดๆ เพื่อปิดหน้าต่าง

#### Task 2: Examine the Job History for the Failing Job
1. เริ่ม Microsoft SQL Server Management Studio แล้วเชื่อมต่อกับ Database Engine instance
   `DATAFABRIC-SQL-x` โดยใช้ Windows authentication
2. ใน Object Explorer ขยาย **SQL Server Agent** ขยาย **Jobs** คลิกขวาที่ `Generate Sales Log` แล้วคลิก
   **View History**
3. ในหน้าต่าง Log File Viewer - DATAFABRIC-SQL-x ขยาย job execution แรกโดยคลิกเครื่องหมายบวกบนแถวใน
   บานหน้าต่างด้านขวา แล้วเลื่อนหน้าต่างไปทางขวาเพื่อให้คอลัมน์ **Message** มองเห็นได้ (job เริ่มตาม
   schedule ดังนั้นอาจมีแถวของ job history หนึ่งแถวหรือมากกว่า)
4. สังเกตว่าข้อความ failure สำหรับ job step อ่านว่า:
   ```
   Non-SysAdmins have been denied permission to run DTS Execution job steps without a 
   proxy account. The step failed.
   ```
5. คลิก **Close**
6. ใน Object Explorer คลิกขวาที่ `Generate Sales Log` แล้วคลิก **Properties**
7. ในหน้าต่าง Job Properties - Generate Sales Log สังเกตว่า owner ของ job คือ login
   `PromoteApp09` แล้วคลิก **Cancel**
8. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป Job step ล้มเหลวเพราะ job
   เป็นของ login ที่ไม่ใช่สมาชิกของ role sysadmin

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณควรได้ระบุสาเหตุของ job failure แล้ว

---

### Exercise 2: Configuring a Credential

#### Task 1: Create a Credential
1. ใน Object Explorer ภายใต้ `DATAFABRIC-SQL-x` ขยาย **Security** คลิกขวาที่ **Credentials** แล้วคลิก
   **New Credential**
2. ในกล่องโต้ตอบ New Credential ในช่อง **Credential name** พิมพ์ `ExtractUser`
3. ในช่อง **Identity** คลิกปุ่มจุดไข่ปลา (…)
4. ในกล่องโต้ตอบ Select User or Group คลิก **Locations**
5. ในกล่องโต้ตอบ Locations คลิก **Entire Directory** แล้วคลิก **OK**
6. ในกล่องโต้ตอบ Select User, Service Account, or Group ในช่อง **Enter the object name to select**
   พิมพ์ `Student` คลิก **Check Names** แล้วคลิก **OK**
7. ในหน้าต่าง New Credential ในช่อง **Password** และ **Confirm password** พิมพ์ `Pa$$w0rd` แล้วคลิก
   **OK**
8. ใน Object Explorer ขยาย **Credentials** เพื่อตรวจสอบว่า `ExtractUser` ปรากฏขึ้น
9. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณควรได้สร้าง credential ที่อ้างอิงถึงบัญชี Windows
`DATAFABRIC\Student`

---

### Exercise 3: Configuring a Proxy Account

#### Task 1: Create a Proxy Account
1. ใน Object Explorer ภายใต้ **SQL Server Agent** คลิกขวาที่ **Proxies** แล้วคลิก **New Proxy**
2. ในหน้าต่าง New Proxy Account บนหน้า **General** ในช่อง **Proxy name** พิมพ์ `ExtractProxy`
3. ในช่อง **Credential name** คลิกปุ่มจุดไข่ปลา (…)
4. ในกล่องโต้ตอบ Select Credential คลิก **Browse**
5. ในกล่องโต้ตอบ Browse for Objects เลือก `ExtractUser` แล้วคลิก **OK**
6. ในกล่องโต้ตอบ Select Credential คลิก **OK**
7. ในหน้าต่าง New Proxy Account ในช่อง **Active to the following subsystems** เลือก **SQL Server
   Integration Services Package**
8. บนหน้า **Principals** คลิก **Add**
9. ในกล่องโต้ตอบ Add Principal ตรวจสอบว่า **Principal type** มีค่า **SQL Login** เลือก
   `PromoteApp09` แล้วคลิก **OK**
10. ในหน้าต่าง New Proxy Account คลิก **OK**
11. ใน Object Explorer ขยาย **Proxies** แล้วขยาย **SSIS Package Execution** เพื่อตรวจสอบว่า
    `ExtractProxy` ปรากฏขึ้น
12. ปล่อยให้ SQL Server Management Studio เปิดไว้สำหรับ exercise ถัดไป

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณควรได้สร้าง proxy account ที่เหมาะสมสำหรับแก้ไข
ปัญหากับ SQL Server Agent job ชื่อ `Generate Sales Log`

---

### Exercise 4: Configuring and Testing the Security Context of the Job

#### Task 1: Configure the Job to Use a Proxy Account
1. ใน Object Explorer ภายใต้ **SQL Server Agent** ภายใต้ **Jobs** คลิกขวาที่ `Generate Sales Log` แล้ว
   คลิก **Properties**
2. ในหน้าต่าง Job Properties - Generate Sales Log บนหน้า **Steps** คลิก **Edit**
3. บนหน้า Job Step Properties - Execute Package ในช่อง **Run as** คลิก `ExtractProxy` แล้วคลิก **OK**
4. ในหน้าต่าง Job Properties - Generate Sales Log คลิก **OK**

#### Task 2: Test the Configuration
1. คลิกขวาที่ `Generate Sales Log` แล้วคลิก **Start Job at Step**
2. ในกล่องโต้ตอบ Start Jobs - DATAFABRIC-SQL-x ตรวจสอบว่า job รันสำเร็จ แล้วคลิก **Close**
3. ใน File Explorer เรียกดูไปยัง `D:\Labfiles\Lab09\Starter\SalesLog` แล้วตรวจสอบว่า
   `sales_log.csv` ถูกสร้างขึ้น
4. ปิด File Explorer แล้วปิด SQL Server Management Studio โดยไม่บันทึกการเปลี่ยนแปลงใดๆ

**Results:** หลังจากเสร็จสิ้น exercise นี้ SQL Server Agent job `Generate Sales Log` ควรทำงาน
อย่างถูกต้อง และไฟล์ `sales_log.csv` ควรถูกสร้างไปยัง `D:\Labfiles\Lab09\Starter\SalesLog` ทุกครั้ง
ที่ job รัน


