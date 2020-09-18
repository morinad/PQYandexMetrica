// This file contains your Data Connector logic
section YandexMetrika;

[DataSource.Kind="YandexMetrika", Publish="YandexMetrika.Publish"]
shared YandexMetrika.Data = Value.ReplaceType(YandexMetrika.Stat, FuncType);

FuncType = type function (
      ids as (type text meta [
        Documentation.FieldCaption = "ID счетчика Яндекс.Метрики:",
        Documentation.SampleValues = {"1234567"}
    ]),
     
 metrics as (type text meta [
        Documentation.FieldCaption = "Список показателей через запятую:",
        Documentation.SampleValues = {"ym:s:visits,ym:s:bounces"}
    ]),

     dimensions as (type nullable text meta [
        Documentation.FieldCaption = "Список параметров через запятую:",
        Documentation.SampleValues = {"ym:s:date,ym:s:UTMCampaign"}
    ]),

    date1 as (type text meta [
        Documentation.FieldCaption = "Дата начала:",
        Documentation.SampleValues = {"2020-02-28"}
    ]),

     date2 as (type text meta [
        Documentation.FieldCaption = "Дата окончания:",
        Documentation.SampleValues = {"yesterday"}
    ]),


     filters as (type nullable text meta [
        Documentation.FieldCaption = "Фильтры:",
        Documentation.SampleValues = {"ym:s:UTMSource=='yandex'"}

    ]),
      direct_ids as (type nullable text meta [
        Documentation.FieldCaption = "ID Яндекс Директа:",
        Documentation.SampleValues = {"12345678"}
    ])

    )
    as table meta [
        Documentation.Name = "Функция Максима Уварова (learn.needfordata.ru). Забираем данные из Яндекс.Метрики.",
        Documentation.LongDescription = 
        "Получите ТОКЕН по ссылке ниже.

",
        Documentation.Examples = {
        [
            Description = "Возвращает табличку по Показам, Кликам и Расходам по Дате и Кампаниям.",
            Code = "YandexMetrika.Data(""76543210"",""ym:s:visits,ym:s:bounces"", ""ym:s:date,ym:s:UTMCampaign"", ""2020-01-31"", ""yesterday"", ""AQAAyJ1APquh4JeqEyfNMG8"",  ""ym:s:UTMSource=='yandex'"", null)",
            Result = "Таблица из 4 столбцов: Дата, UTM Campaign, Визиты и Отказы."
        ],
        [
            Description = "Возвращает конверсии по 3 целям по фразам и устройствам. Модель атрибуции по последний клик с Директа.",
            Code = "YandexMetrika.Data(""76543210"",""ym:ad:RUBAdCost,ym:ad:clicks"", ""ym:ad:date,ym:ad:directOrder"", ""500daysAgo"", ""today"", ""AQAAyJ1APquh4JeqEyfNMG8"",  null, ""12345678"")",
            Result ="Таблица из 4 столбцов: Кампания, Дата, Расходы и Клики."
        ],
        [
            Description = "Первая ссылка - на получение токена. Вторая ссылка - полный список параметров и показателей Яндекс.Метрики:",
            Code = "https://oauth.yandex.ru/authorize?response_type=token&client_id=f8bd88fd26064cfa8042faf436795a7a",
            Result = "https://docs.google.com/spreadsheets/d/1zWAq_wYQymYcJvKV-XcodNVTYu5ZiZJ2YqKWhscPf0Y/"
                    ],
         [
            Description = "Ссылка на сайт автора функции:",
            Code = "https://learn.needfordata.ru/",
            Result = ""
                    ]

        }
    ];


redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html";
windowWidth = 1000;
windowHeight = 800;
clientID = "54c7d85869d9431cb6b1e6a18f689184";
clientSecret = "ac499951f7954b2fb6af34059818246c";

YandexMetrika.Stat =  (ids as text, metrics as text, dimensions as nullable  text,  date1 as text, date2 as text, filters as  nullable text,  direct_ids as nullable text) => 

