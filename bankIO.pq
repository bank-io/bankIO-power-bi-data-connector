section BankIO;

//
// OAuth configuration settings
// 
// Note: due to incompatibilities with the Internet Explorer control used in Visual Studio,
// you will not be able to authorize a new bankIO application during the OAuth flow. You can workaround
// this by loading your extension in Power BI Desktop, and completing the OAuth flow there. 
// Once the application has been authorized for a given user, then the OAuth flow will work when 
// run in Visual Studio.

redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html";

client_id       = Json.Document ( Extension.Contents( "WebApp.json") ) [web][client_id];
token_uri       = Json.Document ( Extension.Contents( "WebApp.json") ) [web][token_uri];
authorize_uri   = Json.Document ( Extension.Contents( "WebApp.json") ) [web][authorize_uri];
logout_uri   = Json.Document ( Extension.Contents( "WebApp.json") ) [web][logout_uri];
organisation   = Json.Document ( Extension.Contents( "WebApp.json") ) [web][organisation];

windowWidth = 1200;
windowHeight = 1000;

//
// Exported functions
//
// These functions are exported to the M Engine (making them visible to end users), and associates 
// them with the specified Data Source Kind. The Data Source Kind is used when determining which 
// credentials to use during evaluation. Credential matching is done based on the function's parameters. 
// All data source functions associated to the same Data Source Kind must have a matching set of required 
// function parameters, including type, name, and the order in which they appear. 

// Data Source UI publishing description
BankIO.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { "bankIO Link", "bankIO Link" },
    LearnMoreUrl = "https://github.com/bank-io/bankIO-power-bi-data-connector",
    SourceImage = BankIO.Icons,
    SourceTypeImage = BankIO.Icons
];

DefaultRequestHeaders = [
    #"Accept" = "application/json"  // column name and values only
];

BaseUrl = "https://ob.bankio.ro/";

AmountType = type [
    amount = text,
    currency = text
];

PartyAccountType = type [
    iban = text
];

RemittanceInformationStructuredType = type [
    reference = text,
    referenceType = text,
    referenceIssuer = text
];

StandingOrderDetailsType = type [
    startDate = date,
    frequency = text,
    endDate = date,
    executionRule = text,
    withinAMonthFlag = Logical.Type,
    monthsOfExecution = list,
    multiplicator = Int64.Type,
    dayOfExecution = text,
    limitAmount = AmountType
];

AdditionalInformationStructuredType = type [
    standingOrderDetails = StandingOrderDetailsType
];

BalanceType = type [
    balanceAmount = AmountType,
    balanceType = text,
    creditLimitIncluded = Logical.Type,
    lastChangeDateTime = nullable date,
    referenceDate = nullable date,
    lastCommittedTransaction = nullable text
];

SchemaTable = #table({"Entity", "SchemaTable"}, {
    {"Accounts", #table({"Name", "Type"}, {
        {"iban", type text},
        {"resourceId", type text},
        {"product", type nullable text},
        {"currency", type text},
        {"name", type nullable text},
        {"cashAccountType", type nullable text},
        {"originalObject", type record}
    })},    
    
    {"Balances", #table({"Name", "Type"}, {
        {"balanceType", type text},
        {"creditDebitIndicator", type nullable text},
        {"referenceDate", type date},
        {"balanceAmount", AmountType},
        {"originalObject", type record}
    })},

    {"Transactions", #table({"Name", "Type"}, {
        {"transactionId", type nullable text},
        {"endToEndId", type nullable text},
        {"mandateId", type nullable text},
        {"checkId", type nullable text},
        {"creditorId", type nullable text},
        {"currencyExchange", type nullable list},
        {"entryReference", type nullable text},
        {"ultimateCreditor", type nullable text},
        {"ultimateDebtor", type nullable text},
        {"remittanceInformationUnstructured", type nullable text},
        {"remittanceInformationUnstructuredArray", type nullable list},
        {"remittanceInformationStructured", RemittanceInformationStructuredType },
        {"remittanceInformationStructuredArray", type nullable list},
        {"bookingDate", type date},
        {"valueDate", type date},
        {"transactionAmount", AmountType},
        {"transactionStatus", type nullable text},
        {"creditorName", type nullable text},
        {"debtorName", type nullable text},
        {"creditorAgent", type nullable text},
        {"debtorAgent", type nullable text},
        {"creditorAccount", PartyAccountType },
        {"debtorAccount", PartyAccountType },
        {"additionalInformation", type nullable text},
        {"purposeCode", type nullable text},
        {"bankTransactionCode", type nullable text},
        {"proprietaryBankTransactionCode", type nullable text},
        {"balanceAfterTransaction", BalanceType},
        {"originalObject", type record}
    })}
});
        
