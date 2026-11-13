# Section 4 — Alerts บน Azure SQL Database: Azure Monitor

SQL Server Agent (jobs, alerts, operators) เป็นกลไกของ Database Engine ที่รันอยู่ใน instance ของคุณ — ซึ่ง **Azure SQL Database ไม่มี** ในรุ่น PaaS ทั้ง Agent ทั้ง Database Mail จะหายไป คำถามจริงคือ "จะแจ้งเตือนตอน log จะเต็ม หรือ DTU พุ่ง ยังไง?" — คำตอบทางการคือ **Azure Monitor metric alerts + Action Groups** ซึ่งทำหน้าที่เทียบเท่า alert+operator ของ Agent และมีอานุภาพกว่าเรื่องปลายทางการแจ้ง (อีเมล, SMS, webhook, Logic App, ITSM)

> แยกแยะรุ่นให้ชัด: **Azure SQL Database** (single/database server) = ใช้ Azure Monitor; **Azure SQL Managed Instance** = มี SQL Agent + Database Mail แบบเดียวกับ on-prem ใช้เนื้อหา Section 1–3 ได้เต็มรูป; **SQL Server on-prem/Arc** = ใช้ Agent เป็นหลัก แต่เสริม Azure Monitor ได้ผ่าน Azure Arc

## 4.1 เทียบกันชัด: Agent Alerts vs Azure Monitor

| มิติ | SQL Server Agent Alerts (on-prem/MI) | Azure Monitor Metric Alerts (Azure SQL DB) |
|:-----|:-------------------------------------|:-------------------------------------------|
| ตัวจับเหตุการณ์ | error number/severity ที่ถึง Windows Application Log, performance counter, WMI | **Metrics** ที่ platform เก็บให้อยู่แล้ว: DTU/CPU/IO/storage/`storage_percent`, `workers_percent`, `sessions_percent` ฯลฯ |
| การตอบสนอง | รัน job + อีเมลถึง operator | **Action group**: อีเมล, SMS, โทร (voice), webhook, Logic App, Azure Function, ITSM ticket |
| ที่เก็บ config | `msdb` ของ instance | Azure Resource (ARM) — ทำ IaC ด้วย Bicep/Terraform/az CLI ได้เลย |
| เงื่อนไขซับซ้อน | ต่อ alert เดียว (จุดเดียว) | Dynamic thresholds (เรียนรู้ baseline เอง), multi-signal rules รวมกันได้ |
| ข้อจำกัด | ต้องมี Agent รัน; จับได้เฉพาะข้อความที่เข้า Application Log | metric ที่ platform มีให้เท่านั้น (error ภายใน engine เฉพาะราย ๆ ต้องเสริม query-based alert บน Azure Monitor Logs ถ้ามี diagnostics เปิด) |

ความคิดที่ย้ายตามมา: ใน SQL Server เราจับ "เหตุการณ์" (เมื่อ error เกิด) — ใน Azure Monitor เราจับ "สถานะเชิงเวลา" (เมื่อค่า metric เกิน threshold ในช่วงเวลาที่กำหนด) ซึ่งจริง ๆ ตอบได้ทั้งสองแบบ เพราะ SQL Server ก็มี performance condition alert อยู่แล้ว

## 4.2 ตั้งค่าแบบสั้น — Portal 4 ขั้น

1. เปิด **Azure SQL Database ของคุณ → Monitoring → Alerts → + Create → Alert rule**
2. เลือก **Condition (Signal)**: metric เช่น `storage_percent` (พื้นที่ข้อมูล+log ใช้ %), `dtu_consumption_percent`, `cpu_percent` — กำหนด threshold/logic เช่น *greater than 90% for 5 minutes*
3. เลือก/สร้าง **Action Group**: ใส่ชื่อ → Add action → **Email/SMS** (ใส่อีเมลทีม DBA) หรือ webhook → จำ `action group` เอาไว้ใช้ซ้ำกับ alert ตัวอื่น
4. ตั้งชื่อ rule (เช่น `awdb-log-storage>90`), severity (Sev 1–4), เปิดใช้ → Create — เสร็จแล้วทดสอบด้วยปุ่ม **Create + Fire alert (test)** ได้ทันที

