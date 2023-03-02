$ScriptPath = Split-Path $MyInvocation.MyCommand.Path -Parent
$FontPath   = Join-Path (Split-Path $ScriptPath -Parent) "fonts"

Get-ChildItem $FontPath\* | Foreach-Object {

  #$uninstalled = Uninstall-ChocolateyFont $_.name
  $uninstalled = & $ScriptPath\remove-font.ps1 -file "$($_.name)"

  If ( $LASTEXITCODE -eq 0 ) { 

    Write-Host "uninstalled ""$($_.basename)"""

  } Else { 

    Write-Warning "Problem uninstalling ""$($_.basename)""."

  }

}