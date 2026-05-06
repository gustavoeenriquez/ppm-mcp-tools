unit MCPTool.HuggingFace;

{
  MCPTool.HuggingFace  ·  mcp-huggingface  (port 8627)
  HuggingFace Inference API — text, vision, audio tasks.

  Operations:
    text_generation     - generate/continue text
    text_classification - classify text into labels
    fill_mask           - predict masked token in text
    summarization       - summarize long text
    translation         - translate text between languages
    ner                 - named entity recognition
    question_answering  - answer questions given a context
    zero_shot           - zero-shot text classification (custom labels)
    sentence_similarity - compute sentence similarity scores
    image_classification - classify an image from URL
    list_models         - search/list models on HF Hub
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  THFParams = class
  private
    FOperation:  string;
    FApiKey:     string;
    FModel:      string;
    FText:       string;
    FTexts:      string;
    FContext:     string;
    FQuestion:   string;
    FLabels:     string;
    FSrcLang:    string;
    FTgtLang:    string;
    FMaxTokens:  Integer;
    FMinTokens:  Integer;
    FTemperature:Double;
    FSearch:     string;
    FTask:       string;
    FLimit:      Integer;
    FImageUrl:   string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: text_generation, text_classification, fill_mask, summarization, translation, ner, question_answering, zero_shot, sentence_similarity, image_classification, list_models')]
    property Operation:   string  read FOperation   write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HuggingFace API key (from huggingface.co/settings/tokens)')]
    property ApiKey:      string  read FApiKey      write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Model ID (e.g. gpt2, facebook/bart-large-cnn, Helsinki-NLP/opus-mt-en-es). If omitted, HF picks default for task.')]
    property Model:       string  read FModel       write FModel;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Input text for generation, classification, summarization, translation, NER, fill_mask')]
    property Text:        string  read FText        write FText;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Texts as JSON string array for sentence_similarity: ["sentence1","sentence2"]')]
    property Texts:       string  read FTexts       write FTexts;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Context passage for question_answering')]
    property Context:     string  read FContext     write FContext;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Question for question_answering')]
    property Question:    string  read FQuestion    write FQuestion;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Candidate labels as JSON array: ["label1","label2"] (for zero_shot)')]
    property Labels:      string  read FLabels      write FLabels;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Source language code for translation (e.g. en, fr, de)')]
    property SrcLang:     string  read FSrcLang     write FSrcLang;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Target language code for translation (e.g. es, zh, ja)')]
    property TgtLang:     string  read FTgtLang     write FTgtLang;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max new tokens for generation (default: 256)')]
    property MaxTokens:   Integer read FMaxTokens   write FMaxTokens;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Min new tokens for summarization (default: 0)')]
    property MinTokens:   Integer read FMinTokens   write FMinTokens;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Temperature for generation (default: 1.0)')]
    property Temperature: Double  read FTemperature write FTemperature;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search keyword for list_models')]
    property Search:      string  read FSearch      write FSearch;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Task filter for list_models (e.g. text-generation, translation, image-classification)')]
    property Task:        string  read FTask        write FTask;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max results for list_models (default: 10)')]
    property Limit:       Integer read FLimit       write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Image URL for image_classification')]
    property ImageUrl:    string  read FImageUrl    write FImageUrl;
  end;

  THuggingFaceTool = class(TAiMCPToolBase<THFParams>)
  private
    function AuthHeader(const ApiKey: string): string;
    function InferPost(const Model, DefaultModel, Body, ApiKey: string): string;
    function Wrap(const Raw: string): TJSONObject;
    function DoTextGeneration(const P: THFParams): TJSONObject;
    function DoTextClassification(const P: THFParams): TJSONObject;
    function DoFillMask(const P: THFParams): TJSONObject;
    function DoSummarization(const P: THFParams): TJSONObject;
    function DoTranslation(const P: THFParams): TJSONObject;
    function DoNER(const P: THFParams): TJSONObject;
    function DoQA(const P: THFParams): TJSONObject;
    function DoZeroShot(const P: THFParams): TJSONObject;
    function DoSentenceSimilarity(const P: THFParams): TJSONObject;
    function DoImageClassification(const P: THFParams): TJSONObject;
    function DoListModels(const P: THFParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: THFParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient;

const
  INFER_BASE = 'https://api-inference.huggingface.co/models/';
  HUB_BASE   = 'https://huggingface.co/api/models';

{ THFParams }

constructor THFParams.Create;
begin
  inherited;
  FMaxTokens   := 256;
  FMinTokens   := 0;
  FTemperature := 1.0;
  FLimit       := 10;
end;

{ THuggingFaceTool }

function THuggingFaceTool.AuthHeader(const ApiKey: string): string;
begin
  if Trim(ApiKey) <> '' then
    Result := 'Bearer ' + Trim(ApiKey)
  else
    Result := '';
end;

function THuggingFaceTool.InferPost(const Model, DefaultModel, Body,
  ApiKey: string): string;
var
  HTTP:     THTTPClient;
  Stream:   TStringStream;
  Resp:     IHTTPResponse;
  M, URL:   string;
  Headers:  TArray<TNameValuePair>;
begin
  M   := Trim(Model); if M = '' then M := DefaultModel;
  URL := INFER_BASE + M;
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Headers := [TNameValuePair.Create('Content-Type', 'application/json'),
                TNameValuePair.Create('x-wait-for-model', 'true')];
    if AuthHeader(ApiKey) <> '' then
      Headers := Headers + [TNameValuePair.Create('Authorization', AuthHeader(ApiKey))];
    Resp   := HTTP.Post(URL, Stream, nil, Headers);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function THuggingFaceTool.Wrap(const Raw: string): TJSONObject;
var
  J: TJSONValue;
begin
  J := TJSONObject.ParseJSONValue(Raw);
  if Assigned(J) then
  begin
    if J is TJSONObject then
      Result := J as TJSONObject
    else
    begin
      Result := TJSONObject.Create;
      Result.AddPair('result', J);
    end;
  end
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('raw', TJSONString.Create(Raw));
  end;
  Result.AddPair('ok', TJSONTrue.Create);
end;

function THuggingFaceTool.DoTextGeneration(const P: THFParams): TJSONObject;
var
  T, Body: string;
  MaxT:    Integer;
begin
  T := Trim(P.Text); if T = '' then raise Exception.Create('"text" required for text_generation');
  MaxT := P.MaxTokens; if MaxT <= 0 then MaxT := 256;
  Body := Format('{"inputs":"%s","parameters":{"max_new_tokens":%d,"temperature":%.2f,"return_full_text":false}}',
    [T.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,''),
     MaxT, P.Temperature]);
  Result := Wrap(InferPost(P.Model, 'gpt2', Body, P.ApiKey));
end;

function THuggingFaceTool.DoTextClassification(const P: THFParams): TJSONObject;
var
  T, Body: string;
begin
  T := Trim(P.Text); if T = '' then raise Exception.Create('"text" required for text_classification');
  Body   := Format('{"inputs":"%s"}',
    [T.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);
  Result := Wrap(InferPost(P.Model, 'distilbert-base-uncased-finetuned-sst-2-english', Body, P.ApiKey));
end;

function THuggingFaceTool.DoFillMask(const P: THFParams): TJSONObject;
var
  T, Body: string;
begin
  T := Trim(P.Text); if T = '' then raise Exception.Create('"text" with [MASK] required for fill_mask');
  Body   := Format('{"inputs":"%s"}',
    [T.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);
  Result := Wrap(InferPost(P.Model, 'bert-base-uncased', Body, P.ApiKey));
end;

function THuggingFaceTool.DoSummarization(const P: THFParams): TJSONObject;
var
  T, Body: string;
  MaxT, MinT: Integer;
begin
  T := Trim(P.Text); if T = '' then raise Exception.Create('"text" required for summarization');
  MaxT := P.MaxTokens; if MaxT <= 0 then MaxT := 256;
  MinT := P.MinTokens;
  Body := Format('{"inputs":"%s","parameters":{"max_length":%d,"min_length":%d}}',
    [T.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,''), MaxT, MinT]);
  Result := Wrap(InferPost(P.Model, 'facebook/bart-large-cnn', Body, P.ApiKey));
end;

function THuggingFaceTool.DoTranslation(const P: THFParams): TJSONObject;
var
  T, Body, M, Src, Tgt: string;
begin
  T   := Trim(P.Text);    if T = '' then raise Exception.Create('"text" required for translation');
  Src := Trim(P.SrcLang); if Src = '' then Src := 'en';
  Tgt := Trim(P.TgtLang); if Tgt = '' then Tgt := 'es';
  M   := Trim(P.Model);
  if M = '' then M := 'Helsinki-NLP/opus-mt-' + Src + '-' + Tgt;
  Body   := Format('{"inputs":"%s"}',
    [T.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);
  Result := Wrap(InferPost(M, M, Body, P.ApiKey));
end;

function THuggingFaceTool.DoNER(const P: THFParams): TJSONObject;
var
  T, Body: string;
begin
  T := Trim(P.Text); if T = '' then raise Exception.Create('"text" required for ner');
  Body   := Format('{"inputs":"%s","parameters":{"aggregation_strategy":"simple"}}',
    [T.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);
  Result := Wrap(InferPost(P.Model, 'dbmdz/bert-large-cased-finetuned-conll03-english', Body, P.ApiKey));
end;

function THuggingFaceTool.DoQA(const P: THFParams): TJSONObject;
var
  Q, C, Body: string;
begin
  Q := Trim(P.Question); if Q = '' then raise Exception.Create('"question" required for question_answering');
  C := Trim(P.Context);  if C = '' then raise Exception.Create('"context" required for question_answering');
  Body := Format('{"inputs":{"question":"%s","context":"%s"}}',
    [Q.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,''),
     C.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);
  Result := Wrap(InferPost(P.Model, 'deepset/roberta-base-squad2', Body, P.ApiKey));
end;

function THuggingFaceTool.DoZeroShot(const P: THFParams): TJSONObject;
var
  T, L, Body: string;
begin
  T := Trim(P.Text);   if T = '' then raise Exception.Create('"text" required for zero_shot');
  L := Trim(P.Labels); if L = '' then raise Exception.Create('"labels" JSON array required for zero_shot');
  Body := Format('{"inputs":"%s","parameters":{"candidate_labels":%s}}',
    [T.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,''), L]);
  Result := Wrap(InferPost(P.Model, 'facebook/bart-large-mnli', Body, P.ApiKey));
end;

function THuggingFaceTool.DoSentenceSimilarity(const P: THFParams): TJSONObject;
var
  T, Texts, Body: string;
begin
  Texts := Trim(P.Texts);
  if Texts = '' then
  begin
    T := Trim(P.Text);
    if T = '' then raise Exception.Create('"texts" (JSON array) or "text" required for sentence_similarity');
    Texts := Format('["%s"]', [T.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);
  end;
  Body   := Format('{"inputs":%s}', [Texts]);
  Result := Wrap(InferPost(P.Model, 'sentence-transformers/all-MiniLM-L6-v2', Body, P.ApiKey));
end;

function THuggingFaceTool.DoImageClassification(const P: THFParams): TJSONObject;
var
  ImgURL: string;
  HTTP:   THTTPClient;
  InferStream: TBytesStream;
  InferResp:   IHTTPResponse;
  M: string;
begin
  ImgURL := Trim(P.ImageUrl);
  if ImgURL = '' then raise Exception.Create('"imageUrl" required for image_classification');

  // Download the image bytes first, then post to inference API
  InferStream := TBytesStream.Create;
  HTTP := THTTPClient.Create;
  try
    HTTP.Get(ImgURL, InferStream);
  finally
    HTTP.Free;
  end;
  InferStream.Position := 0;

  M := Trim(P.Model); if M = '' then M := 'google/vit-base-patch16-224';

  HTTP := THTTPClient.Create;
  try
    var Headers: TArray<TNameValuePair> := [
      TNameValuePair.Create('Content-Type', 'application/octet-stream'),
      TNameValuePair.Create('x-wait-for-model', 'true')];
    if AuthHeader(P.ApiKey) <> '' then
      Headers := Headers + [TNameValuePair.Create('Authorization', AuthHeader(P.ApiKey))];
    InferResp := HTTP.Post(INFER_BASE + M, InferStream, nil, Headers);
    Result    := Wrap(InferResp.ContentAsString(TEncoding.UTF8));
  finally
    InferStream.Free;
    HTTP.Free;
  end;
end;

function THuggingFaceTool.DoListModels(const P: THFParams): TJSONObject;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  URL, Q: string;
  Lim:    Integer;
  Headers: TArray<TNameValuePair>;
begin
  Q   := Trim(P.Search);
  Lim := P.Limit; if Lim <= 0 then Lim := 10;
  URL := HUB_BASE + '?limit=' + IntToStr(Lim);
  if Q <> ''          then URL := URL + '&search=' + Q.Replace(' ', '+');
  if Trim(P.Task) <> '' then URL := URL + '&pipeline_tag=' + Trim(P.Task).Replace(' ','-');
  URL := URL + '&sort=downloads&direction=-1';

  HTTP := THTTPClient.Create;
  try
    Headers := [TNameValuePair.Create('Accept', 'application/json')];
    if AuthHeader(P.ApiKey) <> '' then
      Headers := Headers + [TNameValuePair.Create('Authorization', AuthHeader(P.ApiKey))];
    Resp   := HTTP.Get(URL, nil, Headers);
    Result := Wrap(Resp.ContentAsString(TEncoding.UTF8));
  finally
    HTTP.Free;
  end;
end;

function THuggingFaceTool.ExecuteWithParams(const AParams: THFParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'text_generation'     then R := DoTextGeneration(AParams)
    else if Op = 'text_classification' then R := DoTextClassification(AParams)
    else if Op = 'fill_mask'           then R := DoFillMask(AParams)
    else if Op = 'summarization'       then R := DoSummarization(AParams)
    else if Op = 'translation'         then R := DoTranslation(AParams)
    else if Op = 'ner'                 then R := DoNER(AParams)
    else if Op = 'question_answering'  then R := DoQA(AParams)
    else if Op = 'zero_shot'           then R := DoZeroShot(AParams)
    else if Op = 'sentence_similarity' then R := DoSentenceSimilarity(AParams)
    else if Op = 'image_classification' then R := DoImageClassification(AParams)
    else if Op = 'list_models'         then R := DoListModels(AParams)
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

constructor THuggingFaceTool.Create;
begin
  inherited;
  FName        := 'mcp-huggingface';
  FDescription :=
    'HuggingFace Inference API — ML models for text, vision and NLP. ' +
    'Operations: text_generation (params: text, model?, maxTokens?, temperature?) → generated text, ' +
    'text_classification (params: text, model?) → sentiment/labels, ' +
    'fill_mask (params: text with [MASK], model?) → predictions, ' +
    'summarization (params: text, model?, maxTokens?, minTokens?) → summary, ' +
    'translation (params: text, srcLang?, tgtLang?, model?) → translated text, ' +
    'ner (params: text, model?) → named entities, ' +
    'question_answering (params: question, context, model?) → answer, ' +
    'zero_shot (params: text, labels=JSON array, model?) → classification, ' +
    'sentence_similarity (params: texts=JSON array or text, model?) → scores, ' +
    'image_classification (params: imageUrl, model?) → labels, ' +
    'list_models (params: search?, task?, limit?) → model catalog. ' +
    'apiKey optional (free tier has rate limits). Get key at huggingface.co/settings/tokens.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-huggingface',
    function: IAiMCPTool
    begin
      Result := THuggingFaceTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-huggingface');
end;

end.
