﻿/**
 * CoronaAI Fix by Typhlomence, a bugfix version of CoronaAI that tries to preserve the general behaviour of the original while fixing some issues.
 * For details, refer to the readme.
 */

// Original preamble by Libor Vilimek:
/**
 * This is very simple AI that was written while I was ill due to having covid-19.
 * I spent only two partial days working on it, therefore it really is intended to be simple.
 * It will try to spread to all cities with buses alone.
 */

// Import the pathfinder to allow checking if there's an existing road connection between stations and depots.
import("pathfinder.road", "RoadPathFinder", 4);

/**
 * Constructor.
 */
class CoronaAIFix extends AIController {
    // Current town that the AI is working on.
    currentTownId = null;

    // Since the passenger ID cannot be assumed, this will store it when it's found later.
    passengerCargoId = -1;

    // List of towns to "spread" to. This counts down on each iteration and can be refilled later.
    townList = null;

    // Current best engine(s) available. Should usually only have one in the list.
    engines = null;

    // Array for data on all towns the company has successfully "spread" to.
    townInfoArray = [];

    // Pathfinder for checking if stations and depots are connected.
    pathfinder = null;

    // The date to next iterate through the list of towns.
    nextDate = null;

    // Number of years to wait between runs through the town list.
    yearGap = AIController.GetSetting("yearGap");

    // Number of years to keep a record of a town having an unprofitable vehicle.
    yearGapUnprofitable = AIController.GetSetting("yearGapUnprofitable");

    // Array for towns which had an unprofitable vehicle at some point.
    unprofitableTownArray = [];

    // Whether we currently want to process the town list.
    processTowns = false;

    // How long to wait between performing build functions.
    dayGap = AIController.GetSetting("dayGap");

    // What criteria to use when choosing a vehicle.
    vehicleCriteria = AIController.GetSetting("vehicleCriteria");

    // The number of days in a "year", depending on whether we're using calendar or wallclock mode.
    daysInYear = null;

    constructor() {
        // Set the current road type as the default road type.
        AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
        this.townInfoArray = [];

        // Find the ID for the passenger cargo.
        local list = AICargoList();
        for (local i = list.Begin(); list.IsEnd() == false; i = list.Next()) {
            if (AICargo.HasCargoClass(i, AICargo.CC_PASSENGERS)) {
                this.passengerCargoId = i;
                break;
            }
        }

        // Add the pathfinder, and set it to only look at existing roads.
        this.pathfinder = RoadPathFinder();
        this.pathfinder.cost.no_existing_road = pathfinder.cost.max_cost
    }

    // Start running the AI.
    function Start();
}

/**
 * All the logic starts here.
 */
function CoronaAIFix::Start() {

    // At present, there isn't a way to use the API to otherwise determine if we're using calendar or wallclock mode.
    // Hence, we check the game settings, and assume regular (calendar) time if we can't find it.
    if (AIGameSettings.IsValid("timekeeping_units")) {
        if (AIGameSettings.GetValue("timekeeping_units") == 1) {
            AILog.Info("Game is using wallclock timekeeping. A year is 360 days");
            this.daysInYear = 360;
        } else {
            AILog.Info("Game is using calendar timekeeping. A year is 365 days");
            this.daysInYear = 365;
        }
    } else {
        AILog.Info("Could not find the timekeeping setting - assuming a year is a standard 365 days");
        this.daysInYear = 365;
    }

    // Set the name if there isn't a name for the company already.
    // Borrowed some code from AAAHogEx to number the names after the first instance of CoronaAI.
    if (AICompany.GetName(AICompany.COMPANY_SELF) == "Unnamed") {
        local i = 0;
	    if(!AICompany.SetName("CoronaAI")) {
			i = 2;
			while(!AICompany.SetName("CoronaAI #" + i)) {
				i = i + 1;
				if(i > 255) break;
			}
		}

        // Also set the secondary colour for the company. It is allowed to be the same as the first.
        AICompany.SetSecondaryLiveryColour(AICompany.LS_DEFAULT, AIBase.RandRange(16));
    }

    // Take out the maximum loan if the company already has a loan but it's not at the max.
    // This is to avoid re-taking a loan and getting interest when it was repaid before.
    if (AICompany.GetLoanAmount() > 0) {
        AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
    }

    // Turn off autorenew as it causes old vehicles to never be sold if vehicles never expire.
    AICompany.SetAutoRenewStatus(false);

    // Check if there's existing infrastructure first, if there's no saved data.
    if (this.townInfoArray.len() == 0) {
        this.CheckTowns();
    }

    // Continuously while the AI is active...
    while (true) {

        // Note when we start this for the correct delay.
        local startTime = AIDate.GetCurrentDate();

        // Update the chosen bus to build.
        this.FindBestEngine();

        // Don't try building anything if there isn't a good buffer of money.
        // Also, don't try to build anything if no bus could be found to buy.
        if (AICompany.GetBankBalance(AICompany.COMPANY_SELF) > (AICompany.GetMaxLoanAmount() / 10) && this.engines.Count() > 0) {
            this.SelectTown();
            if (this.currentTownId != null) {
                BuildStationsAndBuses();
            }
        }

        // Other maintenance tasks.
        this.SellUnprofitables();
        this.HandleOldVehicles();
        this.HandleOldTowns();
        this.DeleteUnusedCrap();
        this.RestartStoppedVehicles();

        // If the company has a lot of money (at least the whole loan + 20%), repay the loan.
        if (AICompany.GetBankBalance(AICompany.COMPANY_SELF) > (AICompany.GetMaxLoanAmount() * 1.25) && AICompany.GetLoanAmount() > 0) {
            AILog.Info("Plenty of money - repaying loan");
            AICompany.SetLoanAmount(0);

        // Otherwise if the company doesn't have a lot of money (less than 5% of the max loan amount), try getting a loan if the loan isn't at max already.
        } else if (AICompany.GetBankBalance(AICompany.COMPANY_SELF) < (AICompany.GetMaxLoanAmount() / 20) && AICompany.GetLoanAmount() != AICompany.GetMaxLoanAmount()) {
            AILog.Info("Running out of money - getting out a loan");
            AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
        }

        // Sleep until the correct number of days has passed.
        while (startTime + this.dayGap > AIDate.GetCurrentDate()) {
            this.Sleep(1)
        }
    }
}

