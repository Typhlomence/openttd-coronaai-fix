class CoronaAIFix extends AIInfo {
  function GetAuthor()      { return "Libor Vilimek, Typhlomence"; }
  function GetName()        { return "CoronaAI Fix"; }
  function GetDescription() { return "A light modification of Corona AI that fixes some issues. This AI will attempt to build bus services in all cities on the map. You may need to increase the number of road vehicles allowed (e.g. 2500 on a 1024x1024 map). Originally by Libor Vilimek."; }
  function GetVersion()     { return 2; }
  function GetDate()        { return "2024-05-03"; }
  function CreateInstance() { return "CoronaAIFix"; }
  function GetShortName()   { return "COVF"; }
  function GetAPIVersion()  { return "1.9"; }
}

/* Tell the core we are an AI */
RegisterAI(CoronaAIFix());
