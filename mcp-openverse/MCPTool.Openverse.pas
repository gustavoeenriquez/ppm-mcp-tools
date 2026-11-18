unit MCPTool.Openverse;

{
  MCPTool.Openverse - mcp-openverse

  Imagenes y audio con licencia abierta (CC / dominio publico) via la API de
  Openverse (https://api.openverse.org). Diseno: DESIGN.md.

  Herramientas:
    openverse_search   buscar (por defecto solo lo apto para uso comercial)
    openverse_get      detalle de un item (atribucion, archivos alternativos)
    openverse_related  items parecidos
    openverse_download descargar + manifiesto (formato de earshot). Solo stdio.
    openverse_credits  creditos para YouTube / Markdown / HTML / JSON
    openverse_status   cuota, autenticacion y fuentes
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Classes,
  System.JSON;

type
  TOvSearchParams = class
  private
    FMedia, FQuery, FUse, FLicenses, FCategory, FLength, FSource, FCreator,
    FExtension, FAspectRatio, FSize: string;
    FLimit, FPage: Integer;
  public
    constructor Create;
    [AiMCPSchemaDescription('Media type: audio or image')]
    property Media: string read FMedia write FMedia;

    [AiMCPSchemaDescription('What to look for. Openverse indexes mostly English metadata: query in English ' +
      '(e.g. "soft ui click", "rain on window", "coffee beans").')]
    property Query: string read FQuery write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Intended use; only licences that allow it are returned. Default: commercial. ' +
      'commercial_modify = commercial use AND editing (trim, mix, crop). any = no licence filter.')]
    property Use: string read FUse write FUse;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Exact licence codes, comma separated (cc0, pdm, by, by-sa, by-nd, by-nc, by-nc-sa, ' +
      'by-nc-nd). Overrides "use".')]
    property Licenses: string read FLicenses write FLicenses;

    [AiMCPOptional]
    [AiMCPSchemaDescription('audio: sound_effect, music, podcast, audiobook, news, pronunciation. ' +
      'image: photograph, illustration, digitized_artwork. Comma separated.')]
    property Category: string read FCategory write FCategory;

    [AiMCPOptional]
    [AiMCPSchemaDescription('audio only: shortest, short, medium, long. Comma separated.')]
    property Length: string read FLength write FLength;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Only these sources, comma separated (see openverse_status), e.g. freesound, ' +
      'jamendo, wikimedia_audio, flickr, wikimedia.')]
    property Source: string read FSource write FSource;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Creator name')]
    property Creator: string read FCreator write FCreator;

    [AiMCPOptional]
    [AiMCPSchemaDescription('File extension filter, e.g. mp3, wav, flac, ogg, jpg, png, svg')]
    property Extension: string read FExtension write FExtension;

    [AiMCPOptional]
    [AiMCPSchemaDescription('image only: tall, wide, square')]
    property AspectRatio: string read FAspectRatio write FAspectRatio;

    [AiMCPOptional]
    [AiMCPSchemaDescription('image only: small, medium, large')]
    property Size: string read FSize write FSize;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Results per page (default 10; max 20 anonymous, 50 registered)')]
    property Limit: Integer read FLimit write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page number (default 1). Ask for more pages only when needed: the daily quota is small.')]
    property Page: Integer read FPage write FPage;
  end;

  TOvItemParams = class
  private
    FMedia, FId: string;
    FLimit: Integer;
  public
    constructor Create;
    [AiMCPSchemaDescription('Media type: audio or image')]
    property Media: string read FMedia write FMedia;

    [AiMCPSchemaDescription('Openverse id (UUID) from openverse_search')]
    property Id: string read FId write FId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('openverse_related only: max results (default 10, max 20)')]
    property Limit: Integer read FLimit write FLimit;
  end;

  TOvDownloadParams = class
  private
    FMedia, FIds, FDir, FUse, FCategory, FNeed: string;
    FPreferOriginal, FAllowRestricted: Boolean;
  public
    [AiMCPSchemaDescription('Media type: audio or image')]
    property Media: string read FMedia write FMedia;

    [AiMCPSchemaDescription('Openverse ids from openverse_search, comma separated (max 10)')]
    property Ids: string read FIds write FIds;

    [AiMCPSchemaDescription('Absolute destination folder (created if missing). openverse_manifest.json is ' +
      'written there.')]
    property Dir: string read FDir write FDir;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Intended use (default commercial). Items whose licence does not allow it are ' +
      'skipped unless allowRestricted=true.')]
    property Use: string read FUse write FUse;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Category written to the manifest (e.g. ui, impacts, music, photos)')]
    property Category: string read FCategory write FCategory;

    [AiMCPOptional]
    [AiMCPSchemaDescription('What the item is for, written to the manifest (e.g. ui_click, hero_reveal_hit)')]
    property Need: string read FNeed write FNeed;

    [AiMCPOptional]
    [AiMCPSchemaDescription('audio: download the WAV/FLAC original when Openverse lists one (default false)')]
    property PreferOriginal: Boolean read FPreferOriginal write FPreferOriginal;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Download even if the licence does not allow "use" (default false). Only when the ' +
      'user explicitly asked for it.')]
    property AllowRestricted: Boolean read FAllowRestricted write FAllowRestricted;
  end;

  TOvCreditsParams = class
  private
    FMedia, FIds, FManifest, FFormat, FLang: string;
    FIncludeCc0: Boolean;
  public
    constructor Create;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Media type of "ids": audio or image')]
    property Media: string read FMedia write FMedia;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Openverse ids, comma separated (max 50)')]
    property Ids: string read FIds write FIds;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Absolute path of an openverse_manifest.json written by openverse_download (or an ' +
      'earshot manifest with the same fields)')]
    property Manifest: string read FManifest write FManifest;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output format (default youtube = plain text for a video description)')]
    property Format: string read FFormat write FFormat;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Language of the text: en or es (default en)')]
    property Lang: string read FLang write FLang;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Also list CC0 / public domain items, which need no attribution (default false)')]
    property IncludeCc0: Boolean read FIncludeCc0 write FIncludeCc0;
  end;

  TOvStatusParams = class
  private
    FMedia: string;
  public
    [AiMCPOptional]
    [AiMCPSchemaDescription('Only the sources of this media type (default: both)')]
    property Media: string read FMedia write FMedia;
  end;

  TOvSearchTool = class(TAiMCPToolBase<TOvSearchParams>)
  protected
    function ExecuteWithParams(const AParams: TOvSearchParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TOvGetTool = class(TAiMCPToolBase<TOvItemParams>)
  protected
    function ExecuteWithParams(const AParams: TOvItemParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TOvRelatedTool = class(TAiMCPToolBase<TOvItemParams>)
  protected
    function ExecuteWithParams(const AParams: TOvItemParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TOvDownloadTool = class(TAiMCPToolBase<TOvDownloadParams>)
  protected
    function ExecuteWithParams(const AParams: TOvDownloadParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TOvCreditsTool = class(TAiMCPToolBase<TOvCreditsParams>)
  protected
    function ExecuteWithParams(const AParams: TOvCreditsParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TOvStatusTool = class(TAiMCPToolBase<TOvStatusParams>)
  protected
    function ExecuteWithParams(const AParams: TOvStatusParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

// AAllowDisk = False en http/sse: no se registra openverse_download y
// openverse_credits no lee manifiestos (un proceso compartido no toca disco
// por orden del modelo; ver _shared/MCPTool.Credential.pas).
procedure RegisterTools(AServer: TAiMCPServer; AAllowDisk: Boolean);

implementation

uses
  System.Math,
  System.DateUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  MCPTool.Licenses,
  MCPTool.OpenverseApi;

const
  NOTE_VERIFY =
    'Licences are as indexed by Openverse and can be out of date: confirm on page_url before publishing.';
  MAX_FILE_BYTES = Int64(100) * 1024 * 1024;
  MAX_CALL_BYTES = Int64(300) * 1024 * 1024;
  MAX_MANIFEST_BYTES = 10 * 1024 * 1024;
  ALLOWED_EXTS: array[0..13] of string = ('mp3', 'ogg', 'wav', 'flac', 'm4a', 'aac', 'opus',
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'tif', 'tiff');

var
  GAllowDisk: Boolean = True;

{ ---------- utilidades ---------- }

function Api: TOpenverseApi;
begin
  Result := TOpenverseApi.Instance;
end;

function JStr(O: TJSONObject; const N: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  if O = nil then Exit;
  V := O.GetValue(N);
  if (V = nil) or (V is TJSONNull) then Exit;
  if V is TJSONString then
    Result := TJSONString(V).Value
  else if (V is TJSONNumber) or (V is TJSONBool) then
    Result := V.Value;
end;

function JNum(O: TJSONObject; const N: string; out D: Double): Boolean;
var
  V: TJSONValue;
begin
  D := 0;
  Result := False;
  if O = nil then Exit;
  V := O.GetValue(N);
  if V is TJSONNumber then
  begin
    D := TJSONNumber(V).AsDouble;
    Result := True;
  end;
end;

// Numero JSON: enteros sin ".0" (5240986 y no 5240986.0)
function JNumber(const D: Double): TJSONNumber;
begin
  if (Frac(D) = 0) and (Abs(D) < 1e15) then
    Result := TJSONNumber.Create(Trunc(D))
  else
    Result := TJSONNumber.Create(D);
end;

procedure CopyNum(Src, Dst: TJSONObject; const SrcName, DstName: string; ADiv: Double = 1);
var
  D: Double;
begin
  if JNum(Src, SrcName, D) then
  begin
    if ADiv <> 1 then
      Dst.AddPair(DstName, JNumber(RoundTo(D / ADiv, -2)))
    else
      Dst.AddPair(DstName, JNumber(D));
  end;
end;

procedure AddStr(Dst: TJSONObject; const N, V: string);
begin
  if V <> '' then
    Dst.AddPair(N, V);
end;

function LicenseOf(Src: TJSONObject): TOvLicense;
begin
  Result := OvLicense(JStr(Src, 'license'), JStr(Src, 'license_version'));
end;

function LicenseUrlOf(Src: TJSONObject; const L: TOvLicense): string;
begin
  Result := JStr(Src, 'license_url');
  if Result = '' then
    Result := OvLicenseUrl(L.Code, L.Version);
end;

// Formato de atribucion de earshot (TASL: titulo, autor, fuente, licencia)
function AttributionText(const ATitle, ACreator, APage, ALic, ALicUrl: string): string;
begin
  Result := '"' + ATitle + '"';
  if ACreator <> '' then
    Result := Result + ' by ' + ACreator;
  if APage <> '' then
    Result := Result + ' (' + APage + ')';
  Result := Result + ', licensed under ' + ALic;
  if ALicUrl <> '' then
    Result := Result + ' (' + ALicUrl + ')';
end;

function NewOk: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('ok', TJSONBool.Create(True));
end;

function ToolResult(R: TJSONObject): TJSONObject;
begin
  try
    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
  finally
    R.Free;
  end;
end;

function ToolError(const AMsg: string): TJSONObject;
var
  R: TJSONObject;
begin
  R := TJSONObject.Create;
  R.AddPair('ok', TJSONBool.Create(False));
  R.AddPair('error', AMsg);
  Result := ToolResult(R);
end;

type
  TOvBody = reference to function: TJSONObject;

function RunTool(const ABody: TOvBody): TJSONObject;
begin
  try
    Result := ToolResult(ABody());
  except
    on E: Exception do
      Result := ToolError(E.Message);
  end;
end;

function NormUse(const AUse: string): string;
begin
  Result := LowerCase(Trim(AUse));
  if Result = '' then
    Result := 'commercial';
  if not OvValidUse(Result) then
    raise EOpenverse.Create('"use" must be commercial, modify, commercial_modify or any');
end;

procedure CheckSimpleList(const AName, AValue: string);
var
  Ch: Char;
begin
  for Ch in AValue do
    if not CharInSet(Ch, ['a'..'z', '0'..'9', ',', '-', '+', '_']) then
      raise EOpenverse.CreateFmt('"%s" has an invalid character: %s', [AName, Ch]);
end;

procedure AddOpt(var Q: string; const AName, AValue: string);
begin
  if Trim(AValue) <> '' then
    Q := Q + '&' + AName + '=' + OvUrlEncode(Trim(AValue));
end;

function SplitIds(const S: string; AMax: Integer): TArray<string>;
var
  Parts: TArray<string>;
  P, Id: string;
  L: TList<string>;
begin
  L := TList<string>.Create;
  try
    Parts := S.Replace(' ', ',').Replace(';', ',').Split([',']);
    for P in Parts do
    begin
      Id := LowerCase(Trim(P));
      if Id = '' then Continue;
      if not OvValidId(Id) then
        raise EOpenverse.CreateFmt('invalid Openverse id: "%s"', [Id]);
      if not L.Contains(Id) then
        L.Add(Id);
    end;
    if L.Count > AMax then
      raise EOpenverse.CreateFmt('at most %d ids per call', [AMax]);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function ItemPath(const AMediaPath, AId: string): string;
begin
  Result := '/v1/' + AMediaPath + '/' + AId + '/';
end;

{ Item compacto: lo justo para decidir, sin waveform ni listas largas }
function CompactItem(const AMediaPath: string; Src: TJSONObject; AFull: Boolean): TJSONObject;
var
  L: TOvLicense;
  Tags, OutArr, Alts, OutAlts: TJSONArray;
  Alt: TJSONObject;
  I: Integer;
  V: TJSONValue;
begin
  L := LicenseOf(Src);
  Result := TJSONObject.Create;
  Result.AddPair('id', JStr(Src, 'id'));
  Result.AddPair('title', JStr(Src, 'title'));
  AddStr(Result, 'creator', JStr(Src, 'creator'));
  AddStr(Result, 'source', JStr(Src, 'source'));
  Result.AddPair('license', L.Display);
  Result.AddPair('license_code', L.Code);
  AddStr(Result, 'license_url', LicenseUrlOf(Src, L));
  Result.AddPair('commercial_ok', TJSONBool.Create(L.Known and L.CommercialOk));
  Result.AddPair('modify_ok', TJSONBool.Create(L.Known and L.ModifyOk));
  Result.AddPair('attribution_required', TJSONBool.Create((not L.Known) or L.AttributionRequired));
  if not L.Known then
    Result.AddPair('license_note', 'unknown licence code: read the licence on page_url before using it');

  if AMediaPath = 'audio' then
  begin
    CopyNum(Src, Result, 'duration', 'duration_s', 1000);
    AddStr(Result, 'filetype', JStr(Src, 'filetype'));
    CopyNum(Src, Result, 'sample_rate', 'sample_rate');
  end
  else
  begin
    CopyNum(Src, Result, 'width', 'width');
    CopyNum(Src, Result, 'height', 'height');
    AddStr(Result, 'filetype', JStr(Src, 'filetype'));
    AddStr(Result, 'thumb_url', JStr(Src, 'thumbnail'));
  end;

  AddStr(Result, 'page_url', JStr(Src, 'foreign_landing_url'));
  AddStr(Result, 'file_url', JStr(Src, 'url'));

  V := Src.GetValue('tags');
  if V is TJSONArray then
  begin
    Tags := TJSONArray(V);
    OutArr := TJSONArray.Create;
    for I := 0 to Min(Tags.Count, 8) - 1 do
      if Tags.Items[I] is TJSONObject then
        OutArr.Add(JStr(TJSONObject(Tags.Items[I]), 'name'));
    Result.AddPair('tags', OutArr);
  end;

  if AFull then
  begin
    AddStr(Result, 'creator_url', JStr(Src, 'creator_url'));
    AddStr(Result, 'category', JStr(Src, 'category'));
    CopyNum(Src, Result, 'filesize', 'filesize');
    CopyNum(Src, Result, 'bit_rate', 'bit_rate');
    Result.AddPair('attribution', AttributionText(JStr(Src, 'title'), JStr(Src, 'creator'),
      JStr(Src, 'foreign_landing_url'), L.Display, LicenseUrlOf(Src, L)));
    AddStr(Result, 'openverse_attribution', JStr(Src, 'attribution'));
    V := Src.GetValue('genres');
    if V is TJSONArray then
      Result.AddPair('genres', TJSONArray(V.Clone));
    V := Src.GetValue('alt_files');
    if V is TJSONArray then
    begin
      Alts := TJSONArray(V);
      OutAlts := TJSONArray.Create;
      for I := 0 to Alts.Count - 1 do
        if Alts.Items[I] is TJSONObject then
        begin
          Alt := TJSONObject.Create;
          AddStr(Alt, 'url', JStr(TJSONObject(Alts.Items[I]), 'url'));
          AddStr(Alt, 'filetype', JStr(TJSONObject(Alts.Items[I]), 'filetype'));
          CopyNum(TJSONObject(Alts.Items[I]), Alt, 'filesize', 'filesize');
          CopyNum(TJSONObject(Alts.Items[I]), Alt, 'sample_rate', 'sample_rate');
          OutAlts.AddElement(Alt);
        end;
      Result.AddPair('alt_files', OutAlts);
    end;
  end;
end;

{ ---------- parametros ---------- }

constructor TOvSearchParams.Create;
begin
  inherited;
  FUse   := 'commercial';
  FLimit := 10;
  FPage  := 1;
end;

constructor TOvItemParams.Create;
begin
  inherited;
  FLimit := 10;
end;

constructor TOvCreditsParams.Create;
begin
  inherited;
  FFormat := 'youtube';
  FLang   := 'en';
end;

{ ---------- openverse_search ---------- }

constructor TOvSearchTool.Create;
begin
  inherited;
  FName := 'openverse_search';
  FDescription :=
    'Search openly licensed images and audio (Creative Commons / public domain) on Openverse: 5M sounds ' +
    '(Freesound effects, Jamendo music, Wikimedia) and 900M+ images (Flickr, Wikimedia, museums...). ' +
    'By default returns only items whose licence allows commercial use. Each result says commercial_ok, ' +
    'modify_ok and attribution_required. Query in English. The anonymous quota is 200 requests/day: ' +
    'search narrowly (category, length, source) instead of paging.';
end;

function TOvSearchTool.ExecuteWithParams(const AParams: TOvSearchParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  P: TOvSearchParams;
begin
  P := AParams;
  Result := RunTool(
    function: TJSONObject
    var
      MP, Use, Lic, Q: string;
      Limit, MaxLimit, Page, I, Dropped: Integer;
      V, R: TJSONValue;
      Root, It: TJSONObject;
      Res: TJSONArray;
      D: Double;
    begin
      MP := OvMediaPath(P.Media);
      if Trim(P.Query) = '' then
        raise EOpenverse.Create('"query" is required');
      Use := NormUse(P.Use);

      if Api.Authenticated then MaxLimit := 50 else MaxLimit := 20;
      Limit := P.Limit;
      if Limit <= 0 then Limit := 10;
      if Limit > MaxLimit then Limit := MaxLimit;
      Page := Max(P.Page, 1);

      Q := '/v1/' + MP + '/?q=' + OvUrlEncode(Trim(P.Query));
      Lic := LowerCase(Trim(P.Licenses)).Replace(' ', '');
      if Lic <> '' then
      begin
        CheckSimpleList('licenses', Lic);
        Q := Q + '&license=' + OvUrlEncode(Lic);
      end
      else if Use <> 'any' then
        Q := Q + '&license=' + OvUrlEncode(OvLicensesFor(Use));

      AddOpt(Q, 'category', LowerCase(P.Category));
      if MP = 'audio' then
        AddOpt(Q, 'length', LowerCase(P.Length));
      AddOpt(Q, 'source', LowerCase(P.Source));
      AddOpt(Q, 'creator', P.Creator);
      AddOpt(Q, 'extension', LowerCase(P.Extension));
      if MP = 'images' then
      begin
        AddOpt(Q, 'aspect_ratio', LowerCase(P.AspectRatio));
        AddOpt(Q, 'size', LowerCase(P.Size));
      end;
      Q := Q + Format('&page_size=%d&page=%d&filter_dead=true&mature=false', [Limit, Page]);

      V := Api.GetJSON(Q, OV_TTL_SEARCH);
      try
        if not (V is TJSONObject) then
          raise EOpenverse.Create('Openverse: unexpected search response');
        Root := TJSONObject(V);
        Res := TJSONArray.Create;
        Dropped := 0;
        R := Root.GetValue('results');
        if R is TJSONArray then
          for I := 0 to TJSONArray(R).Count - 1 do
            if TJSONArray(R).Items[I] is TJSONObject then
            begin
              It := TJSONObject(TJSONArray(R).Items[I]);
              // Segunda barrera: aunque la API ya filtro, se comprueba con la tabla propia
              if (Lic = '') and not LicenseOf(It).AllowsUse(Use) then
                Inc(Dropped)
              else
                Res.AddElement(CompactItem(MP, It, False));
            end;

        Result := NewOk;
        Result.AddPair('media', LowerCase(Trim(P.Media)));
        if Lic <> '' then
          Result.AddPair('licenses', Lic)
        else
          Result.AddPair('use', Use);
        if JNum(Root, 'result_count', D) then
          Result.AddPair('total', JNumber(D));
        Result.AddPair('page', TJSONNumber.Create(Page));
        if JNum(Root, 'page_count', D) then
          Result.AddPair('pages', JNumber(D));
        Result.AddPair('count', TJSONNumber.Create(Res.Count));
        Result.AddPair('results', Res);
        if Dropped > 0 then
          Result.AddPair('dropped_by_licence_check', TJSONNumber.Create(Dropped));
        Result.AddPair('quota', Api.QuotaJSON);
        Result.AddPair('note', NOTE_VERIFY);
      finally
        V.Free;
      end;
    end);
end;

{ ---------- openverse_get ---------- }

constructor TOvGetTool.Create;
begin
  inherited;
  FName := 'openverse_get';
  FDescription :=
    'Full details of one Openverse item: licence, ready-made attribution text, creator, page_url, ' +
    'file size and, for audio, alternative files (e.g. the original WAV).';
end;

function TOvGetTool.ExecuteWithParams(const AParams: TOvItemParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  P: TOvItemParams;
begin
  P := AParams;
  Result := RunTool(
    function: TJSONObject
    var
      MP, Id: string;
      V: TJSONValue;
    begin
      MP := OvMediaPath(P.Media);
      Id := LowerCase(Trim(P.Id));
      if not OvValidId(Id) then
        raise EOpenverse.Create('"id" must be an Openverse id (UUID)');
      V := Api.GetJSON(ItemPath(MP, Id), OV_TTL_DETAIL);
      try
        if not (V is TJSONObject) then
          raise EOpenverse.Create('Openverse: unexpected item response');
        Result := NewOk;
        Result.AddPair('item', CompactItem(MP, TJSONObject(V), True));
        Result.AddPair('note', NOTE_VERIFY);
      finally
        V.Free;
      end;
    end);
end;

{ ---------- openverse_related ---------- }

constructor TOvRelatedTool.Create;
begin
  inherited;
  FName := 'openverse_related';
  FDescription :=
    'Items similar to a given Openverse item (variants of a sound or picture that already works). ' +
    'Results are not filtered by licence: check commercial_ok / modify_ok.';
end;

function TOvRelatedTool.ExecuteWithParams(const AParams: TOvItemParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  P: TOvItemParams;
begin
  P := AParams;
  Result := RunTool(
    function: TJSONObject
    var
      MP, Id: string;
      V, R: TJSONValue;
      Res: TJSONArray;
      I, Limit: Integer;
    begin
      MP := OvMediaPath(P.Media);
      Id := LowerCase(Trim(P.Id));
      if not OvValidId(Id) then
        raise EOpenverse.Create('"id" must be an Openverse id (UUID)');
      Limit := P.Limit;
      if (Limit <= 0) or (Limit > 20) then Limit := Min(Max(Limit, 10), 20);

      V := Api.GetJSON(ItemPath(MP, Id) + 'related/', OV_TTL_SEARCH);
      try
        Res := TJSONArray.Create;
        if V is TJSONObject then
        begin
          R := TJSONObject(V).GetValue('results');
          if R is TJSONArray then
            for I := 0 to TJSONArray(R).Count - 1 do
            begin
              if Res.Count >= Limit then Break;
              if TJSONArray(R).Items[I] is TJSONObject then
                Res.AddElement(CompactItem(MP, TJSONObject(TJSONArray(R).Items[I]), False));
            end;
        end;
        Result := NewOk;
        Result.AddPair('count', TJSONNumber.Create(Res.Count));
        Result.AddPair('results', Res);
        Result.AddPair('note', NOTE_VERIFY);
      finally
        V.Free;
      end;
    end);
end;

{ ---------- openverse_download ---------- }

function Slug(const S: string): string;
var
  Ch: Char;
  Dash: Boolean;
begin
  Result := '';
  Dash := False;
  for Ch in LowerCase(S) do
    if CharInSet(Ch, ['a'..'z', '0'..'9']) then
    begin
      Result := Result + Ch;
      Dash := False;
    end
    else if (not Dash) and (Result <> '') then
    begin
      Result := Result + '-';
      Dash := True;
    end;
  if System.Length(Result) > 40 then
    SetLength(Result, 40);
  Result := Result.Trim(['-']);
  if Result = '' then
    Result := 'item';
end;

function ExtFromUrl(const AUrl: string): string;
var
  P: string;
  I: Integer;
begin
  P := AUrl;
  I := P.IndexOfAny(['?', '#']);
  if I >= 0 then
    P := P.Substring(0, I);
  I := P.LastIndexOf('/');
  if I >= 0 then
    P := P.Substring(I + 1);
  I := P.LastIndexOf('.');
  if I >= 0 then
    Result := LowerCase(P.Substring(I + 1))
  else
    Result := '';
end;

function AllowedExt(const AExt: string): Boolean;
var
  E: string;
begin
  for E in ALLOWED_EXTS do
    if E = AExt then
      Exit(True);
  Result := False;
end;

procedure PickOriginal(Src: TJSONObject; var AUrl, AType: string; var ASize: Double);
const
  PREFERRED: array[0..1] of string = ('wav', 'flac');
var
  V: TJSONValue;
  A: TJSONArray;
  Ext: string;
  I: Integer;
  It: TJSONObject;
  D: Double;
begin
  V := Src.GetValue('alt_files');
  if not (V is TJSONArray) then Exit;
  A := TJSONArray(V);
  for Ext in PREFERRED do
    for I := 0 to A.Count - 1 do
      if A.Items[I] is TJSONObject then
      begin
        It := TJSONObject(A.Items[I]);
        // Las URL de la API de Freesound (/apiv2/.../download/) exigen OAuth
        // propio de Freesound: sin eso dan 401. Se usa la vista previa.
        if (LowerCase(JStr(It, 'filetype')) = Ext) and (JStr(It, 'url') <> '') and
           (Pos('/apiv2/', LowerCase(JStr(It, 'url'))) = 0) then
        begin
          AUrl  := JStr(It, 'url');
          AType := Ext;
          if JNum(It, 'filesize', D) then ASize := D else ASize := 0;
          Exit;
        end;
      end;
end;

function UtcNowIso: string;
begin
  Result := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
end;

function LoadManifest(const APath: string): TJSONArray;
var
  V: TJSONValue;
begin
  if not TFile.Exists(APath) then
    Exit(TJSONArray.Create);
  if TFile.GetSize(APath) > MAX_MANIFEST_BYTES then
    raise EOpenverse.Create('manifest too large: ' + APath);
  V := TJSONObject.ParseJSONValue(TFile.ReadAllText(APath, TEncoding.UTF8));
  if not (V is TJSONArray) then
  begin
    V.Free;
    raise EOpenverse.Create('the existing manifest is not a JSON list, not touching it: ' + APath);
  end;
  Result := TJSONArray(V);
end;

procedure SaveManifest(const APath: string; AArr: TJSONArray);
var
  Tmp: string;
begin
  Tmp := APath + '.tmp';
  // Sin BOM: lo leen Python (earshot) y otras herramientas
  TFile.WriteAllBytes(Tmp, TEncoding.UTF8.GetBytes(AArr.Format(2)));
  if TFile.Exists(APath) then
    TFile.Delete(APath);
  TFile.Move(Tmp, APath);
end;

procedure UpsertManifest(AArr: TJSONArray; AEntry: TJSONObject; const AOvId: string);
var
  I: Integer;
begin
  for I := AArr.Count - 1 downto 0 do
    if (AArr.Items[I] is TJSONObject) and
       (JStr(TJSONObject(AArr.Items[I]), 'openverse_id') = AOvId) then
      AArr.Remove(I).Free;
  AArr.AddElement(AEntry);
end;

procedure AddSkip(AArr: TJSONArray; const AId, AReason: string);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('id', AId);
  O.AddPair('reason', AReason);
  AArr.AddElement(O);
end;

constructor TOvDownloadTool.Create;
begin
  inherited;
  FName := 'openverse_download';
  FDescription :=
    'Download Openverse items (by id, from openverse_search) into a local folder and record each one in ' +
    'openverse_manifest.json (title, author, page_url, licence, attribution; same fields as an earshot ' +
    'manifest). Skips items whose licence does not allow "use". Max 10 ids, 100 MB per file, 300 MB per call. ' +
    'Then pick the best take with earshot (rank / find) and build credits with openverse_credits.';
end;

function TOvDownloadTool.ExecuteWithParams(const AParams: TOvDownloadParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  P: TOvDownloadParams;
begin
  P := AParams;
  Result := RunTool(
    function: TJSONObject
    var
      MP, Use, Dir, ManPath, Id, Url, FType, FileName, Dest, Title: string;
      Ids: TArray<string>;
      Manifest, Done, Skipped: TJSONArray;
      V: TJSONValue;
      Src, Entry, Item: TJSONObject;
      L: TOvLicense;
      Size: Double;
      Bytes, Total: Int64;
      Existed: Boolean;
    begin
      MP  := OvMediaPath(P.Media);
      Use := NormUse(P.Use);
      Dir := Trim(P.Dir);
      if Dir = '' then
        raise EOpenverse.Create('"dir" is required');
      if not TPath.IsPathRooted(Dir) then
        raise EOpenverse.Create('"dir" must be an absolute path');
      if Dir.Contains('..') then
        raise EOpenverse.Create('"dir" must not contain ".."');
      Dir := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Dir));
      Ids := SplitIds(P.Ids, 10);
      if System.Length(Ids) = 0 then
        raise EOpenverse.Create('"ids" is required');

      ForceDirectories(Dir);
      ManPath := TPath.Combine(Dir, 'openverse_manifest.json');
      Manifest := LoadManifest(ManPath);
      Done    := TJSONArray.Create;
      Skipped := TJSONArray.Create;
      Total   := 0;
      try
        for Id in Ids do
        begin
          try
            V := Api.GetJSON(ItemPath(MP, Id), OV_TTL_DETAIL);
            try
              if not (V is TJSONObject) then
                raise EOpenverse.Create('unexpected item response');
              Src := TJSONObject(V);
              L := LicenseOf(Src);
              if (not P.AllowRestricted) and (not L.AllowsUse(Use)) then
              begin
                AddSkip(Skipped, Id, Format('licence %s does not allow use "%s" (allowRestricted=false)',
                  [L.Display, Use]));
                Continue;
              end;

              // La URL sale SIEMPRE de la API, nunca del modelo
              Url   := JStr(Src, 'url');
              FType := LowerCase(JStr(Src, 'filetype'));
              if not JNum(Src, 'filesize', Size) then Size := 0;
              if P.PreferOriginal and (MP = 'audio') then
                PickOriginal(Src, Url, FType, Size);
              if Url = '' then
              begin
                AddSkip(Skipped, Id, 'Openverse lists no file url');
                Continue;
              end;
              FType := FType.TrimLeft(['.']);
              if FType = '' then
                FType := ExtFromUrl(Url);
              if not AllowedExt(FType) then
              begin
                AddSkip(Skipped, Id, 'file type not allowed: "' + FType + '"');
                Continue;
              end;
              if Size > MAX_FILE_BYTES then
              begin
                AddSkip(Skipped, Id, 'file larger than 100 MB');
                Continue;
              end;
              if Total + Size > MAX_CALL_BYTES then
              begin
                AddSkip(Skipped, Id, '300 MB per call reached: download it in another call');
                Continue;
              end;

              Title := JStr(Src, 'title');
              FileName := 'ov-' + Copy(Id, 1, 8) + '_' + Slug(Title) + '.' + FType;
              Dest := TPath.Combine(Dir, FileName);
              if not TPath.GetFullPath(Dest).StartsWith(IncludeTrailingPathDelimiter(Dir)) then
                raise EOpenverse.Create('destination outside "dir"');

              Existed := TFile.Exists(Dest);
              if Existed then
                Bytes := TFile.GetSize(Dest)
              else
              begin
                Bytes := Api.DownloadFile(Url, Dest, Min(MAX_FILE_BYTES, MAX_CALL_BYTES - Total));
                Inc(Total, Bytes);
              end;

              Entry := TJSONObject.Create;
              Entry.AddPair('id', 'ov-' + Copy(Id, 1, 8));
              Entry.AddPair('openverse_id', Id);
              Entry.AddPair('media', LowerCase(Trim(P.Media)));
              if Trim(P.Category) <> '' then
                Entry.AddPair('category', Trim(P.Category))
              else
                AddStr(Entry, 'category', JStr(Src, 'category'));
              Entry.AddPair('file', FileName);
              Entry.AddPair('title', Title);
              Entry.AddPair('author', JStr(Src, 'creator'));
              Entry.AddPair('source', JStr(Src, 'source'));
              Entry.AddPair('page_url', JStr(Src, 'foreign_landing_url'));
              Entry.AddPair('download_url', Url);
              Entry.AddPair('license', L.Display);
              Entry.AddPair('license_code', L.Code);
              Entry.AddPair('license_url', LicenseUrlOf(Src, L));
              if L.Known and L.IsPublicDomain then
                Entry.AddPair('attribution', TJSONNull.Create)
              else
                Entry.AddPair('attribution', AttributionText(Title, JStr(Src, 'creator'),
                  JStr(Src, 'foreign_landing_url'), L.Display, LicenseUrlOf(Src, L)));
              AddStr(Entry, 'need', Trim(P.Need));
              Entry.AddPair('licence_checked_on_page', TJSONBool.Create(False));
              Entry.AddPair('retrieved_at', UtcNowIso);
              UpsertManifest(Manifest, Entry, Id);

              Item := TJSONObject.Create;
              Item.AddPair('id', Id);
              Item.AddPair('file', TPath.Combine(Dir, FileName));
              Item.AddPair('bytes', TJSONNumber.Create(Bytes));
              Item.AddPair('license', L.Display);
              if Existed then
                Item.AddPair('already_there', TJSONBool.Create(True));
              Done.AddElement(Item);
            finally
              V.Free;
            end;
          except
            on E: Exception do
              AddSkip(Skipped, Id, E.Message);
          end;
        end;

        if Done.Count > 0 then
          SaveManifest(ManPath, Manifest);

        Result := TJSONObject.Create;
        Result.AddPair('ok', TJSONBool.Create(Done.Count > 0));
        Result.AddPair('dir', Dir);
        Result.AddPair('manifest', ManPath);
        Result.AddPair('downloaded', Done);
        Result.AddPair('skipped', Skipped);
        Result.AddPair('total_bytes', JNumber(Total));
        Result.AddPair('note', NOTE_VERIFY +
          ' Set licence_checked_on_page=true in the manifest once checked.');
        Done := nil;
        Skipped := nil;
      finally
        Manifest.Free;
        Done.Free;
        Skipped.Free;
      end;
    end);
end;

{ ---------- openverse_credits ---------- }

type
  TCredit = record
    Title, Author, Page, Lic, LicUrl: string;
    L: TOvLicense;
  end;

function CodeFromDisplay(const ALicense: string): string;
var
  S: string;
  I: Integer;
begin
  S := UpperCase(Trim(ALicense));
  if S.StartsWith('CC0') then
    Exit('cc0');
  if S.StartsWith('PUBLIC DOMAIN') then
    Exit('pdm');
  if S.StartsWith('CC ') then
  begin
    S := S.Substring(3);
    I := S.IndexOf(' ');
    if I >= 0 then
      S := S.Substring(0, I);
    Exit(LowerCase(S));
  end;
  Result := '';
end;

function HtmlEsc(const S: string): string;
begin
  Result := S.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;');
end;

function CreditLine(const C: TCredit; const AFormat, ALang: string): string;
var
  By: string;
begin
  if ALang = 'es' then By := ' de ' else By := ' by ';
  if AFormat = 'markdown' then
  begin
    Result := '- [' + C.Title + '](' + C.Page + ')';
    if C.Author <> '' then Result := Result + By + C.Author;
    Result := Result + ' - [' + C.Lic + '](' + C.LicUrl + ')';
  end
  else if AFormat = 'html' then
  begin
    Result := '<li><a href="' + HtmlEsc(C.Page) + '">' + HtmlEsc(C.Title) + '</a>';
    if C.Author <> '' then Result := Result + HtmlEsc(By + C.Author);
    Result := Result + ', <a href="' + HtmlEsc(C.LicUrl) + '">' + HtmlEsc(C.Lic) + '</a></li>';
  end
  else
  begin
    Result := '"' + C.Title + '"';
    if C.Author <> '' then Result := Result + By + C.Author;
    if C.Page <> '' then Result := Result + ' (' + C.Page + ')';
    if ALang = 'es' then
      Result := Result + ' - licencia ' + C.Lic
    else
      Result := Result + ' - licensed under ' + C.Lic;
    if C.LicUrl <> '' then Result := Result + ' (' + C.LicUrl + ')';
  end;
end;

constructor TOvCreditsTool.Create;
begin
  inherited;
  FName := 'openverse_credits';
  FDescription :=
    'Build the credits for openly licensed items, from Openverse ids and/or an openverse_manifest.json: ' +
    'plain text for a YouTube description, Markdown, HTML or JSON (title, author, source page, licence). ' +
    'CC0 / public domain items are left out unless includeCc0=true. Warns about NC (non-commercial), ' +
    'ND (no edits), SA and unknown licences.';
end;

function TOvCreditsTool.ExecuteWithParams(const AParams: TOvCreditsParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  P: TOvCreditsParams;
begin
  P := AParams;
  Result := RunTool(
    function: TJSONObject
    var
      Fmt, Lang, MP, Id, Head, PdHead, Code: string;
      Ids: TArray<string>;
      Credits: TList<TCredit>;
      C: TCredit;
      V: TJSONValue;
      Arr, JsonOut, Warn: TJSONArray;
      O, JItem: TJSONObject;
      I: Integer;
      SB: TStringBuilder;
      Attr, Pd: TList<TCredit>;
      W: string;
    begin
      Fmt := LowerCase(Trim(P.Format));
      if Fmt = '' then Fmt := 'youtube';
      if (Fmt <> 'youtube') and (Fmt <> 'markdown') and (Fmt <> 'html') and (Fmt <> 'json') then
        raise EOpenverse.Create('"format" must be youtube, markdown, html or json');
      Lang := LowerCase(Trim(P.Lang));
      if Lang <> 'es' then Lang := 'en';
      if (Trim(P.Ids) = '') and (Trim(P.Manifest) = '') then
        raise EOpenverse.Create('give "ids" (with "media") or "manifest"');

      Credits := TList<TCredit>.Create;
      Attr := TList<TCredit>.Create;
      Pd := TList<TCredit>.Create;
      Warn := TJSONArray.Create;
      SB := TStringBuilder.Create;
      try
        // 1) Desde un manifiesto
        if Trim(P.Manifest) <> '' then
        begin
          if not GAllowDisk then
            raise EOpenverse.Create('"manifest" is not available in server mode: use "ids"');
          if not TPath.IsPathRooted(Trim(P.Manifest)) then
            raise EOpenverse.Create('"manifest" must be an absolute path');
          if not TFile.Exists(Trim(P.Manifest)) then
            raise EOpenverse.Create('manifest not found: ' + Trim(P.Manifest));
          Arr := LoadManifest(Trim(P.Manifest));
          try
            for I := 0 to Arr.Count - 1 do
              if Arr.Items[I] is TJSONObject then
              begin
                O := TJSONObject(Arr.Items[I]);
                C := Default(TCredit);
                C.Title  := JStr(O, 'title');
                C.Author := JStr(O, 'author');
                C.Page   := JStr(O, 'page_url');
                C.Lic    := JStr(O, 'license');
                C.LicUrl := JStr(O, 'license_url');
                Code := JStr(O, 'license_code');
                if Code = '' then Code := CodeFromDisplay(C.Lic);
                C.L := OvLicense(Code, '');
                Credits.Add(C);
              end;
          finally
            Arr.Free;
          end;
        end;

        // 2) Desde ids (consulta el detalle, cacheado 24 h)
        if Trim(P.Ids) <> '' then
        begin
          MP := OvMediaPath(P.Media);
          Ids := SplitIds(P.Ids, 50);
          for Id in Ids do
          begin
            V := Api.GetJSON(ItemPath(MP, Id), OV_TTL_DETAIL);
            try
              if not (V is TJSONObject) then Continue;
              O := TJSONObject(V);
              C := Default(TCredit);
              C.Title  := JStr(O, 'title');
              C.Author := JStr(O, 'creator');
              C.Page   := JStr(O, 'foreign_landing_url');
              C.L      := LicenseOf(O);
              C.Lic    := C.L.Display;
              C.LicUrl := LicenseUrlOf(O, C.L);
              Credits.Add(C);
            finally
              V.Free;
            end;
          end;
        end;

        for C in Credits do
        begin
          if C.L.Known and C.L.IsPublicDomain then
            Pd.Add(C)
          else
            Attr.Add(C);
          W := '';
          if not C.L.Known then
            W := 'unknown licence "' + C.Lic + '": read it on the page before using'
          else if not C.L.CommercialOk then
            W := C.Lic + ': non-commercial use only'
          else if not C.L.ModifyOk then
            W := C.Lic + ': no derivatives (do not trim, edit or remix)'
          else if C.L.ShareAlike then
            W := C.Lic + ': adaptations must be shared under the same licence';
          if W <> '' then
            Warn.Add('"' + C.Title + '" - ' + W);
        end;

        if Fmt = 'json' then
        begin
          JsonOut := TJSONArray.Create;
          for C in Credits do
            if P.IncludeCc0 or not (C.L.Known and C.L.IsPublicDomain) then
            begin
              JItem := TJSONObject.Create;
              JItem.AddPair('title', C.Title);
              JItem.AddPair('author', C.Author);
              JItem.AddPair('page_url', C.Page);
              JItem.AddPair('license', C.Lic);
              JItem.AddPair('license_url', C.LicUrl);
              JItem.AddPair('attribution_required',
                TJSONBool.Create((not C.L.Known) or C.L.AttributionRequired));
              JsonOut.AddElement(JItem);
            end;
          Result := NewOk;
          Result.AddPair('format', Fmt);
          Result.AddPair('credits', JsonOut);
        end
        else
        begin
          if Lang = 'es' then
          begin
            Head   := 'Cr' + #$00E9 + 'ditos:';
            PdHead := 'Dominio p' + #$00FA + 'blico / CC0 (no requiere atribuci' + #$00F3 + 'n):';
          end
          else
          begin
            Head   := 'Credits:';
            PdHead := 'Public domain / CC0 (no attribution required):';
          end;

          if Attr.Count > 0 then
          begin
            if Fmt = 'html' then SB.Append('<p>' + HtmlEsc(Head) + '</p>' + sLineBreak + '<ul>' + sLineBreak)
            else if Fmt = 'markdown' then SB.Append('**' + Head + '**' + sLineBreak + sLineBreak)
            else SB.Append(Head + sLineBreak);
            for C in Attr do
              SB.Append(CreditLine(C, Fmt, Lang) + sLineBreak);
            if Fmt = 'html' then SB.Append('</ul>' + sLineBreak);
          end;

          if P.IncludeCc0 and (Pd.Count > 0) then
          begin
            if Attr.Count > 0 then SB.Append(sLineBreak);
            if Fmt = 'html' then SB.Append('<p>' + HtmlEsc(PdHead) + '</p>' + sLineBreak + '<ul>' + sLineBreak)
            else if Fmt = 'markdown' then SB.Append('**' + PdHead + '**' + sLineBreak + sLineBreak)
            else SB.Append(PdHead + sLineBreak);
            for C in Pd do
              SB.Append(CreditLine(C, Fmt, Lang) + sLineBreak);
            if Fmt = 'html' then SB.Append('</ul>' + sLineBreak);
          end;

          Result := NewOk;
          Result.AddPair('format', Fmt);
          Result.AddPair('text', SB.ToString.TrimRight);
        end;

        Result.AddPair('items', TJSONNumber.Create(Credits.Count));
        Result.AddPair('needing_attribution', TJSONNumber.Create(Attr.Count));
        if Warn.Count > 0 then
        begin
          Result.AddPair('warnings', Warn);
          Warn := nil;
        end;
        Result.AddPair('note', NOTE_VERIFY);
      finally
        Warn.Free;
        SB.Free;
        Pd.Free;
        Attr.Free;
        Credits.Free;
      end;
    end);
end;

{ ---------- openverse_status ---------- }

constructor TOvStatusTool.Create;
begin
  inherited;
  FName := 'openverse_status';
  FDescription :=
    'Openverse connection status: anonymous or registered, remaining quota (from the last response) and ' +
    'the available sources with their item counts (cached 24 h). Use it before a large batch of searches.';
end;

function TOvStatusTool.ExecuteWithParams(const AParams: TOvStatusParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  P: TOvStatusParams;
begin
  P := AParams;
  Result := RunTool(
    function: TJSONObject
    var
      Medias: TArray<string>;
      MP: string;
      V: TJSONValue;
      Arr: TJSONArray;
      List: TList<TJSONObject>;
      Sources: TJSONObject;
      OutArr: TJSONArray;
      O, S: TJSONObject;
      I: Integer;
      Total, D: Double;
      Quota: TJSONObject;
    begin
      if Trim(P.Media) <> '' then
        Medias := [OvMediaPath(P.Media)]
      else
        Medias := ['audio', 'images'];

      Result := NewOk;
      Result.AddPair('version', OV_VERSION);
      Result.AddPair('authenticated', TJSONBool.Create(Api.Authenticated));
      if not Api.Authenticated then
        Result.AddPair('auth_note', 'Anonymous: 20 requests/min, 200/day, small pages. Register at ' +
          'https://api.openverse.org/v1/#tag/auth and set OPENVERSE_CLIENT_ID / OPENVERSE_CLIENT_SECRET.');

      Sources := TJSONObject.Create;
      Result.AddPair('sources', Sources);
      for MP in Medias do
      begin
        V := Api.GetJSON('/v1/' + MP + '/stats/?format=json', OV_TTL_DETAIL);
        List := TList<TJSONObject>.Create;
        try
          if V is TJSONArray then
          begin
            Arr := TJSONArray(V);
            Total := 0;
            for I := 0 to Arr.Count - 1 do
              if Arr.Items[I] is TJSONObject then
              begin
                List.Add(TJSONObject(Arr.Items[I]));
                if JNum(TJSONObject(Arr.Items[I]), 'media_count', D) then
                  Total := Total + D;
              end;
            List.Sort(TComparer<TJSONObject>.Construct(
              function(const A, B: TJSONObject): Integer
              var
                DA, DB: Double;
              begin
                JNum(A, 'media_count', DA);
                JNum(B, 'media_count', DB);
                Result := CompareValue(DB, DA);
              end));
            O := TJSONObject.Create;
            O.AddPair('total_items', JNumber(Total));
            O.AddPair('source_count', TJSONNumber.Create(List.Count));
            OutArr := TJSONArray.Create;
            for I := 0 to Min(List.Count, 15) - 1 do
            begin
              S := TJSONObject.Create;
              S.AddPair('name', JStr(List[I], 'source_name'));
              S.AddPair('display_name', JStr(List[I], 'display_name'));
              CopyNum(List[I], S, 'media_count', 'count');
              OutArr.AddElement(S);
            end;
            O.AddPair('top_sources', OutArr);
            Sources.AddPair(MP, O);
          end;
        finally
          List.Free;
          V.Free;
        end;
      end;

      Quota := Api.QuotaJSON;
      if Quota.Count = 0 then
        Quota.AddPair('note', 'no request made yet in this session');
      Result.AddPair('quota', Quota);
    end);
end;

{ ---------- registro ---------- }

procedure RegisterTools(AServer: TAiMCPServer; AAllowDisk: Boolean);
begin
  GAllowDisk := AAllowDisk;
  AServer.RegisterTool('openverse_search',
    function: IAiMCPTool begin Result := TOvSearchTool.Create; end);
  AServer.RegisterTool('openverse_get',
    function: IAiMCPTool begin Result := TOvGetTool.Create; end);
  AServer.RegisterTool('openverse_related',
    function: IAiMCPTool begin Result := TOvRelatedTool.Create; end);
  if AAllowDisk then
    AServer.RegisterTool('openverse_download',
      function: IAiMCPTool begin Result := TOvDownloadTool.Create; end);
  AServer.RegisterTool('openverse_credits',
    function: IAiMCPTool begin Result := TOvCreditsTool.Create; end);
  AServer.RegisterTool('openverse_status',
    function: IAiMCPTool begin Result := TOvStatusTool.Create; end);

  if TOpenverseApi.Instance.Authenticated then
    WriteLn(ErrOutput, '[mcp-openverse] ready (registered client)')
  else
    WriteLn(ErrOutput, '[mcp-openverse] ready (anonymous: 200 requests/day)');
end;

end.