/**
 * For randomising a list.
 */
function CoronaAIFix::RandomValue(id) {
    return AIBase.Rand();
}

/**
 * Find best bus for passengers available.
 */
function CoronaAIFix::FindBestEngine() {
    local engines = AIEngineList(AIVehicle.VT_ROAD);

    // Only keep vehicles that can operate on the default road type (chosen as the current road type).
    engines.Valuate(AIEngine.CanRunOnRoad, AIRoad.GetCurrentRoadType())
    engines.KeepValue(1);

    // Only keep vehicles that can carry passengers.
    engines.Valuate(AIEngine.GetCargoType)
    engines.KeepValue(this.passengerCargoId);

    // Pick the vehicle depending on the criteria from the parameters.
    // For each of the normal ones, sort by capacity first, unless we're already sorting by capacity, in which case sort by newest first.
    // i.e. if more than one vehicle has the same introduction date, etc. pick the highest capacity one out of those. For highest capacity, pick the newest if multiple have the same.
    switch(this.vehicleCriteria) {
        // 2 - Newest
        case 2:
            engines.Valuate(AIEngine.GetCapacity);
            engines.Sort(AIList.SORT_BY_VALUE, false);
            engines.Valuate(AIEngine.GetDesignDate);
            engines.Sort(AIList.SORT_BY_VALUE, false);
            break;
        // 3 - Fastest
        case 3:
            engines.Valuate(AIEngine.GetCapacity);
            engines.Sort(AIList.SORT_BY_VALUE, false);
            engines.Valuate(AIEngine.GetMaxSpeed);
            engines.Sort(AIList.SORT_BY_VALUE, false);
            break;
        // 4 - Most reliable
        case 4:
            engines.Valuate(AIEngine.GetCapacity);
            engines.Sort(AIList.SORT_BY_VALUE, false);
            engines.Valuate(AIEngine.GetReliability);
            engines.Sort(AIList.SORT_BY_VALUE, false);
            break;
        // 5 - Cheapest
        case 5:
            engines.Valuate(AIEngine.GetCapacity);
            engines.Sort(AIList.SORT_BY_VALUE, false);
            engines.Valuate(AIEngine.GetPrice);
            engines.Sort(AIList.SORT_BY_VALUE, true);
            break;
        // 6 - Random
        case 6:
            engines.Valuate(this.RandomValue);
            engines.Sort(AIList.SORT_BY_VALUE, false);
            break;
        // 1 - Highest capacity (default)
        default:
            engines.Valuate(AIEngine.GetDesignDate);
            engines.Sort(AIList.SORT_BY_VALUE, false);
            engines.Valuate(AIEngine.GetCapacity);
            engines.Sort(AIList.SORT_BY_VALUE, false);
            break;
    }

    // Keep the one that is at the top of the list.
    engines.KeepTop(1);

    // Ensure a bus was actually found. If not, return an empty list.
    // (We check for the road vehicle type again since if there's no buses, it might pick a vehicle of a different type.)
    if (engines.Count() < 1 || AIEngine.GetVehicleType(engines.Begin()) != AIVehicle.VT_ROAD || AIEngine.GetCapacity(engines.Begin()) < 1) {
        this.engines = AIList();
    } else {
        this.engines = engines;
    }
}

/**
 * Initialize towns or select next town.
 * Normally, this only runs if there is no next scheduled date, or it's past that date. Passing true as an argument will have it ignore dates.
 */
function CoronaAIFix::SelectTown(ignoreDates = false) {
    // Allow the town list to be regenerated if it's the specified number of gap years since it was last generated, or dates are being ignored.
    if ((!this.processTowns && (this.nextDate == null || this.nextDate < AIDate.GetCurrentDate())) || ignoreDates) {
        this.processTowns = true;
    }

    // If we want to process the town list...
    if (this.processTowns) {
        if (this.townList == null) {
            AILog.Info("Generating town list");
            local townList = AITownList();
            townList.Valuate(AITown.GetPopulation);
            townList.Sort(AIList.SORT_BY_VALUE, false);
            this.townList = townList;

            // If dates are not being ignored...
            if (!ignoreDates) {
                // Set the next date to be the specified number of gap years after the current iteration.
                // If there wasn't a last date, set it to the current date.
                if (this.nextDate == null) {
                    this.nextDate = this.AddYears(AIDate.GetCurrentDate(), this.yearGap);

                // Otherwise, add the gap years to the current "next" date.
                } else {
                    this.nextDate = this.AddYears(this.nextDate, this.yearGap);

                    // Keep adding until we get a future date. This is to account for if an iteration took longer than the specified number of gap years.
                    if (this.nextDate < AIDate.GetCurrentDate()) {
                        AILog.Info("We missed a scheduled date. Skipping ahead until we get a date in the future");
                        local skips = 0;
                        while (this.nextDate < AIDate.GetCurrentDate()) {
                            this.nextDate = this.AddYears(this.nextDate, this.yearGap);
                            skips++;
                        }
                        AILog.Info("Skipped " + skips + " date(s)");
                    }
                }
            }

            // Only show the message below if there's an actual next date.
            if (this.nextDate != null) {
                AILog.Info("Next scheduled date is " + AIDate.GetYear(this.nextDate) + "-" + AIDate.GetMonth(this.nextDate) + "-" + AIDate.GetDayOfMonth(this.nextDate));
            }
        }

        // If reaching the end of the list, set the current town and list as null.
        if (this.townList.Count() == 0) {
            this.currentTownId = null;

            // Only show the message below if there's an actual next date.
            if (this.nextDate != null) {
                AILog.Info("Reached end of town list, waiting up to " + this.yearGap + " year(s) until " + AIDate.GetYear(this.nextDate) + "-" + AIDate.GetMonth(this.nextDate) + "-" + AIDate.GetDayOfMonth(this.nextDate) + " to regenerate");
            }
            this.townList = null;
            this.processTowns = false;

        // Otherwise, set the current town as the one at the top of the list.
        } else {
            this.currentTownId = this.townList.Begin();
            AILog.Info("Number of towns remaining: " + this.townList.Count())
            this.townList.RemoveTop(1);
        }
    }
}

