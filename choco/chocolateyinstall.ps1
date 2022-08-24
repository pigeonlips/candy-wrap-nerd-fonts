$ScriptPath = Split-Path $MyInvocation.MyCommand.Path -Parent
$FontPath   = Join-Path (Split-Path $ScriptPath -Parent) "fonts"

Get-ChildItem $FontPath\* | Foreach-Object {

  $Installed = Install-ChocolateyFont $_.fullname
 
  If ( $Installed -eq 0 ) { 

    Write-Host "Installed $($_.basename)"

  } Else {

    Write-Warning "Problem installing ""$($_.basename)"". You can try and install it manually from ""$($FontPath)"""

  }

}
