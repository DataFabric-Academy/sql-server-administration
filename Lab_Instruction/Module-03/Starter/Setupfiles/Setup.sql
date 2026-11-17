USE master
GO

-- Drop and restore Databases

IF EXISTS(SELECT * FROM sys.sysdatabases WHERE name = 'InternetSales')
BEGIN
	DROP DATABASE InternetSales
END
GO

RESTORE DATABASE InternetSales FROM  DISK = N'D:\SetupFiles\InternetSales_03.bak' WITH REPLACE,
MOVE N'InternetSales' TO N'$(SUBDIR)SetupFiles\InternetSales.mdf',
MOVE N'InternetSales_data1' TO N'$(SUBDIR)SetupFiles\InternetSales1.ndf',
MOVE N'InternetSales_data2' TO N'$(SUBDIR)SetupFiles\InternetSales2.ndf',
MOVE N'InternetSales_Log' TO N'$(SUBDIR)SetupFiles\InternetSales.ldf';
GO
ALTER AUTHORIZATION ON DATABASE::InternetSales TO [DATAFABRIC\Student];
GO

EXEC  msdb.dbo.sp_delete_database_backuphistory @database_name = 'InternetSales';
GO

IF EXISTS(SELECT * FROM sys.sysdatabases WHERE name = 'AdventureWorks')
BEGIN
	DROP DATABASE AdventureWorks
END
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name ='DATAFABRIC\Database_Managers')
	DROP LOGIN [DATAFABRIC\Database_Managers]
GO
CREATE LOGIN [DATAFABRIC\Database_Managers] FROM WINDOWS;
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name ='DATAFABRIC\InternetSales_Users')
	DROP LOGIN [DATAFABRIC\InternetSales_Users]
GO
CREATE LOGIN [DATAFABRIC\InternetSales_Users] FROM WINDOWS;
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name ='DATAFABRIC\InternetSales_Managers')
	DROP LOGIN [DATAFABRIC\InternetSales_Managers]
GO
CREATE LOGIN [DATAFABRIC\InternetSales_Managers] FROM WINDOWS;
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name ='Marketing_Application')
	DROP LOGIN Marketing_Application
GO
CREATE LOGIN Marketing_Application WITH PASSWORD = 'Pa$$w0rd';
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name ='DATAFABRIC\WebApplicationSvc')
	DROP LOGIN [DATAFABRIC\WebApplicationSvc]
GO
CREATE LOGIN [DATAFABRIC\WebApplicationSvc] FROM WINDOWS;
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'database_manager' AND type = 'R')
	DROP SERVER ROLE database_manager;
GO

USE InternetSales;
GO

CREATE USER WebApplicationSvc
FOR LOGIN [DATAFABRIC\WebApplicationSvc];

CREATE USER InternetSales_Users
FOR LOGIN [DATAFABRIC\InternetSales_Users];

CREATE USER InternetSales_Managers
FOR LOGIN [DATAFABRIC\InternetSales_Managers];

CREATE USER Database_Managers
FOR LOGIN [DATAFABRIC\Database_Managers];

GO