# TODO : param for version ? 
# TODO : add param to test
#        this should:
#        * insure font is not installed
#        * run the script
#        * install package
#        * check to see if font is installed (c:\windows\fonts or registry)
#        * uninstall package 
#        * insure font is uninstalled (c:\windows\fonts or registry)
# TODO : put it in a repo and push it
# TODO : include custom fonts folder, or full path to the font ?
#        * could check to see if the font exists on disk
#        * if so copy it
#        * if not download it


$ScriptPath = Split-Path $MyInvocation.MyCommand.Path -Parent
$ScriptName = Split-Path $MyInvocation.MyCommand.Path -Leaf
$ConfigFile = "$scriptPath\candy-wrap-nerd-fonts.yml"

# sets up a staging folder for chocolatey to pack
function New-ChocoPackage { 
  Param(
    [Parameter()][string]$path,
    [Parameter()][String]$name
  )

  Write-Host "[$ScriptName] ~ ~ ~ Creating Files for Choco Package ""$path\$name"""

  If ( Test-Path "$path\$name" ) {
   
    Remove-Item  `
      -Path "$path\$name" `
      -Recurse
  
  }

  New-Item `
    -Path "$path\$name" `
    -Name "fonts" `
    -ItemType Directory | Out-Null
  
  New-Item `
    -Path "$path\$name" `
    -Name "tools" `
    -ItemType Directory | Out-Null

  Copy-Item `
    -Path "$ScriptPath\Choco\*" `
    -Destination "$path\$name\tools" | Out-Null

  Return ( Get-Item $path\$name ) 

}

# writes the chocolatey nuspec file
function Write-ChocoSpec { 
  Param(
    [Parameter()][String]$SpecFile,
    [Parameter()][PSCustomObject]$Config

  )
  
  Write-Host "[$ScriptName] ~ ~ ~ Writing Choco Nuspec ""$Specfile"""
  [XML]$ChocoNuspec = '<?xml version="1.0" encoding="utf-8"?><package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd"></package>'
  $package  = $ChocoNuspec.ChildNodes | Where-Object { $_.LocalName -eq 'package' }

  $metadata = $ChocoNuspec.CreateElement( 'metadata' , $ChocoNuspec.package.NamespaceURI )
  $package.AppendChild( $metadata ) | Out-Null

  $files    = $ChocoNuspec.CreateElement( 'files'    , $ChocoNuspec.package.NamespaceURI )
  $package.AppendChild( $files ) | Out-Null

  $Config.Metadata.GetEnumerator() | Foreach-Object {
 
    $data = $ChocoNuspec.CreateElement( $_.name , $ChocoNuspec.package.NamespaceURI )
    $data.InnerXml = $_.value
    $metadata.AppendChild( $data ) | Out-Null

  }
  
  $Config.files.GetEnumerator() | Foreach-Object {
 
    $file = $ChocoNuspec.CreateElement( "file" , $ChocoNuspec.package.NamespaceURI )

    $FileSrcAtt = $ChocoNuspec.CreateAttribute("src")
    $FileSrcAtt.Value = $_.src
    $file.Attributes.Append($fileSrcAtt) | Out-Null

    $FileTargetAtt = $ChocoNuspec.CreateAttribute("target")
    $FileTargetAtt.Value = $_.target
    $file.Attributes.Append($fileTargetAtt) | Out-Null

    $files.AppendChild( $file ) | Out-Null

  }

  $ChocoNuspec.Save( $SpecFile )

}

# gets a list of font assets available for a give git tag
function Request-NerdFonts {
  param(
    [Parameter()][String]$GitUrl,
    [Parameter()][String]$GitTag
  )

  Write-Host "[$ScriptName] ~ ~ ~ Requesting Nerd Fonts @ $GitTag"
  $url         = $GitUrl + "releases/tag/" + $GitTag
  $WebResponse = Invoke-WebRequest $url -UseBasicParsing
  $fonts       = Split-Path -leaf ($webResponse.Links | Where-Object { $_ -match '.zip' }).href
  $fonts       = $fonts | Where-Object { $_ -ne "$GitTag.zip" } | Out-GridView -PassThru

  Return $fonts

}

