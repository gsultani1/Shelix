ipconfig /flushdns
Stop-Process -Name explorer -Force
Start-Process explorer.exe -WorkingDirectory $env:windir
Get-Process -Name RuntimeBroker,SearchHost -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process -FilePath "C:\Windows\System32\rundll32.exe" -ArgumentList "advapi32.dll,ProcessIdleTasks"
