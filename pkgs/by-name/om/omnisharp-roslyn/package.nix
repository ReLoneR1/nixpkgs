{
  buildDotnetModule,
  dotnetCorePackages,
  fetchFromGitHub,
  lib,
  stdenv,
  runCommand,
  expect,
}:

let
  inherit (dotnetCorePackages) sdk_8_0 runtime_6_0;
in
let
  finalPackage = buildDotnetModule rec {
    pname = "omnisharp-roslyn";
    version = "1.39.12";

    src = fetchFromGitHub {
      owner = "OmniSharp";
      repo = "omnisharp-roslyn";
      rev = "refs/tags/v${version}";
      hash = "sha256-WQIBNqUqvVA0UhSoPdf179X+GYKp4LhPvYeEAet6TnY=";
    };

    projectFile = "src/OmniSharp.Stdio.Driver/OmniSharp.Stdio.Driver.csproj";
    nugetDeps = ./deps.nix;

    dotnet-sdk =
      with dotnetCorePackages;
      combinePackages [
        sdk_6_0
        sdk_8_0
      ];
    dotnet-runtime = sdk_8_0;

    dotnetInstallFlags = [ "--framework net6.0" ];
    dotnetBuildFlags = [
      "--framework net6.0"
      "--no-self-contained"
    ];
    dotnetFlags = [
      # These flags are set by the cake build.
      "-property:PackageVersion=${version}"
      "-property:AssemblyVersion=${version}.0"
      "-property:FileVersion=${version}.0"
      "-property:InformationalVersion=${version}"
      "-property:RuntimeFrameworkVersion=${runtime_6_0.version}"
      "-property:RollForward=LatestMajor"
    ];

    postPatch = ''
      # Relax the version requirement
      rm global.json

      # Patch the project files so we can compile them properly
      for project in src/OmniSharp.Http.Driver/OmniSharp.Http.Driver.csproj src/OmniSharp.LanguageServerProtocol/OmniSharp.LanguageServerProtocol.csproj src/OmniSharp.Stdio.Driver/OmniSharp.Stdio.Driver.csproj; do
        substituteInPlace $project \
          --replace '<RuntimeIdentifiers>win7-x64;win7-x86;win10-arm64</RuntimeIdentifiers>' '<RuntimeIdentifiers>linux-x64;linux-arm64;osx-x64;osx-arm64</RuntimeIdentifiers>'
      done
    '';

    useDotnetFromEnv = true;
    executables = [ "OmniSharp" ];

    passthru.tests =
      let
        with-sdk =
          sdk:
          runCommand "with-${if sdk ? version then sdk.version else "no"}-sdk"
            {
              nativeBuildInputs = [
                finalPackage
                sdk
                expect
              ];
              meta.timeout = 60;
            }
            ''
              HOME=$TMPDIR
              expect <<"EOF"
                spawn OmniSharp
                expect_before timeout {
                  send_error "timeout!\n"
                  exit 1
                }
                expect ".NET Core SDK ${if sdk ? version then sdk.version else sdk_8_0.version}"
                expect "{\"Event\":\"started\","
                send \x03
                expect eof
                catch wait result
                exit [lindex $result 3]
              EOF
              touch $out
            '';
      in
      {
        # Make sure we can run OmniSharp with any supported SDK version, as well as without
        with-net6-sdk = with-sdk dotnetCorePackages.sdk_6_0;
        with-net8-sdk = with-sdk dotnetCorePackages.sdk_8_0;
        no-sdk = with-sdk null;
      };

    passthru.updateScript = ./update.sh;

    meta = {
      description = "OmniSharp based on roslyn workspaces";
      homepage = "https://github.com/OmniSharp/omnisharp-roslyn";
      sourceProvenance = with lib.sourceTypes; [
        fromSource
        binaryNativeCode # dependencies
      ];
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [
        corngood
        ericdallo
        gepbird
        mdarocha
        tesq0
      ];
      mainProgram = "OmniSharp";
    };
  };
in
finalPackage
