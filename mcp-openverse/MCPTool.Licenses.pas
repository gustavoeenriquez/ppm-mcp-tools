unit MCPTool.Licenses;

{
  MCPTool.Licenses - mcp-openverse

  Tabla fija de licencias de Openverse -> que permite cada una.
  Se ENUMERA lo que se acepta: un codigo que no esta en la tabla (sampling+,
  nc-sampling+, uno nuevo que agregue Openverse...) se marca como desconocido
  y no es apto para ningun uso salvo 'any'.
}

interface

type
  TOvLicense = record
    Code: string;               // codigo de Openverse en minusculas (cc0, by-sa...)
    Version: string;            // '4.0', '1.0'...
    Known: Boolean;
    CommercialOk: Boolean;
    ModifyOk: Boolean;
    AttributionRequired: Boolean;
    ShareAlike: Boolean;
    function Display: string;   // 'CC BY 4.0', 'CC0 1.0', 'Public Domain Mark 1.0'
    function IsPublicDomain: Boolean;
    function AllowsUse(const AUse: string): Boolean;
  end;

// Usos validos: commercial, modify, commercial_modify, any
function OvValidUse(const AUse: string): Boolean;

function OvLicense(const ACode, AVersion: string): TOvLicense;

// URL canonica de la licencia (si la API no trae license_url)
function OvLicenseUrl(const ACode, AVersion: string): string;

// Codigos aceptados para un uso, separados por coma, para el parametro
// license= de la API. '' para 'any' (sin filtro).
function OvLicensesFor(const AUse: string): string;

implementation

uses
  System.SysUtils;

type
  TRow = record
    Code: string;
    Comm, Modi, Attr, SA: Boolean;
  end;

const
  ROWS: array[0..7] of TRow = (
    (Code: 'cc0';      Comm: True;  Modi: True;  Attr: False; SA: False),
    (Code: 'pdm';      Comm: True;  Modi: True;  Attr: False; SA: False),
    (Code: 'by';       Comm: True;  Modi: True;  Attr: True;  SA: False),
    (Code: 'by-sa';    Comm: True;  Modi: True;  Attr: True;  SA: True),
    (Code: 'by-nd';    Comm: True;  Modi: False; Attr: True;  SA: False),
    (Code: 'by-nc';    Comm: False; Modi: True;  Attr: True;  SA: False),
    (Code: 'by-nc-sa'; Comm: False; Modi: True;  Attr: True;  SA: True),
    (Code: 'by-nc-nd'; Comm: False; Modi: False; Attr: True;  SA: False)
  );

function OvValidUse(const AUse: string): Boolean;
begin
  Result := (AUse = 'commercial') or (AUse = 'modify') or
            (AUse = 'commercial_modify') or (AUse = 'any');
end;

function OvLicense(const ACode, AVersion: string): TOvLicense;
var
  I: Integer;
begin
  Result := Default(TOvLicense);
  Result.Code    := LowerCase(Trim(ACode));
  Result.Version := Trim(AVersion);
  for I := Low(ROWS) to High(ROWS) do
    if ROWS[I].Code = Result.Code then
    begin
      Result.Known               := True;
      Result.CommercialOk        := ROWS[I].Comm;
      Result.ModifyOk            := ROWS[I].Modi;
      Result.AttributionRequired := ROWS[I].Attr;
      Result.ShareAlike          := ROWS[I].SA;
      Exit;
    end;
end;

function OvLicenseUrl(const ACode, AVersion: string): string;
var
  C, V: string;
begin
  C := LowerCase(Trim(ACode));
  V := Trim(AVersion);
  if V = '' then V := '1.0';
  if C = 'cc0' then
    Result := 'https://creativecommons.org/publicdomain/zero/1.0/'
  else if C = 'pdm' then
    Result := 'https://creativecommons.org/publicdomain/mark/1.0/'
  else if OvLicense(C, V).Known then
    Result := Format('https://creativecommons.org/licenses/%s/%s/', [C, V])
  else
    Result := '';
end;

function OvLicensesFor(const AUse: string): string;
var
  I: Integer;
  L: TOvLicense;
begin
  Result := '';
  if AUse = 'any' then Exit;
  for I := Low(ROWS) to High(ROWS) do
  begin
    L := OvLicense(ROWS[I].Code, '');
    if L.AllowsUse(AUse) then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + ROWS[I].Code;
    end;
  end;
end;

{ TOvLicense }

function TOvLicense.IsPublicDomain: Boolean;
begin
  Result := (Code = 'cc0') or (Code = 'pdm');
end;

function TOvLicense.AllowsUse(const AUse: string): Boolean;
begin
  if AUse = 'any' then Exit(True);
  if not Known then Exit(False);
  if AUse = 'commercial' then
    Result := CommercialOk
  else if AUse = 'modify' then
    Result := ModifyOk
  else if AUse = 'commercial_modify' then
    Result := CommercialOk and ModifyOk
  else
    Result := False;
end;

function TOvLicense.Display: string;
var
  V: string;
begin
  V := Version;
  if Code = 'cc0' then
    Result := 'CC0'
  else if Code = 'pdm' then
    Result := 'Public Domain Mark'
  else if Known then
    Result := 'CC ' + UpperCase(Code)
  else
    Result := UpperCase(Code);
  if V <> '' then
    Result := Result + ' ' + V;
end;

end.
