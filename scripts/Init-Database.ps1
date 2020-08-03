param(
	[Parameter(Mandatory=$true)]
    [string] $dbIntellixUser,
	[Parameter(Mandatory=$true)]
    [string] $dbIntellixUserPassword,
    [string] $serverInstance = "SQLEXPRESS"
	[Parameter(Mandatory=$true)]
	[string] $intellixAdminUser,
	[Parameter(Mandatory=$true)]
    [string] $intellixAdminUserPassword
)

$dataSource = '.\' + $serverInstance


Write-Host "Creating database..."
sqlcmd -S $dataSource -i .\init_database.sql 1>.\init_database.log 2>.\init_database.err
if($LASTEXITCODE -ne 0) {
    Write-Error "Creating database failed. Please check init_database.log and init_database.err for details."
    exit $LASTEXITCODE
}


Write-Host "Creating Intelligent Indexing admin user..."
$intellixAdminUserCmd = "
USE intellixv2
go

IF NOT EXISTS(select * from users where Name=N'$intellixAdminUser')
BEGIN
	Execute AddUser N'$intellixAdminUser', N'$intellixAdminUserPassword'; 

    declare @adminUserRoleId int

	set @adminUserRoleId = (select Id from Roles where name = N'Administrator');
	insert into UserRoles(UserId, RoleId)
	select u.Id, @adminUserRoleId from 
		(select * from Users where name = N'$intellixAdminUser') u left outer join 
		(select * from UserRoles where RoleId = @adminUserRoleId) ur on u.Id = ur.UserId 
		where ur.UserId is null
END

"

