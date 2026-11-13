-- ============================================================================
-- Section 01 — Demo 04: WITH GRANT OPTION และ Re-grant Chain
-- ฐานข้อมูล: AdventureWorks2025
-- สาธิตการมอบสิทธิ์แบบ "แจกต่อได้" และการเรียกคืนแบบ CASCADE
-- ============================================================================
USE master;
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DemoChainMgr')
    DROP LOGIN DemoChainMgr;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'DemoChainStaff')
    DROP LOGIN DemoChainStaff;
GO
CREATE LOGIN DemoChainMgr   WITH PASSWORD = 'Pa$$w0rd2025', CHECK_POLICY = OFF;
CREATE LOGIN DemoChainStaff WITH PASSWORD = 'Pa$$w0rd2025', CHECK_POLICY = OFF;
GO

USE AdventureWorks2025;
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoChainMgr')
    DROP USER DemoChainMgr;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoChainStaff')
    DROP USER DemoChainStaff;
GO
CREATE USER DemoChainMgr   FOR LOGIN DemoChainMgr;
CREATE USER DemoChainStaff FOR LOGIN DemoChainStaff;
GO

-- ---------- ขั้น 1: มอบสิทธิ์ระดับบนด้วย WITH GRANT OPTION ----------
GRANT SELECT ON Production.Product
    TO DemoChainMgr WITH GRANT OPTION;
GO

-- ---------- ขั้น 2: manager ใช้สิทธิ์แจกต่อให้ staff ----------
EXECUTE AS USER = 'DemoChainMgr';
GRANT SELECT ON Production.Product TO DemoChainStaff;
REVERT;
GO

-- ---------- ขั้น 3: ตรวจสายการให้สิทธิ์ (grantor เป็นใครบ้าง) ----------
SELECT pr.name AS grantee,
       pe.permission_name,
       pe.state_desc,               -- GRANT / GRANT_WITH_GRANT_OPTION
       gr.name AS grantor
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
JOIN sys.database_principals gr ON gr.principal_id = pe.grantor_principal_id
WHERE pe.class = 1
  AND pe.major_id = OBJECT_ID('Production.Product')
  AND pr.name IN ('DemoChainMgr', 'DemoChainStaff');
GO
-- สังเกต: แถวของ DemoChainStaff มี grantor = DemoChainMgr

-- ---------- ขั้น 4: REVOKE ระดับบนโดยไม่ใส่ CASCADE ----------
-- (สิทธิ์ของ staff ที่ได้จาก manager ยังอยู่ — SQL Server เรียกคืนเฉพาะที่ manager
--  ได้รับโดยตรง; ทางลบ: สิ่งที่ manager แจกต่อยังคงแขวนอยู่จนแจ้ง revoke ชัดเจน)
REVOKE SELECT ON Production.Product FROM DemoChainMgr;
GO

SELECT pr.name AS grantee, pe.state_desc, gr.name AS grantor
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
JOIN sys.database_principals gr ON gr.principal_id = pe.grantor_principal_id
WHERE pe.class = 1
  AND pe.major_id = OBJECT_ID('Production.Product')
  AND pr.name IN ('DemoChainMgr', 'DemoChainStaff');
GO
-- สังเกต: DemoChainMgr หมดสิทธิ์แล้ว แต่แถว staff (grantor = manager) ยังอยู่

-- ---------- ขั้น 5: เริ่ม chain ใหม่แล้วลบทั้งสายด้วย CASCADE ----------
GRANT SELECT ON Production.Product TO DemoChainMgr WITH GRANT OPTION;
EXECUTE AS USER = 'DemoChainMgr';
GRANT SELECT ON Production.Product TO DemoChainStaff;
REVERT;
GO

REVOKE SELECT ON Production.Product FROM DemoChainMgr CASCADE;
GO

SELECT pr.name AS grantee, pe.state_desc, gr.name AS grantor
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
JOIN sys.database_principals gr ON gr.principal_id = pe.grantor_principal_id
WHERE pe.class = 1
  AND pe.major_id = OBJECT_ID('Production.Product')
  AND pr.name IN ('DemoChainMgr', 'DemoChainStaff');
GO
-- สังเกต: แถวของทั้ง manager และ staff หายหมด

-- ---------- Cleanup ----------
DROP USER DemoChainMgr;
DROP USER DemoChainStaff;
GO
USE master;
GO
DROP LOGIN DemoChainMgr;
DROP LOGIN DemoChainStaff;
GO
-- จบสคริปต์
