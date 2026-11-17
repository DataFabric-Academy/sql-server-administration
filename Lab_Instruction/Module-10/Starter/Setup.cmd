@Echo Off
ECHO Preparing the demo environment...

REM - Get current directory
SET SUBDIR=%~dp0

REM - Restart SQL Server Service to force closure of any open connections
NET STOP SQLAGENT$SQL2
NET STOP MSSQL$SQL2
NET START MSSQL$SQL2
NET START SQLAGENT$SQL2
NET STOP MSSQLLaunchpad
NET STOP SQLSERVERAGENT
NET STOP MSSQLSERVER
NET START MSSQLSERVER
NET START SQLSERVERAGENT
NET START MSSQLLaunchpad

REM - Run SQL Script to prepare the database environment
ECHO Preparing Databases...
REM - wait until the SQL2 instance accepts connections
set /a WAITTRIES=0
:wait_sql2
set /a WAITTRIES+=1
sqlcmd -S %COMPUTERNAME%\SQL2 -E -C -Q "SELECT 1" >nul 2>&1
if errorlevel 1 if %WAITTRIES% lss 10 goto wait_sql2

SQLCMD -S %COMPUTERNAME%\SQL2 -E -C -i %SUBDIR%SetupFiles\Setup2.sql 
REM - wait until the default instance accepts connections
set /a WAITTRIES=0
:wait_default
set /a WAITTRIES+=1
sqlcmd -E -C -Q "SELECT 1" >nul 2>&1
if errorlevel 1 if %WAITTRIES% lss 10 goto wait_default

SQLCMD -E -C -v SUBDIR="%SUBDIR%" -i %SUBDIR%SetupFiles\Setup.sql 

ECHO Deleting email...
DEL c:\inetpub\mailroot\drop\*.* /Q













