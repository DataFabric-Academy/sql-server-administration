# Module 11: Introduction to Managing SQL Server Using PowerShell
## Lab: Using PowerShell to Manage SQL Server

### Exercise 1: Getting Started with PowerShell

#### Task 1: Prepare the Lab Environment
1. ตรวจสอบให้แน่ใจว่า DC และ SQL virtual machines ทำงานอยู่ทั้งคู่ จากนั้น
   เข้าสู่ระบบ SQL เป็น `DATAFABRIC\Student` ด้วยรหัสผ่าน `Pa$$w0rd`
2. ในโฟลเดอร์ `D:\Labfiles\Lab11\Starter` คลิกขวาที่ `Setup.cmd` แล้วคลิก **Run as administrator**
3. ในกล่องโต้ตอบ User Account Control คลิก **Yes** และรอให้สคริปต์ทำงานเสร็จ

#### Task 2: Using PowerShell Help
1. บน taskbar คลิกขวาที่ **Windows PowerShell** แล้วคลิก **Run as Administrator**
2. ในกล่องโต้ตอบ User Account Control คลิก **Yes**
3. ใน console พิมพ์ `Update-Help` แล้วกด Enter รอให้ไฟล์ help อัปเดต
4. ที่ command prompt พิมพ์ `Get-Help` แล้วกด Enter เพื่อแสดงหน้า help สรุป
5. ที่ command prompt พิมพ์ `Get-Help Get-ChildItem` แล้วกด Enter เพื่อแสดง help สำหรับ cmdlet
6. ที่ command prompt พิมพ์ `Get-Command Remove-*` แล้วกด Enter เพื่อรับรายการ cmdlets ทั้งหมดที่
   ขึ้นต้นด้วย verb Remove-
7. ที่ command prompt พิมพ์ `Get-Command *sql*` แล้วกด Enter เพื่อรับรายการ cmdlets ทั้งหมดที่รวม
   "sql"
8. ที่ command prompt พิมพ์ `Get-Item` แล้วกด TAB เพื่อดู tab-completion ของ cmdlet
9. กด ESC เพื่อล้างคำสั่ง

#### Task 3: Using PowerShell Providers
1. ที่ command prompt พิมพ์ `Get-PsProvider` แล้วกด Enter เพื่อแสดงรายการ PowerShell providers
   และ locations ที่ถูกต้อง
2. ที่ command prompt พิมพ์ `Set-Location Env:` แล้วกด Enter เพื่อไปยัง location Environment
3. ที่ command prompt พิมพ์ `Get-ChildItem` แล้วกด Enter เพื่อแสดงรายการเนื้อหาของ location
4. ที่ command prompt พิมพ์ `Get-PSDrive` แล้วกด Enter เพื่อแสดงรายการ drives ที่ใช้ได้
5. เปรียบเทียบ PSDrives กับ PSProviders
6. ที่ command prompt พิมพ์ `Import-Module SQLPS` แล้วกด Enter เพื่อ import SQL PowerShell module
   คุณสามารถละเว้นคำเตือนใดๆ ที่ปรากฏ
7. ที่ command prompt พิมพ์ `Get-PsProvider` แล้วกด Enter เพื่อแสดงรายการ PowerShell providers
   สังเกตว่า SqlServer ตอนนี้ปรากฏในรายการ
8. ที่ command prompt พิมพ์ `Get-PSDrive` แล้วกด Enter เพื่อแสดงรายการ drives ที่ใช้ได้ สังเกตว่า
   SqlServer ตอนนี้ปรากฏในรายการ
9. ที่ command prompt พิมพ์ `Get-Help Get-PSProvider` กด Enter แล้วอ่านข้อมูลที่ส่งกลับมาเพื่อ
   เรียนรู้เพิ่มเติมเกี่ยวกับ cmdlet PSProvider