/**
 * Core functionality - This will build the stations and buses.
 */
function CoronaAIFix::BuildStationsAndBuses() {
    AILog.Info("City name: " + AITown.GetName(this.currentTownId));

    // Get any existing town information, to skip towns that already have stations, depots and buses.
    local existingInfo = this.GetTownInfo(this.currentTownId);
    if (existingInfo == null) {

        // Check if the town hasn't had an unprofitable vehicle within the specified period.
        local unprofitableInfo = this.GetUnprofitableTownInfo(this.currentTownId);
        if (unprofitableInfo != null) {
            if (this.AddYears(unprofitableInfo.date, this.yearGapUnprofitable) < AIDate.GetCurrentDate()) {
                AILog.Info("Since it's been over " + this.yearGapUnprofitable + " year(s), can now try building at " + AITown.GetName(unprofitableInfo.townId) + " again");
                if (DeleteUnprofitableTownInfo(unprofitableInfo.townId)) {
                    AILog.Info("Deleted unprofitability information for "  + AITown.GetName(unprofitableInfo.townId));
                }
            } else {
                AILog.Info("This town has no infrastructure, but an unprofitable vehicle was sold here within the last " + this.yearGapUnprofitable + " year(s)");
                AILog.Info("Skipping to the next town");
                return;
            }
        }

        AILog.Info("This town has no information yet");
        AILog.Info("Will attempt to build here");
    } else {
        AILog.Info("This town is already serviced");
        AILog.Info("Skipping to the next town");
        return;
    }

    local townCenter = AITown.GetLocation(this.currentTownId);
    local list = AITileList();

    // Check an 16x16 area around the city center.
    list.AddRectangle(townCenter - AIMap.GetTileIndex(8, 8), townCenter + AIMap.GetTileIndex(8, 8));

    // Find only road tiles
    list.Valuate(AIRoad.IsRoadTile);
    list.RemoveValue(0);

    // Check only for tiles that are in the current town's local authority radius.
    // Since small towns may be enroached by large ones, the latter's roads may enter the search radius.
    list.Valuate(AITile.IsWithinTownInfluence, this.currentTownId);
    list.RemoveValue(0);

    // Find the best place for a station (that accepts most humans).
    list.Valuate(AITile.GetCargoAcceptance, this.passengerCargoId, 1, 1, 3);
    list.RemoveBelowValue(10);
    list.Sort(AIList.SORT_BY_VALUE, false);

    // Attempt to build the first station.
    local firstStation = null;
    local tile = list.Begin();
    while (list.IsEnd() == false && firstStation == null) {
        this.BuildRoadDrivethroughStation(tile);

        // Check if the current tile actually has a station that the company owns on it after attempting to build.
        // IsStationTile is used over IsRoadStationTile since the latter might not work if the road type differs from the default.
        if (AITile.IsStationTile(tile) && AICompany.IsMine(AITile.GetOwner(tile))) {
            AILog.Info("First station built successfully");
            firstStation = tile;
        }

        tile = list.Next();
    }

    // Abort if the first station couldn't be built.
    if (firstStation == null) {
        AILog.Info("First station failed, aborting");
        return;
    }

    // Set the starting distance for the second station from the first.
    local distanceOfStations = 7;
    local secondStation = null;

    // Attempt to build the second station.
    while (distanceOfStations > 2 && secondStation == null) {
        local filteredList = AIList();
        filteredList.AddList(list);

        // Allow only tiles that are far enough away from the first station.
        filteredList.Valuate(AIMap.DistanceManhattan, firstStation);
        filteredList.KeepAboveValue(distanceOfStations);

        // Again, check for the cargo acceptance.
        filteredList.Valuate(AITile.GetCargoAcceptance, this.passengerCargoId, 1, 1, 3);
        filteredList.RemoveBelowValue(10);
        filteredList.Sort(AIList.SORT_BY_VALUE, false);

        if (filteredList.Count() > 0) {
            local tile = filteredList.Begin();

            // Make sure that there's a road connection between the first and second station tiles.
            while (filteredList.IsEnd() == false && secondStation == null && this.CheckRoadConnection(firstStation, tile) != null) {
                this.BuildRoadDrivethroughStation(tile);

                // Again, properly check that this company built a station.
                if (AITile.IsStationTile(tile) && AICompany.IsMine(AITile.GetOwner(tile))) {
                    AILog.Info("Second station built successfully");
                    secondStation = tile;
                }

                tile = filteredList.Next();
            }
        }

        // If a station wasn't built, try again a bit closer.
        if (secondStation == null) {
            distanceOfStations = distanceOfStations - 1;
        }
    }

    // Abort if the second station couldn't be built.
    if (secondStation == null) {
        AILog.Info("Second station failed, aborting");
        AIRoad.RemoveRoadStation(firstStation);
        return;
    }

    // Find a place to build a depot. It uses the same radius as the stations.
    list = AITileList();
    list.AddRectangle(townCenter - AIMap.GetTileIndex(8, 8), townCenter + AIMap.GetTileIndex(8, 8));
    list.Valuate(AIRoad.IsRoadTile);
    list.RemoveValue(0);
    // Check only for tiles that are in the current town's local authority radius.
    list.Valuate(AITile.IsWithinTownInfluence, this.currentTownId);
    list.RemoveValue(0);
    list.Valuate(AITile.GetSlope);
    list.KeepValue(AITile.SLOPE_FLAT);
    list.Valuate(AIMap.DistanceManhattan, AITown.GetLocation(this.currentTownId));
    list.Sort(AIList.SORT_BY_VALUE, true);

    // Attempt to build a depot.
    tile = list.Begin();
    local depotTile = null;
    local isConnected = false;
    while (list.IsEnd() == false && isConnected == false) {

        // See if there's a tile adjacent to the current road tile that a depot can be built on.
        for (local i = 0; i < 4; i++) {
            if (i == 0) {
                depotTile = tile + AIMap.GetTileIndex(0, 1);
            }
            if (i == 1) {
                depotTile = tile + AIMap.GetTileIndex(1, 0);
            }
            if (i == 2) {
                depotTile = tile + AIMap.GetTileIndex(0, -1);
            }
            if (i == 3) {
                depotTile = tile + AIMap.GetTileIndex(-1, 0);
            }

            // Like with the second station, check that there's a road connection between the depot's connection tile and the first station tile.
            if (AITile.GetSlope(depotTile) == AITile.SLOPE_FLAT && AITile.IsBuildable(depotTile) && this.CheckRoadConnection(firstStation, tile) != null) {
                AIRoad.BuildRoadDepot(depotTile, tile);
                AIRoad.BuildRoad(depotTile, tile);
                AILog.Info("Attempting to build depot at: " + AIMap.GetTileX(depotTile) + ":" + AIMap.GetTileY(depotTile));

                // Like with the stations, ensure that the depot on the tile also belongs to this company.
                if (AIRoad.AreRoadTilesConnected(tile, depotTile) && AICompany.IsMine(AITile.GetOwner(depotTile))) {
                    AILog.Info("Depot built and connected to road successfully");
                    isConnected = true;
                    break;
                } else {
                    // Demolish the depot if it couldn't be connected to the road.
                    AITile.DemolishTile(depotTile);
                    depotTile = null;
                }
            } else {
                depotTile = null;
            }
        }
        tile = list.Next();
    }

    // Abort if the depot couldn't be built.
    if (depotTile == null) {
        AILog.Info("Depot failed, aborting");
        AIRoad.RemoveRoadStation(firstStation);
        AIRoad.RemoveRoadStation(secondStation);
        return;
    }


    // Buy our first bus in the depot that was just built.
    local bus = AIVehicle.BuildVehicle(depotTile, this.engines.Begin());

    // Check that a bus was bought successfully. If not, abort the attempt to build in this town.
    if (AIVehicle.IsValidVehicle(bus)) {
        AIOrder.AppendOrder(bus, firstStation, AIOrder.OF_NONE);
        AIOrder.AppendOrder(bus, secondStation, AIOrder.OF_NONE);
        AIVehicle.StartStopVehicle(bus);
        AILog.Info("Vehicle bought successfully");
    } else {
        AILog.Info("Failed to buy a vehicle, aborting");
        AIRoad.RemoveRoadStation(firstStation);
        AIRoad.RemoveRoadStation(secondStation);
        AITile.DemolishTile(depotTile);
        return;
    }

    // Store information about all the stations, town, etc.
    local townInfo = {
        bus = bus,
        firstStation = firstStation,
        secondStation = secondStation,
        depotTile = depotTile,
        lastChange = AIDate.GetCurrentDate(),
        townId = this.currentTownId
    };
    this.townInfoArray.append(townInfo);

    AILog.Info("Service successfully built in this town");
}

