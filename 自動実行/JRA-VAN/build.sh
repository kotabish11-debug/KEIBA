#!/bin/bash
# jvget.cs を32bitでビルドする(JV-Link が32bitのCOMのため)
cd "$(dirname "$0")"
/c/Windows/Microsoft.NET/Framework/v4.0.30319/csc.exe -nologo -platform:x86 -r:Microsoft.CSharp.dll -r:System.Windows.Forms.dll -out:jvget.exe jvget.cs
