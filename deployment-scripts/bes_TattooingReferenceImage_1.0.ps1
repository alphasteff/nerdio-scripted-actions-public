$runingScriptName = 'bes_TattooingReferenceImage_1.0'
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

Write-PSFMessage -Level Host -Message ("Tattooing Windows Reference Image")

$RefImageBuild = Get-Date -Format "yyMM"
$Name = "RefImageBuild"
$Value = $RefImageBuild

Write-PSFMessage -Level Host -Message ("Create Variable: $Name = $Value")
[System.Environment]::SetEnvironmentVariable($Name,$Value,[System.EnvironmentVariableTarget]::Machine)

$DateOfCreation = Get-Date -Format "MM/dd/yyyy HH:mm K"
$Name = "DateOfCreation"
$Value = $DateOfCreation

Write-PSFMessage -Level Host -Message ("Create Variable: $Name = $Value")
[System.Environment]::SetEnvironmentVariable($Name,$Value,[System.EnvironmentVariableTarget]::Machine)

Write-PSFMessage -Level Host -Message ("Stop " + $runingScriptName)

Stop-PSFRunspace
