unit MCPTool.Notes;

(*
  MCPTool.Notes  ·  mcp-notes  ·  port 8648

  Markdown note store with BM25 full-text search.
  - Notes stored as .md files with simple key: value frontmatter
  - BM25 inverted index maintained in memory (lazy-loaded on first search)
  - Index updated incrementally on write/delete

  Operations:
    write    {id, title, content, tags?}    → {ok, id, is_new, created_at, updated_at}
    read     {id}                           → {ok, id, title, content, tags, created_at, updated_at}
    delete   {id}                           → {ok, id, existed}
    search   {query, limit?}                → {ok, results:[{id,title,score,snippet}], count}
    list     {tag?}                         → {ok, notes:[{id,title,tags,updated_at}], count}
    tags                                    → {ok, tags:{tag→count}, count}
    reindex                                 → {ok, indexed:N}

  Optional param for all ops: storage_path (default: {Documents}/mcp-notes/)
  Frontmatter format:
    ---
    id: note-id
    title: Note Title
    tags: tag1,tag2,tag3
    created_at: 2026-04-01T10:00:00
    updated_at: 2026-04-01T10:00:00
    ---
    Content...
  Port: 8648
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.SyncObjs,
  System.Math,
  StrUtils;

type
  TNotesParams = class
  private
    FOperation:   string;
    FId:          string;
    FTitle:       string;
    FContent:     string;
    FTags:        string;
    FQuery:       string;
    FLimit:       Integer;
    FTag:         string;
    FStoragePath: string;
  public
    [AiMCPSchemaDescription('Operation: write, read, delete, search, list, tags, reindex')]
    property Operation:   string  read FOperation   write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Note identifier (slug). Required for: write, read, delete.')]
    property Id:          string  read FId          write FId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Note title (required for write)')]
    property Title:       string  read FTitle       write FTitle;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Markdown content (required for write)')]
    property Content:     string  read FContent     write FContent;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comma-separated tags (optional for write)')]
    property Tags:        string  read FTags        write FTags;

    [AiMCPOptional]
    [AiMCPSchemaDescription('BM25 search query (required for search)')]
    property Query:       string  read FQuery       write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max results for search. Default: 10.')]
    property Limit:       Integer read FLimit       write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Filter by tag for list operation')]
    property Tag:         string  read FTag         write FTag;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Storage base directory. Default: {Documents}/mcp-notes/')]
    property StoragePath: string  read FStoragePath write FStoragePath;
  end;

  { BM25 index — one instance per storage directory }

  TDocMeta = record
    Id:        string;
    Title:     string;
    Tags:      string;
    CreatedAt: string;
    UpdatedAt: string;
    DocLen:    Integer;
  end;

  TBM25Index = class
  private const
    BM25_K1 = 1.5;
    BM25_B  = 0.75;
    SNIPPET_LEN = 220;

    STOPWORDS: array[0..32] of string = (
      'a','an','the','and','or','not','is','are','was','were','be','been',
      'being','have','has','had','do','does','did','will','would','could',
      'should','may','might','to','of','in','on','at','by','for','with'
    );

  private
    FStorageDir: string;
    FLoaded:     Boolean;
    // docId → metadata (title, tags, dates, docLen)
    FMeta:       TDictionary<string, TDocMeta>;
    // docId → (term → freq)
    FTermFreqs:  TObjectDictionary<string, TDictionary<string, Integer>>;
    // term → [docId, ...]
    FInvIdx:     TObjectDictionary<string, TList<string>>;
    FTotalDocLen: Int64;   // sum of all docLens; AvgDocLen = FTotalDocLen / N

    function  IsStopword(const W: string): Boolean;
    function  Tokenize(const Text: string): TArray<string>;
    procedure AddDocToIndex(const DocId: string; const Tokens: TArray<string>;
                            const Meta: TDocMeta);
    procedure RemoveDocFromIndex(const DocId: string);
    function  IDF(const Term: string): Double;
    function  ScoreDoc(const DocId: string; const QueryTerms: TArray<string>): Double;
    function  BuildSnippet(const Content, Query: string): string;
    function  NoteFilePath(const Id: string): string;
    function  SafeId(const Id: string): string;
    procedure ParseFile(const FilePath: string; out Meta: TDocMeta; out Content: string);
    procedure WriteFile(const Meta: TDocMeta; const Content: string);
    function  LoadMeta(const FilePath: string): TDocMeta;
    procedure LoadAllDocs;
  public
    constructor Create(const StorageDir: string);
    destructor Destroy; override;
    procedure EnsureLoaded;
    function WriteNote(const Id, Title, Content, Tags: string): TJSONObject;
    function ReadNote(const Id: string): TJSONObject;
    function DeleteNote(const Id: string): TJSONObject;
    function SearchNotes(const Query: string; Limit: Integer): TJSONObject;
    function ListNotes(const Tag: string): TJSONObject;
    function GetTags: TJSONObject;
    function Reindex: TJSONObject;
  end;

  TNotesTool = class(TAiMCPToolBase<TNotesParams>)
  private
    function ResolveDir(const P: TNotesParams): string;
    function GetIndex(const Dir: string): TBM25Index;  // caller MUST hold GNotesLock
    function DoWrite(const P: TNotesParams): TJSONObject;
    function DoRead(const P: TNotesParams): TJSONObject;
    function DoDelete(const P: TNotesParams): TJSONObject;
    function DoSearch(const P: TNotesParams): TJSONObject;
    function DoList(const P: TNotesParams): TJSONObject;
    function DoTags(const P: TNotesParams): TJSONObject;
    function DoReindex(const P: TNotesParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TNotesParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure SetDefaultStoragePath(const APath: string);
procedure RegisterTools(AServer: TAiMCPServer);

implementation

var
  GNotesLock:          TCriticalSection;
  GNotesIndices:       TObjectDictionary<string, TBM25Index>;
  GDefaultStoragePath: string = '';

{ TBM25Index }

constructor TBM25Index.Create(const StorageDir: string);
begin
  inherited Create;
  FStorageDir  := StorageDir;
  FLoaded      := False;
  FTotalDocLen := 0;
  FMeta        := TDictionary<string, TDocMeta>.Create;
  FTermFreqs   := TObjectDictionary<string, TDictionary<string, Integer>>.Create([doOwnsValues]);
  FInvIdx      := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
end;

destructor TBM25Index.Destroy;
begin
  FMeta.Free;
  FTermFreqs.Free;
  FInvIdx.Free;
  inherited;
end;

function TBM25Index.SafeId(const Id: string): string;
var
  I: Integer;
  C: Char;
  S: string;
begin
  S := '';
  for I := 1 to Length(Id) do
  begin
    C := Id[I];
    if CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) then
      S := S + C
    else
      S := S + '_';
  end;
  if S = '' then S := 'note';
  Result := S;
end;

function TBM25Index.NoteFilePath(const Id: string): string;
begin
  Result := TPath.Combine(FStorageDir, SafeId(Id) + '.md');
end;

function TBM25Index.IsStopword(const W: string): Boolean;
var
  I: Integer;
begin
  for I := Low(STOPWORDS) to High(STOPWORDS) do
    if STOPWORDS[I] = W then Exit(True);
  Result := False;
end;

function TBM25Index.Tokenize(const Text: string): TArray<string>;
var
  List:  TList<string>;
  LText: string;
  I:     Integer;
  Start: Integer;
  Token: string;
  C:     Char;
begin
  List  := TList<string>.Create;
  try
    Start := 0;
    LText := LowerCase(Text);  // lowercase once; O(n) not O(n²)
    for I := 1 to Length(LText) do
    begin
      C := LText[I];
      if CharInSet(C, ['a'..'z', '0'..'9']) then
      begin
        if Start = 0 then Start := I;
      end
      else
      begin
        if Start > 0 then
        begin
          Token := Copy(LText, Start, I - Start);
          if (Length(Token) >= 2) and not IsStopword(Token) then
            List.Add(Token);
          Start := 0;
        end;
      end;
    end;
    // flush last token
    if Start > 0 then
    begin
      Token := Copy(LText, Start, Length(LText) - Start + 1);
      if (Length(Token) >= 2) and not IsStopword(Token) then
        List.Add(Token);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure TBM25Index.AddDocToIndex(const DocId: string;
  const Tokens: TArray<string>; const Meta: TDocMeta);
var
  TF:     TDictionary<string, Integer>;
  Token:  string;
  Freq:   Integer;
  DocIds: TList<string>;
begin
  // Update FMeta
  FMeta.AddOrSetValue(DocId, Meta);

  // Build term-freq map for this doc
  TF := TDictionary<string, Integer>.Create;
  for Token in Tokens do
  begin
    if TF.TryGetValue(Token, Freq) then
      TF[Token] := Freq + 1
    else
      TF.Add(Token, 1);
  end;
  FTermFreqs.AddOrSetValue(DocId, TF);

  // Update inverted index
  for Token in TF.Keys do
  begin
    if not FInvIdx.TryGetValue(Token, DocIds) then
    begin
      DocIds := TList<string>.Create;
      FInvIdx.Add(Token, DocIds);
    end;
    if not DocIds.Contains(DocId) then
      DocIds.Add(DocId);
  end;

  FTotalDocLen := FTotalDocLen + Meta.DocLen;
end;

procedure TBM25Index.RemoveDocFromIndex(const DocId: string);
var
  TF:     TDictionary<string, Integer>;
  Token:  string;
  DocIds: TList<string>;
  Meta:   TDocMeta;
begin
  if FTermFreqs.TryGetValue(DocId, TF) then
  begin
    // Remove from inverted index
    for Token in TF.Keys do
    begin
      if FInvIdx.TryGetValue(Token, DocIds) then
      begin
        DocIds.Remove(DocId);
        if DocIds.Count = 0 then
          FInvIdx.Remove(Token);
      end;
    end;
    FTermFreqs.Remove(DocId);
  end;

  if FMeta.TryGetValue(DocId, Meta) then
  begin
    FTotalDocLen := FTotalDocLen - Meta.DocLen;
    FMeta.Remove(DocId);
  end;
end;

function TBM25Index.IDF(const Term: string): Double;
var
  N:  Integer;
  DF: Integer;
  DocIds: TList<string>;
begin
  N := FMeta.Count;
  if N = 0 then Exit(0);
  DF := 0;
  if FInvIdx.TryGetValue(Term, DocIds) then
    DF := DocIds.Count;
  Result := Ln((N - DF + 0.5) / (DF + 0.5) + 1);
end;

function TBM25Index.ScoreDoc(const DocId: string;
  const QueryTerms: TArray<string>): Double;
var
  Term:     string;
  TF:       TDictionary<string, Integer>;
  Freq:     Integer;
  DocLen:   Integer;
  AvgLen:   Double;
  Meta:     TDocMeta;
  IdfVal:   Double;
  TFNorm:   Double;
begin
  Result := 0;
  if not FTermFreqs.TryGetValue(DocId, TF) then Exit;
  if not FMeta.TryGetValue(DocId, Meta)    then Exit;
  DocLen := Meta.DocLen;
  AvgLen := IfThen(FMeta.Count > 0, FTotalDocLen / FMeta.Count, 1);
  if AvgLen < 1 then AvgLen := 1;

  for Term in QueryTerms do
  begin
    if not TF.TryGetValue(Term, Freq) then Continue;
    IdfVal := IDF(Term);
    TFNorm := Freq * (BM25_K1 + 1) /
              (Freq + BM25_K1 * (1 - BM25_B + BM25_B * DocLen / AvgLen));
    Result := Result + IdfVal * TFNorm;
  end;
end;

function TBM25Index.BuildSnippet(const Content, Query: string): string;
var
  MatchPos: Integer;
  Start: Integer;
  Len:   Integer;
  Lcont: string;
  Word:  string;
  Tokens: TArray<string>;
begin
  Lcont    := LowerCase(Content);
  Tokens   := Tokenize(Query);
  MatchPos := 0;

  // Find first occurrence of any query token in content
  for Word in Tokens do
  begin
    MatchPos := Pos(Word, Lcont);
    if MatchPos > 0 then Break;
  end;

  if MatchPos = 0 then
    MatchPos := 1;

  Start := Max(1, MatchPos - 60);
  Len   := Min(SNIPPET_LEN, Length(Content) - Start + 1);
  Result := Trim(Copy(Content, Start, Len));
  if Start > 1        then Result := '...' + Result;
  if Start + Len - 1 < Length(Content) then Result := Result + '...';
end;

procedure TBM25Index.ParseFile(const FilePath: string;
  out Meta: TDocMeta; out Content: string);
var
  Lines:    TStringList;
  I:        Integer;
  InFront:  Boolean;
  FrontEnd: Boolean;
  Line:     string;
  Key:      string;
  Val:      string;
  ColPos:   Integer;
  Body:     TStringBuilder;
begin
  Meta := Default(TDocMeta);
  Content  := '';
  InFront  := False;
  FrontEnd := False;

  Lines := TStringList.Create;
  Body  := TStringBuilder.Create;
  try
    Lines.LoadFromFile(FilePath, TEncoding.UTF8);
    I := 0;
    while I < Lines.Count do
    begin
      Line := Lines[I];
      if (I = 0) and (Trim(Line) = '---') then
      begin
        InFront := True;
        Inc(I); Continue;
      end;
      if InFront and not FrontEnd then
      begin
        if Trim(Line) = '---' then
        begin
          FrontEnd := True;
          Inc(I); Continue;
        end;
        ColPos := Pos(':', Line);
        if ColPos > 0 then
        begin
          Key := Trim(Copy(Line, 1, ColPos - 1));
          Val := Trim(Copy(Line, ColPos + 1, MaxInt));
          if      Key = 'id'         then Meta.Id        := Val
          else if Key = 'title'      then Meta.Title      := Val
          else if Key = 'tags'       then Meta.Tags       := Val
          else if Key = 'created_at' then Meta.CreatedAt  := Val
          else if Key = 'updated_at' then Meta.UpdatedAt  := Val;
        end;
      end
      else if FrontEnd then
      begin
        if Body.Length > 0 then Body.Append(#10);
        Body.Append(Line);
      end;
      Inc(I);
    end;
    Content := Body.ToString;
  finally
    Lines.Free;
    Body.Free;
  end;
end;

procedure TBM25Index.WriteFile(const Meta: TDocMeta; const Content: string);
var
  Dir: string;
  FP:  string;
  SB:  TStringBuilder;
begin
  FP  := NoteFilePath(Meta.Id);
  Dir := TPath.GetDirectoryName(FP);
  if not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('---');
    SB.AppendLine('id: '         + Meta.Id);
    SB.AppendLine('title: '      + Meta.Title);
    SB.AppendLine('tags: '       + Meta.Tags);
    SB.AppendLine('created_at: ' + Meta.CreatedAt);
    SB.AppendLine('updated_at: ' + Meta.UpdatedAt);
    SB.AppendLine('---');
    SB.Append(Content);
    TFile.WriteAllText(FP, SB.ToString, TEncoding.UTF8);
  finally
    SB.Free;
  end;
end;

function TBM25Index.LoadMeta(const FilePath: string): TDocMeta;
var
  Content: string;
begin
  ParseFile(FilePath, Result, Content);
  if Result.Id = '' then
    Result.Id := TPath.GetFileNameWithoutExtension(FilePath);
end;

procedure TBM25Index.LoadAllDocs;
var
  Files:   TArray<string>;
  FP:      string;
  Meta:    TDocMeta;
  Content: string;
  Tokens:  TArray<string>;
begin
  FMeta.Clear;
  FTermFreqs.Clear;
  FInvIdx.Clear;
  FTotalDocLen := 0;

  if not TDirectory.Exists(FStorageDir) then Exit;

  Files := TDirectory.GetFiles(FStorageDir, '*.md');
  for FP in Files do
  begin
    ParseFile(FP, Meta, Content);
    if Meta.Id = '' then
      Meta.Id := TPath.GetFileNameWithoutExtension(FP);
    Tokens       := Tokenize(Meta.Title + ' ' + Content);
    Meta.DocLen  := Length(Tokens);
    AddDocToIndex(Meta.Id, Tokens, Meta);
  end;
end;

procedure TBM25Index.EnsureLoaded;
begin
  if not FLoaded then
  begin
    LoadAllDocs;
    FLoaded := True;
  end;
end;

{ Public operations }

function TBM25Index.WriteNote(const Id, Title, Content, Tags: string): TJSONObject;
var
  Meta:    TDocMeta;
  Tokens:  TArray<string>;
  Now:     string;
  IsNew:   Boolean;
  OldMeta: TDocMeta;
begin
  EnsureLoaded;
  Now     := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', System.SysUtils.Now);
  OldMeta := Default(TDocMeta);  // must init before TryGetValue; IfThen is NOT short-circuit
  IsNew   := not FMeta.TryGetValue(SafeId(Id), OldMeta);

  // Remove old index entries if updating
  if not IsNew then
    RemoveDocFromIndex(SafeId(Id));

  Meta.Id        := SafeId(Id);
  Meta.Title     := Title;
  Meta.Tags      := Tags;
  Meta.CreatedAt := IfThen(IsNew, Now, OldMeta.CreatedAt);
  Meta.UpdatedAt := Now;

  Tokens      := Tokenize(Title + ' ' + Content);
  Meta.DocLen := Length(Tokens);

  WriteFile(Meta, Content);
  AddDocToIndex(Meta.Id, Tokens, Meta);

  Result := TJSONObject.Create;
  Result.AddPair('ok',         TJSONTrue.Create);
  Result.AddPair('id',         Meta.Id);
  Result.AddPair('is_new',     TJSONBool.Create(IsNew));
  Result.AddPair('created_at', Meta.CreatedAt);
  Result.AddPair('updated_at', Meta.UpdatedAt);
end;

function TBM25Index.ReadNote(const Id: string): TJSONObject;
var
  FP:      string;
  Meta:    TDocMeta;
  Content: string;
begin
  FP := NoteFilePath(Id);
  if not TFile.Exists(FP) then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('ok',    TJSONFalse.Create);
    Result.AddPair('error', 'Note not found: ' + Id);
    Exit;
  end;
  ParseFile(FP, Meta, Content);
  if Meta.Id = '' then Meta.Id := SafeId(Id);

  Result := TJSONObject.Create;
  Result.AddPair('ok',         TJSONTrue.Create);
  Result.AddPair('id',         Meta.Id);
  Result.AddPair('title',      Meta.Title);
  Result.AddPair('content',    Content);
  Result.AddPair('tags',       Meta.Tags);
  Result.AddPair('created_at', Meta.CreatedAt);
  Result.AddPair('updated_at', Meta.UpdatedAt);
end;

function TBM25Index.DeleteNote(const Id: string): TJSONObject;
var
  FP:      string;
  Existed: Boolean;
begin
  EnsureLoaded;
  FP      := NoteFilePath(Id);
  Existed := TFile.Exists(FP);
  if Existed then
  begin
    TFile.Delete(FP);
    RemoveDocFromIndex(SafeId(Id));
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('id',      SafeId(Id));
  Result.AddPair('existed', TJSONBool.Create(Existed));
end;

function TBM25Index.SearchNotes(const Query: string; Limit: Integer): TJSONObject;
type
  TScorePair = TPair<string, Double>;
var
  QueryTerms: TArray<string>;
  Term:       string;
  DocIds:     TList<string>;
  Scored:     TList<TScorePair>;
  DocId:      string;
  Score:      Double;
  Seen:       TDictionary<string, Boolean>;
  Arr:        TJSONArray;
  Item:       TJSONObject;
  Meta:       TDocMeta;
  FP:         string;
  RawContent: string;
  RawMeta:    TDocMeta;
  I:          Integer;
begin
  EnsureLoaded;
  if Limit <= 0 then Limit := 10;

  QueryTerms := Tokenize(Query);
  Seen       := TDictionary<string, Boolean>.Create;
  Scored     := TList<TScorePair>.Create;
  try
    // Collect candidate docs from inverted index
    for Term in QueryTerms do
    begin
      if not FInvIdx.TryGetValue(Term, DocIds) then Continue;
      for DocId in DocIds do
        if not Seen.ContainsKey(DocId) then
          Seen.Add(DocId, True);
    end;

    // Score each candidate
    for DocId in Seen.Keys do
    begin
      Score := ScoreDoc(DocId, QueryTerms);
      if Score > 0 then
        Scored.Add(TScorePair.Create(DocId, Score));
    end;

    // Sort descending by score
    Scored.Sort(TComparer<TScorePair>.Construct(
      function(const A, B: TScorePair): Integer
      begin
        if A.Value > B.Value then Result := -1
        else if A.Value < B.Value then Result := 1
        else Result := 0;
      end));

    Arr := TJSONArray.Create;
    I   := 0;
    while (I < Scored.Count) and (I < Limit) do
    begin
      DocId := Scored[I].Key;
      Score := Scored[I].Value;
      if FMeta.TryGetValue(DocId, Meta) then
      begin
        FP      := NoteFilePath(DocId);
        RawMeta := Default(TDocMeta);
        RawContent := '';
        if TFile.Exists(FP) then
          ParseFile(FP, RawMeta, RawContent);

        Item := TJSONObject.Create;
        Item.AddPair('id',      DocId);
        Item.AddPair('title',   Meta.Title);
        Item.AddPair('score',   TJSONNumber.Create(Score));
        Item.AddPair('snippet', BuildSnippet(RawContent, Query));
        Item.AddPair('tags',    Meta.Tags);
        Arr.AddElement(Item);
      end;
      Inc(I);
    end;
  finally
    Scored.Free;
    Seen.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('query',   Query);
  Result.AddPair('results', Arr);
  Result.AddPair('count',   TJSONNumber.Create(Arr.Count));
end;

function TBM25Index.ListNotes(const Tag: string): TJSONObject;
var
  Files:   TArray<string>;
  FP:      string;
  Meta:    TDocMeta;
  Arr:     TJSONArray;
  Item:    TJSONObject;
  TagF:    string;
begin
  TagF := LowerCase(Trim(Tag));
  Arr  := TJSONArray.Create;

  if TDirectory.Exists(FStorageDir) then
  begin
    Files := TDirectory.GetFiles(FStorageDir, '*.md');
    for FP in Files do
    begin
      Meta := LoadMeta(FP);
      if (TagF <> '') and (Pos(TagF, LowerCase(Meta.Tags)) = 0) then
        Continue;
      Item := TJSONObject.Create;
      Item.AddPair('id',         Meta.Id);
      Item.AddPair('title',      Meta.Title);
      Item.AddPair('tags',       Meta.Tags);
      Item.AddPair('updated_at', Meta.UpdatedAt);
      Arr.AddElement(Item);
    end;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('notes', Arr);
  Result.AddPair('count', TJSONNumber.Create(Arr.Count));
end;

function TBM25Index.GetTags: TJSONObject;
var
  Files:    TArray<string>;
  FP:       string;
  Meta:     TDocMeta;
  TagCounts: TDictionary<string, Integer>;
  TagList:  TArray<string>;
  Tag:      string;
  TagsObj:  TJSONObject;
  Cnt:      Integer;
begin
  TagCounts := TDictionary<string, Integer>.Create;
  try
    if TDirectory.Exists(FStorageDir) then
    begin
      Files := TDirectory.GetFiles(FStorageDir, '*.md');
      for FP in Files do
      begin
        Meta    := LoadMeta(FP);
        TagList := Meta.Tags.Split([',']);
        for Tag in TagList do
        begin
          var T := Trim(Tag);
          if T = '' then Continue;
          if TagCounts.TryGetValue(T, Cnt) then
            TagCounts[T] := Cnt + 1
          else
            TagCounts.Add(T, 1);
        end;
      end;
    end;

    TagsObj := TJSONObject.Create;
    for Tag in TagCounts.Keys do
      TagsObj.AddPair(Tag, TJSONNumber.Create(TagCounts[Tag]));
  finally
    TagCounts.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('tags',  TagsObj);
  Result.AddPair('count', TJSONNumber.Create(TagsObj.Count));
end;

function TBM25Index.Reindex: TJSONObject;
var
  N: Integer;
begin
  LoadAllDocs;
  FLoaded := True;
  N       := FMeta.Count;
  Result  := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('indexed', TJSONNumber.Create(N));
end;

{ TNotesTool }

function TNotesTool.ResolveDir(const P: TNotesParams): string;
begin
  if Trim(P.StoragePath) <> '' then
    Result := P.StoragePath                // per-call override
  else if GDefaultStoragePath <> '' then
    Result := GDefaultStoragePath          // set via --storage-path at startup
  else
    Result := TPath.Combine(TPath.GetDocumentsPath, 'mcp-notes');
end;

function TNotesTool.GetIndex(const Dir: string): TBM25Index;
begin
  if not GNotesIndices.TryGetValue(Dir, Result) then
  begin
    Result := TBM25Index.Create(Dir);
    GNotesIndices.Add(Dir, Result);
  end;
end;

function TNotesTool.DoWrite(const P: TNotesParams): TJSONObject;
var
  Dir: string;
  Idx: TBM25Index;
begin
  if P.Id      = '' then raise Exception.Create('"id" is required for write');
  if P.Title   = '' then raise Exception.Create('"title" is required for write');
  if P.Content = '' then raise Exception.Create('"content" is required for write');
  Dir := ResolveDir(P);
  GNotesLock.Acquire;
  try
    Idx    := GetIndex(Dir);
    Result := Idx.WriteNote(P.Id, P.Title, P.Content, P.Tags);
  finally
    GNotesLock.Release;
  end;
end;

function TNotesTool.DoRead(const P: TNotesParams): TJSONObject;
var
  Dir: string;
  Idx: TBM25Index;
begin
  if P.Id = '' then raise Exception.Create('"id" is required for read');
  Dir := ResolveDir(P);
  GNotesLock.Acquire;
  try
    Idx    := GetIndex(Dir);
    Result := Idx.ReadNote(P.Id);
  finally
    GNotesLock.Release;
  end;
end;

function TNotesTool.DoDelete(const P: TNotesParams): TJSONObject;
var
  Dir: string;
  Idx: TBM25Index;
begin
  if P.Id = '' then raise Exception.Create('"id" is required for delete');
  Dir := ResolveDir(P);
  GNotesLock.Acquire;
  try
    Idx    := GetIndex(Dir);
    Result := Idx.DeleteNote(P.Id);
  finally
    GNotesLock.Release;
  end;
end;

function TNotesTool.DoSearch(const P: TNotesParams): TJSONObject;
var
  Dir:   string;
  Idx:   TBM25Index;
  Limit: Integer;
begin
  if P.Query = '' then raise Exception.Create('"query" is required for search');
  Dir   := ResolveDir(P);
  Limit := P.Limit;
  if Limit <= 0 then Limit := 10;
  GNotesLock.Acquire;
  try
    Idx    := GetIndex(Dir);
    Result := Idx.SearchNotes(P.Query, Limit);
  finally
    GNotesLock.Release;
  end;
end;

function TNotesTool.DoList(const P: TNotesParams): TJSONObject;
var
  Dir: string;
  Idx: TBM25Index;
begin
  Dir := ResolveDir(P);
  GNotesLock.Acquire;
  try
    Idx    := GetIndex(Dir);
    Result := Idx.ListNotes(P.Tag);
  finally
    GNotesLock.Release;
  end;
end;

function TNotesTool.DoTags(const P: TNotesParams): TJSONObject;
var
  Dir: string;
  Idx: TBM25Index;
begin
  Dir := ResolveDir(P);
  GNotesLock.Acquire;
  try
    Idx    := GetIndex(Dir);
    Result := Idx.GetTags;
  finally
    GNotesLock.Release;
  end;
end;

function TNotesTool.DoReindex(const P: TNotesParams): TJSONObject;
var
  Dir: string;
  Idx: TBM25Index;
begin
  Dir := ResolveDir(P);
  GNotesLock.Acquire;
  try
    Idx    := GetIndex(Dir);
    Result := Idx.Reindex;
  finally
    GNotesLock.Release;
  end;
end;

function TNotesTool.ExecuteWithParams(const AParams: TNotesParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'write'   then R := DoWrite(AParams)
    else if Op = 'read'    then R := DoRead(AParams)
    else if Op = 'delete'  then R := DoDelete(AParams)
    else if Op = 'search'  then R := DoSearch(AParams)
    else if Op = 'list'    then R := DoList(AParams)
    else if Op = 'tags'    then R := DoTags(AParams)
    else if Op = 'reindex' then R := DoReindex(AParams)
    else raise Exception.CreateFmt('Unknown operation "%s"', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\','\\').Replace('"','\"')
                   .Replace(#10,'\n').Replace(#13,'') + '"}')
        .Build;
  end;
end;

constructor TNotesTool.Create;
begin
  inherited;
  FName        := 'mcp-notes';
  FDescription :=
    'Markdown note store with BM25 full-text search. Notes are .md files saved to disk — they survive restarts.' + #10 +
    'ALWAYS include "operation" in every call. Use "id" as a short slug (letters, digits, hyphens only — no spaces).' + #10 +
    '' + #10 +
    'OPERATIONS (required params listed after each name):' + #10 +
    '  write   — id, title, content. Optional: tags (comma-separated). Creates or updates a note.' + #10 +
    '            Example: {"operation":"write","id":"meeting-2026","title":"Team meeting","content":"Discussed roadmap and Q2 goals.","tags":"meeting,work"}' + #10 +
    '  read    — id. Returns: title, content, tags, created_at, updated_at.' + #10 +
    '            Example: {"operation":"read","id":"meeting-2026"}' + #10 +
    '  delete  — id. Removes the note permanently.' + #10 +
    '            Example: {"operation":"delete","id":"meeting-2026"}' + #10 +
    '  search  — query (searches title + content). Optional: limit (default 10). Returns ranked list with score and snippet.' + #10 +
    '            Example: {"operation":"search","query":"roadmap Q2","limit":5}' + #10 +
    '  list    — no required params. Optional: tag to filter by one tag. Returns all notes with id, title, tags, updated_at.' + #10 +
    '            Example: {"operation":"list","tag":"work"}' + #10 +
    '  tags    — no params. Returns all tags with their note counts.' + #10 +
    '            Example: {"operation":"tags"}' + #10 +
    '  reindex — no params. Rebuilds the search index from disk (use after external file changes).' + #10 +
    '            Example: {"operation":"reindex"}';
end;

procedure SetDefaultStoragePath(const APath: string);
begin
  GDefaultStoragePath := Trim(APath);
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-notes',
    function: IAiMCPTool
    begin
      Result := TNotesTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-notes');
end;

initialization
  GNotesLock    := TCriticalSection.Create;
  GNotesIndices := TObjectDictionary<string, TBM25Index>.Create([doOwnsValues]);

// No finalization: server process killed externally; OS reclaims all memory.
// Freeing globals races with MCPServer background thread -> AV on close.

end.
