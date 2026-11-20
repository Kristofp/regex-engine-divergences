#!/bin/sh
# run_csharp.sh: build and run the C# ground-truth runner (run_csharp.cs) inside the `dotnet` engine image, for
# test/corpus/generate-ground-truth.ts and generate-flag-ground-truth.ts. stdin (the JSON entries) passes through to
# the runner; the build log goes to stderr so only the runner's JSON reaches stdout.
#
# The target framework comes from the image's own SDK (`dotnet --version` 10.0.404 -> net10.0), never a literal:
# a literal goes stale on the next SDK bump, and a lower TFM needs that version's targeting pack from nuget.org and
# a runtime the image does not have (task E6 fix round, 2026-11-20; the same class of literal c04049173 removed
# from regexpilot-vscode/test/containerCsharp.test.ts). run_csharp.csproj reads it as $(RunnerTfm) and has no default,
# so a build without it fails instead of guessing.
set -eu
mkdir -p /tmp/app
cp /runners/run_csharp.cs /runners/run_csharp.csproj /tmp/app/
cd /tmp/app
sdk=$(dotnet --version </dev/null)
tfm="net${sdk%%.*}.0"
echo "run_csharp.sh: SDK $sdk -> $tfm" >&2
dotnet build -c Release -p:RunnerTfm="$tfm" -o out </dev/null >&2
exec dotnet out/run_csharp.dll