GetSchemaForEntity = (entity as text) as table => try SchemaTable{[Entity=entity]}[SchemaTable] otherwise error "Couldn't find entity: '" & entity &"'";

// Navigation entry point
[DataSource.Kind="bankIO", Publish="BankIO.Publish"]
shared BankIO.Contents = Value.ReplaceType(Navigation, NavigationType);

NavigationType = type function (
        name as (type text meta [
            Documentation.FieldCaption = "Name",
            Documentation.FieldDescription = "ASPSP Connection name",
            Documentation.SampleValues = {"RBS Bank"}
        ])
        ) as table meta [                  
        Documentation.Name = "bankIO",
        Documentation.LongDescription = "Accesses objects available through the bankIO Link API.",
        Documentation.Examples = {[
            Description = "",
            Code = "",
            Result = ""
        ]}
    ];

 Navigation = (name as text) =>
    let
        objects = #table(
            {"Name",                "Key",                      "Data",                     "ItemKind", "ItemName", "IsLeaf"},
            {
                {"bankIO",  "NavTableCoreResources",    NavTableCoreResources(),    "Folder",   "Folder",   false},
                {"PSD2",          "NavTablePSD2",           BankIO.NavTablePSD2(name),           "Folder",   "Folder",   false}
            }),
            NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf") 
    in
        NavTable;

NavTableCoreResources = () as table => 
    let
        objects = #table(
            {
                "Name",             "Key",                          "Data",                         "ItemKind", "ItemName", "IsLeaf"},{
//                 {"Consents", "BankIO.Consents",    BankIO.Consents(),    "Table",    "Table",    true},
            }),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;

shared BankIO.NavTablePSD2 = (optional name as text) =>
    let
        key = Extension.CurrentCredential()[access_token],
        seed = BaseUrl & "api/org/" & organisation & "/v1/accounts",
        schemaTable = GetSchemaForEntity("Accounts"),
        pagedResult = GetAllPagesByNextLink(seed, schemaTable, (mapData as record) as list => mapData[accounts]),
        accountsTable = BankIO.Accounts(pagedResult),
        balancesTable = BankIO.Balances(pagedResult),
        transactionsTable = BankIO.Transactions(pagedResult),
        accountsWithBalances = Table.NestedJoin(
            accountsTable, {"resourceId"},
            balancesTable, {"resourceId"},
            "accountBalances",
            JoinKind.LeftOuter),
        accountsWithTransactions = Table.NestedJoin(
            accountsWithBalances, { "resourceId" },
            transactionsTable, {"resourceId" },
            "accountTransactions",
            JoinKind.LeftOuter),

        objects = #table(
            {
                "Name",             "Key",                          "Data",                         "ItemKind", "ItemName", "IsLeaf"},{
                {name & " Accounts", name & " BankIO.Accounts",    accountsWithTransactions,    "Table",    "Table",    true},
                {name & " Balances",         name & " BankIO.Balances",           balancesTable,           "Table",    "Table",    true},
                {name & " Transactions",       name & " BankIO.Transactions",         transactionsTable,         "Table",    "Table",    true}
            }),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;

AggregateEntities = (accounts as table, map as function) as table =>
    let
        withData = Table.AddColumn(accounts, "AggregateData", each map([resourceId]), type table),
        aggregateData = Table.Column(withData, "AggregateData"),
        pagesList = Table.Combine(aggregateData)
    in
        pagesList;

shared BankIO.Accounts = (accounts as table) as table =>
    let
        withKey = Table.AddKey(accounts, {"resourceId"}, true)
    in
        withKey;

shared BankIO.Balances = (accounts as table) as table =>
    let
        balances = AggregateEntities(accounts, BankIO.GetAccountBalances)
    in
        balances;

shared BankIO.Transactions = (accounts as table) as table =>
    let
        transactions = AggregateEntities(accounts, BankIO.GetAccountTransactions)
    in
        transactions;
        
