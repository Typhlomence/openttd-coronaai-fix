class CoronaAIFix extends AIInfo {
    function GetAuthor()      { return "Libor Vilimek, Typhlomence"; }
    function GetName()        { return "CoronaAI Fix"; }
    function GetDescription() { return "A light modification of Corona AI that fixes some issues. This AI will attempt to build bus services in all cities on the map. You may need to increase the number of road vehicles allowed (e.g. 2500 on a 1024x1024 map). Originally by Libor Vilimek."; }
    function GetVersion()     { return 3; }
    function GetDate()        { return "2024-06-16"; }
    function CreateInstance() { return "CoronaAIFix"; }
    function GetShortName()   { return "COVF"; }
    function GetAPIVersion()  { return "1.9"; }

    // Let's add some parameters!
    function GetSettings() {
        AddSetting({name = "yearGap",
			description = "Number of years/economy periods to wait between checks of town infrastructure",
			easy_value = 1,
			medium_value = 1,
			hard_value = 1,
			custom_value = 1,
			min_value = 1,
			max_value = 100,
            flags = 0});

        AddSetting({name = "yearGapUnprofitable",
			description = "Number of years/economy periods to wait before rebuilding in an unprofitable town",
			easy_value = 5,
			medium_value = 5,
			hard_value = 5,
			custom_value = 5,
			min_value = 1,
			max_value = 100,
            flags = 0});

        AddSetting({name = "dayGap",
			description = "Number of (economy) days to pause after performing build actions",
			easy_value = 1,
			medium_value = 1,
			hard_value = 1,
			custom_value = 1,
			min_value = 1,
			max_value = 30,
            flags = 0});

        AddSetting({name = "vehicleCriteria",
			description = "What criteria to use when picking a vehicle",
			easy_value = 1,
			medium_value = 1,
			hard_value = 1,
			custom_value = 1,
			min_value = 1,
			max_value = 6,
			flags = 0});

		AddLabels("vehicleCriteria",
			{_1 = "Highest capacity", _2="Newest", _3="Fastest", _4="Most reliable", _5="Cheapest", _6="Random"});

        AddSetting({name = "secondaryColour",
			description = "Pick a random secondary colour when starting the company",
			easy_value = 0,
			medium_value = 0,
			hard_value = 0,
			custom_value = 0,
			flags = CONFIG_BOOLEAN});
    }
}

/* Tell the core we are an AI */
RegisterAI(CoronaAIFix());
