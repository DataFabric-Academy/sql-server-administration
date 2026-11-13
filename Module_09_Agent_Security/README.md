# Module 09 — ตั้งค่าความปลอดภัยของ SQL Server Agent (SQL Server Agent Security)

โมดูลที่แล้วคุณสร้าง jobs ให้ทำงานอัตโนมัติได้แล้ว แต่ยังทำในฐานะ sysadmin ซึ่งเป็น "โหมดพระเจ้า" — job ที่ sysadmin สร้างรันในบริบทของ Agent service account ที่มีสิทธิ์เกือบไม่จำกัด คำถามต่อไปของ DBA จริงคือ: **ถ้านักพัฒนาหรือทีมอื่นต้องสร้าง job เอง จะให้สิทธิ์แค่ไหน?** และ **job ที่ต้องแตะ OS (copy ไฟล์, เรียก exe) จะรันด้วย account ไหนเพื่อไม่ต้องยก sysadmin ให้ใคร?**

โมดูลนี้ตอบทั้งสองคำถามด้วยกลไกสามชั้น: **fixed database roles ใน msdb** (SQLAgentUserRole / ReaderRole / OperatorRole) ที่คุมใครสร้าง/แก้/รัน job ได้แค่ไหน, **Credentials** (`CREATE CREDENTIAL`) ที่ห่อ Windows account ไว้ใช้จากฝั่ง SQL Server และ **Proxies** ที่ปล่อย credential เหล่านั้นให้ใช้เฉพาะ subsystem และเฉพาะคนที่อนุญาต — เป็นการต่อยอดหลัก least-privilege ที่เรียนมาตั้งแต่ Module 1–3 เข้าสู่งาน automation

### Skill Progression (ทักษะที่ควรได้จาก Module นี้)

- **ระดับ 1 – Job Security Context**: อธิบายได้ว่า job step รันในบริบทใด (owner vs EXECUTE AS vs Agent service account) และจำกัดของ SQLAgentUserRole มีอะไรบ้าง
- **ระดับ 2 – มอบสิทธิ์ Agent อย่างจำกัด**: มอบ msdb fixed roles ให้ user สร้าง/รัน job ของตัวเองได้โดยไม่ต้องเป็น sysadmin และรู้ข้อจำกัดที่ตามมา
- **ระดับ 3 – Credentials**: สร้าง/แก้ไข/ลบ credential ที่ห่อ Windows account และเข้าใจการใช้ credential นอก Agent (backup to URL/S3, cross-ref Module 6)
- **ระดับ 4 – Proxies**: สร้าง proxy, ผูกเข้ากับ subsystem และ login เฉพาะทาง แล้วสร้าง job step ที่รันด้วย proxy ได้ครบวงจรพร้อม troubleshoot

---

## 📚 Sections (สารบัญบทเรียน)

| # | Section |
|---|---------|
| 1 | [บริบทความปลอดภัยของ SQL Server Agent](Sections/01_Agent_Security_Context/README.md) |
| 2 | [Credentials — ห่อ Windows Account ไว้ใช้จาก SQL Server](Sections/02_Credentials/README.md) |
| 3 | [Proxies — ปล่อยสิทธิ์แบบจำกัดให้ Job Steps ข้าม Subsystem](Sections/03_Proxies/README.md) |

---

## 🧪 Labs

คู่มือปฏิบัติแบบ Instruction + Code block: [Labs/README.md](Labs/README.md) — สคริปต์ประกอบอยู่ใน `Sections/*/Scripts/` ตามหัวข้อ

---

## Quiz ทบทวน

<details>
<summary><b>1. Job step ชนิด T-SQL รันในบริบทของใคร — เจ้าขอน job หรือ Agent service account?</b></summary>
ขึ้นกับเจ้าขอน: ถ้าเจ้าขอนเป็นสมาชิก **sysadmin** step รันในบริบทของ **SQL Server Agent service account** แต่ถ้าเจ้าขอนไม่ใช่ sysadmin step รันในบริบทของ **เจ้าขอน job** (พฤติกรรมแบบ EXECUTE AS OWNER) — subsystem อื่น (CmdExec, PowerShell, SSIS) ไม่ใช้กฎนี้ ต้องใช้ **proxy** เสมอเมื่อเจ้าขอนไม่ใช่ sysadmin — อ่านละเอียด: [Section 1](Sections/01_Agent_Security_Context/README.md)
</details>