shared BankIO.GetAccountBalances = (resourceId as text) as table =>
    let
        access_token = Extension.CurrentCredential()[access_token],
        seed = BaseUrl & "api/org/" & organisation & "/v1/accounts/" & resourceId & "/balances",

        schemaTable = GetSchemaForEntity("Balances"),

        result = GetAllPagesByNextLink(seed, schemaTable, (mapData as record) as list => mapData[balances]),
        withAmountExpanded = Table.ExpandRecordColumn(result, "balanceAmount", { "currency", "amount" } ),
        withAccountResourceId = Table.AddColumn(withAmountExpanded, "resourceId", each resourceId, type text)
    in
        withAccountResourceId;


shared BankIO.GetAccountTransactions = (resourceId as text) as table =>
    let
        access_token = Extension.CurrentCredential()[access_token],
        seed = BaseUrl & "api/org/" & organisation & "/v1/accounts/" & resourceId & "/transactions",

        schemaTable = GetSchemaForEntity("Transactions"),

        result = GetAllPagesByNextLink(seed, schemaTable, (mapData as record) as list => mapData[transactions]),
        withAmountExpanded = Table.ExpandRecordColumn(result, "transactionAmount", { "currency", "amount" } ),
        withCreditorAccountExpanded = Table.ExpandRecordColumn(withAmountExpanded, "creditorAccount", { "iban" }, { "creditorIban" } ),
        withDebtorAccountExpanded = Table.ExpandRecordColumn(withCreditorAccountExpanded, "debtorAccount", { "iban" }, { "debtorIban" } ),
        
        withAccountResourceId = Table.AddColumn(withAmountExpanded, "resourceId", each resourceId, type text)
    in
        withAccountResourceId;

BankIO.Feed = (url as text, optional schema as table) as table => GetAllPagesByNextLink(url, schema);

GetPage = (url as text, optional schema as table, optional map as function) as table =>
    let
        response = Web.Contents(url, [ Headers = DefaultRequestHeaders ]),        
        body = Json.Document(response),
        nextLink = GetNextLink(body),
        mapFunction = if (map <> null) then map else (mapData as record) as list => mapData,
        data = Table.FromRecords(mapFunction(body), schema[Name], MissingField.UseNull),
//         data = Table.FromRecords(mapFunction(body)),
        // enforce the schema
        withSchema = if (schema <> null) then SchemaTransformTable(data, schema) else data
    in
        data meta [NextLink = nextLink];

// Read all pages of data.
// After every page, we check the "NextLink" record on the metadata of the previous request.
// Table.GenerateByPage will keep asking for more pages until we return null.
GetAllPagesByNextLink = (url as text, optional schema as table, optional map as function) as table =>
    Table.GenerateByPage((previous) => 
        let
            // if previous is null, then this is our first page of data
            nextLink = if (previous = null) then url else Value.Metadata(previous)[NextLink]?,
            // if NextLink was set to null by the previous call, we know we have no more data
            page = if (nextLink <> null) then GetPage(nextLink, schema, map) else null
        in
            page
    );

// In this implementation, 'response' will be the parsed body of the response after the call to Json.Document.
// We look for the '@odata.nextLink' field and simply return null if it doesn't exist.
GetNextLink = (response) as nullable text => Record.FieldOrDefault(response, "@odata.nextLink");

//
// Common functions
//


// The getNextPage function takes a single argument and is expected to return a nullable table
Table.GenerateByPage = (getNextPage as function) as table =>
    let        
        listOfPages = List.Generate(
            () => getNextPage(null),            // get the first page of data
            (lastPage) => lastPage <> null,     // stop when the function returns null
            (lastPage) => getNextPage(lastPage) // pass the previous page to the next function call
        ),
        // concatenate the pages together
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        // if we didn't get back any pages of data, return an empty table
        // otherwise set the table type based on the columns of the first page
        if (firstRow = null) then
            Table.FromRows({})
        else        
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );

//
// Schema functions
//

EnforceSchema.Strict = 1;               // Add any missing columns, remove extra columns, set table type
EnforceSchema.IgnoreExtraColumns = 2;   // Add missing columns, do not remove extra columns
EnforceSchema.IgnoreMissingColumns = 3; // Do not add or remove columns

