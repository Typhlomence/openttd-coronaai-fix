/**
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
import("pathfinder.road", "RoadPathFinder", 3);

/**
 * Constructor
 */
class CoronaAIFix extends AIController {
    // Current town that the AI is working on.
    actualTown = null;
    // Since the passenger ID cannot be assumed, this will store it when it's found later.
    passengerCargoId = -1;
    // List of towns to "spread" to. This counts down on each iteration and can be refilled later.
    towns = null;
    // Current best engine(s) available. Should usually only have one in the list.
    engines = null;
    // Array for data on all towns the company has successfully "spread" to.
    existing = [];
    // Pathfinder for checking if stations and depots are connected.
    pathfinder = null;
    // The last time the end of the town list was reached.
    lastDate = null;

    constructor() {
        // Set the current road type as the default road type.
        AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
        this.existing = [];

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
 * Äll the logic starts here
 */
function CoronaAIFix::Start() {

    // Set the name and take out the maximum loan possible.
    AICompany.SetName("CoronaAI")
    AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());

    // Turn off autorenew as it causes old vehicles to never be sold if vehicles never expire.
    AICompany.SetAutoRenewStatus(false);

    // Check if there's existing infrastructure first.
    this.CheckTowns();
    
    // Continuously while the AI is active...
    while (true) {
    
        // Sleep for 10 ticks before performing more actions.
        this.Sleep(10);
        this.FindBestEngine();
        
        // Don't try building anything if there isn't a good buffer of money.
        // Also, don't try to build anything if no bus could be found to buy.
        if (AICompany.GetBankBalance(AICompany.COMPANY_SELF) > (AICompany.GetMaxLoanAmount() / 10) && this.engines.Count() > 0) {
            this.SelectTown();
            if (this.actualTown != null) {
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

    }
}

/**
 * Find best bus for passengers avialable
 */
function CoronaAIFix::FindBestEngine() {
    local engines = AIEngineList(AIVehicle.VT_ROAD);

    // Only keep vehicles that can operate on the default road type (chosen as the current road type).
    engines.Valuate(AIEngine.CanRunOnRoad, AIRoad.GetCurrentRoadType())
    engines.KeepValue(1);
    
    // Only keep vehicles that can carry passengers.
    engines.Valuate(AIEngine.GetCargoType)
    engines.KeepValue(this.passengerCargoId);

    // Pick the vehicle that has the highest capacity.
    engines.Valuate(AIEngine.GetCapacity)
    engines.Sort(AIList.SORT_BY_VALUE, false);
    engines.KeepTop(1);

    // Ensure a bus was actually found. If not, return an empty list.
    // (We check for the road vehicle type again since if there's no buses, it might pick a vehicle of a different type.)
    if (engines.Count() < 0 || AIEngine.GetVehicleType(engines.Begin()) != AIVehicle.VT_ROAD || AIEngine.GetCapacity(engines.Begin()) < 1) {
        this.engines = AIList();
    } else {
        this.engines = engines;
    }
}

/**
 * Initialize towns or select next town
 */
function CoronaAIFix::SelectTown() {
    // Allow the town list to be regenerated if it's a year since it was last generated.
    if (this.lastDate == null || this.lastDate + 30 * 12 < AIDate.GetCurrentDate()) {
        if (this.towns == null) {
                AILog.Info("Generating town list");
                local towns = AITownList();
                towns.Valuate(AITown.GetPopulation);
                towns.Sort(AIList.SORT_BY_VALUE, false);
                this.towns = towns;
        }

        // If reaching the end of the list, set the current town and list as null and record the current date to check again in a year's time.
        if (this.towns.Count() == 0) {
            this.actualTown = null;
            local nextDate = AIDate.GetCurrentDate() + 30 * 12;
            AILog.Info("Reached end of town list, waiting until " + AIDate.GetYear(nextDate) + "-" + AIDate.GetMonth(nextDate) + "-" + AIDate.GetDayOfMonth(nextDate) + " to regenerate");
            this.towns = null;
            this.lastDate = AIDate.GetCurrentDate();
            
        // Otherwise, set the current town as the one at the top of the list.
        } else {
            this.actualTown = this.towns.Begin();
            AILog.Info("Number of towns remaining: " + this.towns.Count())
            this.towns.RemoveTop(1);
        }
    }
}

/**
 * Core functionality - This will build the stations and buses
 */
function CoronaAIFix::BuildStationsAndBuses() {
    AILog.Info("City name " + AITown.GetName(this.actualTown));

    // Get any existing town information, to skip towns that already have stations, depots and buses.
    local existingInfo = this.GetTownInfo(this.actualTown);
    if (existingInfo == null) {
        AILog.Info("This town has no information yet");
    } else {
        AILog.Info("This town is already serviced - skipping to the next town");
        return;
    }

    local townCenter = AITown.GetLocation(this.actualTown);
    local list = AITileList();

    // Check an 16x16 area around the city center.
    list.AddRectangle(townCenter - AIMap.GetTileIndex(8, 8), townCenter + AIMap.GetTileIndex(8, 8));

    // Find only road tiles
    list.Valuate(AIRoad.IsRoadTile);
    list.RemoveValue(0);

    // Check only for tiles that are in the current town's local authority radius.
    // Since small towns may be enroached by large ones, the latter's roads may enter the search radius.
    list.Valuate(AITile.IsWithinTownInfluence, this.actualTown);
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
    list.Valuate(AITile.IsWithinTownInfluence, this.actualTown);
    list.RemoveValue(0);
    list.Valuate(AITile.GetSlope);
    list.KeepValue(AITile.SLOPE_FLAT);
    list.Valuate(AIMap.DistanceManhattan, AITown.GetLocation(this.actualTown));
    list.Sort(AIList.SORT_BY_VALUE, true);

    // Attempt to build a depot.
    tile = list.Begin();
    local potentialDepot = null;
    local isConnected = false;
    while (list.IsEnd() == false && isConnected == false) {
    
        // See if there's a tile adjacent to the current road tile that a depot can be built on.
        for (local i = 0; i < 4; i++) {
            if (i == 0) {
                potentialDepot = tile + AIMap.GetTileIndex(0, 1);
            }
            if (i == 1) {
                potentialDepot = tile + AIMap.GetTileIndex(1, 0);
            }
            if (i == 2) {
                potentialDepot = tile + AIMap.GetTileIndex(0, -1);
            }
            if (i == 3) {
                potentialDepot = tile + AIMap.GetTileIndex(-1, 0);
            }

            // Like with the second station, check that there's a road connection between the depot's connection tile and the first station tile.
            if (AITile.GetSlope(potentialDepot) == AITile.SLOPE_FLAT && AITile.IsBuildable(potentialDepot) && this.CheckRoadConnection(firstStation, tile) != null) {
                AIRoad.BuildRoadDepot(potentialDepot, tile);
                AIRoad.BuildRoad(potentialDepot, tile);
                AILog.Info("Attempting to build depot at: " + AIMap.GetTileX(potentialDepot) + ":" + AIMap.GetTileY(potentialDepot));

                // Like with the stations, ensure that the depot on the tile also belongs to this company.
                if (AIRoad.AreRoadTilesConnected(tile, potentialDepot) && AICompany.IsMine(AITile.GetOwner(potentialDepot))) {
                    AILog.Info("Depot built and connected to road successfully");
                    isConnected = true;
                    break;
                } else {
                    // Demolish the depot if it couldn't be connected to the road.
                    AITile.DemolishTile(potentialDepot);
                    potentialDepot = null;
                }
            } else {
                potentialDepot = null;
            }
        }
        tile = list.Next();
    }

    // Abort if the depot couldn't be built.
    if (potentialDepot == null) {
        AILog.Info("Depot failed, aborting");
        AIRoad.RemoveRoadStation(firstStation);
        AIRoad.RemoveRoadStation(secondStation);
        return;
    }


    // Buy our first bus in the depot that was just built.
    local bus = AIVehicle.BuildVehicle(potentialDepot, this.engines.Begin());

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
        AITile.DemolishTile(potentialDepot);
        return;
    }

    // Store information about all the stations, town, etc.
    local obj = {
        bus = bus,
        firstStation = firstStation,
        secondStation = secondStation,
        potentialDepot = potentialDepot,
        lastChange = AIDate.GetCurrentDate(),
        actualTown = this.actualTown
    };
    this.existing.append(obj);

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
 * If vehicle is highly unprofitable - just sell it
 */
function CoronaAIFix::SellUnprofitables() {
    local vehicles = AIVehicleList();
    local vehicle = vehicles.Begin();

    // Check if the company is low on money even with the maximum loan.
    local badFinances = AICompany.GetBankBalance(AICompany.COMPANY_SELF) < (AICompany.GetMaxLoanAmount() / 20) && AICompany.GetLoanAmount() == AICompany.GetMaxLoanAmount();
    while (vehicles.IsEnd() == false) {

        // Check for vehicles that are making a loss of at least 90% of their running cost.
        // If the company is running out of money, sell the vehicle if it's unprofitable at all, rather than just highly unprofitable.
        if (((AIVehicle.GetProfitLastYear(vehicle) <= AIVehicle.GetRunningCost(vehicle) * -0.9) || (AIVehicle.GetProfitLastYear(vehicle) < 0 && badFinances)) && AIOrder.IsCurrentOrderPartOfOrderList(vehicle)) {
            AILog.Info("Sending unprofitable vehicle to be sold: " + AIVehicle.GetName(vehicle))
            AIVehicle.SendVehicleToDepot(vehicle);
        }
        
        // If a vehicle is already in the depot...
        if (AIVehicle.IsStoppedInDepot(vehicle) && ((AIVehicle.GetProfitLastYear(vehicle) <= AIVehicle.GetRunningCost(vehicle) * -0.9) || (AIVehicle.GetProfitLastYear(vehicle) < 0 && badFinances))) {
            local depotLocation = AIVehicle.GetLocation(vehicle);
            AILog.Info("Selling unprofitable vehicle: " + AIVehicle.GetName(vehicle));
            AIVehicle.SellVehicle(vehicle);
        }
        vehicle = vehicles.Next();
    }
}

/**
 * Add buses in old towns where we already have stations - if there is enough passengers
 */
function CoronaAIFix::HandleOldTowns() {
    foreach (obj in this.existing) {
        // we only add bus once per year to avoid spamming it
        if (obj.lastChange + 30 * 12 < AIDate.GetCurrentDate()) {
            local waitingPassengers1 = AIStation.GetCargoWaiting(AIStation.GetStationID(obj.firstStation), this.passengerCargoId);
            local waitingPassengers2 = AIStation.GetCargoWaiting(AIStation.GetStationID(obj.secondStation), this.passengerCargoId);
            if ((waitingPassengers1 > 200 && waitingPassengers2 > 200) || (waitingPassengers1 + waitingPassengers2 > 600)) {
                local newBus = AIVehicle.BuildVehicle(obj.potentialDepot, this.engines.Begin());
                if (AIVehicle.IsValidVehicle(newBus)) {
                    AILog.Info("Cloning vehicle in " + AITown.GetName(obj.actualTown) + " as there is " + waitingPassengers1 + ":" + waitingPassengers2 + " passengers");
                    AIOrder.AppendOrder(newBus, obj.firstStation, AIOrder.OF_NONE);
                    AIOrder.AppendOrder(newBus, obj.secondStation, AIOrder.OF_NONE);
                    AIVehicle.StartStopVehicle(newBus);
                    obj.lastChange = AIDate.GetCurrentDate();
                }
            }
        }
    }
}

/**
 * If we find out that there is non-used infrastructure - remove it
 */
// I like the name for this function, by the way. :P
function CoronaAIFix::DeleteUnusedCrap() {
    foreach (obj in this.existing) {
        local firstStationId = AIStation.GetStationID(obj.firstStation);
        local secondStationId = AIStation.GetStationID(obj.secondStation);
        local stationsNotUsed = AIVehicleList_Station(firstStationId).Count() == 0 && AIVehicleList_Station(secondStationId).Count() == 0;
        if (stationsNotUsed) {
            AILog.Info("Removing unused things from " + AITown.GetName(obj.actualTown));
            AILog.Info("Attempting to remove station at: " + AIMap.GetTileX(obj.firstStation) + ":" + AIMap.GetTileY(obj.firstStation));
            AIRoad.RemoveRoadStation(obj.firstStation);
            AILog.Info("Attempting to remove station at: " + AIMap.GetTileX(obj.secondStation) + ":" + AIMap.GetTileY(obj.secondStation));
            AIRoad.RemoveRoadStation(obj.secondStation);
            AILog.Info("Attempting to remove depot at: " + AIMap.GetTileX(obj.potentialDepot) + ":" + AIMap.GetTileY(obj.potentialDepot));
            AIRoad.RemoveRoadDepot(obj.potentialDepot);

            // Check if the items were actually removed yet (by checking if the tiles are not owned by the company). Sometimes this can fail if a vehicle is in the way.
            if (!AICompany.IsMine(AITile.GetOwner(obj.firstStation)) && !AICompany.IsMine(AITile.GetOwner(obj.secondStation)) && !AICompany.IsMine(AITile.GetOwner(obj.potentialDepot))) {
                AILog.Info("Successfully deleted infrastructure from this town")
                if (DeleteTownInfo(obj.actualTown)) {
                    AILog.Info("Deleted information for "  + AITown.GetName(obj.actualTown));
                }
            } else {
                AILog.Info("Some things were not removed yet - will retry later")
            }
        }
    }
}

/**
 * Selling vehicles that are too old
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
        if (AIVehicle.GetAgeLeft(vehicle) <= -30 * 12 * 7 && AIOrder.IsCurrentOrderPartOfOrderList(vehicle)) {
            AILog.Info("Sending old vehicle to be sold: " + AIVehicle.GetName(vehicle))
            AIVehicle.SendVehicleToDepot(vehicle);
        }
        
        // If a vehicle is already in the depot...
        if (AIVehicle.IsStoppedInDepot(vehicle) && AIVehicle.GetAgeLeft(vehicle) <= -30 * 12 * 7) {
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
                } else {
                    AILog.Info("Couldn't replace vehicle: " + AIVehicle.GetName(vehicle));

                    // If there's no available replacement, send it out again.
                    if (this.engines.Count() < 1) {
                        AIVehicle.StartStopVehicle(vehicle);
                    }
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
function CoronaAIFix::GetTownInfo(townName) {
    foreach (obj in this.existing) {
        if (obj.actualTown == townName) {
            return obj;
        }
    }
    return null;
}

/**
 * Deletes the information for a town if it exists in the array of serviced towns.
 */
function CoronaAIFix::DeleteTownInfo(townName) {
    for (local index = 0 ; index < this.existing.len() ; index = index + 1) {
        if (this.existing[index].actualTown == townName) {

            // Check that the town information was deleted properly.
            local temp = this.existing.remove(index);
            return (temp.actualTown == townName);
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
    this.SelectTown();
    while (this.actualTown != null) {

        // Potential values to store - if there's a bus, two stations and a depot.
        local bus = null;
        local firstStation = null;
        local secondStation = null;
        local potentialDepot = null;

        // Start the check by looking in the same range of tiles as when building.
        AILog.Info("Checking " + AITown.GetName(this.actualTown));
        local townCenter = AITown.GetLocation(this.actualTown);
        local list = AITileList();
        list.AddRectangle(townCenter - AIMap.GetTileIndex(8, 8), townCenter + AIMap.GetTileIndex(8, 8));

        // Check only road tiles.
        list.Valuate(AIRoad.IsRoadTile);
        list.RemoveValue(0);

        // Check only for tiles that are in the current town's local authority radius.
        // Since small towns may be enroached by large ones, the latter's roads may enter the search radius.
        list.Valuate(AITile.IsWithinTownInfluence, this.actualTown);
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
        while (list.IsEnd() == false && potentialDepot == null) {
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
                    if (AIRoad.AreRoadTilesConnected(nextTile, tile) && AITile.IsWithinTownInfluence(nextTile, this.actualTown)) {
                        AILog.Info("It's connected to an adjacent tile, therefore adding it as the depot for this town");
                        potentialDepot = tile;
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
        if (firstStation != null && secondStation != null && potentialDepot != null) {
            AILog.Info("Adding information for this town");
            local obj = {
                bus = bus,
                firstStation = firstStation,
                secondStation = secondStation,
                potentialDepot = potentialDepot,
                lastChange = AIDate.GetCurrentDate(),
                actualTown = this.actualTown
            };
            this.existing.append(obj);
        } else {
            AILog.Info("Couldn't find enough infrastructure for this town");
        }

        this.SelectTown();
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
            local notTooOld = AIVehicle.GetAgeLeft(vehicle) > -30 * 12 * 7;
            local notTooUnprofitable = (AIVehicle.GetProfitLastYear(vehicle) > AIVehicle.GetRunningCost(vehicle) * -0.9) || (AIVehicle.GetProfitLastYear(vehicle) >= 0 && badFinances);
            
            // Also check that it has orders (in case something went wrong with assigning them).
            if (notTooOld && notTooUnprofitable && AIOrder.GetOrderCount(vehicle) > 1) {
                AILog.Info("Found vehicle: " + AIVehicle.GetName(vehicle) + " stopped in a depot that isn't too old or too unprofitable, restarting it");
                AIVehicle.StartStopVehicle(vehicle);
            }
        }
        vehicle = vehicles.Next();
    }
}