/**
 * Function for building a station on a specific tile. Tries both orientations.
 */
function CoronaAIFix::BuildRoadDrivethroughStation(tile) {
    AILog.Info("Attempting to build station at: " + AIMap.GetTileX(tile) + ":" + AIMap.GetTileY(tile));
    AIRoad.BuildDriveThroughRoadStation(tile, tile + AIMap.GetTileIndex(0, 1), AIRoad.ROADVEHTYPE_BUS, AIBaseStation.STATION_NEW);
    AIRoad.BuildDriveThroughRoadStation(tile, tile + AIMap.GetTileIndex(1, 0), AIRoad.ROADVEHTYPE_BUS, AIBaseStation.STATION_NEW);
}

/**
 * If vehicle is highly unprofitable - just sell it.
 */
function CoronaAIFix::SellUnprofitables() {
    local vehicles = AIVehicleList();
    local vehicle = vehicles.Begin();

    // Check if the company is low on money even with the maximum loan.
    local badFinances = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < (AICompany.GetMaxLoanAmount() / 20) && AICompany.GetLoanAmount() == AICompany.GetMaxLoanAmount();
    while (vehicles.IsEnd() == false) {

        // Check for vehicles that are making a loss of at least 90% of their running cost.
        // If the company is running out of money, sell the vehicle if it's unprofitable at all, rather than just highly unprofitable.
        if (((AIVehicle.GetProfitLastYear(vehicle) <= AIVehicle.GetRunningCost(vehicle) * -0.9) || (AIVehicle.GetProfitLastYear(vehicle) < 0 && badFinances)) && AIOrder.IsCurrentOrderPartOfOrderList(vehicle) && !AIVehicle.IsStoppedInDepot(vehicle)) {
            AILog.Info("Sending unprofitable vehicle to be sold: " + AIVehicle.GetName(vehicle))
            AIVehicle.SendVehicleToDepot(vehicle);
        }

        // If a vehicle is already in the depot...
        if (AIVehicle.IsStoppedInDepot(vehicle) && ((AIVehicle.GetProfitLastYear(vehicle) <= AIVehicle.GetRunningCost(vehicle) * -0.9) || (AIVehicle.GetProfitLastYear(vehicle) < 0 && badFinances))) {
            local depotLocation = AIVehicle.GetLocation(vehicle);
            AILog.Info("Selling unprofitable vehicle: " + AIVehicle.GetName(vehicle));
            AIVehicle.SellVehicle(vehicle);

            // Make a note that this town had an unprofitable vehicle.
            // First, get the town that the sold vehicle belonged to (by looking for which town owns the depot).
            local town = null;
            foreach (townInfo in this.townInfoArray) {
                if (townInfo.depotTile == depotLocation) {
                    town = townInfo.townId;
                    break;
                }
            }

            // If the town was found, check there's no entry in the unprofitable town array for it already.
            if (town != null) {
                if (this.GetUnprofitableTownInfo(town) == null) {
                    local townInfo = {
                        date = AIDate.GetCurrentDate(),
                        townId = town
                    };
                    this.unprofitableTownArray.append(townInfo);
                    AILog.Info("Making a note that " + AITown.GetName(town) + " had an unprofitable vehicle");
                }
            }
        }
        vehicle = vehicles.Next();
    }
}