# downloads font assets from github and un zips them
function Add-ChocoFonts {
  param(
    [Parameter()][String[]]$Fonts,
    [Parameter()][String]$Destination,
    [Parameter()][String]$GitUrl,
    [Parameter()][String]$GitTag,
    [Parameter()][Switch]$WindowsCompatibleOnly
  )

  $url = $GitUrl + "releases/download/" + $GitTag 

  $fonts | Foreach-Object {
    Write-Host "[$ScriptName] ~ ~ ~ getting $url/$_"
    Start-BitsTransfer `
      -Source  "$url/$_" `
      -Destination "$Destination\$_"

    Write-Host "[$scriptName] ~ ~ ~ unzipping $Destination\$_"

    Expand-Archive `
      -Path "$Destination\$_" `
      -DestinationPath $Destination `
      -Force

    # TODO : we should ls for all files extracted and move then to 
    #        destination. One of the zips has the fonts in a sub 
    #        folder for example, we want them loose in the 
    #        destination 

    Remove-Item -Path "$Destination\$_"

    If ( $WindowsCompatibleOnly ) { 

      Get-ChildItem $Destination | Where-Object { $_ -notmatch 'Windows Compatible' } | Remove-Item

    }

  }
}

# -- -----------------------------------------------------------------------------------------------------------------------------------------
# --                                                                                                                         read yml config

If ($Host.UI.RawUI.WindowSize) { Write-Host ("-" * $($Host.UI.RawUI.WindowSize.Width -1) )  -ForegroundColor Gray }
Write-Host "[$ScriptName] ~ getting config ""$ConfigFile"""
If ($Host.UI.RawUI.WindowSize) { Write-Host ("-" * $($Host.UI.RawUI.WindowSize.Width -1) )  -ForegroundColor Gray }

# check if we can support yaml ...
If ( Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue  ) {

  If ( -not ( Test-Path $ConfigFile ) ) {

    # ... ask to install the "powershell-yaml" module from the Powershell Gallery
    Write-Warning "YML config file ""$ConfigFile "" is missing ! A blank one will be created and defaults used. See the Readme.md file for how to configure it."
    Out-File -FilePath $ConfigFile -Encoding ascii

  }

  $ChocoConfig = Get-Content $ConfigFile | ConvertFrom-Yaml

} Else {
  
  Write-Warning "Powershell-Yaml is not installed. This script uses it to read the config file. You can install it yourself if you like by running the following"
  write-Warning "Install-Module -Name Powershell-Yaml"
  Write-Warning "This script can still run, however a minimum default values will be used. Press Ctrl-C to cancel, any other key to continue"
  Pause
  $ChocoConfig = @{ 
    candywrap  = @{}
    nerdfont   = @{}
    choco      = @{
      metadata  = @{}
      files     = @()
    }
  }

}

# -- -----------------------------------------------------------------------------------------------------------------------------------------
# --                                                                                                               set up defaults for config

Write-Host "[$ScriptName] ~ ~ ~ reading config values ""$ConfigFile"""


# Set up defaults for a bare minimum run through the script.
If ( $ChocoConfig.candywrap.packageperfont -eq $null  ) { $ChocoConfig.candywrap.packageperfont = $true } 
If ( -not $ChocoConfig.candywrap.packpath             ) { $ChocoConfig.candywrap.packpath  = "$env:temp\choco-nerd-fonts" }
If ( -not $ChocoConfig.nerdfont.giturl                ) { $ChocoConfig.nerdfont.giturl = "https://github.com/ryanoasis/nerd-fonts/" }
If ( -not $ChocoConfig.nerdfont.gittag                ) { $ChocoConfig.nerdfont.gittag = "v2.1.0" }
If ( -not $ChocoConfig.choco.metadata.id              ) { $ChocoConfig.choco.metadata.id = "nerd-fonts" }
If ( -not $ChocoConfig.choco.metadata.version         ) { $ChocoConfig.choco.metadata.version = ( $ChocoConfig.nerdfont.gittag -replace '[a-zA-Z]' , '' ) }
If ( -not $ChocoConfig.choco.metadata.title           ) { $ChocoConfig.choco.metadata.title = $ChocoConfig.choco.metadata.id }
If ( -not $ChocoConfig.choco.metadata.authors         ) { $ChocoConfig.choco.metadata.authors = $env:USERNAME   }
If ( -not $ChocoConfig.choco.metadata.description     ) { $ChocoConfig.choco.metadata.description = $chococonfig.choco.metadata.title   }
If ( $ChocoConfig.choco.files.count -lt 1             ) { 
  $ChocoConfig.choco.files = @( 
    @{ src = "tools\**" ; target = "tools" },
    @{ src = "fonts\**" ; target = "fonts" }
  )
}

# If not fonts are given, try and work out what there is 
If ( ( -not $ChocoConfig.nerdfont.fonts ) -or ( $ChocoConfig.nerdfont.fonts.Count -lt 1 ) ) {

  Write-Warning "No fonts in config : will attempt to look up what's available for $($ChocoConfig.nerdfont.gittag)"
  
  $ChocoConfig.nerdfont.fonts = Request-NerdFonts -GitUrl $ChocoConfig.nerdfont.gitUrl -GitTag $ChocoConfig.nerdfont.gittag

  If ( $ChocoConfig.nerdfont.fonts.count -lt 1 ) {

    Write-Warning "no fonts selected - nothing to do"
    Return

  } 

}

# -- -----------------------------------------------------------------------------------------------------------------------------------------
# --                                                                                                                    create choco packages

If ( $ChocoConfig.candywrap.packageperfont -eq $true ) { 
  
  $ChocoTitle = $ChocoConfig.choco.metadata.title
  $ChocoId    = $ChocoConfig.choco.metadata.Id

  $ChocoConfig.nerdfont.fonts | Foreach-Object {

    $FontName = $_ -Replace '\.zip$' , ''
    $ChocoConfig.choco.metadata.title = "$ChocoTitle-$Fontname"
    $ChocoConfig.choco.metadata.id = "$ChocoId-$Fontname"

    If ($Host.UI.RawUI.WindowSize) { Write-Host ("-" * $($Host.UI.RawUI.WindowSize.Width -1) )  -ForegroundColor Gray }
    Write-Host "[$ScriptName] ~ Creating package ""$($ChocoConfig.choco.metadata.id)"""
    If ($Host.UI.RawUI.WindowSize) { Write-Host ("-" * $($Host.UI.RawUI.WindowSize.Width -1) )  -ForegroundColor Gray }

    $package = New-ChocoPackage `
      -path $ChocoConfig.candywrap.packpath `
      -name $ChocoConfig.choco.metadata.id 

    Write-ChocoSpec `
      -SpecFile "$($Package.fullname)\$($ChocoConfig.choco.metadata.id).nuspec" `
      -Config $ChocoConfig.choco

    Add-ChocoFonts `
      -Fonts $_ `
      -Destination ( Join-Path $Package.fullname "fonts" ) `
      -GitUrl $ChocoConfig.nerdfont.giturl `
      -GitTag $ChocoConfig.nerdfont.gittag `
      -WindowsCompatibleOnly:$ChocoConfig.candywrap.windowscompatibleonly

    Choco pack  "$($Package.fullname)\$($ChocoConfig.choco.metadata.id).nuspec" 

  } # end for each font in config

} Else {

  If ($Host.UI.RawUI.WindowSize) { Write-Host ("-" * $($Host.UI.RawUI.WindowSize.Width -1) )  -ForegroundColor Gray }
  Write-Host "[$ScriptName] ~ Creating package ""$($ChocoConfig.choco.metadata.id)"""
  If ($Host.UI.RawUI.WindowSize) { Write-Host ("-" * $($Host.UI.RawUI.WindowSize.Width -1) )  -ForegroundColor Gray }

  $package = New-ChocoPackage `
    -path $ChocoConfig.candywrap.packpath `
    -name $ChocoConfig.choco.metadata.id

  Write-ChocoSpec `
    -SpecFile "$($Package.fullname)\$($ChocoConfig.choco.metadata.id).nuspec" `
    -Config $ChocoConfig.choco

  Add-ChocoFonts `
    -Fonts $ChocoConfig.nerdfont.fonts `
    -Destination ( Join-Path $Package.fullname "fonts" ) `
    -GitUrl $ChocoConfig.nerdfont.giturl `
    -GitTag $ChocoConfig.nerdfont.gittag `
    -WindowsCompatibleOnly:$ChocoConfig.candywrap.windowscompatibleonly

  Choco pack  "$($Package.fullname)\$($ChocoConfig.choco.metadata.id).nuspec" 

} # end if packageperfont is true
