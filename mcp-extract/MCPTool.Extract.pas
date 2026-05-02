unit MCPTool.Extract;

(*
  MCPTool.Extract  -  mcp-extract

  Convert a local file to Markdown text using the delphi-libraries/extract
  engine (TAiExtractLib).  Supports 13 formats: TXT, Markdown, CSV, TSV,
  JSON, XML, INI, RTF, HTML, DOCX, XLSX, PPTX, PDF, EPUB.

  Tool:
    extract_file
      file_path   - full path to the file to convert (required)

  Returns JSON:
    { "success": true,  "file_path": "...", "title": "...", "markdown": "..." }
    { "success": false, "file_path": "...", "error": "reason" }
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  uExtract.Engine,
  uExtract.Result;

type

  TExtractParams = class
  private
    FFilePath: string;
  public
    [AiMCPSchemaDescription('Full path to the local file to convert to Markdown. ' +
      'Supported formats: TXT, MD, CSV, TSV, JSON, XML, INI, RTF, HTML, ' +
      'DOCX, XLSX, PPTX, PDF, EPUB.')]
    property FilePath: string read FFilePath write FFilePath;
  end;

  TExtractTool = class(TAiMCPToolBase<TExtractParams>)
  protected
    function ExecuteWithParams(const AParams: TExtractParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.IOUtils;

function TExtractTool.ExecuteWithParams(const AParams: TExtractParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Engine: TAiExtractLib;
  Conv  : TConversionResult;
  R     : TJSONObject;
begin
  try
    if AParams.FilePath.Trim = '' then
      raise Exception.Create('"file_path" is required');

    if not TFile.Exists(AParams.FilePath) then
      raise Exception.CreateFmt('File not found: %s', [AParams.FilePath]);

    Engine := TAiExtractLib.Create;
    try
      Conv := Engine.ConvertFile(AParams.FilePath);
    finally
      Engine.Free;
    end;

    R := TJSONObject.Create;
    R.AddPair('success',   TJSONBool.Create(Conv.Success));
    R.AddPair('file_path', AParams.FilePath);
    if Conv.Success then
    begin
      R.AddPair('title',    Conv.Title);
      R.AddPair('markdown', Conv.Markdown);
    end
    else
      R.AddPair('error', Conv.ErrorMessage);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-extract]: ' + E.Message)
        .Build;
  end;
end;

constructor TExtractTool.Create;
begin
  inherited;
  FName        := 'extract_file';
  FDescription :=
    'Convert a local file to Markdown text. ' +
    'Supported: TXT, MD, CSV, TSV, JSON, XML, INI, RTF, HTML, DOCX, XLSX, PPTX, PDF, EPUB. ' +
    'Returns: markdown (full extracted text), title (when available, e.g. PDF/HTML), ' +
    'success (bool), error (on failure). ' +
    'Example: extract_file("C:\\Docs\\report.xlsx") returns a Markdown table of each worksheet.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('extract_file',
    function: IAiMCPTool
    begin
      Result := TExtractTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + extract_file');
end;

end.
