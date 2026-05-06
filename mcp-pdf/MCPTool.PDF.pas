unit MCPTool.PDF;

(*
  MCPTool.PDF
  MCP tool: mcp-pdf

  100% Delphi — uses delphi-libraries/pdf (no DLLs required)

  Operations:
    info          — page count, sizes, version, encrypted status, file size
    extract_text  — extract text from all pages or a specific page (0-based)
    get_metadata  — title, author, subject, keywords, producer, creator, dates
    search        — search text, returns matches with page and position info
    split         — extract pages [from..to] into a new PDF file
    merge         — merge a list of PDF files into one output file
    rotate        — rotate pages by 90/180/270 degrees and save
    add_watermark — add a diagonal text watermark and save
    fill_form     — fill form fields from a JSON object and save
    list_fields   — list all AcroForm fields with types and current values
    is_scanned    — detect whether the PDF contains scanned page images

  Parameters:
    operation    (required) — one of the operations above
    file_path    — input PDF file path (required for all except merge)
    output_path  — output PDF file path (for split, merge, rotate, add_watermark, fill_form)
    password     — password for encrypted PDFs
    page         — 0-based page index; -1 = all pages (default -1)
    page_from    — 0-based start page for split (default 0)
    page_to      — 0-based end page inclusive for split; -1 = last (default -1)
    rotation     — degrees for rotate: 90, 180 or 270 (default 90)
    text         — search query (search) or watermark text (add_watermark)
    case_sensitive — case-sensitive search (default false)
    whole_word   — whole-word search (default false)
    opacity      — watermark opacity 0.0-1.0 (default 0.3)
    font_size    — watermark font size in points (default 48)
    fields       — JSON object with fieldName/value pairs for fill_form
    files        — JSON array of file paths for merge
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Math,
  System.IOUtils,
  System.DateUtils,
  uPDF.Document,
  uPDF.TextExtractor,
  uPDF.Metadata,
  uPDF.PageOperations,
  uPDF.Watermark,
  uPDF.TextSearch,
  uPDF.AcroForms,
  uPDF.AcroForms.Fill,
  uPDF.ScanDetector,
  uPDF.ImageExtractor;

type

  // ── Parameters ──────────────────────────────────────────────────────────────

  TPDFParams = class
  private
    FOperation:    string;
    FFilePath:     string;
    FOutputPath:   string;
    FPassword:     string;
    FPage:         Integer;
    FPageFrom:     Integer;
    FPageTo:       Integer;
    FRotation:     Integer;
    FText:         string;
    FCaseSensitive: Boolean;
    FWholeWord:    Boolean;
    FOpacity:      Double;
    FFontSize:     Double;
    FFields:       string;
    FFiles:        string;
  public
    [AiMCPSchemaDescription('Operation: info, extract_text, get_metadata, search, split, ' +
      'merge, rotate, add_watermark, fill_form, list_fields, is_scanned')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Input PDF file path (required for all ops except merge)')]
    property FilePath: string read FFilePath write FFilePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output PDF file path (for split, merge, rotate, add_watermark, fill_form)')]
    property OutputPath: string read FOutputPath write FOutputPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Password for encrypted PDFs')]
    property Password: string read FPassword write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('0-based page index for extract_text; -1 = all pages (default -1)')]
    property Page: Integer read FPage write FPage;

    [AiMCPOptional]
    [AiMCPSchemaDescription('0-based start page for split (default 0)')]
    property PageFrom: Integer read FPageFrom write FPageFrom;

    [AiMCPOptional]
    [AiMCPSchemaDescription('0-based end page inclusive for split; -1 = last page (default -1)')]
    property PageTo: Integer read FPageTo write FPageTo;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Rotation degrees: 90, 180 or 270 (default 90)')]
    property Rotation: Integer read FRotation write FRotation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query text (search) or watermark text (add_watermark)')]
    property Text: string read FText write FText;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Case-sensitive search (default false)')]
    property CaseSensitive: Boolean read FCaseSensitive write FCaseSensitive;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Whole-word search (default false)')]
    property WholeWord: Boolean read FWholeWord write FWholeWord;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Watermark opacity 0.0-1.0 (default 0.3)')]
    property Opacity: Double read FOpacity write FOpacity;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Watermark font size in points (default 48)')]
    property FontSize: Double read FFontSize write FFontSize;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON object with form field values: {"fieldName": "value"} or {"checkboxName": true}')]
    property Fields: string read FFields write FFields;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON array of PDF file paths for merge: ["file1.pdf", "file2.pdf"]')]
    property Files: string read FFiles write FFiles;
  end;

  // ── Tool ────────────────────────────────────────────────────────────────────

  TPDFTool = class(TAiMCPToolBase<TPDFParams>)
  private
    function LoadDoc(const APath, APassword: string): TPDFDocument;
    function DateToStr(DT: TDateTime; HasDate: Boolean): string;

    function OpInfo(const P: TPDFParams): TJSONObject;
    function OpExtractText(const P: TPDFParams): TJSONObject;
    function OpGetMetadata(const P: TPDFParams): TJSONObject;
    function OpSearch(const P: TPDFParams): TJSONObject;
    function OpSplit(const P: TPDFParams): TJSONObject;
    function OpMerge(const P: TPDFParams): TJSONObject;
    function OpRotate(const P: TPDFParams): TJSONObject;
    function OpAddWatermark(const P: TPDFParams): TJSONObject;
    function OpFillForm(const P: TPDFParams): TJSONObject;
    function OpListFields(const P: TPDFParams): TJSONObject;
    function OpIsScanned(const P: TPDFParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TPDFParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ─────────────────────────────────────────────────────────────────

function TPDFTool.LoadDoc(const APath, APassword: string): TPDFDocument;
begin
  if APath = '' then
    raise Exception.Create('"file_path" is required');
  if not TFile.Exists(APath) then
    raise Exception.CreateFmt('File not found: "%s"', [APath]);

  Result := TPDFDocument.Create;
  try
    Result.LoadFromFile(APath);
    if Result.IsEncrypted then
    begin
      if not Result.Authenticate(APassword) then
        raise Exception.Create('PDF is encrypted — provide the correct "password"');
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TPDFTool.DateToStr(DT: TDateTime; HasDate: Boolean): string;
begin
  if HasDate then
    Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', DT)
  else
    Result := '';
end;

// ── Operations ───────────────────────────────────────────────────────────────

function TPDFTool.OpInfo(const P: TPDFParams): TJSONObject;
var
  Doc:   TPDFDocument;
  Pages: TJSONArray;
  i:     Integer;
  PgObj: TJSONObject;
  FSize: Int64;
begin
  Doc := LoadDoc(P.FilePath, P.Password);
  try
    FSize := TFile.GetSize(P.FilePath);

    Pages := TJSONArray.Create;
    for i := 0 to Doc.PageCount - 1 do
    begin
      PgObj := TJSONObject.Create;
      PgObj.AddPair('index',    TJSONNumber.Create(i));
      PgObj.AddPair('width',    TJSONNumber.Create(Doc.Pages[i].Width));
      PgObj.AddPair('height',   TJSONNumber.Create(Doc.Pages[i].Height));
      PgObj.AddPair('rotation', TJSONNumber.Create(Doc.Pages[i].Rotation));
      Pages.AddElement(PgObj);
    end;

    Result := TJSONObject.Create;
    Result.AddPair('file',        P.FilePath);
    Result.AddPair('file_size',   TJSONNumber.Create(FSize));
    Result.AddPair('page_count',  TJSONNumber.Create(Doc.PageCount));
    Result.AddPair('is_encrypted', TJSONBool.Create(Doc.IsEncrypted));
    Result.AddPair('pages',       Pages);
  finally
    Doc.Free;
  end;
end;

function TPDFTool.OpExtractText(const P: TPDFParams): TJSONObject;
var
  Doc:       TPDFDocument;
  Extractor: TPDFTextExtractor;
  PageIdx:   Integer;
  PagesArr:  TJSONArray;
  PgObj:     TJSONObject;
  AllPages:  TArray<TPDFPageText>;
  OnePage:   TPDFPageText;
begin
  Doc := LoadDoc(P.FilePath, P.Password);
  try
    Extractor := TPDFTextExtractor.Create(Doc);
    try
      PageIdx := P.Page;
      if PageIdx < 0 then
        PageIdx := -1; // all

      Result := TJSONObject.Create;
      Result.AddPair('file', P.FilePath);

      if PageIdx = -1 then
      begin
        // All pages
        AllPages := Extractor.ExtractAll;
        PagesArr := TJSONArray.Create;
        for var Pg in AllPages do
        begin
          PgObj := TJSONObject.Create;
          PgObj.AddPair('page',  TJSONNumber.Create(Pg.PageIndex));
          PgObj.AddPair('text',  Pg.PlainText);
          PgObj.AddPair('chars', TJSONNumber.Create(Length(Pg.PlainText)));
          PagesArr.AddElement(PgObj);
        end;
        Result.AddPair('page_count', TJSONNumber.Create(Length(AllPages)));
        Result.AddPair('pages',      PagesArr);
        Result.AddPair('full_text',  Extractor.ExtractAllText);
      end
      else
      begin
        // Single page
        if (PageIdx < 0) or (PageIdx >= Doc.PageCount) then
          raise Exception.CreateFmt('Page index %d out of range (0..%d)',
            [PageIdx, Doc.PageCount - 1]);
        OnePage := Extractor.ExtractPage(PageIdx);
        Result.AddPair('page', TJSONNumber.Create(PageIdx));
        Result.AddPair('text', OnePage.PlainText);
        Result.AddPair('chars', TJSONNumber.Create(Length(OnePage.PlainText)));
      end;
    finally
      Extractor.Free;
    end;
  finally
    Doc.Free;
  end;
end;

function TPDFTool.OpGetMetadata(const P: TPDFParams): TJSONObject;
var
  Doc:  TPDFDocument;
  Meta: TPDFMetadata;
begin
  Doc := LoadDoc(P.FilePath, P.Password);
  try
    Meta := TPDFMetadataLoader.Load(Doc.Trailer, Doc.Catalog, Doc.Resolver);
    try
      Result := TJSONObject.Create;
      Result.AddPair('file',         P.FilePath);
      Result.AddPair('title',        Meta.BestTitle);
      Result.AddPair('author',       Meta.BestAuthor);
      Result.AddPair('subject',      Meta.BestSubject);
      Result.AddPair('keywords',     Meta.BestKeywords);
      Result.AddPair('creator',      Meta.BestCreator);
      Result.AddPair('producer',     Meta.BestProducer);
      Result.AddPair('creation_date', DateToStr(Meta.Info.CreationDate, Meta.Info.HasCreationDate));
      Result.AddPair('mod_date',     DateToStr(Meta.Info.ModDate, Meta.Info.HasModDate));
      Result.AddPair('page_count',   TJSONNumber.Create(Doc.PageCount));
      Result.AddPair('is_encrypted', TJSONBool.Create(Doc.IsEncrypted));
      Result.AddPair('has_xmp',      TJSONBool.Create(Meta.HasXMP));
    finally
      Meta.Free;
    end;
  finally
    Doc.Free;
  end;
end;

function TPDFTool.OpSearch(const P: TPDFParams): TJSONObject;
var
  Doc:     TPDFDocument;
  Searcher: TPDFTextSearch;
  Opts:    TPDFSearchOptions;
  Matches: TArray<TPDFSearchMatch>;
  Arr:     TJSONArray;
  MObj:    TJSONObject;
  Limit:   Integer;
begin
  if P.Text = '' then
    raise Exception.Create('"text" is required for search');

  Doc := LoadDoc(P.FilePath, P.Password);
  try
    Searcher := TPDFTextSearch.Create(Doc);
    try
      Opts := TPDFSearchOptions.Default;
      Opts.CaseSensitive := P.CaseSensitive;
      Opts.WholeWord     := P.WholeWord;

      if P.Page >= 0 then
        Matches := Searcher.SearchPage(P.Page, P.Text, Opts)
      else
        Matches := Searcher.Search(P.Text, Opts);

      Limit := Min(Length(Matches), 200);
      Arr   := TJSONArray.Create;
      for var i := 0 to Limit - 1 do
      begin
        MObj := TJSONObject.Create;
        MObj.AddPair('page',  TJSONNumber.Create(Matches[i].PageIndex));
        MObj.AddPair('text',  Matches[i].Text);
        Arr.AddElement(MObj);
      end;

      Result := TJSONObject.Create;
      Result.AddPair('query',         P.Text);
      Result.AddPair('total_matches', TJSONNumber.Create(Length(Matches)));
      Result.AddPair('returned',      TJSONNumber.Create(Limit));
      Result.AddPair('matches',       Arr);
    finally
      Searcher.Free;
    end;
  finally
    Doc.Free;
  end;
end;

function TPDFTool.OpSplit(const P: TPDFParams): TJSONObject;
var
  Doc:  TPDFDocument;
  From, ToP: Integer;
begin
  if P.OutputPath = '' then
    raise Exception.Create('"output_path" is required for split');

  Doc := LoadDoc(P.FilePath, P.Password);
  try
    From := Max(0, P.PageFrom);
    ToP  := P.PageTo;
    if (ToP < 0) or (ToP >= Doc.PageCount) then
      ToP := Doc.PageCount - 1;

    if From > ToP then
      raise Exception.CreateFmt('page_from (%d) must be <= page_to (%d)', [From, ToP]);

    TPDFPageOperations.Split(Doc, From, ToP, P.OutputPath);

    Result := TJSONObject.Create;
    Result.AddPair('output',     P.OutputPath);
    Result.AddPair('page_from',  TJSONNumber.Create(From));
    Result.AddPair('page_to',    TJSONNumber.Create(ToP));
    Result.AddPair('page_count', TJSONNumber.Create(ToP - From + 1));
    Result.AddPair('file_size',  TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
  finally
    Doc.Free;
  end;
end;

function TPDFTool.OpMerge(const P: TPDFParams): TJSONObject;
var
  FilesArr: TJSONValue;
  Paths:    TArray<string>;
  i:        Integer;
begin
  if P.Files = '' then
    raise Exception.Create('"files" is required for merge — JSON array of file paths');
  if P.OutputPath = '' then
    raise Exception.Create('"output_path" is required for merge');

  FilesArr := TJSONObject.ParseJSONValue(P.Files);
  if not (FilesArr is TJSONArray) then
    raise Exception.Create('"files" must be a JSON array of file paths');

  try
    SetLength(Paths, TJSONArray(FilesArr).Count);
    for i := 0 to High(Paths) do
    begin
      Paths[i] := TJSONArray(FilesArr).Items[i].Value;
      if not TFile.Exists(Paths[i]) then
        raise Exception.CreateFmt('File not found: "%s"', [Paths[i]]);
    end;
  finally
    FilesArr.Free;
  end;

  TPDFPageOperations.MergeFiles(Paths, P.OutputPath);

  Result := TJSONObject.Create;
  Result.AddPair('output',      P.OutputPath);
  Result.AddPair('files_merged', TJSONNumber.Create(Length(Paths)));
  Result.AddPair('file_size',   TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
end;

function TPDFTool.OpRotate(const P: TPDFParams): TJSONObject;
var
  Doc:      TPDFDocument;
  RotDeg:   Integer;
  Indices:  TArray<Integer>;
begin
  if P.OutputPath = '' then
    raise Exception.Create('"output_path" is required for rotate');

  RotDeg := P.Rotation;
  if RotDeg = 0 then RotDeg := 90;
  if (RotDeg <> 90) and (RotDeg <> 180) and (RotDeg <> 270) then
    raise Exception.Create('"rotation" must be 90, 180 or 270');

  Doc := LoadDoc(P.FilePath, P.Password);
  try
    if P.Page >= 0 then
    begin
      SetLength(Indices, 1);
      Indices[0] := P.Page;
      TPDFPageOperations.RotatePages(Doc, RotDeg, Indices);
    end
    else
      TPDFPageOperations.RotatePages(Doc, RotDeg);

    Doc.SaveToFile(P.OutputPath);

    Result := TJSONObject.Create;
    Result.AddPair('output',      P.OutputPath);
    Result.AddPair('rotation',    TJSONNumber.Create(RotDeg));
    Result.AddPair('pages_rotated',
      TJSONNumber.Create(IfThen(P.Page >= 0, 1, Doc.PageCount)));
    Result.AddPair('file_size',   TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
  finally
    Doc.Free;
  end;
end;

function TPDFTool.OpAddWatermark(const P: TPDFParams): TJSONObject;
var
  Doc:  TPDFDocument;
  Opts: TPDFWatermarkOptions;
  Sz:   Single;
  Op:   Single;
begin
  if P.Text = '' then
    raise Exception.Create('"text" is required for add_watermark');
  if P.OutputPath = '' then
    raise Exception.Create('"output_path" is required for add_watermark');

  Sz := P.FontSize;
  if Sz <= 0 then Sz := 48;

  Op := P.Opacity;
  if Op <= 0 then Op := 0.3;
  Op := Min(Max(Op, 0.01), 1.0);

  Doc := LoadDoc(P.FilePath, P.Password);
  try
    Opts         := TPDFWatermarkOptions.Default;
    Opts.Opacity := Op;

    TPDFWatermark.ApplyText(Doc, P.Text, 'Helvetica', Sz,
      0.5, 0.5, 0.5, Opts, P.OutputPath);

    Result := TJSONObject.Create;
    Result.AddPair('output',     P.OutputPath);
    Result.AddPair('text',       P.Text);
    Result.AddPair('opacity',    TJSONNumber.Create(Op));
    Result.AddPair('font_size',  TJSONNumber.Create(Sz));
    Result.AddPair('file_size',  TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
  finally
    Doc.Free;
  end;
end;

function TPDFTool.OpFillForm(const P: TPDFParams): TJSONObject;
var
  Doc:    TPDFDocument;
  Filler: TPDFFormFiller;
  JObj:   TJSONValue;
  JFields: TJSONObject;
  Pair:   TJSONPair;
  Filled: Integer;
begin
  if P.Fields = '' then
    raise Exception.Create('"fields" is required for fill_form — JSON object {"fieldName": value}');
  if P.OutputPath = '' then
    raise Exception.Create('"output_path" is required for fill_form');

  JObj := TJSONObject.ParseJSONValue(P.Fields);
  if not (JObj is TJSONObject) then
    raise Exception.Create('"fields" must be a JSON object');
  JFields := TJSONObject(JObj);

  Doc := LoadDoc(P.FilePath, P.Password);
  try
    Filler := TPDFFormFiller.Create(Doc);
    try
      Filler.LoadForm;
      Filled := 0;

      for Pair in JFields do
      begin
        if Pair.JsonValue is TJSONBool then
          Filler.SetCheckBox(Pair.JsonString.Value,
            TJSONBool(Pair.JsonValue).AsBoolean)
        else
          Filler.SetTextField(Pair.JsonString.Value,
            Pair.JsonValue.Value);
        Inc(Filled);
      end;

      Filler.Save(P.OutputPath);

      Result := TJSONObject.Create;
      Result.AddPair('output',        P.OutputPath);
      Result.AddPair('fields_filled', TJSONNumber.Create(Filled));
      Result.AddPair('file_size',     TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
    finally
      Filler.Free;
    end;
  finally
    Doc.Free;
    JFields.Free;
  end;
end;

function TPDFTool.OpListFields(const P: TPDFParams): TJSONObject;
var
  Doc:   TPDFDocument;
  Form:  TPDFAcroForm;
  Arr:   TJSONArray;
  FObj:  TJSONObject;
  FType: string;
begin
  Doc := LoadDoc(P.FilePath, P.Password);
  try
    Form := TPDFAcroForm.Create;
    try
      Form.LoadFromCatalog(Doc.Catalog, Doc.Resolver);

      Arr := TJSONArray.Create;
      for var F in Form.LeafFields do
      begin
        case F.FieldType of
          TPDFFieldType.Text:      FType := 'text';
          TPDFFieldType.Button:
            if F.IsCheckBox then   FType := 'checkbox'
            else if F.IsRadioButton then FType := 'radio'
            else                   FType := 'button';
          TPDFFieldType.Choice:
            if F.IsComboBox then   FType := 'combobox'
            else                   FType := 'listbox';
          TPDFFieldType.Signature: FType := 'signature';
        else
          FType := 'unknown';
        end;

        FObj := TJSONObject.Create;
        FObj.AddPair('name',      F.FullName);
        FObj.AddPair('type',      FType);
        FObj.AddPair('value',     F.ValueString);
        FObj.AddPair('required',  TJSONBool.Create(F.IsRequired));
        FObj.AddPair('read_only', TJSONBool.Create(F.IsReadOnly));
        if F.AltName <> '' then
          FObj.AddPair('label', F.AltName);
        Arr.AddElement(FObj);
      end;

      Result := TJSONObject.Create;
      Result.AddPair('file',        P.FilePath);
      Result.AddPair('field_count', TJSONNumber.Create(Arr.Count));
      Result.AddPair('fields',      Arr);
    finally
      Form.Free;
    end;
  finally
    Doc.Free;
  end;
end;

function TPDFTool.OpIsScanned(const P: TPDFParams): TJSONObject;
var
  Doc:      TPDFDocument;
  Detector: TPDFScanDetector;
  PagesArr: TJSONArray;
  PageResults: TArray<TPDFPageScanResult>;
  PObj:     TJSONObject;
begin
  Doc := LoadDoc(P.FilePath, P.Password);
  try
    Detector := TPDFScanDetector.Create(Doc);
    try
      PageResults := Detector.AnalyzeDocument;
      PagesArr    := TJSONArray.Create;
      for var R in PageResults do
      begin
        PObj := TJSONObject.Create;
        PObj.AddPair('page',           TJSONNumber.Create(R.PageIndex));
        PObj.AddPair('is_scanned',     TJSONBool.Create(R.IsScanned));
        PObj.AddPair('text_fragments', TJSONNumber.Create(R.TextFragments));
        PObj.AddPair('image_coverage', TJSONNumber.Create(R.ImageCoverage));
        PagesArr.AddElement(PObj);
      end;

      Result := TJSONObject.Create;
      Result.AddPair('file',       P.FilePath);
      Result.AddPair('is_scanned', TJSONBool.Create(Detector.IsScanned));
      Result.AddPair('pages',      PagesArr);
    finally
      Detector.Free;
    end;
  finally
    Doc.Free;
  end;
end;

// ── Main dispatch ────────────────────────────────────────────────────────────

function TPDFTool.ExecuteWithParams(const AParams: TPDFParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Data: TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));

    if      Op = 'info'          then Data := OpInfo(AParams)
    else if Op = 'extract_text'  then Data := OpExtractText(AParams)
    else if Op = 'get_metadata'  then Data := OpGetMetadata(AParams)
    else if Op = 'search'        then Data := OpSearch(AParams)
    else if Op = 'split'         then Data := OpSplit(AParams)
    else if Op = 'merge'         then Data := OpMerge(AParams)
    else if Op = 'rotate'        then Data := OpRotate(AParams)
    else if Op = 'add_watermark' then Data := OpAddWatermark(AParams)
    else if Op = 'fill_form'     then Data := OpFillForm(AParams)
    else if Op = 'list_fields'   then Data := OpListFields(AParams)
    else if Op = 'is_scanned'    then Data := OpIsScanned(AParams)
    else raise Exception.CreateFmt(
      'Unknown operation: "%s". Valid: info, extract_text, get_metadata, search, ' +
      'split, merge, rotate, add_watermark, fill_form, list_fields, is_scanned', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(Data.ToJSON).Build;
    Data.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-pdf]: ' + E.Message)
        .Build;
  end;
end;

constructor TPDFTool.Create;
begin
  inherited;
  FName        := 'mcp-pdf';
  FDescription :=
    'Read and manipulate PDF files. 100% Delphi, no external DLLs. ' +
    'info: page count, sizes, encryption status. ' +
    'extract_text: extract plain text (all pages or single page). ' +
    'get_metadata: title, author, subject, keywords, dates. ' +
    'search: find text with page and position results. ' +
    'split: extract page range into new PDF. ' +
    'merge: combine multiple PDFs into one (files=[...]). ' +
    'rotate: rotate pages 90/180/270 degrees. ' +
    'add_watermark: add diagonal text watermark with opacity. ' +
    'fill_form: fill AcroForm fields from JSON object. ' +
    'list_fields: list all form fields with types and values. ' +
    'is_scanned: detect if PDF contains scanned images.';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-pdf',
    function: IAiMCPTool
    begin
      Result := TPDFTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-pdf] registered.');
end;

end.