let
    dimensionsAfterNull = if dimensions = null then "" else dimensions,
    bigRecordWithOptions = [ids = ids, dimensions = dimensionsAfterNull,  metrics = metrics, date1 = date1, date2 = date2,  accuracy = "full"], 
    bigRecordWithFilters = if filters = null then bigRecordWithOptions else Record.AddField(bigRecordWithOptions, "filters", filters), 
    bigRecordWithDirectIds = if direct_ids = null  then bigRecordWithFilters else Record.AddField(bigRecordWithOptions, "direct_client_ids", direct_ids), 
    jsonResponse = metrika_json(bigRecordWithDirectIds),
    Source0 = Number.RoundDown(jsonResponse/10000,0),
    listOfPages = {0..Source0},
    listOf10kPages = List.Transform(listOfPages, each _ * 10000 + 1),
    TableChunks = List.Transform(listOf10kPages, each metrika_fun(bigRecordWithDirectIds, _)),
    TableNames = Table.ColumnNames(TableChunks{0}),
    TableFromChunks = Table.FromList(TableChunks, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    OutputTable = try Table.ExpandTableColumn( TableFromChunks , "Column1", TableNames )  otherwise jsonResponse 
in
    OutputTable;
    

 metrika_fun = (bigRecordWithOptions as record, X as number) =>
let
    offset = Number.ToText (X),
    bigRecordWithWithLimit = bigRecordWithOptions & [limit = "10000", offset = offset],
    urlToGet = "https://api-metrika.yandex.ru/stat/v1/data.csv?ids=2138128&metrics=ym%3As%3Avisits&date1=yesterday&date2=yesterday",
    webContents2 = Web.Contents(urlToGet, [Query = bigRecordWithWithLimit, Headers = [Authorization="OAuth " & Extension.CurrentCredential()[access_token]]] ),
    Source = Csv.Document(webContents2,null,",",null,65001),
    #"First Row as Header" = Table.PromoteHeaders(Source),
    mergedColumns = if Table.RowCount(#"First Row as Header") = 1 then #"First Row as Header" else Table.Skip(#"First Row as Header",1)
in
    mergedColumns;




 metrika_json = (bigRecordWithOptions as record) =>
let
    urlToGet = "https://api-metrika.yandex.ru/stat/v1/data?ids=2138128&metrics=ym%3As%3Avisits&date1=yesterday&date2=yesterday",
    webContents1 = Web.Contents(urlToGet, [Query = bigRecordWithOptions & [limit = "1"], Headers = [Authorization="OAuth " & Extension.CurrentCredential()[access_token]], ManualStatusHandling={400}]),
    jsonDocumentFromMetrika = Json.Document(webContents1),
    MetrikaJsonOutput = if jsonDocumentFromMetrika[total_rows]? = null then jsonDocumentFromMetrika[message] else jsonDocumentFromMetrika[total_rows]
in
    MetrikaJsonOutput;


dateFunc= (dat)=>
       if dat = "yesterday" then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()) , -1),"yyyy-MM-dd") 
       else if dat = "today" then Date.ToText(Date.From(DateTime.LocalNow()),"yyyy-MM-dd")
       else if (try Number.From(Text.BeforeDelimiter(dat,"daysAgo")) otherwise 0) >0 then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()),-1*Number.From(Text.BeforeDelimiter(dat,"daysAgo"))),"yyyy-MM-dd") 
       else dat;





// Data Source Kind description
YandexMetrika = [
    TestConnection = (dataSourcePath) => 
        { 
        "YandexMetrika.Data",
        Json.Document(dataSourcePath)[ids],
        Json.Document(dataSourcePath)[metrics],
        Json.Document(dataSourcePath)[dimensions]?,
        Json.Document(dataSourcePath)[date1],
        Json.Document(dataSourcePath)[date2],
        Json.Document(dataSourcePath)[filters]?,
        Json.Document(dataSourcePath)[direct_ids]?
        },
    Authentication = [
        
        OAuth = [
            StartLogin = StartLogin,
            FinishLogin = FinishLogin,
         //  Refresh=Refresh,
         // Logout=Logout,
            Label = "Log In"
            ]
    ],
    Label = "YandexMetrika Connection"
];