<details>
<summary><b>2. SQLAgentUserRole, SQLAgentReaderRole และ SQLAgentOperatorRole ต่างกันอย่างไร?</b></summary>
สาม role นี้ใน msdb ซ้อนกันแบบ concentric (role ที่ใหญ่ขึ้นได้สิทธิ์ของเล็ก): <b>SQLAgentUserRole</b> — สร้าง/แก้/รัน **job และ schedule ที่ตัวเองเป็นเจ้าขอน** เท่านั้น <b>SQLAgentReaderRole</b> — ทำได้เหมือนเดิม + **มองเห็น job/schedule/operator ของทุกคน** (อ่านเท่านั้น) <b>SQLAgentOperatorRole</b> — ทุกข้างบน + **เริ่ม/หยุด/เปิด-ปิด job ของคนอื่น** และมองเห็น alerts/proxies ได้ — อ่านละเอียด: [Section 1](Sections/01_Agent_Security_Context/README.md)
</details>

<details>
<summary><b>3. Credential ต่างจาก Proxy อย่างไร?</b></summary>
<b>Credential</b> คือ object ระดับ server ที่ห่อชื่อ Windows account + รหัสผ่าน ใช้สำหรับ authentication ขาออก (เช่น backup ไป S3/Blob, เป็นฐานของ proxy) — <b>Proxy</b> คือ "ทางเข้า" ของ Agent job steps ที่อ้างถึง credential และถูกจำกัดด้วย subsystem ใดบ้าง + login ใดบ้างมีสิทธิ์ใช้ — credential ใช้ได้โดยไม่ต้องมี proxy, แต่ proxy ต้องมี credential เสมอ — อ่านละเอียด: [Section 2](Sections/02_Credentials/README.md) และ [Section 3](Sections/03_Proxies/README.md)
</details>

<details>
<summary><b>4. User ใน SQLAgentUserRole สร้าง job step ชนิด CmdExec ได้ไหม?</b></summary>
ไม่ได้จนกว่าจะถูก GRANT สิทธิ์ใช้ proxy ที่ผูกกับ subsystem CmdExec ไว้แล้ว และต้องระบุ <code>@proxy_name</code> ใน sp_add_jobstep — การพยายามใช้ CmdExec โดยไม่มี proxy จะ error ตอนสร้าง step เลย นี่คือด่านป้องกันแรกของ Agent security ที่กัน user ทั่วไปรันคำสั่ง OS — อ่านละเอียด: [Section 3](Sections/03_Proxies/README.md)
</details>

<details>
<summary><b>5. SQL Server 2025 มีอะไรที่กระทบความปลอดภัยของ Agent บ้าง?</b></summary>
(1) PBKDF2+SHA512 เป็น default ของ password hash (login/application role — NIST SP 800-63b) ทำให้การ brute force แพงขึ้น (2) credentials ใช้ร่วมกับ managed identity ผ่าน Azure Arc ได้ ลดการเก็บ secret (3) Agent รองรับ TLS 1.3/TDS 8.0 — อ่านละเอียด: กล่อง SQL Server 2025 ในแต่ละ Section
</details>

---

### 🚀 สิ่งที่เปลี่ยนใน SQL Server 2025 (สรุปย่อของโมดูลนี้)

- **PBKDF2 password hashing เป็น default** — CREATE LOGIN / ALTER LOGIN / APPLICATION ROLE ใช้ PBKDF2+SHA512 ตาม NIST SP 800-63b รวมถึงรหัสผ่านของ account ที่ห่อใน credentials ฝั่ง SQL Server เก็บ hash แบบเดิม แต่งานที่เกี่ยวกับรหัสผ่านทั้งระบบปลอดภัยขึ้น
- **Managed identity ผ่าน Azure Arc (SQL Server 2025)** — outbound connections ไป Azure resources ใช้ identity ที่ Azure จัดการได้ ลดความจำเป็นของ credential ที่ฝังรหัสผ่าน
- **TLS 1.3 + TDS 8.0** — SQL Server Agent เชื่อมต่อ engine ด้วยการเข้ารหัสรุ่นใหม่แบบ strict ได้
- **โครงสร้าง msdb roles/proxies/credentials ไม่เปลี่ยน** — สคริปต์และแนวปฏิบัติจากรุ่นก่อนยังใช้ได้ทั้งหมด จุดเปลี่ยนอยู่ที่ข้อกำหนดการเข้ารหัสข้อมูลระหว่างเครื่องมากกว่า

> อ้างอิง: [What's new in SQL Server 2025](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2025?view=sql-server-ver17), [Implement SQL Server Agent security](https://learn.microsoft.com/sql/ssms/agent/implement-sql-server-agent-security), [SQL Server Agent fixed database roles](https://learn.microsoft.com/sql/ssms/agent/sql-server-agent-fixed-database-roles), [CREATE CREDENTIAL](https://learn.microsoft.com/sql/t-sql/statements/create-credential-transact-sql?view=sql-server-ver17)