SchemaTransformTable = (table as table, schema as table, optional enforceSchema as number) as table =>
    let
        // Default to EnforceSchema.Strict
        _enforceSchema = if (enforceSchema <> null) then enforceSchema else EnforceSchema.Strict,

        // Applies type transforms to a given table
        EnforceTypes = (table as table, schema as table) as table =>
            let
                map = (t) => if Type.Is(t, type list) or Type.Is(t, type record) or t = type any then null else t,
                mapped = Table.TransformColumns(schema, {"Type", map}),
                omitted = Table.SelectRows(mapped, each [Type] <> null),
                existingColumns = Table.ColumnNames(table),
                removeMissing = Table.SelectRows(omitted, each List.Contains(existingColumns, [Name])),
                primativeTransforms = Table.ToRows(removeMissing),
                changedPrimatives = Table.TransformColumnTypes(table, primativeTransforms)
            in
                changedPrimatives,

        // Returns the table type for a given schema
        SchemaToTableType = (schema as table) as type =>
            let
                toList = List.Transform(schema[Type], (t) => [Type=t, Optional=false]),
                toRecord = Record.FromList(toList, schema[Name]),
                toType = Type.ForRecord(toRecord, false)
            in
                type table (toType),

        // Determine if we have extra/missing columns.
        // The enforceSchema parameter determines what we do about them.
        schemaNames = schema[Name],
        foundNames = Table.ColumnNames(table),
        addNames = List.RemoveItems(schemaNames, foundNames),
        extraNames = List.RemoveItems(foundNames, schemaNames),
        tmp = Text.NewGuid(),
        added = Table.AddColumn(table, tmp, each []),
        expanded = Table.ExpandRecordColumn(added, tmp, addNames),
        result = if List.IsEmpty(addNames) then table else expanded,
        fullList =
            if (_enforceSchema = EnforceSchema.Strict) then
                schemaNames
            else if (_enforceSchema = EnforceSchema.IgnoreMissingColumns) then
                foundNames
            else
                schemaNames & extraNames,

        // Select the final list of columns.
        // These will be ordered according to the schema table.
        reordered = Table.SelectColumns(result, fullList, MissingField.Ignore),
        enforcedTypes = EnforceTypes(reordered, schema),
        withType = if (_enforceSchema = EnforceSchema.Strict) then Value.ReplaceType(enforcedTypes, SchemaToTableType(schema)) else enforcedTypes
    in
        withType;


//
// Data Source definition
//
bankIO = [
//     TestConnection = (dataSourcePath) => {"BankIO.Contents", dataSourcePath},
    Authentication = [
        OAuth = [
            StartLogin = StartLogin,
            FinishLogin = FinishLogin,
            Refresh=Refresh,
            Logout=Logout
//             Label = Extension.LoadString("AuthenticationLabel")
        ]
    ]
];

BankIO.Icons = [
    Icon16 = { Extension.Contents("icon-16x16.png"), Extension.Contents("icon-20x20.png"), Extension.Contents("icon-24x24.png"), Extension.Contents("icon-32x32.png") },
    Icon32 = { Extension.Contents("icon-32x32.png"), Extension.Contents("icon-40x40.png"), Extension.Contents("icon-48x48.png"), Extension.Contents("icon-64x64.png") }
];

BankIO.PagedTable = (url as text) => Table.GenerateByPage((previous) =>
    let
        // If we have a previous page, get its Next link from metadata on the page.
        next = if (previous <> null) then Value.Metadata(previous)[Next] else null,
        // If we have a next link, use it, otherwise use the original URL that was passed in.
        urlToUse = if (next <> null) then next else url,
        // If we have a previous page, but don't have a next link, then we're done paging.
        // Otherwise retrieve the next page.
        current = if (previous <> null and next = null) then null else BankIO.Contents(urlToUse),
        // If we got data back from the current page, get the link for the next page
        link = if (current <> null) then Value.Metadata(current)[Next] else null
    in
        current meta [Next=link]);

//
// OAuth2 flow definition
//

StartLogin = (resourceUrl, state, display) =>
    let
        AuthorizeUrl = authorize_uri & "?" & Uri.BuildQueryString([
           client_id = client_id,
           redirect_uri = redirect_uri])
    in
        [
            LoginUri = AuthorizeUrl,
            CallbackUri = redirect_uri,
            WindowHeight = windowHeight,
            WindowWidth = windowWidth,
            Context = null
        ];

