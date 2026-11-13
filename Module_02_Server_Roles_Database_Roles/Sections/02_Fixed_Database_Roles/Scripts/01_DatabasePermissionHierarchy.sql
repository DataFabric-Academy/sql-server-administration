-- 01_DatabasePermissionHierarchy.sql
-- ดูลำดับสิทธิ์ระดับฐานข้อมูลตามหัวข้อ 2.1 ของ Section 2 (Module 2)

WITH recCTE AS
(
    SELECT permission_name,
           covering_permission_name AS parent_permission,
           1 AS hierarchy_level
    FROM sys.fn_builtin_permissions('DATABASE')
    WHERE covering_permission_name = ''

    UNION ALL

    SELECT bp.permission_name, bp.covering_permission_name, r.hierarchy_level + 1
    FROM recCTE AS r
    CROSS APPLY sys.fn_builtin_permissions('DATABASE') AS bp
    WHERE bp.covering_permission_name = r.permission_name
)
SELECT * FROM recCTE
ORDER BY hierarchy_level, permission_name;
GO
