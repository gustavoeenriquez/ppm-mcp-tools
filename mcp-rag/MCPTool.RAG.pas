unit MCPTool.RAG;

(*
  MCPTool.RAG  ·  mcp-rag

  Simple file-based Retrieval-Augmented Generation (RAG) system.
  No embeddings, no vectors — pure keyword-based text search with TF scoring.

  Storage: JSON file at {StoragePath}/mcp_rag_index.json
  Index structure:
    { "chunks": [
        {"doc":"name","chunk":0,"text":"...","words":["w1","w2",...]},
        ...
      ]
    }

  Operations:
    index_file  - read a text file and index its chunks
    index_text  - index a text string directly
    search      - find top-K relevant chunks by keyword matching
    list_docs   - list indexed documents
    delete_doc  - remove a document from the index
    clear_index - remove all indexed data
    get_chunk   - retrieve a specific chunk by doc name and chunk index
    stats       - index statistics

  Port: 8648
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type

  TRAGParams = class
  private
    FOperation:   string;
    FStoragePath: string;
    FFilePath:    string;
    FText:        string;
    FDocName:     string;
    FQuery:       string;
    FTopK:        Integer;
    FChunkSize:   Integer;
    FOverlap:     Integer;
    FChunkIndex:  Integer;
    FMinScore:    string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: index_file, index_text, search, list_docs, delete_doc, clear_index, get_chunk, stats')]
    property Operation:   string  read FOperation   write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Directory for the index file (default: Documents folder)')]
    property StoragePath: string  read FStoragePath write FStoragePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Path to a text file to index (for index_file)')]
    property FilePath:    string  read FFilePath    write FFilePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Text content to index directly (for index_text)')]
    property TextContent: string  read FText        write FText;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Document name identifier (for index_text, delete_doc, get_chunk)')]
    property DocName:     string  read FDocName     write FDocName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query string (for search)')]
    property Query:       string  read FQuery       write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum number of results to return (default: 5)')]
    property TopK:        Integer read FTopK        write FTopK;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Words per chunk (default: 200)')]
    property ChunkSize:   Integer read FChunkSize   write FChunkSize;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Overlapping words between consecutive chunks (default: 50)')]
    property Overlap:     Integer read FOverlap     write FOverlap;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Chunk index to retrieve (for get_chunk, default: 0)')]
    property ChunkIndex:  Integer read FChunkIndex  write FChunkIndex;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Minimum score threshold as string, e.g. "0.1" (for search, default: "0.1")')]
    property MinScore:    string  read FMinScore    write FMinScore;
  end;

  TRAGTool = class(TAiMCPToolBase<TRAGParams>)
  private
    function ResolveIndexPath(const StoragePath: string): string;
    function LoadIndex(const IndexPath: string): TJSONObject;
    procedure SaveIndex(const IndexPath: string; const Index: TJSONObject);
    procedure Tokenize(const AText: string; out Words: TArray<string>);
    procedure SplitIntoChunks(const Words: TArray<string>;
      const DocName: string; ChunkSize, Overlap: Integer;
      const Chunks: TJSONArray);
    function DoIndexFile(const P: TRAGParams): TJSONObject;
    function DoIndexText(const P: TRAGParams): TJSONObject;
    function DoSearch(const P: TRAGParams): TJSONObject;
    function DoListDocs(const P: TRAGParams): TJSONObject;
    function DoDeleteDoc(const P: TRAGParams): TJSONObject;
    function DoClearIndex(const P: TRAGParams): TJSONObject;
    function DoGetChunk(const P: TRAGParams): TJSONObject;
    function DoStats(const P: TRAGParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TRAGParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Math;

{ TRAGParams }

constructor TRAGParams.Create;
begin
  inherited;
  FTopK       := 5;
  FChunkSize  := 200;
  FOverlap    := 50;
  FChunkIndex := 0;
  FMinScore   := '0.1';
end;

{ TRAGTool }

constructor TRAGTool.Create;
begin
  inherited;
  FName        := 'mcp-rag';
  FDescription :=
    'Simple file-based RAG (Retrieval-Augmented Generation) system. ' +
    'Indexes text documents and retrieves relevant chunks via keyword matching (TF scoring). ' +
    'Operations: ' +
    'index_file (index a text file; params: filepath, chunk_size, overlap, storage_path), ' +
    'index_text (index a text string; params: text_content, doc_name, chunk_size, overlap, storage_path), ' +
    'search (find top-K relevant chunks; params: query, top_k, min_score, storage_path), ' +
    'list_docs (list indexed documents; param: storage_path), ' +
    'delete_doc (remove a document; params: doc_name, storage_path), ' +
    'clear_index (remove all data; param: storage_path), ' +
    'get_chunk (retrieve a specific chunk; params: doc_name, chunk_index, storage_path), ' +
    'stats (index statistics; param: storage_path). ' +
    'Storage: JSON file mcp_rag_index.json in storage_path (default: Documents folder).';
end;

function TRAGTool.ResolveIndexPath(const StoragePath: string): string;
var
  Dir: string;
begin
  if StoragePath <> '' then
    Dir := StoragePath
  else
    Dir := TPath.GetDocumentsPath;
  if not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  Result := TPath.Combine(Dir, 'mcp_rag_index.json');
end;

function TRAGTool.LoadIndex(const IndexPath: string): TJSONObject;
var
  Raw:    string;
  Parsed: TJSONValue;
begin
  if TFile.Exists(IndexPath) then
  begin
    Raw    := TFile.ReadAllText(IndexPath, TEncoding.UTF8);
    Parsed := TJSONObject.ParseJSONValue(Raw);
    if Parsed is TJSONObject then
      Result := TJSONObject(Parsed)
    else
    begin
      if Assigned(Parsed) then Parsed.Free;
      Result := TJSONObject.Create;
      Result.AddPair('chunks', TJSONArray.Create);
    end;
  end
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('chunks', TJSONArray.Create);
  end;

  if not Assigned(Result.GetValue('chunks')) then
    Result.AddPair('chunks', TJSONArray.Create);
end;

procedure TRAGTool.SaveIndex(const IndexPath: string; const Index: TJSONObject);
begin
  TFile.WriteAllText(IndexPath, Index.ToJSON, TEncoding.UTF8);
end;

procedure TRAGTool.Tokenize(const AText: string; out Words: TArray<string>);
var
  i:      Integer;
  c:      Char;
  Token:  string;
  List:   TStringList;
  Lower:  string;
begin
  List  := TStringList.Create;
  try
    Token := '';
    for i := 1 to Length(AText) do
    begin
      c := AText[i];
      if CharInSet(c, ['A'..'Z', 'a'..'z', '0'..'9']) then
        Token := Token + c
      else
      begin
        if Length(Token) >= 2 then
        begin
          Lower := LowerCase(Token);
          List.Add(Lower);
        end;
        Token := '';
      end;
    end;
    if Length(Token) >= 2 then
      List.Add(LowerCase(Token));
    Words := List.ToStringArray;
  finally
    List.Free;
  end;
end;

procedure TRAGTool.SplitIntoChunks(const Words: TArray<string>;
  const DocName: string; ChunkSize, Overlap: Integer;
  const Chunks: TJSONArray);
var
  Start:     Integer;
  Stop:      Integer;
  ChunkIdx:  Integer;
  i:         Integer;
  ChunkObj:  TJSONObject;
  WordArr:   TJSONArray;
  ChunkText: string;
  Step:      Integer;
begin
  if Length(Words) = 0 then
    Exit;
  if ChunkSize < 1 then
    ChunkSize := 200;
  if Overlap < 0 then
    Overlap := 0;
  if Overlap >= ChunkSize then
    Overlap := ChunkSize - 1;

  Step     := ChunkSize - Overlap;
  if Step < 1 then
    Step := 1;
  ChunkIdx := 0;
  Start    := 0;

  while Start < Length(Words) do
  begin
    Stop := Start + ChunkSize - 1;
    if Stop >= Length(Words) then
      Stop := Length(Words) - 1;

    ChunkText := '';
    WordArr   := TJSONArray.Create;
    for i := Start to Stop do
    begin
      if ChunkText <> '' then
        ChunkText := ChunkText + ' ';
      ChunkText := ChunkText + Words[i];
      WordArr.Add(Words[i]);
    end;

    ChunkObj := TJSONObject.Create;
    ChunkObj.AddPair('doc',   DocName);
    ChunkObj.AddPair('chunk', TJSONNumber.Create(ChunkIdx));
    ChunkObj.AddPair('text',  ChunkText);
    ChunkObj.AddPair('words', WordArr);
    Chunks.AddElement(ChunkObj);

    Inc(ChunkIdx);
    Inc(Start, Step);
  end;
end;

function TRAGTool.DoIndexFile(const P: TRAGParams): TJSONObject;
var
  IndexPath: string;
  Index:     TJSONObject;
  Chunks:    TJSONArray;
  RawText:   string;
  DocName:   string;
  Words:     TArray<string>;
  NewChunks: TJSONArray;
  OldChunks: TJSONArray;
  i:         Integer;
  Elem:      TJSONValue;
  ElemObj:   TJSONObject;
  DocVal:    TJSONValue;
  AddedCount: Integer;
begin
  if P.FilePath = '' then
    raise Exception.Create('"filepath" required for index_file');
  if not TFile.Exists(P.FilePath) then
    raise Exception.CreateFmt('File not found: %s', [P.FilePath]);

  DocName := TPath.GetFileName(P.FilePath);
  RawText := TFile.ReadAllText(P.FilePath, TEncoding.UTF8);

  Tokenize(RawText, Words);

  NewChunks := TJSONArray.Create;
  try
    SplitIntoChunks(Words, DocName, P.ChunkSize, P.Overlap, NewChunks);

    IndexPath := ResolveIndexPath(P.StoragePath);
    Index     := LoadIndex(IndexPath);
    try
      OldChunks := Index.GetValue('chunks') as TJSONArray;

      (* Remove existing chunks for this doc *)
      i := OldChunks.Count - 1;
      while i >= 0 do
      begin
        Elem := OldChunks.Items[i];
        if Elem is TJSONObject then
        begin
          ElemObj := TJSONObject(Elem);
          DocVal  := ElemObj.GetValue('doc');
          if Assigned(DocVal) and (DocVal.Value = DocName) then
            OldChunks.Remove(i);
        end;
        Dec(i);
      end;

      (* Add new chunks *)
      AddedCount := NewChunks.Count;
      for i := 0 to NewChunks.Count - 1 do
        OldChunks.AddElement(NewChunks.Items[i].Clone as TJSONValue);

      SaveIndex(IndexPath, Index);
    finally
      Index.Free;
    end;
  finally
    NewChunks.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('indexed', DocName);
  Result.AddPair('chunks',  TJSONNumber.Create(AddedCount));
end;

function TRAGTool.DoIndexText(const P: TRAGParams): TJSONObject;
var
  IndexPath:  string;
  Index:      TJSONObject;
  OldChunks:  TJSONArray;
  NewChunks:  TJSONArray;
  Words:      TArray<string>;
  DocName:    string;
  i:          Integer;
  Elem:       TJSONValue;
  ElemObj:    TJSONObject;
  DocVal:     TJSONValue;
  AddedCount: Integer;
begin
  if P.TextContent = '' then
    raise Exception.Create('"text_content" required for index_text');
  if P.DocName = '' then
    raise Exception.Create('"doc_name" required for index_text');

  DocName := P.DocName;
  Tokenize(P.TextContent, Words);

  NewChunks := TJSONArray.Create;
  try
    SplitIntoChunks(Words, DocName, P.ChunkSize, P.Overlap, NewChunks);

    IndexPath := ResolveIndexPath(P.StoragePath);
    Index     := LoadIndex(IndexPath);
    try
      OldChunks := Index.GetValue('chunks') as TJSONArray;

      i := OldChunks.Count - 1;
      while i >= 0 do
      begin
        Elem := OldChunks.Items[i];
        if Elem is TJSONObject then
        begin
          ElemObj := TJSONObject(Elem);
          DocVal  := ElemObj.GetValue('doc');
          if Assigned(DocVal) and (DocVal.Value = DocName) then
            OldChunks.Remove(i);
        end;
        Dec(i);
      end;

      AddedCount := NewChunks.Count;
      for i := 0 to NewChunks.Count - 1 do
        OldChunks.AddElement(NewChunks.Items[i].Clone as TJSONValue);

      SaveIndex(IndexPath, Index);
    finally
      Index.Free;
    end;
  finally
    NewChunks.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',     TJSONTrue.Create);
  Result.AddPair('chunks', TJSONNumber.Create(AddedCount));
end;

function TRAGTool.DoSearch(const P: TRAGParams): TJSONObject;
var
  IndexPath:   string;
  Index:       TJSONObject;
  AllChunks:   TJSONArray;
  QueryWords:  TArray<string>;
  ResultsArr:  TJSONArray;
  i, j:        Integer;
  Elem:        TJSONValue;
  ChunkObj:    TJSONObject;
  WordsVal:    TJSONValue;
  WordsArr:    TJSONArray;
  MatchCount:  Integer;
  Score:       Double;
  MinScoreVal: Double;
  TopK:        Integer;
  QueryLen:    Integer;
  QWord:       string;
  WVal:        TJSONValue;
  (* Sorting structures *)
  ScoreList:   array of Double;
  IdxList:     array of Integer;
  Temp:        Double;
  TempIdx:     Integer;
  k:           Integer;
  ResObj:      TJSONObject;
  DocVal:      TJSONValue;
  ChunkVal:    TJSONValue;
  TextVal:     TJSONValue;
begin
  if P.Query = '' then
    raise Exception.Create('"query" required for search');

  Tokenize(P.Query, QueryWords);
  QueryLen := Length(QueryWords);
  if QueryLen = 0 then
    raise Exception.Create('Query produced no tokens');

  MinScoreVal := 0.1;
  if P.MinScore <> '' then
    MinScoreVal := StrToFloatDef(P.MinScore, 0.1);

  TopK := P.TopK;
  if TopK < 1 then
    TopK := 5;

  IndexPath := ResolveIndexPath(P.StoragePath);
  Index     := LoadIndex(IndexPath);
  try
    AllChunks := Index.GetValue('chunks') as TJSONArray;

    SetLength(ScoreList, AllChunks.Count);
    SetLength(IdxList,   AllChunks.Count);

    for i := 0 to AllChunks.Count - 1 do
    begin
      IdxList[i]   := i;
      ScoreList[i] := 0.0;

      Elem := AllChunks.Items[i];
      if not (Elem is TJSONObject) then
        Continue;

      ChunkObj := TJSONObject(Elem);
      WordsVal := ChunkObj.GetValue('words');
      if not (WordsVal is TJSONArray) then
        Continue;

      WordsArr   := TJSONArray(WordsVal);
      MatchCount := 0;

      for j := 0 to Length(QueryWords) - 1 do
      begin
        QWord := QueryWords[j];
        for k := 0 to WordsArr.Count - 1 do
        begin
          WVal := WordsArr.Items[k];
          if Assigned(WVal) and (WVal.Value = QWord) then
          begin
            Inc(MatchCount);
            Break;
          end;
        end;
      end;

      if QueryLen > 0 then
        ScoreList[i] := MatchCount / QueryLen
      else
        ScoreList[i] := 0.0;
    end;

    (* Bubble sort descending by score *)
    for i := 0 to High(ScoreList) - 1 do
      for j := i + 1 to High(ScoreList) do
        if ScoreList[j] > ScoreList[i] then
        begin
          Temp        := ScoreList[i];
          ScoreList[i]:= ScoreList[j];
          ScoreList[j]:= Temp;
          TempIdx     := IdxList[i];
          IdxList[i]  := IdxList[j];
          IdxList[j]  := TempIdx;
        end;

    ResultsArr := TJSONArray.Create;
    k := 0;
    i := 0;
    while (i < Length(ScoreList)) and (k < TopK) do
    begin
      Score := ScoreList[i];
      if Score < MinScoreVal then
        Break;

      Elem := AllChunks.Items[IdxList[i]];
      if Elem is TJSONObject then
      begin
        ChunkObj := TJSONObject(Elem);
        DocVal   := ChunkObj.GetValue('doc');
        ChunkVal := ChunkObj.GetValue('chunk');
        TextVal  := ChunkObj.GetValue('text');

        ResObj := TJSONObject.Create;
        if Assigned(DocVal)   then ResObj.AddPair('doc',   DocVal.Value)   else ResObj.AddPair('doc',   '');
        if Assigned(ChunkVal) then ResObj.AddPair('chunk', TJSONNumber.Create((ChunkVal as TJSONNumber).AsInt)) else ResObj.AddPair('chunk', TJSONNumber.Create(0));
        ResObj.AddPair('score', TJSONNumber.Create(Score));
        if Assigned(TextVal)  then ResObj.AddPair('text',  TextVal.Value)  else ResObj.AddPair('text',  '');
        ResultsArr.AddElement(ResObj);
        Inc(k);
      end;
      Inc(i);
    end;
  finally
    Index.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('results', ResultsArr);
end;

function TRAGTool.DoListDocs(const P: TRAGParams): TJSONObject;
var
  IndexPath:   string;
  Index:       TJSONObject;
  AllChunks:   TJSONArray;
  Seen:        TStringList;
  DocsArr:     TJSONArray;
  i:           Integer;
  Elem:        TJSONValue;
  ChunkObj:    TJSONObject;
  DocVal:      TJSONValue;
  DocName:     string;
  TotalChunks: Integer;
begin
  IndexPath   := ResolveIndexPath(P.StoragePath);
  Index       := LoadIndex(IndexPath);
  Seen        := TStringList.Create;
  Seen.Sorted := True;
  Seen.Duplicates := dupIgnore;
  try
    AllChunks   := Index.GetValue('chunks') as TJSONArray;
    TotalChunks := AllChunks.Count;

    for i := 0 to AllChunks.Count - 1 do
    begin
      Elem := AllChunks.Items[i];
      if Elem is TJSONObject then
      begin
        ChunkObj := TJSONObject(Elem);
        DocVal   := ChunkObj.GetValue('doc');
        if Assigned(DocVal) then
          Seen.Add(DocVal.Value);
      end;
    end;

    DocsArr := TJSONArray.Create;
    for DocName in Seen do
      DocsArr.Add(DocName);
  finally
    Index.Free;
    Seen.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',           TJSONTrue.Create);
  Result.AddPair('docs',         DocsArr);
  Result.AddPair('total_chunks', TJSONNumber.Create(TotalChunks));
end;

function TRAGTool.DoDeleteDoc(const P: TRAGParams): TJSONObject;
var
  IndexPath:    string;
  Index:        TJSONObject;
  AllChunks:    TJSONArray;
  i:            Integer;
  Elem:         TJSONValue;
  ChunkObj:     TJSONObject;
  DocVal:       TJSONValue;
  RemovedCount: Integer;
begin
  if P.DocName = '' then
    raise Exception.Create('"doc_name" required for delete_doc');

  IndexPath    := ResolveIndexPath(P.StoragePath);
  Index        := LoadIndex(IndexPath);
  RemovedCount := 0;
  try
    AllChunks := Index.GetValue('chunks') as TJSONArray;
    i := AllChunks.Count - 1;
    while i >= 0 do
    begin
      Elem := AllChunks.Items[i];
      if Elem is TJSONObject then
      begin
        ChunkObj := TJSONObject(Elem);
        DocVal   := ChunkObj.GetValue('doc');
        if Assigned(DocVal) and (DocVal.Value = P.DocName) then
        begin
          AllChunks.Remove(i);
          Inc(RemovedCount);
        end;
      end;
      Dec(i);
    end;
    SaveIndex(IndexPath, Index);
  finally
    Index.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',             TJSONTrue.Create);
  Result.AddPair('removed_chunks', TJSONNumber.Create(RemovedCount));
end;

function TRAGTool.DoClearIndex(const P: TRAGParams): TJSONObject;
var
  IndexPath: string;
  Index:     TJSONObject;
  AllChunks: TJSONArray;
  Cleared:   Integer;
  NewIndex:  TJSONObject;
begin
  IndexPath := ResolveIndexPath(P.StoragePath);
  Index     := LoadIndex(IndexPath);
  try
    AllChunks := Index.GetValue('chunks') as TJSONArray;
    Cleared   := AllChunks.Count;
  finally
    Index.Free;
  end;

  NewIndex := TJSONObject.Create;
  try
    NewIndex.AddPair('chunks', TJSONArray.Create);
    SaveIndex(IndexPath, NewIndex);
  finally
    NewIndex.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('cleared', TJSONNumber.Create(Cleared));
end;

function TRAGTool.DoGetChunk(const P: TRAGParams): TJSONObject;
var
  IndexPath: string;
  Index:     TJSONObject;
  AllChunks: TJSONArray;
  i:         Integer;
  Elem:      TJSONValue;
  ChunkObj:  TJSONObject;
  DocVal:    TJSONValue;
  ChunkVal:  TJSONValue;
  TextVal:   TJSONValue;
  Found:     Boolean;
begin
  if P.DocName = '' then
    raise Exception.Create('"doc_name" required for get_chunk');

  IndexPath := ResolveIndexPath(P.StoragePath);
  Index     := LoadIndex(IndexPath);
  Found     := False;
  Result    := nil;
  try
    AllChunks := Index.GetValue('chunks') as TJSONArray;
    for i := 0 to AllChunks.Count - 1 do
    begin
      Elem := AllChunks.Items[i];
      if not (Elem is TJSONObject) then
        Continue;
      ChunkObj := TJSONObject(Elem);
      DocVal   := ChunkObj.GetValue('doc');
      ChunkVal := ChunkObj.GetValue('chunk');
      TextVal  := ChunkObj.GetValue('text');
      if Assigned(DocVal) and (DocVal.Value = P.DocName) and
         Assigned(ChunkVal) and ((ChunkVal as TJSONNumber).AsInt = P.ChunkIndex) then
      begin
        Result := TJSONObject.Create;
        Result.AddPair('ok',    TJSONTrue.Create);
        if Assigned(TextVal)  then Result.AddPair('text',  TextVal.Value)  else Result.AddPair('text', '');
        Result.AddPair('doc',   DocVal.Value);
        Result.AddPair('chunk', TJSONNumber.Create(P.ChunkIndex));
        Found := True;
        Break;
      end;
    end;
  finally
    Index.Free;
  end;

  if not Found then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('ok',    TJSONFalse.Create);
    Result.AddPair('error', Format('Chunk %d not found in doc "%s"', [P.ChunkIndex, P.DocName]));
  end;
end;

function TRAGTool.DoStats(const P: TRAGParams): TJSONObject;
var
  IndexPath:   string;
  Index:       TJSONObject;
  AllChunks:   TJSONArray;
  Seen:        TStringList;
  TotalChunks: Integer;
  IndexSize:   Int64;
  i:           Integer;
  Elem:        TJSONValue;
  ChunkObj:    TJSONObject;
  DocVal:      TJSONValue;
begin
  IndexPath   := ResolveIndexPath(P.StoragePath);
  Index       := LoadIndex(IndexPath);
  Seen        := TStringList.Create;
  Seen.Sorted := True;
  Seen.Duplicates := dupIgnore;
  IndexSize := 0;
  try
    AllChunks   := Index.GetValue('chunks') as TJSONArray;
    TotalChunks := AllChunks.Count;

    for i := 0 to AllChunks.Count - 1 do
    begin
      Elem := AllChunks.Items[i];
      if Elem is TJSONObject then
      begin
        ChunkObj := TJSONObject(Elem);
        DocVal   := ChunkObj.GetValue('doc');
        if Assigned(DocVal) then
          Seen.Add(DocVal.Value);
      end;
    end;

    if TFile.Exists(IndexPath) then
      IndexSize := TFile.GetSize(IndexPath);
  finally
    Index.Free;
    Seen.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',               TJSONTrue.Create);
  Result.AddPair('total_docs',       TJSONNumber.Create(Seen.Count));
  Result.AddPair('total_chunks',     TJSONNumber.Create(TotalChunks));
  Result.AddPair('index_size_bytes', TJSONNumber.Create(IndexSize));
end;

function TRAGTool.ExecuteWithParams(const AParams: TRAGParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then
      raise Exception.Create('"operation" is required');

    if      Op = 'index_file'  then R := DoIndexFile(AParams)
    else if Op = 'index_text'  then R := DoIndexText(AParams)
    else if Op = 'search'      then R := DoSearch(AParams)
    else if Op = 'list_docs'   then R := DoListDocs(AParams)
    else if Op = 'delete_doc'  then R := DoDeleteDoc(AParams)
    else if Op = 'clear_index' then R := DoClearIndex(AParams)
    else if Op = 'get_chunk'   then R := DoGetChunk(AParams)
    else if Op = 'stats'       then R := DoStats(AParams)
    else raise Exception.CreateFmt('Unknown operation "%s"', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\', '\\').Replace('"', '\"')
                   .Replace(#10, '\n').Replace(#13, '') + '"}')
        .Build;
  end;
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-rag',
    function: IAiMCPTool
    begin
      Result := TRAGTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-rag');
end;

end.