// https://oauth.YandexMetrika.ru/authorize?response_type=code&client_id=5240a313fe8a4e2a92449b35cf09b64e

StartLogin = (resourceUrl, state, display) =>
    let
        AuthorizeUrl = "https://oauth.yandex.ru/authorize?" & Uri.BuildQueryString([
            response_type="code",
            client_id=clientID,
            state = state,
            force_confirm="yes",
            redirect_uri = redirect_uri
            ])
    in
        [
            LoginUri = AuthorizeUrl,
            CallbackUri = redirect_uri,
            WindowHeight = windowHeight,
            WindowWidth = windowWidth,
            Context = "Hello"
        ];

FinishLogin = (context, callbackUri, state) =>
    let
        Parts = Uri.Parts(callbackUri)[Query]
    in
        TokenMethod(Text.From(Parts[code]));
        
    




TokenMethod = (code) =>
    let
         Response = Web.Contents("https://oauth.yandex.ru/token", [IsRetry=false, ManualStatusHandling={400},
                Content = Text.ToBinary(Uri.BuildQueryString([
                grant_type ="authorization_code",
                client_id=clientID,
                client_secret = clientSecret,
                code = code,
                redirect_uri = redirect_uri
                ])),
                Headers=[#"Content-type" = "application/x-www-form-urlencoded",#"Accept" = "application/json"]]),
        Body = Json.Document(Response)
    in
        Body;



Refresh = (resourceUrl, refresh_token) =>
    let
         Response = Web.Contents("https://oauth.yandex.ru/token", [IsRetry=false, ManualStatusHandling={400},
                Content = Text.ToBinary(Uri.BuildQueryString([
                grant_type ="refresh_token",
                refresh_token =refresh_token,
                client_id=clientID,
                client_secret = clientSecret,
                redirect_uri = redirect_uri
                ])),
                Headers=[#"Content-type" = "application/x-www-form-urlencoded",#"Accept" = "application/json"]]),
        Body = Json.Document(Response)
    in
        Body;



Logout = (token ) =>
    let
         Response = Web.Contents("https://oauth.yandex.ru/revoke_token", [ ManualStatusHandling={400},
                Content = Text.ToBinary(Uri.BuildQueryString([
                access_token=if token = null then "" else token,
                 client_id=clientID,
                client_secret = clientSecret
              //  device_id="0",
                //redirect_uri = redirect_uri
                ])),
                Headers=[#"Content-type" = "application/x-www-form-urlencoded",#"Accept" = "application/json"]]),
        Body = Json.Document(Response)
    in
        if Body[status]?="ok" then Body else [status="ne ok"];





// Data Source UI publishing description
YandexMetrika.Publish = [
    Beta = false,
    Category = "Other",
    ButtonText = { "YandexMetrika Connector", "Help" },
    LearnMoreUrl = "https://www.youtube.com/channel/UCqSLNYLN_3mf6nA1Xf7fu1g",
    SourceImage = YandexMetrika.Icons,
    SourceTypeImage = YandexMetrika.Icons
];

YandexMetrika.Icons = [
    Icon16 = { Extension.Contents("YandexMetrika16.png"), Extension.Contents("YandexMetrika20.png"), Extension.Contents("YandexMetrika24.png"), Extension.Contents("YandexMetrika32.png") },
    Icon32 = { Extension.Contents("YandexMetrika32.png"), Extension.Contents("YandexMetrika40.png"), Extension.Contents("YandexMetrika48.png"), Extension.Contents("YandexMetrika64.png") }
];