10. ที่ command prompt พิมพ์ `Get-Help Get-PSDrive` กด Enter แล้วอ่านข้อมูลที่ส่งกลับมาเพื่อ
    เรียนรู้เพิ่มเติมเกี่ยวกับ cmdlet PSDrive
11. ที่ command prompt พิมพ์ `Exit` เพื่อปิด console

**Results:** หลังจากเสร็จสิ้น exercise นี้ คุณจะได้ตรวจสอบ PowerShell help และ SQL PowerShell
provider

---

### Exercise 2: Using PowerShell to Change SQL Server Settings

#### Task 1: View Database Settings
1. บน taskbar คลิกขวาที่ **Windows PowerShell** แล้วคลิก **Run ISE as Administrator**
2. ในกล่องโต้ตอบ User Account Control คลิก **Yes**
3. บนเมนู **File** คลิก **Open**
4. ในกล่องโต้ตอบ Open นำทางไปยัง `D:\Labfiles\Lab11\Starter` คลิก `DisplayProperties.ps1` แล้วคลิก
   **Open**
5. เลือกโค้ดภายใต้ comment `#1#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อแสดง "import
   the SQL module" ละเว้นคำเตือนใดๆ ที่อาจปรากฏ
6. เลือกโค้ดภายใต้ comment `#2#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อเปลี่ยน location
7. เลือกโค้ดภายใต้ comment `#3#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อรับ database
   object
8. เลือกโค้ดภายใต้ comment `#4#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อแสดง database
   properties
9. เลือกโค้ดภายใต้ comment `#5#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อแสดง database
   options

#### Task 2: Amend Database Settings
1. บนเมนู **File** คลิก **Open**
2. ในกล่องโต้ตอบ Open นำทางไปยัง `D:\Labfiles\Lab11\Starter` คลิก `ChangeProperties.ps1` แล้วคลิก
   **Open**
3. เลือกโค้ดภายใต้ comment `#1#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อเตรียมสคริปต์
4. เลือกโค้ดภายใต้ comment `#2#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อเปลี่ยน location
5. เลือกโค้ดภายใต้ comment `#3#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อรับ database
   object
6. เลือกโค้ดภายใต้ comment `#4#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อเปลี่ยน
   compatibility level ของ database AdventureWorks2016
7. เลือกโค้ดภายใต้ comment `#5#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อเปลี่ยน options
   ANSI nulls, autoshrink, read only, และ recovery model

#### Task 3: View and Amend Server Settings
1. บนเมนู **File** คลิก **Open**
2. ในกล่องโต้ตอบ Open นำทางไปยัง `D:\Labfiles\Lab11\Starter` คลิก `ChangeServerSettings.ps1` แล้ว
   คลิก **Open**
3. เลือกโค้ดภายใต้ comment `#1#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อแสดง "import
   the SQL module" ละเว้นคำเตือนใดๆ ที่อาจปรากฏ
4. เลือกโค้ดภายใต้ comment `#2#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อเปลี่ยน location
5. เลือกโค้ดภายใต้ comment `#3#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อรับ server object
6. เลือกโค้ดภายใต้ comment `#4#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อแสดง object
   **Settings**
7. เลือกโค้ดภายใต้ comment `#5#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อเปลี่ยน login
   mode เป็น mixed authentication
8. เลือกโค้ดภายใต้ comment `#6#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อเปลี่ยน login
   mode กลับเป็น integrated authentication
9. เลือกโค้ดภายใต้ comment `#7#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อตรวจสอบ object
   **UserOptions**
10. เลือกโค้ดภายใต้ comment `#8#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อเปลี่ยน server
    settings บางอย่าง
11. เลือกโค้ดภายใต้ comment `#9#` แล้วบนแถบเครื่องมือ คลิก **Run Selection** เพื่อรีเซ็ต server
    settings
12. บนเมนู **File** คลิก **Exit**

**Results:** หลังจากเสร็จสิ้น lab exercise นี้ คุณจะมี PowerShell scripts เพื่อแสดงให้ IT Director