/**
 * Add buses in old towns where we already have stations - if there is enough passengers.
 */
function CoronaAIFix::HandleOldTowns() {
    foreach (townInfo in this.townInfoArray) {
        // we only add bus once per year to avoid spamming it
        if (this.AddYears(townInfo.lastChange, 1) < AIDate.GetCurrentDate()) {
            local waitingPassengers1 = AIStation.GetCargoWaiting(AIStation.GetStationID(townInfo.firstStation), this.passengerCargoId);
            local waitingPassengers2 = AIStation.GetCargoWaiting(AIStation.GetStationID(townInfo.secondStation), this.passengerCargoId);

            // Check if there's a lot of passengers waiting (either more than 200 at each, or more than 600 combined).
            // Also check if the company is not low on money, with the same criteria as building new services in a town.
            if (((waitingPassengers1 > 200 && waitingPassengers2 > 200) || (waitingPassengers1 + waitingPassengers2 > 600)) && AICompany.GetBankBalance(AICompany.COMPANY_SELF) > (AICompany.GetMaxLoanAmount() / 10) && this.engines.Count() > 0) {
                local newBus = AIVehicle.BuildVehicle(townInfo.depotTile, this.engines.Begin());
                if (AIVehicle.IsValidVehicle(newBus)) {
                    AILog.Info("Cloning vehicle in " + AITown.GetName(townInfo.townId) + " as there is " + waitingPassengers1 + ":" + waitingPassengers2 + " passengers");
                    AIOrder.AppendOrder(newBus, townInfo.firstStation, AIOrder.OF_NONE);
                    AIOrder.AppendOrder(newBus, townInfo.secondStation, AIOrder.OF_NONE);
                    AIVehicle.StartStopVehicle(newBus);
                    townInfo.lastChange = AIDate.GetCurrentDate();
                }
            }
        }
    }
}

/**
 * If we find out that there is non-used infrastructure - remove it.
 */
// I like the name for this function, by the way. :P
function CoronaAIFix::DeleteUnusedCrap() {
    foreach (townInfo in this.townInfoArray) {
        local firstStationId = AIStation.GetStationID(townInfo.firstStation);
        local secondStationId = AIStation.GetStationID(townInfo.secondStation);
        local stationsNotUsed = AIVehicleList_Station(firstStationId).Count() == 0 && AIVehicleList_Station(secondStationId).Count() == 0;
        if (stationsNotUsed) {
            AILog.Info("Removing unused things from " + AITown.GetName(townInfo.townId));
            AILog.Info("Attempting to remove station at: " + AIMap.GetTileX(townInfo.firstStation) + ":" + AIMap.GetTileY(townInfo.firstStation));
            AIRoad.RemoveRoadStation(townInfo.firstStation);
            AILog.Info("Attempting to remove station at: " + AIMap.GetTileX(townInfo.secondStation) + ":" + AIMap.GetTileY(townInfo.secondStation));
            AIRoad.RemoveRoadStation(townInfo.secondStation);
            AILog.Info("Attempting to remove depot at: " + AIMap.GetTileX(townInfo.depotTile) + ":" + AIMap.GetTileY(townInfo.depotTile));
            AIRoad.RemoveRoadDepot(townInfo.depotTile);

            // Check if the items were actually removed yet (by checking if the tiles are not owned by the company). Sometimes this can fail if a vehicle is in the way.
            if (!AICompany.IsMine(AITile.GetOwner(townInfo.firstStation)) && !AICompany.IsMine(AITile.GetOwner(townInfo.secondStation)) && !AICompany.IsMine(AITile.GetOwner(townInfo.depotTile))) {
                AILog.Info("Successfully deleted infrastructure from this town")
                if (DeleteTownInfo(townInfo.townId)) {
                    AILog.Info("Deleted information for "  + AITown.GetName(townInfo.townId));
                }
            } else {
                AILog.Info("Some things were not removed yet - will retry later")
            }
        }
    }
}

