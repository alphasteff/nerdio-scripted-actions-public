$runingScriptName = 'bes_DisabelShutdown_1.0'
$logFile = Join-Path -path $env:InstallLogDir -ChildPath "$runingScriptName-$(Get-date -f 'yyyy-MM-dd').log"

$paramSetPSFLoggingProvider = @{
  Name         = 'logfile'
  InstanceName = $runingScriptName
  FilePath     = $logFile
  FileType     = 'CMTrace'
  Enabled      = $true
}
If (!(Get-PSFLoggingProvider -Name logfile).Enabled){$Null = Set-PSFLoggingProvider @paramSetPSFLoggingProvider}

# Default Parameters
Write-PSFMessage -Level Host -Message ("Start " + $runingScriptName)

Write-PSFMessage -Level Host -Message ("Disable Shutdown in start menu")
# Disable Shutdown in start menu
$ShutdownPath = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Start\HideShutDown'
New-ItemProperty -Path $ShutdownPath -Name 'value' -Value 3 -PropertyType DWord -Force

Write-PSFMessage -Level Host -Message ("Stop " + $runingScriptName)

Stop-PSFRunspace