ปลายทางที่นิยมเพิ่มเติมใน action group จริง: webhook ไป Teams/Slack (ผ่าน Logic App หรือ function จัด format), ticket ไป ITSM (ServiceNow/PagerDuty) — จำนวนข้อความ SMS/โทรจำกัดตาม quota ของ action group ให้อ่านเอกสารก่อนใช้ production

## 4.3 ตั้งผ่าน Azure CLI — ครบใน 6 บรรทัด

```bash
# ตัวแปรตาม subscription/resource group ของคุณ
RG=rg-fabrikam; SERVER=sql-fabrikam-001; DB=awdb; MAIL=dba-team@fabrikam.example

# 1) Action group สำหรับรับการแจ้ง (อีเมล)
az monitor action-group create -g $RG -n ag-fabrikam-dba \
  --short-name fabdba \
  --action email dba-team $MAIL

# 2) Metric alert: storage_percent (ข้อมูล+log) เกิน 90% ต่อเนื่อง 5 นาที
az monitor metrics alert create -g $RG -n awdb-storage-gt-90 \
  --scopes "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Sql/servers/$SERVER/databases/$DB" \
  --condition "avg storage_percent > 90" \
  --window-size 5m --evaluation-frequency 1m \
  --severity 2 \
  --action ag-fabrikam-dba

# 3) Metric alert ที่ตรงใจ DBA เดิม: DTU ใช้เกิน 85% ต่อเนื่อง 10 นาที
az monitor metrics alert create -g $RG -n awdb-dtu-gt-85 \
  --scopes "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Sql/servers/$SERVER/databases/$DB" \
  --condition "avg dtu_consumption_percent > 85" \
  --window-size 10m --evaluation-frequency 1m \
  --severity 3 \
  --action ag-fabrikam-dba
```

**Expected:** `az monitor metrics alert list -g $RG` เห็น rule ทั้งสองตัว (enabled = true); ทดสอบด้วยการยิง load จริงหรือแก้ threshold ต่ำ ๆ ชั่วคราวเพื่อเห็นอีเมลทดสอบ

## 4.4 Metric ที่ DBA ใช้จริง — เลือกจุดจับให้ครบพื้นฐาน

ชุด alert พื้นฐานที่ควรมีบนทุก Azure SQL Database (เทียบกับ alert ที่คุณเคยตั้งบน Agent):

| Metric | เทียบเท่ากับอะไรบน SQL Server | Threshold เริ่มต้นที่แนะนำ |
|:-------|:------------------------------|:---------------------------|
| `storage_percent` | log full (9002) + พื้นที่ data เต็ม | > 90% |
| `dtu_consumption_percent` / `cpu_percent` | performance counter ของ CPU/Batch Requests | > 85% ต่อเนื่อง 10 นาที |
| `workers_percent` | "Worker thread pending creation" (เมื่อ connection pool อิ่ม) | > 90% |
| `sessions_percent` | connection ใกล้ขอบเขต max connections | > 90% |
| `tempdb_data_size` | tempdb เต็ม (Module 13 เจองาน tempdb บ่อย) | เกินทรงของ baseline มาก ๆ |
| `connection_successful_rate`/`connection_failed` | อาการ login storm/ระบบรับ connection ไม่ไหว | failed > 0 ต่อเนื่อง |

ข้อจำกัดที่ต้องออกแบบรอบมัน: metric เหล่านี้บอก "สถานะรวมของ database" ไม่ใช่ "error รายตัว" — ถ้าอยากได้ระดับเดียวกับ event alert (เช่น deadlock ครั้งใหญ่) ต้องเปิด **diagnostic settings** ส่ง `SQLSecurityAuditEvents`/`SQLInsights`/Query Store data ไปที่ Log Analytics แล้วสร้าง **query-based (log) alert** แทน

## 4.5 เมื่อต้องการมากกว่า metric — Elastic Jobs และ Managed Instance

