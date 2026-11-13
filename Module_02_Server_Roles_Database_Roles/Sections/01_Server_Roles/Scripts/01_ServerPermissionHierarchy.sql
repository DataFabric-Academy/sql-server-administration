-- 01_ServerPermissionHierarchy.sql
-- ดูลำดับซ้อนของสิทธิ์ระดับ server ตามหัวข้อ 1.1 ของ Section 1 (Module 2)
-- ปรับจาก Microsoft 20764D "Demo 1 - server roles.sql" Step 1

WITH recCTE AS
(
    SELECT permission_name,
           covering_permission_name AS parent_permission,
           1 AS hierarchy_level
    FROM sys.fn_builtin_permissions('SERVER')
    WHERE permission_name = 'CONTROL SERVER'

    UNION ALL

    SELECT bp.permission_name, bp.covering_permission_name, r.hierarchy_level + 1
    FROM recCTE AS r
    CROSS APPLY sys.fn_builtin_permissions('SERVER') AS bp
    WHERE bp.covering_permission_name = r.permission_name
)
SELECT * FROM recCTE
ORDER BY hierarchy_level, permission_name;
GO

-- จำนวน permission ระดับ server ทั้งหมด
SELECT COUNT(*) AS total_server_permissions
FROM sys.fn_builtin_permissions('SERVER');
GO

-- สิทธิ์ระดับ database เทียบเคียง (ใช้ใน Section 2)
SELECT COUNT(*) AS total_database_permissions
FROM sys.fn_builtin_permissions('DATABASE');
GO
