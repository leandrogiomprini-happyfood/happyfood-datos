# Happy Food - Inventario de tablas de Tekno (solo lectura)
# Lee UNICAMENTE el encabezado de cada .DBF (nombre de campos, tipo, cantidad de registros).
# No lee datos de clientes ni montos, no modifica nada. Compatible con PowerShell 2.0 (Windows Server 2008 R2).
param([string]$Origen = "F:\TEKNO\ssoft.hap\DATOS", [string]$Destino = "C:\HAPPY_EXTRACTOR\INVENTARIO_DBF")

New-Item -ItemType Directory -Force -Path $Destino | Out-Null
$tablas = @(); $campos = @()

Get-ChildItem -Path $Origen -Filter *.dbf | Sort-Object Length -Descending | ForEach-Object {
  $f = $_
  try {
    $fs = New-Object System.IO.FileStream($f.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $br = New-Object System.IO.BinaryReader($fs)
    $h = $br.ReadBytes(32)
    $registros = [BitConverter]::ToUInt32($h, 4)
    $largoReg = [BitConverter]::ToUInt16($h, 10)
    $ultima = "{0:0000}-{1:00}-{2:00}" -f (1900 + $h[1] + $(if ($h[1] -lt 50) {100} else {0})), $h[2], $h[3]
    $n = 0
    while ($true) {
      $d = $br.ReadBytes(32)
      if ($d.Length -lt 32 -or $d[0] -eq 13) { break }
      $n++
      $nombre = [System.Text.Encoding]::ASCII.GetString($d, 0, 11).Split([char]0)[0].Trim()
      $campos += New-Object PSObject -Property @{ archivo = $f.Name; orden = $n; campo = $nombre; tipo = [char]$d[11]; largo = $d[16]; decimales = $d[17] }
    }
    $br.Close(); $fs.Close()
    $tablas += New-Object PSObject -Property @{ archivo = $f.Name; tamano_mb = [math]::Round($f.Length / 1MB, 2); registros = $registros; largo_registro = $largoReg; cant_campos = $n; ultima_actualizacion = $ultima; modificado_archivo = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm"); tiene_memo = (Test-Path ([IO.Path]::ChangeExtension($f.FullName, ".fpt"))) }
  } catch {
    $tablas += New-Object PSObject -Property @{ archivo = $f.Name; tamano_mb = [math]::Round($f.Length / 1MB, 2); registros = "ERROR: " + $_.Exception.Message }
  }
}

$tablas | Select-Object archivo, tamano_mb, registros, cant_campos, largo_registro, ultima_actualizacion, modificado_archivo, tiene_memo | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $Destino "tablas.csv")
$campos | Select-Object archivo, orden, campo, tipo, largo, decimales | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $Destino "campos.csv")
Write-Host ("Listo: {0} tablas, {1} campos. Archivos en {2}" -f $tablas.Count, $campos.Count, $Destino)