สองเรื่องที่ DBA จาก on-prem มักถามต่อ:

- **การรันงานอัตโนมัติ (job) บน Azure SQL Database** → ใช้ **Elastic Jobs** (agent ของ Azure, รัน T-SQL ข้ามหลาย database ตามเวลา) — ครอบคลุมการ backup ไม่ได้ (backup อัตโนมัติของ platform ทำให้แล้ว) แต่ครอบงาน maintenance เช่น `DBCC CHECKDB` รายสัปดาห์, ล้างข้อมูลตามกำหนด
- **ต้องการ Agent แบบเดิมจริง ๆ** → เลือก **Azure SQL Managed Instance** ซึ่งมี SQL Server Agent + Database Mail ครบ รวมถึง alert ที่เราสร้างใน Section 3 ได้เหมือนเดิม (ยกเว้น multiserver administration ที่ไม่รองรับ — จำจาก Module 8)

## 4.6 แผนที่การย้าย: จาก Agent Alerts สู่ Azure Monitor

แนวปฏิบัติตอนย้ายระบบเดิมขึ้น cloud — จัดกลุ่ม alert เดิมตาม "ความสำคัญต่อการรับรู้" แล้วเลือกชนิดใหม่ที่เหมาะ:

| Alert เดิมบน SQL Server | ปลายทางที่เหมาะบน Azure |
|:------------------------|:------------------------|
| Event alert severity 19–25 (fatal) | Metric alert Sev 1 (หรือพึ่ง platform recovery — Azure SQL DB จัดการ fatal ให้เองส่วนใหญ่) |
| Performance condition (Percent Log Used > 90) | Metric alert บน `storage_percent` — เทียบเคียงตรงที่สุด |
| Event alert 1205 (deadlock) | ย้ายไป query-based alert บน Log Analytics (ต้องเปิด diagnostics) หรือเฝ้าด้วย XE ฝั่งแอป |
| Operator รับอีเมล | Action group: email + webhook ไป Teams/Slack + ITSM ticket |
| Job notification เมื่อล้ม (Agent) | Elastic Jobs + Azure Monitor บน job status หรือย้ายงานไป Automation/Logic Apps |

ทั้งหมดทำเป็น **code** ได้ด้วย Bicep/Terraform/az CLI — จุดนี้ที่ทำให้ระบบ alert cloud ทั้งชุด commit ใน git และ deploy ซ้ำได้ ซึ่งเป็นข้อได้เปรียบเหนือ Agent alerts ที่เก็บใน msdb ของแต่ละเครื่อง

### 🚀 SQL Server 2025 & Modern Notes

- **Azure Arc-enabled SQL Server (2025)** — SQL Server on-prem ที่ onboard Arc ได้รับ assessment ความพร้อม/ความปลอดภัยรวมกับ Azure Monitor ทำให้ fleet hybrid ถูกเฝ้าที่เดียวกับ Azure SQL DB
- **Managed identity ผ่าน Arc (2025)** — outbound จาก instance ไป Azure (รวมการส่งข้อมูล monitoring) ใช้ identity ที่ Azure จัดการ ลด credential ที่ต้องดูแล
- **Azure Monitor alerts ยังพัฒนาต่อเนื่อง** — dynamic thresholds และ query-based alert (Azure Monitor Logs) คือเครื่องมือระดับ production; metric alert พื้นฐานที่เราตั้งใน Section นี้คือขั้นแรกที่ควรทำทุก database
- **สิ่งที่ "ไม่เปลี่ยน"**: SQL Server Agent alerts/operators ยังเป็นระบบหลักของ on-prem และ Managed Instance — ความรู้ของ Section 1–3 ใช้ต่อได้เต็มที่

> อ้างอิง: [Azure Monitor alerts overview](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview), [Metric alerts for Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/metrics-diagnostic-telemetry-logging-streaming-export-configure?view=azuresql), [Action groups](https://learn.microsoft.com/azure/azure-monitor/alerts/action-groups), [Elastic jobs](https://learn.microsoft.com/azure/azure-sql/database/elastic-jobs-overview?view=azuresql)