/**
 * Selling vehicles that are too old.
 */
function CoronaAIFix::HandleOldVehicles() {
    // Don't do this if there's currently no valid vehicle to replace old vehicles with.
    // Probably should never happen if the company already has vehicles, but there's no harm in checking.
    if (this.engines.Count() < 1) {
        return;
    }

    local vehicles = AIVehicleList();
    local vehicle = vehicles.Begin();
    while (vehicles.IsEnd() == false) {

        // Only consider vehicles that are seven or more years older than their total age.
        // Vehicle age is *always* in calendar time, so always use 365 for the number of days.
        if (AIVehicle.GetAgeLeft(vehicle) <= -365 * 7 && AIOrder.IsCurrentOrderPartOfOrderList(vehicle) && !AIVehicle.IsStoppedInDepot(vehicle)) {
            AILog.Info("Sending old vehicle to be sold: " + AIVehicle.GetName(vehicle))
            AIVehicle.SendVehicleToDepot(vehicle);
        }

        // If a vehicle is already in the depot...
        if (AIVehicle.IsStoppedInDepot(vehicle) && AIVehicle.GetAgeLeft(vehicle) <= -365 * 7) {
            local depotLocation = AIVehicle.GetLocation(vehicle);
            local stationId = AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 0));
            local vehiclesInStation = AIVehicleList_Station(stationId);
            // If there is just one vehicle in city, we replace it with new one. Otherwise we just sell it.
            if (vehiclesInStation.Count() == 1) {
                local newBus = AIVehicle.BuildVehicle(depotLocation, this.engines.Begin());
                if (AIVehicle.IsValidVehicle(newBus)) {
                    AILog.Info("Only one vehicle servicing this route: " + AIVehicle.GetName(vehicle) + " - replacing");
                    AIOrder.ShareOrders(newBus, vehicle);
                    AIVehicle.StartStopVehicle(newBus);
                    AIVehicle.SellVehicle(vehicle);

                // If a new vehicle wasn't built, don't sell it; if it's a money problem, we can try again later.
                // Commented the message out so it isn't spammed...
                //} else {
                //    AILog.Info("Couldn't replace vehicle: " + AIVehicle.GetName(vehicle));
                }
            } else {
                AILog.Info("Selling " + AIVehicle.GetName(vehicle) + " - there are " + vehiclesInStation.Count() + " other vehicles");
                AIVehicle.SellVehicle(vehicle);
            }
        }
        vehicle = vehicles.Next();
    }
}

/**
 * Simple pathfinder function to find a path. The pathfinder is set in the constructor to only consider existing roads. Based on the AI tutorial on the OpenTTD wiki.
 */
function CoronaAIFix::CheckRoadConnection(startTile, endTile) {
    this.pathfinder.InitializePath([startTile], [endTile]);
    local path = false;
    while (path == false) {
      path = this.pathfinder.FindPath(100);
      AIController.Sleep(1);
    }
    return path;
}

/**
 * Gets the information for a town if it exists in the array of serviced towns.
 */
function CoronaAIFix::GetTownInfo(townId) {
    foreach (townInfo in this.townInfoArray) {
        if (townInfo.townId == townId) {
            return townInfo;
        }
    }
    return null;
}

/**
 * Deletes the information for a town if it exists in the array of serviced towns.
 */
function CoronaAIFix::DeleteTownInfo(townId) {
    for (local index = 0 ; index < this.townInfoArray.len() ; index = index + 1) {
        if (this.townInfoArray[index].townId == townId) {

            // Check that the town information was deleted properly.
            local temp = this.townInfoArray.remove(index);
            return (temp.townId == townId);
        }
    }
    return false;
}

/**
 * Runs on first load to see if there is any existing stations, depots and buses for this company in all towns.
 */