FinishLogin = (context, callbackUri, state) =>
    let
        Parts = Uri.Parts(callbackUri)[Query]
    in
        TokenMethod(Parts[code]);

Refresh = (resourceUrl, refresh_token) => RefreshTokenMethod("refresh_token", "refresh_token", refresh_token);

Logout = (token) => logout_uri;

TokenMethod = (code) =>
    let
        Response = Web.Contents(token_uri, [
            Content = Text.ToBinary(Uri.BuildQueryString([
                client_id = client_id,
                code = code,
                grant_type="authorization_code",
                code_verifier="exampleCodeVerifier0123456789012345678901234567890",
                redirect_uri = redirect_uri])),
            Headers=[#"Content-type" = "application/x-www-form-urlencoded",#"Accept" = "application/json"]]),
        Parts = Json.Document(Response)
    in
        Parts;

// grantType:  Maps to the "grant_type" query parameter.
// tokenField: The name of the query parameter to pass in the code.
// code:       Is the actual code (authorization_code or refresh_token) to send to the service.
RefreshTokenMethod = (grantType, tokenField, code) =>
    let
        queryString = [
            client_id = client_id,
            grant_type = grantType,
            redirect_uri = redirect_uri
        ],
        queryWithCode = Record.AddField(queryString, tokenField, code),

        tokenResponse = Web.Contents(token_uri, [
            Content = Text.ToBinary(Uri.BuildQueryString(queryWithCode)),
            Headers = [
                #"Content-type" = "application/x-www-form-urlencoded",
                #"Accept" = "application/json"
            ],
            ManualStatusHandling = {400} 
        ]),
        body = Json.Document(tokenResponse),
        result = if (Record.HasFields(body, {"error", "error_description"})) then 
                    error Error.Record(body[error], body[error_description], body)
                 else
                    body
    in
        result;


//
// Common code
//

BankIO.GetPagedData = (query, result) =>
    let
        response = Json.Document(Web.Contents(query)),
        newResult = List.Combine({result, response[data]}),
        nextQuery = try response[paging][next] otherwise null,
        testForError = try response
    in
        if testForError[HasError] then 
            {[has_error = testForError[HasError], error_value = try testForError[Value], error_reason = testForError[Error][Reason], error_message = testForError[Error][Message]]}
        else 
            if nextQuery <> null then 
                BankIO.GetPagedData(nextQuery, newResult)
            else
                newResult;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////                                                                            ////////////
////////////The following functions are a set of helper functions provided by Microsoft ////////////
////////////                                                                           ////////////
///////////////////////////////////////////////////////////////////////////////////////////////////


//// Table Navigation function provided by Microsoft. 
//// Get the full example on how to create a Navigation Table from Microsoft here > https://bankIO.com/Microsoft/DataConnectors/tree/master/samples/NavigationTable

Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

//// Function to check if the text string exists or if it should grab the next string
//// Get the full example on why this function was created from Microsoft here > https://bankIO.com/Microsoft/DataConnectors/blob/fe8cb91f694e476bd70c10b9295a815d7bfc42d7/samples/MyGraph/README.md

Value.IfNull = (a, b) => if a <> null then a else b;

//// Function to concatenate all the scopes and create a string for them
//// Get the full example on why this function was created from Microsoft here > https://bankIO.com/Microsoft/DataConnectors/blob/fe8cb91f694e476bd70c10b9295a815d7bfc42d7/samples/MyGraph/README.md
GetScopeString = (scopes as list, optional scopePrefix as text) as text =>
    let
        prefix = Value.IfNull(scopePrefix, ""),
        addPrefix = List.Transform(scopes, each prefix & _),
        asText = Text.Combine(addPrefix, " ")
    in
        asText;

//// Helper function to create sample tables
SampleTable = ( OutputTable as table) as text =>

let
    TableToTransform = Table.FirstN(OutputTable,2),        
    Headers = Text.Combine(List.Transform(Table.ColumnNames(TableToTransform), each """"""&Text.From(_)&""""""), ","),
    Data = Text.Combine(List.Transform(List.Transform(Table.ToRows(TableToTransform), each Text.Combine(List.Transform(_, (_)=> """"""&Text.From(_)&""""""), ",")), each "{"&_&"}"), ","),
    TableFormat = "#table({"&Headers&"},{"&Data&"})"
in
    TableFormat;