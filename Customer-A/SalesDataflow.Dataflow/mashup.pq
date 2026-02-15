[DefaultOutputDestinationSettings = [DestinationDefinition = [Kind = "Reference", QueryName = "DefaultDestination", IsNewTarget = true], UpdateMethod = [Kind = "Replace"], DestinationTypeSettings = [Kind = "Table"]], StagingDefinition = [Kind = "FastCopy"]]
section Section1;
shared EnvironmentName = "DEV" meta [IsParameterQuery = true, IsParameterQueryRequired = true, Type = type text];
shared CustomerName = "A" meta [IsParameterQuery = true, IsParameterQueryRequired = true, Type = type text];
[BindToDefaultDestination = true]
shared SalesData = let
  Source = Table.FromRows(Json.Document(Binary.Decompress(Binary.FromText("i45W8nRR0lFyzM0vzStRitWJVjIEcg0NDMBsIyDbCMSOBQA=", BinaryEncoding.Base64), Compression.Deflate)), let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [Column1 = _t, Column2 = _t]),
  #"Added custom" = Table.AddColumn(Source, "EnvTag", each EnvironmentName),
  #"Added custom 1" = Table.AddColumn(#"Added custom", "CustTag", each CustomerName)
in
  #"Added custom 1";
shared DefaultDestination = Lakehouse.Contents([EnableFolding = false]){[workspaceId = "09426049-3a4b-4063-b35b-43928a03b21a"]}[Data]{[lakehouseId = "34963548-ee7e-42aa-a705-e36d06461251"]}[Data];