function CoronaAIFix::CheckTowns() {
    // Don't do anything if the company has no bus stations.
    if (AIStationList(AIStation.STATION_BUS_STOP).Count() < 1) {
        AILog.Info("This company has no bus stations yet");
        return;
    }

    AILog.Info("Checking all towns for existing company presence");
    this.SelectTown(true);
    while (this.currentTownId != null) {

        // Potential values to store - if there's a bus, two stations and a depot.
        local bus = null;
        local firstStation = null;
        local secondStation = null;
        local depotTile = null;

        // Start the check by looking in the same range of tiles as when building.
        AILog.Info("Checking " + AITown.GetName(this.currentTownId));
        local townCenter = AITown.GetLocation(this.currentTownId);
        local list = AITileList();
        list.AddRectangle(townCenter - AIMap.GetTileIndex(8, 8), townCenter + AIMap.GetTileIndex(8, 8));

        // Check only road tiles.
        list.Valuate(AIRoad.IsRoadTile);
        list.RemoveValue(0);

        // Check only for tiles that are in the current town's local authority radius.
        // Since small towns may be enroached by large ones, the latter's roads may enter the search radius.
        list.Valuate(AITile.IsWithinTownInfluence, this.currentTownId);
        list.RemoveValue(0);

        // Check to see if two bus stations already exist.
        local tile = list.Begin();
        local firstStation = null;
        local secondStation = null;
        while (list.IsEnd() == false && secondStation == null) {
            if (AITile.IsStationTile(tile) && AICompany.IsMine(AITile.GetOwner(tile))) {
                AILog.Info("Found existing station at: " + AIMap.GetTileX(tile) + ":" + AIMap.GetTileY(tile));
                // If we haven't found the first station yet, assume it's this one.
                if (firstStation == null) {
                    AILog.Info("Adding it as first station for this town");
                    firstStation = tile;
                // Otherwise, add it as the second station.
                } else {
                    AILog.Info("Adding it as second station for the town");
                    secondStation = tile;
                }
            }
            tile = list.Next();
        }

        // Check to see if a depot exists.
        list = AITileList();
        // Since we're looking for the depot first rather than the road tile, check one extra tile out.
        list.AddRectangle(townCenter - AIMap.GetTileIndex(9, 9), townCenter + AIMap.GetTileIndex(9, 9));
        tile = list.Begin();
        while (list.IsEnd() == false && depotTile == null) {
            // Check if the current tile already has one of this company's depots
            if (AIRoad.IsRoadDepotTile(tile) && AICompany.IsMine(AITile.GetOwner(tile))) {
                AILog.Info("Found existing depot at: " + AIMap.GetTileX(tile) + ":" + AIMap.GetTileY(tile));
                // Then check if it's connected to an adjacent tile
                for (local i = 0; i < 4; i++) {
                    local nextTile = null;
                    if (i == 0) {
                        nextTile = tile + AIMap.GetTileIndex(0, 1);
                    }
                    if (i == 1) {
                        nextTile = tile + AIMap.GetTileIndex(1, 0);
                    }
                    if (i == 2) {
                        nextTile = tile + AIMap.GetTileIndex(0, -1);
                    }
                    if (i == 3) {
                        nextTile = tile + AIMap.GetTileIndex(-1, 0);
                    }
                    if (AIRoad.AreRoadTilesConnected(nextTile, tile) && AITile.IsWithinTownInfluence(nextTile, this.currentTownId)) {
                        AILog.Info("It's connected to an adjacent tile, therefore adding it as the depot for this town");
                        depotTile = tile;
                        break;
                    }
                }
            }
            tile = list.Next();
        }

        // Check to see if a bus exists that goes to the found stations (if we found two).
        if (secondStation != null) {
            local firstStationVehicles = AIVehicleList_Station(AIStation.GetStationID(firstStation));
            local secondStationVehicles = AIVehicleList_Station(AIStation.GetStationID(secondStation));
            local vehicles = AIVehicleList();
            local vehicle = vehicles.Begin();
            while (vehicles.IsEnd() == false && bus == null) {
                // Check if it's a road vehicle
                if (AIVehicle.GetVehicleType(vehicle) == AIVehicle.VT_ROAD) {
                    if (firstStationVehicles.HasItem(vehicle) && secondStationVehicles.HasItem(vehicle)) {
                        AILog.Info(AIVehicle.GetName(vehicle) + " stops at both found stations, adding it as the bus for this town");
                        bus = vehicle;
                    }
                }
                vehicle = vehicles.Next();
            }
        }

        // Store information about all the stations, town, etc, but only if the facilities were found.
        // It's acceptable if a bus cannot be found since it might have been sold due to being unprofitable. In that case the stations will probably be deleted soon.
        if (firstStation != null && secondStation != null && depotTile != null) {
            AILog.Info("Adding information for this town");
            local townInfo = {
                bus = bus,
                firstStation = firstStation,
                secondStation = secondStation,
                depotTile = depotTile,
                lastChange = AIDate.GetCurrentDate(),
                townId = this.currentTownId
            };
            this.townInfoArray.append(townInfo);
        } else {
            AILog.Info("Couldn't find enough infrastructure for this town");
        }

        this.SelectTown(true);
    }
    AILog.Info("All towns checked");
}

/**
 * Restart vehicles that are stoppped but haven't been sold for being too old or too unprofitable.
 */
function CoronaAIFix::RestartStoppedVehicles() {
    local vehicles = AIVehicleList();
    local vehicle = vehicles.Begin();
    while (vehicles.IsEnd() == false) {
        if (AIVehicle.IsStoppedInDepot(vehicle)) {

            // To avoid starting vehicles that have only just arrived in the depot via the other functions, check that the vehicle isn't too old or too unprofitable first.
            local badFinances = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < (AICompany.GetMaxLoanAmount() / 20) && AICompany.GetLoanAmount() == AICompany.GetMaxLoanAmount();
            local notTooOld = AIVehicle.GetAgeLeft(vehicle) > -365 * 7;
            local notTooUnprofitable = (AIVehicle.GetProfitLastYear(vehicle) > AIVehicle.GetRunningCost(vehicle) * -0.9) || (AIVehicle.GetProfitLastYear(vehicle) >= 0 && badFinances);

            // Also check that it has orders (in case something went wrong with assigning them).
            if (notTooOld && notTooUnprofitable && AIOrder.GetOrderCount(vehicle) > 1) {
                AILog.Info("Found " + AIVehicle.GetName(vehicle) + " stopped in a depot that isn't too old or too unprofitable, restarting it");
                AIVehicle.StartStopVehicle(vehicle);
            }

            // If the vehicle is too old, but there's no valid replacement, send it out again too.
            if (!notTooOld && notTooUnprofitable && AIOrder.GetOrderCount(vehicle) > 1 && this.engines.Count() < 1) {
                AILog.Info("Found " + AIVehicle.GetName(vehicle) + " stopped in a depot that is too old but there's no replacement, restarting it");
                AIVehicle.StartStopVehicle(vehicle);
            }
        }
        vehicle = vehicles.Next();
    }
}

/**
 * Gets the information for a town if it exists in the array of unprofitable towns.
 */
