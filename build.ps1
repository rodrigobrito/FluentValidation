param(
  [string]$version = '1.0.0-dev',
  [string]$configuration = 'Release'
)

. $PSScriptRoot/src/posh-build.ps1

$base = $PSScriptRoot;
$build_dir = "$base\build";
$packages_dir = "$build_dir\packages"
$output_dir = "$build_dir\$configuration";
$solution_file = "$base\FluentValidation.sln";
$key_file = "$base\src\FluentValidation-dev.snk";
$nuget_key = "$env:USERPROFILE\Dropbox\nuget-access-key.txt";

if (test-path "$env:USERPROFILE\Dropbox\FluentValidation-Release.snk") {
  $key_file = "$env:USERPROFILE\Dropbox\FluentValidation-Release.snk";
}

target default -depends compile, test, deploy

target compile {
  Invoke-Dotnet build $solution_file -c $configuration --no-incremental `
    /p:Version=$version /p:AssemblyOriginatorKeyFile=$key_file
}

target test {
  $test_projects = @(
    "$base\src\FluentValidation.Tests\FluentValidation.Tests.csproj",
    "$base\src\FluentValidation.Tests.Mvc5\FluentValidation.Tests.Mvc5.csproj",
    "$base\src\FluentValidation.Tests.AspNetCore\FluentValidation.Tests.AspNetCore.csproj",
    "$base\src\FluentValidation.Tests.WebApi\FluentValidation.Tests.WebApi.csproj"
  )

  Invoke-Tests $test_projects -c $configuration --no-build
}

target deploy {
  Remove-Item $build_dir -Force -Recurse 2> $null
  Invoke-Dotnet pack $solution_file -c $configuration /p:PackageOutputPath=$build_dir\Packages /p:AssemblyOriginatorKeyFile=$key_file /p:Version=$version

  # Copy to output dir
  Copy-Item "$base\src\FluentValidation\bin\$configuration\netstandard2.0" -Destination "$output_dir\FluentValidation-netstandard2.0" -Recurse
  Copy-Item "$base\src\FluentValidation\bin\$configuration\netstandard1.1" -Destination "$output_dir\FluentValidation-netstandard1.1" -Recurse
  Copy-Item "$base\src\FluentValidation\bin\$configuration\net45"  -Destination "$output_dir\FluentValidation-net45" -Recurse
  Copy-Item "$base\src\FluentValidation.Mvc5\bin\$configuration\net45"  -filter FluentValidation.Mvc.* -Destination "$output_dir\FluentValidation.Mvc5-Legacy" -Recurse
  Copy-Item "$base\src\FluentValidation.WebApi\bin\$configuration\net45"  -filter FluentValidation.WebApi.* -Destination "$output_dir\FluentValidation.WebApi-Legacy" -Recurse
  Copy-Item "$base\src\FluentValidation.AspNetCore\bin\$configuration\netstandard2.0"  -filter FluentValidation.AspNetCore.* -Destination "$output_dir\FluentValidation.AspNetCore-netstandard2.0" -Recurse
}

target verify-package {
  $asm = [System.Reflection.Assembly]::LoadFile("$output_dir/FluentValidation-netstandard2.0/FluentValidation.dll")

  if (-not (test-path "$nuget_key")) {
    throw "Could not find the NuGet access key."
  }
  elseif (-not $asm.FullName.EndsWith("PublicKeyToken=7de548da2fbae0f0")) {
    throw "This build is using the dev key. Please rebuild with release key"
  }
  else {
    write-host Package verified
  }
}

target publish -depends verify-package {
  $key = get-content $nuget_key

  # Find all the packages and display them for confirmation
  $packages = dir $packages_dir -Filter "*.nupkg"
  write-host "Packages to upload:"
  $packages | ForEach-Object { write-host $_.Name }

  # Ensure we haven't run this by accident.
  $result = New-Prompt "Upload Packages" "Do you want to upload the NuGet packages to the NuGet server?" @(
    @("&No", "Does not upload the packages."),
    @("&Yes", "Uploads the packages.")
  )
  
  # Cancelled
  if ($result -eq 0) {
    "Upload aborted"
  }
  # upload
  elseif ($result -eq 1) {
    $packages | foreach {
      $package = $_.FullName
      write-host "Uploading $package"
      Invoke-Dotnet nuget push $package --api-key $key --source "https://www.nuget.org/api/v2/package"
      write-host
    }
  }
}

Start-Build $args