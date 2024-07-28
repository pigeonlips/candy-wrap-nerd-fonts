# TODO : add param to test
#        this should:
#        * insure font is not installed
#        * run the script
#        * install package
#        * check to see if font is installed (c:\windows\fonts or registry)
#        * uninstall package 
#        * insure font is uninstalled (c:\windows\fonts or registry)
# TODO : include custom fonts folder, or full path to the font ?
#        * could check to see if the font exists on disk
#        * if so copy it
#        * if not download it
# DONE : get version and download assets via github api
#        see https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28#list-releases
#        Invoke-RestMethod -Method Get 'https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest'
# DONE : put it in a repo and push it


$ScriptPath = Split-Path $MyInvocation.MyCommand.Path -Parent
$ScriptName = Split-Path $MyInvocation.MyCommand.Path -Leaf
$ConfigFile = "$scriptPath\candy-wrap-nerd-fonts.yml"

# sets up a staging folder for chocolatey to pack
Function New-ChocoPackage { 
  Param(
    [Parameter()][string]$path,
    [Parameter()][String]$name
  )

  Write-Host "[$ScriptName] ~~> creating files for choco package ""$path\$name"""

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
Function Write-ChocoSpec { 
  Param(
    [Parameter()][String]$SpecFile,
    [Parameter()][PSCustomObject]$Config

  )
  
  Write-Host "[$ScriptName] ~~> writing choco nuspec ""$Specfile"""
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

  Write-Debug "$($Config | ConvertTo-Yaml)"
  $ChocoNuspec.Save( $SpecFile )

}

# gets a list of font assets available for a given git tag
Function Resolve-NerdFont {
  param(
    [Parameter()][PSCustomObject]$Config
  )

  # build up the url for githib api call 
  $UrlParts      = @()
  $UrlParts     += "https://api.github.com"
  $UrlParts     += "repos"
  $UrlParts     += $Config.nerdfont.gitrepo
  $UrlParts     += "releases"
  $UrlParts     += $Config.nerdfont.gittag 
  $url           = ($UrlParts | ? { $_ } | % { $_.trim('/') } | ? { $_ } ) -join '/'
  
  
  # get data from github
  Write-Host     "[$ScriptName] ~~> resolving nerd fonts from ""$url"""
  $GitRelease    = Invoke-RestMethod -Method GET -Uri $url
  $Config.nerdfont.gittag = $GitRelease.name -replace '[a-zA-Z]', ''
  $GitAssets     = $GitRelease.Assets | Select-Object name, size, browser_download_url
  If ( ( $Config.nerdfont.fonts.count -eq 0 ) -and ($Config.candywrap.interactive) ) { 
    # no fonts given from config, let the user choose fonts
    Write-Host "[$ScriptName] ~ Waiting for user to select fonts"
    $Config.nerdfont.fonts = $GitAssets  | Out-GridView -Title "select nerd fonts [$($GitRelease.name)] to package" -PassThru
    Return $Config 
  } 

  If ( $Config.nerdfont.fonts.count -eq 0 ) {
    Write-host "[$ScriptName] ~ no fonts in config. Assuming all fonts should be packaged"
    $Config.nerdfont.fonts = $GitAssets
    Return $Config
  }

  # filter github data to match fonts in config
  $Config.nerdfont.fonts = $GitAssets | ? { $_.name -in $Config.fonts }
  Return $Config 

}

# downloads font assets from github and un zips them
Function Add-ChocoFonts {
  param(
    [Parameter()][PSCustomObject[]]$Fonts,
    [Parameter()][String]$Destination,
    [Parameter()][Switch]$WindowsCompatibleOnly
  )

  $fonts | Foreach-Object {
    Write-Host "[$ScriptName] ~~> downloading $($_.browser_download_url)"
    Start-BitsTransfer `
      -Source  $($_.browser_download_url) `
      -Destination "$Destination\$($_.name)"

    Write-Host "[$scriptName] ~~> unzipping $Destination\$($_.name)"

    Expand-Archive `
      -Path "$Destination\$($_.name)" `
      -DestinationPath $Destination `
      -Force

    # TODO : we should ls for all files extracted and move then to 
    #        destination. One of the zips has the fonts in a sub 
    #        folder for example, we want them loose in the 
    #        destination 

    Remove-Item -Path "$Destination\$($_.name)"

    If ( $WindowsCompatibleOnly ) { 

      # TODO : what happens if we dont have any 'Windows Compatible'? 
      #        we would end up with an empty package, which theres no point in creating
      #        we should warn and move on to the next one! 
      
      # TODO : not great hard coding the search string of 'Windows Compatible' here. 
      #        maybe move this to the config file
      Get-ChildItem $Destination | Where-Object { $_ -notmatch 'Windows Compatible' } | Remove-Item -Recurse

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
    nerdfont   = @{
      fonts = @()
    }
    choco      = @{
      metadata  = @{}
      files     = @()
    }
  }

}

# -- -----------------------------------------------------------------------------------------------------------------------------------------
# --                                                                                                               set up defaults for config

Write-Host "[$ScriptName] ~~> reading config values ""$ConfigFile"""

# Set up defaults for a bare minimum run through the script.
If ( $ChocoConfig.candywrap.packageperfont -eq $null  ) { $ChocoConfig.candywrap.packageperfont = $true } 
If ( $ChocoConfig.candywrap.interactive    -eq $null  ) { $ChocoConfig.candywrap.interactive = $true } 
If ( -not $ChocoConfig.candywrap.packpath             ) { $ChocoConfig.candywrap.packpath  = "$env:temp\choco-nerd-fonts" }
If ( -not $ChocoConfig.nerdfont.gitrepo               ) { $ChocoConfig.nerdfont.gitrepo = "ryanoasis/nerd-fonts" }
If ( -not $ChocoConfig.nerdfont.gittag                ) { $ChocoConfig.nerdfont.gittag = "latest" }

$ChocoConfigt = Resolve-NerdFont -Config $ChocoConfig

If ( ($ChocoConfig.nerdfont.fonts).count -eq 0 ) {

  Write-Warning "We couldnt resolve nerdfonts. Maybe you canceled the selection. If your specifing fonts in your config you could:"
  Write-Warning ""
  Write-Warning " -> check your spelling, font names must be as they appear in the release page on github including .zip"
  Write-Warning " -> leave the font section in your config blank. This will make the script show a gridbox for you to choose from"
  Write-Warning ""
  Write-Warning "no fonts found, nothing to do! Check your config!"
  Return

} 

If ( -not $ChocoConfig.choco.metadata.id              ) { $ChocoConfig.choco.metadata.id = "nerd-fonts" }
If ( -not $ChocoConfig.choco.metadata.version         ) { $ChocoConfig.choco.metadata.version = $ChocoConfig.nerdfont.gittag }
If ( -not $ChocoConfig.choco.metadata.title           ) { $ChocoConfig.choco.metadata.title = $ChocoConfig.choco.metadata.id }
If ( -not $ChocoConfig.choco.metadata.authors         ) { $ChocoConfig.choco.metadata.authors = $env:USERNAME   }
If ( -not $ChocoConfig.choco.metadata.description     ) { $ChocoConfig.choco.metadata.description = $chococonfig.choco.metadata.title   }
If ( $ChocoConfig.choco.files.count -lt 1             ) { 
  $ChocoConfig.choco.files = @( 
    @{ src = "tools\**" ; target = "tools" },
    @{ src = "fonts\**" ; target = "fonts" }
  )
}



#Return $ChocoConfig.nerdfont.fonts
# -- -----------------------------------------------------------------------------------------------------------------------------------------
# --                                                                                                                    create choco packages

If ( $ChocoConfig.candywrap.packageperfont -eq $true ) { 
  
  $ChocoTitle = $ChocoConfig.choco.metadata.title
  $ChocoId    = $ChocoConfig.choco.metadata.Id

  $ChocoConfig.nerdfont.fonts | Foreach-Object {

    $FontName = $_.name -Replace '\.zip$' , ''
    $ChocoConfig.choco.metadata.title = "$ChocoTitle-$Fontname"
    $ChocoConfig.choco.metadata.id = "$ChocoId-$Fontname"

    If ($Host.UI.RawUI.WindowSize) { Write-Host ("-" * $($Host.UI.RawUI.WindowSize.Width -1) )  -ForegroundColor Gray }
    Write-Host "[$ScriptName] ~ creating package ""$($ChocoConfig.choco.metadata.id)"""
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
      -WindowsCompatibleOnly:$ChocoConfig.candywrap.windowscompatibleonly

    Choco pack  "$($Package.fullname)\$($ChocoConfig.choco.metadata.id).nuspec" 

  } # end for each font in config

} Else {

  If ($Host.UI.RawUI.WindowSize) { Write-Host ("-" * $($Host.UI.RawUI.WindowSize.Width -1) )  -ForegroundColor Gray }
  Write-Host "[$ScriptName] ~ creating package ""$($ChocoConfig.choco.metadata.id)"""
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
    -WindowsCompatibleOnly:$ChocoConfig.candywrap.windowscompatibleonly

  Choco pack  "$($Package.fullname)\$($ChocoConfig.choco.metadata.id).nuspec" 

} # end if packageperfont is true