sqlcmd -b -S $dataSource -Q $intellixAdminUserCmd 1>>.\init_database.log 2>>.\init_database.err
if($LASTEXITCODE -ne 0) {
    Write-Error "Creating the Intelligent Indexing Service administation user failed."
    exit $LASTEXITCODE
}
Write-Host "Creating user $dbIntellixUser for Intelligent Indexing database..."
$createUserCmd = `
    "USE intellixv2`n" + `
    "GO`n" + `
    "CREATE LOGIN [$dbIntellixUser] WITH PASSWORD=N'$dbIntellixUserPassword', DEFAULT_DATABASE=intellixv2`n" + `
    "GO`n" + `
    "ALTER LOGIN [$dbIntellixUser] ENABLE`n" + 
    "GO`n" + `
    "CREATE USER [$dbIntellixUser] FOR LOGIN [$dbIntellixUser]`n" + 
    "GO`n" + `
    "exec sp_addrolemember 'db_owner', '$dbIntellixUser'"

sqlcmd -b -S $dataSource -Q $createUserCmd
if($LASTEXITCODE -ne 0) {
    Write-Error "Creating the Intelligent Indexing database user failed."
    exit $LASTEXITCODE
}


Write-Host "Enabling SQL Server Authentication..."
sqlcmd -S $dataSource -Q "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2"


Write-Host "Enabling TCP/IP and set port to 1433..."
Import-Module SQLPS -DisableNameChecking -Force
$wmi = New-Object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer') $env:COMPUTERNAME
$uri = "ManagedComputer[@Name='$env:COMPUTERNAME']/ ServerInstance[@Name='$serverInstance']/ServerProtocol[@Name='Tcp']"
$tcp = $wmi.GetSmoObject($uri)
$tcp.IsEnabled = $true
$wmi.GetSmoObject($uri + "/IPAddress[@Name='IPAll']").IPAddressProperties[0].Value = ""
$wmi.GetSmoObject($uri + "/IPAddress[@Name='IPAll']").IPAddressProperties[1].Value = "1433"
$tcp.Alter()


Write-Host "Restarting SQL Server..."
$wmi.Services | Where-Object { $_.Type -eq 'SqlServer' } | ForEach-Object { Restart-Service $_.Name }


Write-Host "Updating firewall rules..."
netsh advfirewall firewall add rule name="SQLPort 1433" dir=in action=allow protocol=TCP localport=1433

# SIG # Begin signature block
# MIIcdQYJKoZIhvcNAQcCoIIcZjCCHGICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU9LvE4EOSTJZWgLlZV4SfORRx
# 2jugghebMIID7jCCA1egAwIBAgIQfpPr+3zGTlnqS5p31Ab8OzANBgkqhkiG9w0B
# AQUFADCBizELMAkGA1UEBhMCWkExFTATBgNVBAgTDFdlc3Rlcm4gQ2FwZTEUMBIG
# A1UEBxMLRHVyYmFudmlsbGUxDzANBgNVBAoTBlRoYXd0ZTEdMBsGA1UECxMUVGhh
# d3RlIENlcnRpZmljYXRpb24xHzAdBgNVBAMTFlRoYXd0ZSBUaW1lc3RhbXBpbmcg
# Q0EwHhcNMTIxMjIxMDAwMDAwWhcNMjAxMjMwMjM1OTU5WjBeMQswCQYDVQQGEwJV
# UzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFu
# dGVjIFRpbWUgU3RhbXBpbmcgU2VydmljZXMgQ0EgLSBHMjCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBALGss0lUS5ccEgrYJXmRIlcqb9y4JsRDc2vCvy5Q
# WvsUwnaOQwElQ7Sh4kX06Ld7w3TMIte0lAAC903tv7S3RCRrzV9FO9FEzkMScxeC
# i2m0K8uZHqxyGyZNcR+xMd37UWECU6aq9UksBXhFpS+JzueZ5/6M4lc/PcaS3Er4
# ezPkeQr78HWIQZz/xQNRmarXbJ+TaYdlKYOFwmAUxMjJOxTawIHwHw103pIiq8r3
# +3R8J+b3Sht/p8OeLa6K6qbmqicWfWH3mHERvOJQoUvlXfrlDqcsn6plINPYlujI
# fKVOSET/GeJEB5IL12iEgF1qeGRFzWBGflTBE3zFefHJwXECAwEAAaOB+jCB9zAd
# BgNVHQ4EFgQUX5r1blzMzHSa1N197z/b7EyALt0wMgYIKwYBBQUHAQEEJjAkMCIG
# CCsGAQUFBzABhhZodHRwOi8vb2NzcC50aGF3dGUuY29tMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwPwYDVR0fBDgwNjA0oDKgMIYuaHR0cDovL2NybC50aGF3dGUuY29tL1Ro
# YXd0ZVRpbWVzdGFtcGluZ0NBLmNybDATBgNVHSUEDDAKBggrBgEFBQcDCDAOBgNV
# HQ8BAf8EBAMCAQYwKAYDVR0RBCEwH6QdMBsxGTAXBgNVBAMTEFRpbWVTdGFtcC0y
# MDQ4LTEwDQYJKoZIhvcNAQEFBQADgYEAAwmbj3nvf1kwqu9otfrjCR27T4IGXTdf
# plKfFo3qHJIJRG71betYfDDo+WmNI3MLEm9Hqa45EfgqsZuwGsOO61mWAK3ODE2y
# 0DGmCFwqevzieh1XTKhlGOl5QGIllm7HxzdqgyEIjkHq3dlXPx13SYcqFgZepjhq
# IhKjURmDfrYwggSjMIIDi6ADAgECAhAOz/Q4yP6/NW4E2GqYGxpQMA0GCSqGSIb3
# DQEBBQUAMF4xCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3Jh
# dGlvbjEwMC4GA1UEAxMnU3ltYW50ZWMgVGltZSBTdGFtcGluZyBTZXJ2aWNlcyBD
# QSAtIEcyMB4XDTEyMTAxODAwMDAwMFoXDTIwMTIyOTIzNTk1OVowYjELMAkGA1UE
# BhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMTQwMgYDVQQDEytT
# eW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIFNpZ25lciAtIEc0MIIBIjAN
# BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAomMLOUS4uyOnREm7Dv+h8GEKU5Ow
# mNutLA9KxW7/hjxTVQ8VzgQ/K/2plpbZvmF5C1vJTIZ25eBDSyKV7sIrQ8Gf2Gi0
# jkBP7oU4uRHFI/JkWPAVMm9OV6GuiKQC1yoezUvh3WPVF4kyW7BemVqonShQDhfu
# ltthO0VRHc8SVguSR/yrrvZmPUescHLnkudfzRC5xINklBm9JYDh6NIipdC6Anqh
# d5NbZcPuF3S8QYYq3AhMjJKMkS2ed0QfaNaodHfbDlsyi1aLM73ZY8hJnTrFxeoz
# C9Lxoxv0i77Zs1eLO94Ep3oisiSuLsdwxb5OgyYI+wu9qU+ZCOEQKHKqzQIDAQAB
# o4IBVzCCAVMwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAO
# BgNVHQ8BAf8EBAMCB4AwcwYIKwYBBQUHAQEEZzBlMCoGCCsGAQUFBzABhh5odHRw
# Oi8vdHMtb2NzcC53cy5zeW1hbnRlYy5jb20wNwYIKwYBBQUHMAKGK2h0dHA6Ly90
# cy1haWEud3Muc3ltYW50ZWMuY29tL3Rzcy1jYS1nMi5jZXIwPAYDVR0fBDUwMzAx
# oC+gLYYraHR0cDovL3RzLWNybC53cy5zeW1hbnRlYy5jb20vdHNzLWNhLWcyLmNy
# bDAoBgNVHREEITAfpB0wGzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtMjAdBgNV
# HQ4EFgQURsZpow5KFB7VTNpSYxc/Xja8DeYwHwYDVR0jBBgwFoAUX5r1blzMzHSa
# 1N197z/b7EyALt0wDQYJKoZIhvcNAQEFBQADggEBAHg7tJEqAEzwj2IwN3ijhCcH
# bxiy3iXcoNSUA6qGTiWfmkADHN3O43nLIWgG2rYytG2/9CwmYzPkSWRtDebDZw73
# BaQ1bHyJFsbpst+y6d0gxnEPzZV03LZc3r03H0N45ni1zSgEIKOq8UvEiCmRDoDR
# EfzdXHZuT14ORUZBbg2w6jiasTraCXEQ/Bx5tIB7rGn0/Zy2DBYr8X9bCT2bW+IW
# yhOBbQAuOA2oKY8s4bL0WqkBrxWcLC9JG9siu8P+eJRRw4axgohd8D20UaF5Mysu
# e7ncIAkTcetqGVvP6KUwVyyJST+5z3/Jvz4iaGNTmr1pdKzFHTx/kuDDvBzYBHUw
# ggTKMIIDsqADAgECAhBxjEA+6RvB3HxpyzGvjEDFMA0GCSqGSIb3DQEBCwUAMH8x
# CzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEfMB0G
# A1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazEwMC4GA1UEAxMnU3ltYW50ZWMg
# Q2xhc3MgMyBTSEEyNTYgQ29kZSBTaWduaW5nIENBMB4XDTIwMDQwMzAwMDAwMFoX
# DTIyMDUxOTIzNTk1OVowYjELMAkGA1UEBhMCREUxDzANBgNVBAgMBkJheWVybjES
# MBAGA1UEBwwJR2VybWVyaW5nMRYwFAYDVQQKDA1Eb2N1V2FyZSBHbWJIMRYwFAYD
# VQQDDA1Eb2N1V2FyZSBHbWJIMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
# AQEAws6X00CMv08le23Y3/h5pCDKkjpk7PrmNbJGTsuCOeWXj0xkpfO30W2Y1fK+
# g9EUXlAYMWdwbYl40nC+B5M9o0/h83fM1egwWmnK1hoCrYSZJzBPh8c9RTMp2sJh
# HfiQHAQ6THy+I6NyMlQqzMUGuMW0c1IIF1Z/i7gG1BETIZMk28K2lknx/cy+z7C8
# Q9WjrP206gcJ8JYoM+53V5B6+3BxrQE33MaE/BRI7S6Nz07tkjMHZxy7+jl9KGo3
# 9LWLWY5sHoBBXVGj33yCMmnXVaXWP+INke+i3sKbbJlRbwaVSi1V1p5wNXgUj1Eo
# NaOXTGn4m6v3m8TssXVNnyeUrQIDAQABo4IBXTCCAVkwCQYDVR0TBAIwADAOBgNV
# HQ8BAf8EBAMCB4AwKwYDVR0fBCQwIjAgoB6gHIYaaHR0cDovL3N2LnN5bWNiLmNv
# bS9zdi5jcmwwYQYDVR0gBFowWDBWBgZngQwBBAEwTDAjBggrBgEFBQcCARYXaHR0
# cHM6Ly9kLnN5bWNiLmNvbS9jcHMwJQYIKwYBBQUHAgIwGQwXaHR0cHM6Ly9kLnN5
# bWNiLmNvbS9ycGEwEwYDVR0lBAwwCgYIKwYBBQUHAwMwVwYIKwYBBQUHAQEESzBJ
# MB8GCCsGAQUFBzABhhNodHRwOi8vc3Yuc3ltY2QuY29tMCYGCCsGAQUFBzAChhpo
# dHRwOi8vc3Yuc3ltY2IuY29tL3N2LmNydDAfBgNVHSMEGDAWgBSWO1PweTOXr32D
# 7y4rzMq3hh5yZjAdBgNVHQ4EFgQU7ynicphza0OLlbM38nyP6p7vxKIwDQYJKoZI
# hvcNAQELBQADggEBADIe8w0yugSPdpGKk6r7k98gYDf/S0n7loqiBobSJZr6FWvm
# paD81z4QrlsNmBXz46QnnXO1m7NdlRlwI/wmaQVQ4Nv7j4UypOFHOt0XlESHu6CA
# G57KDwylMWerawT813kA/qDFAsrjI9ILnrRAFtntm6fROXwCnkO65b5Pff+bsbIS
# ShRbJHqXCCL84+4cEnTNJc9Kur//1KJzfP9RW0qm/xDhMaUV+Xm7ivphLeU318bK
# t0HYOZBcBf99F095pVsLvDqBlgYr9gWx/k2RzQUhqfJHqrwC8me7ePceJQQshzvQ
# 84vm8aqrgKNEFSh2TrBvHy6LZm/UTJ8+htbrGKkwggTTMIIDu6ADAgECAhAY2tGe
# Jn3ou0ohWM3MaztKMA0GCSqGSIb3DQEBBQUAMIHKMQswCQYDVQQGEwJVUzEXMBUG
# A1UEChMOVmVyaVNpZ24sIEluYy4xHzAdBgNVBAsTFlZlcmlTaWduIFRydXN0IE5l
# dHdvcmsxOjA4BgNVBAsTMShjKSAyMDA2IFZlcmlTaWduLCBJbmMuIC0gRm9yIGF1
# dGhvcml6ZWQgdXNlIG9ubHkxRTBDBgNVBAMTPFZlcmlTaWduIENsYXNzIDMgUHVi
# bGljIFByaW1hcnkgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkgLSBHNTAeFw0wNjEx
# MDgwMDAwMDBaFw0zNjA3MTYyMzU5NTlaMIHKMQswCQYDVQQGEwJVUzEXMBUGA1UE
# ChMOVmVyaVNpZ24sIEluYy4xHzAdBgNVBAsTFlZlcmlTaWduIFRydXN0IE5ldHdv
# cmsxOjA4BgNVBAsTMShjKSAyMDA2IFZlcmlTaWduLCBJbmMuIC0gRm9yIGF1dGhv
# cml6ZWQgdXNlIG9ubHkxRTBDBgNVBAMTPFZlcmlTaWduIENsYXNzIDMgUHVibGlj
# IFByaW1hcnkgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkgLSBHNTCCASIwDQYJKoZI
# hvcNAQEBBQADggEPADCCAQoCggEBAK8kCAgpejWeYAyq50s7Ttx8vDxFHLsr4P4p
# AvlXCKNkhRUn9fGtyDGJXSLoKqqmQrOP+LlVt7G3S7P+j34HV+zvQ9tmYhVhz2AN
# pNje+ODDYgg9VBPrScpZVIUm5SuPG5/r9aGRwjNJ2ENjalJL0o/ocFFN0Ylpe8dw
# 9rPcEnTbe11LVtOWvxV3obD0oiXyrxySZxjl9AYE75C55ADk3Tq1Gf8CuvQ87uCL
# 6zeL7PTXrPL28D2v3XWRMxkdHEDLdCQZIZPZFP6sKlLHj9UESeSNY0eIPGmDy/5H
# vSt+T8WVrg6d1NFDwGdz4xQIfuU/n3O4MwrPXT80h5aK7lPoJRUCAwEAAaOBsjCB
# rzAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjBtBggrBgEFBQcBDARh
# MF+hXaBbMFkwVzBVFglpbWFnZS9naWYwITAfMAcGBSsOAwIaBBSP5dMahqyNjmvD
# z4Bq1EgYLHsZLjAlFiNodHRwOi8vbG9nby52ZXJpc2lnbi5jb20vdnNsb2dvLmdp
# ZjAdBgNVHQ4EFgQUf9Nlp8Ld7LvwMAnzQzn6Aq8zMTMwDQYJKoZIhvcNAQEFBQAD
# ggEBAJMkSjBfYs/YGpgvPercmS29d/aleSI47MSnoHgSrWIORXBkxeeXZi2YCX5f
# r9bMKGXyAaoIGkfe+fl8kloIaSAN2T5tbjwNbtjmBpFAGLn4we3f20Gq4JYgyc1k
# FTiByZTuooQpCxNvjtsM3SUC26SLGUTSQXoFaUpYT2DKfoJqCwKqJRc5tdt/54Rl
# KpWKvYbeXoEWgy0QzN79qIIqbSgfDQvE5ecaJhnh9BFvELWV/OdCBTLbzp1RXii2
# noXTW++lfUVAco63DmsOBvszNUhxuJ0ni8RlXw2GdpxEevaVXPZdMggzpFS2GD9o
# XPJCSoU4VINf0egs8qwR1qjtY2owggVZMIIEQaADAgECAhA9eNf5dklgsmF99PAe
# yoYqMA0GCSqGSIb3DQEBCwUAMIHKMQswCQYDVQQGEwJVUzEXMBUGA1UEChMOVmVy
# aVNpZ24sIEluYy4xHzAdBgNVBAsTFlZlcmlTaWduIFRydXN0IE5ldHdvcmsxOjA4
# BgNVBAsTMShjKSAyMDA2IFZlcmlTaWduLCBJbmMuIC0gRm9yIGF1dGhvcml6ZWQg
# dXNlIG9ubHkxRTBDBgNVBAMTPFZlcmlTaWduIENsYXNzIDMgUHVibGljIFByaW1h
# cnkgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkgLSBHNTAeFw0xMzEyMTAwMDAwMDBa
# Fw0yMzEyMDkyMzU5NTlaMH8xCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRl
# YyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazEw
# MC4GA1UEAxMnU3ltYW50ZWMgQ2xhc3MgMyBTSEEyNTYgQ29kZSBTaWduaW5nIENB
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAl4MeABavLLHSCMTXaJNR
# YB5x9uJHtNtYTSNiarS/WhtR96MNGHdou9g2qy8hUNqe8+dfJ04LwpfICXCTqdpc
# DU6kDZGgtOwUzpFyVC7Oo9tE6VIbP0E8ykrkqsDoOatTzCHQzM9/m+bCzFhqghXu
# PTbPHMWXBySO8Xu+MS09bty1mUKfS2GVXxxw7hd924vlYYl4x2gbrxF4GpiuxFVH
# U9mzMtahDkZAxZeSitFTp5lbhTVX0+qTYmEgCscwdyQRTWKDtrp7aIIx7mXK3/nV
# jbI13Iwrb2pyXGCEnPIMlF7AVlIASMzT+KV93i/XE+Q4qITVRrgThsIbnepaON2b
# 2wIDAQABo4IBgzCCAX8wLwYIKwYBBQUHAQEEIzAhMB8GCCsGAQUFBzABhhNodHRw
# Oi8vczIuc3ltY2IuY29tMBIGA1UdEwEB/wQIMAYBAf8CAQAwbAYDVR0gBGUwYzBh
# BgtghkgBhvhFAQcXAzBSMCYGCCsGAQUFBwIBFhpodHRwOi8vd3d3LnN5bWF1dGgu
# Y29tL2NwczAoBggrBgEFBQcCAjAcGhpodHRwOi8vd3d3LnN5bWF1dGguY29tL3Jw
# YTAwBgNVHR8EKTAnMCWgI6Ahhh9odHRwOi8vczEuc3ltY2IuY29tL3BjYTMtZzUu
# Y3JsMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggrBgEFBQcDAzAOBgNVHQ8BAf8EBAMC
# AQYwKQYDVR0RBCIwIKQeMBwxGjAYBgNVBAMTEVN5bWFudGVjUEtJLTEtNTY3MB0G
# A1UdDgQWBBSWO1PweTOXr32D7y4rzMq3hh5yZjAfBgNVHSMEGDAWgBR/02Wnwt3s
# u/AwCfNDOfoCrzMxMzANBgkqhkiG9w0BAQsFAAOCAQEAE4UaHmmpN/egvaSvfh1h
# U/6djF4MpnUeeBcj3f3sGgNVOftxlcdlWqeOMNJEWmHbcG/aIQXCLnO6SfHRk/5d
# yc1eA+CJnj90Htf3OIup1s+7NS8zWKiSVtHITTuC5nmEFvwosLFH8x2iPu6H2aZ/
# pFalP62ELinefLyoqqM9BAHqupOiDlAiKRdMh+Q6EV/WpCWJmwVrL7TJAUwnewus
# GQUioGAVP9rJ+01Mj/tyZ3f9J5THujUOiEn+jf0or0oSvQ2zlwXeRAwV+jYrA9zB
# UAHxoRFdFOXivSdLVL4rhF4PpsN0BQrvl8OJIrEfd/O9zUPU8UypP7WLhK9k8tAU
# ITGCBEQwggRAAgEBMIGTMH8xCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRl
# YyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazEw
# MC4GA1UEAxMnU3ltYW50ZWMgQ2xhc3MgMyBTSEEyNTYgQ29kZSBTaWduaW5nIENB
# AhBxjEA+6RvB3HxpyzGvjEDFMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQow
# CKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcC
# AQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBS7NSxI+i0D6bNJUPiP
# OhtDcuEBYDANBgkqhkiG9w0BAQEFAASCAQA/szhlqb3Eg56I3/B8/97bsUwNjFxg
# WSPvIWQZzatQzIGHr9S6+6SMTsmHKqnLF2+3furHMAun8gBYUI/wDfnD2x+8EIfo
# AYCR6XQY6zm4mVVy6o7yhAq0FzDE6gZOYroYBl2mkhhpFr3vBbr70NWYILbwvQak
# RZ1VO9iqDwC8/mixauzT2/jUOAR6X+CpMSriFLP8Mox3tFmnBz6mJV1WIGv/7B8x
# KixFvDgT8nMVmLPEfnW2XUc78h213YVOTUB7K/lU/3dyY+PGzOYskTVm10tqFopG
# 5J5NWpuMCnza9sZiq6hVEj0Wl+OyNIMMkrF3C+M6WSlMOP0nOKtAw5cPoYICCzCC
# AgcGCSqGSIb3DQEJBjGCAfgwggH0AgEBMHIwXjELMAkGA1UEBhMCVVMxHTAbBgNV
# BAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMTAwLgYDVQQDEydTeW1hbnRlYyBUaW1l
# IFN0YW1waW5nIFNlcnZpY2VzIENBIC0gRzICEA7P9DjI/r81bgTYapgbGlAwCQYF
# Kw4DAhoFAKBdMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkF
# MQ8XDTIwMDgwMzE0NTA1OVowIwYJKoZIhvcNAQkEMRYEFGVWLsXSitUNKBOrIqPC
# nyp98WTXMA0GCSqGSIb3DQEBAQUABIIBAEN9uqK0uKp3PSFO6edSs7aG2p8z38mP
# vGvCEDnUXG2cUP4l3M0ih818fT+Xr7I/0VFBd4JD8mwOGfa3sXptkELFDhrzjUB6
# vYQLMw2lQhD6P1z9nGHxtSyIRShBcbeq+sSOJNxNuQ7sszFv3r0Qgnvvql9qdtOo
# M5fQIIigLp+UN0sKuUMXscSxcWBhoZHhXT3wXTC6QbzRAERFKimYA4XaRDwo8l2t
# i4838feEI3jwJA0s7j9VTfDTGVm8aY2rX5Ts6pa3AJRNV7dpkphEGylYWU/KcVaX
# zTJ5GNfODCzmkavO6nlG3zMb7afkb3/feDdeiRJBTfs4CHuyISf2oI8=
# SIG # End signature block