function CoronaAIFix::GetUnprofitableTownInfo(townId) {
    foreach (unprofitableTownInfo in this.unprofitableTownArray) {
        if (unprofitableTownInfo.townId == townId) {
            return unprofitableTownInfo;
        }
    }
    return null;
}

/**
 * Deletes the information for a town if it exists in the array of unprofitable towns.
 */
function CoronaAIFix::DeleteUnprofitableTownInfo(townId) {
    for (local index = 0 ; index < this.unprofitableTownArray.len() ; index = index + 1) {
        if (this.unprofitableTownArray[index].townId == townId) {

            // Check that the town information was deleted properly.
            local temp = this.unprofitableTownArray.remove(index);
            return (temp.townId == townId);
        }
    }
    return false;
}

/**
 * Determines if a given year is a leap year.
 */
function CoronaAIFix::IsLeapYear(year) {
    // There is a leap year every 4 years, except when dividable by 100 but not by 400.
    if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) {
        return true;
    }
    return false;
}

/**
 * Adds the specified number of years to a date, counting any leap days if they occur within the time period (if using calendar timekeeping).
 * To simplify things, we don't let the date fall on the 29th of February later on if we *start* on that date. This is probably too much effort already. :P
 */
function CoronaAIFix::AddYears(initialDate, numYears) {

    // We don't need to worry about leap years if using wallclock timekeeping.
    if (this.daysInYear != 365) {
        return initialDate + numYears * this.daysInYear;

    // Otherwise, make sure we count leap days while adding the years.
    } else {
        local newDate = initialDate + this.daysInYear;
        numYears--;

        // If the current year is a leap year, and we're before the 29th of February, make sure to add that day.
        // (We don't add a day if we're *on* the 29th, since we will just use the 1st of March of the next year in that case.)
        if (this.IsLeapYear(AIDate.GetYear(initialDate)) && (AIDate.GetMonth(initialDate) == 1 || (AIDate.GetMonth(initialDate) == 2 && AIDate.GetDayOfMonth(initialDate) < 29))) {
            newDate++;
        }

        // Add the rest of the years except for the last, counting any leap days.
        while (numYears > 1) {
            newDate += this.daysInYear;
            if (this.IsLeapYear(AIDate.GetYear(newDate))) {
                newDate++;
            }
            numYears--;
        }

        // For the last year, we want to check if the new date falls after the 28th of February if it's a leap year.
        if (numYears == 1) {
            newDate += this.daysInYear;
            if (this.IsLeapYear(AIDate.GetYear(initialDate)) && (AIDate.GetMonth(initialDate) > 2 || (AIDate.GetMonth(initialDate) == 2 && AIDate.GetDayOfMonth(initialDate) == 29))) {
                newDate++;
            }
        }

        return newDate;
    }
    return null;
}

/**
 * Saves the current state of the AI.
 * Saves the next scheduled date, the list of infrastructure, and the list of unprofitable towns.
 */
function CoronaAIFix::Save()
{
    local table = {
        nextDate = null,
        townInfoArray = []
        unprofitableTownArray = []
    }

    // Check if there's a next scheduled date.
    if (this.nextDate != null) {
        AILog.Info("Saving next scheduled date as " + AIDate.GetYear(this.nextDate) + "-" + AIDate.GetMonth(this.nextDate) + "-" + AIDate.GetDayOfMonth(this.nextDate));
        table.nextDate = this.nextDate;
    } else {
        AILog.Info("No next scheduled date to save at the moment");
    }

    // Check if there's a list of infrastructure.
    if (this.townInfoArray.len() > 0) {
        AILog.Info("Saving infrastructure information for " + this.townInfoArray.len() + " town(s)");
        table.townInfoArray = this.townInfoArray;
    } else {
        AILog.Info("No infrastructure information to save at the moment");
    }

    // Check if there's a list of unprofitable towns.
    if (this.unprofitableTownArray.len() > 0) {
        AILog.Info("Saving dates for " + this.unprofitableTownArray.len() + " unprofitable town(s)");
        table.unprofitableTownArray = this.unprofitableTownArray;
    } else {
        AILog.Info("No unprofitable town information to save at the moment");
    }

    // Return the table of data.
    return table;
}

/**
 * Loads the state of the AI from a savegame.
 * Loads the next scheduled date, the list of infrastructure, and the list of unprofitable towns.
 */
function CoronaAIFix::Load(version, data)
{
    // There shouldn't be any data for versions lower than 4, but check anyway...
    if (version > 3) {
        AILog.Info("Checking if there's saved data...")

        // Check if there's a saved scheduled date.
        if (data.rawin("nextDate") && data.nextDate != null) {
            this.nextDate = data.nextDate;
            AILog.Info("Loaded next scheduled date as " + AIDate.GetYear(this.nextDate) + "-" + AIDate.GetMonth(this.nextDate) + "-" + AIDate.GetDayOfMonth(this.nextDate));
        } else {
            AILog.Info("No next scheduled date saved")
        }

        // Check if there's a list of infrastructure.
        if (data.rawin("townInfoArray") && data.townInfoArray.len() > 0) {
            this.townInfoArray = data.townInfoArray;
            AILog.Info("Loaded infrastructure information for " + this.townInfoArray.len() + " town(s)");
        } else {
            AILog.Info("No infrastructure information saved");
        }

        // Check if there's a list of unprofitable towns.
        if (data.rawin("unprofitableTownArray") && data.unprofitableTownArray.len() > 0) {
            this.unprofitableTownArray = data.unprofitableTownArray;
            AILog.Info("Loaded dates for " + this.unprofitableTownArray.len() + " unprofitable town(s)");
        } else {
            AILog.Info("No unprofitable town information saved");
        }
    }
}