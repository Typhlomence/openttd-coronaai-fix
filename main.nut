﻿/**
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
    // The town we are working right now
    actualTown = null;
    // Some nasty surprise - you have find cargoId in list, you cannot just use i.e. AICargo.CC_PASSENGERS
    // This stores the CargoId for passengers. More in constructor
    passengerCargoId = -1;
    // The towns we want to go through and "spread" there
    towns = null;
    // Keeping the best engines avialable there
    engines = null;
    // For storing all things we built so we can keep eye on them
    existing = [];

    // Pathfinder for checking if stations and depots are connected.
    pathfinder = null;
    // The last time the end of the town list was reached.
    lastDate = null;

    constructor() {
        // Without this you cannot build road, station or depot
        AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
        this.existing = [];

        // Persist passengers
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
    function Start() ;
}

/**
 * Äll the logic starts here
 */
function CoronaAIFix::Start() {
    AICompany.SetName("CoronaAI")
    AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());

    // Check if there's existing infrastructure first.
    this.CheckTowns();
    while (true) {
        this.Sleep(10);
        this.FindBestEngine();
        // If we dont have enough money, just dont build any other stations and buses there
        // Also, don't try to build anything if no bus could be found to buy.
        if (AICompany.GetBankBalance(AICompany.COMPANY_SELF) > (AICompany.GetMaxLoanAmount() / 10) && this.engines.Count() > 0) {
            this.SelectTown();
            if (this.actualTown != null) {
                BuildStationsAndBuses();
            }
        }
        this.SellUnprofitables();
        this.HandleOldVehicles();
        this.HandleOldTowns();
        this.DeleteUnusedCrap();
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
                AILog.Info("Generating new towns");
                local towns = AITownList();
                towns.Valuate(AITown.GetPopulation);
                towns.Sort(AIList.SORT_BY_VALUE, false);
                this.towns = towns;
        }

        if (this.towns.Count() == 0) {
            this.actualTown = null;
            AILog.Info("Reached end of town list, waiting for a year");
            this.towns = null;
            this.lastDate = AIDate.GetCurrentDate();
        } else {
            this.actualTown = this.towns.Begin();
            AILog.Info("Size of towns " + this.towns.Count())
            this.towns.RemoveTop(1);
        }
    }
}

/**
 * Core functionality - This will build the stations and buses
 */
function CoronaAIFix::BuildStationsAndBuses() {
    AILog.Info("City name " + AITown.GetName(this.actualTown));

    // Get any existing town information
    local existingInfo = this.GetTownInfo(this.actualTown);
    if (existingInfo == null) {
        AILog.Info("This town has no information yet");
    } else {
        AILog.Info("This town is already serviced - skipping to the next town");
        return;
    }

    local townCenter = AITown.GetLocation(this.actualTown);
    local list = AITileList();
    // Add 16x16 area around city center
    list.AddRectangle(townCenter - AIMap.GetTileIndex(8, 8), townCenter + AIMap.GetTileIndex(8, 8));
    // Find only road tiles
    list.Valuate(AIRoad.IsRoadTile);
    list.RemoveValue(0);
    // Find best places for station (that accepts most humans)
    list.Valuate(AITile.GetCargoAcceptance, this.passengerCargoId, 1, 1, 3);
    list.RemoveBelowValue(10);
    list.Sort(AIList.SORT_BY_VALUE, false);

    // Build first road station
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

    if (firstStation == null) {
        AILog.Info("First station failed, aborting");
        return;
    }

    // Build second station
    local distanceOfStations = 7;
    local secondStation = null;
    while (distanceOfStations > 2 && secondStation == null) {
        local filteredList = AIList();
        filteredList.AddList(list);
        // Allow only far-enough places to be put into selection
        filteredList.Valuate(AIMap.DistanceManhattan, firstStation);
        filteredList.KeepAboveValue(distanceOfStations);
        // Now we have to sort by amount of cargo we gets again
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
        if (secondStation == null) {
            distanceOfStations = distanceOfStations - 1;
        }
    }

    if (secondStation == null) {
        AILog.Info("Second station failed, aborting");
        AIRoad.RemoveRoadStation(firstStation);
        return;
    }

    // Find place to build a depot
    list = AITileList();
    list.AddRectangle(townCenter - AIMap.GetTileIndex(8, 8), townCenter + AIMap.GetTileIndex(8, 8));
    list.Valuate(AIRoad.IsRoadTile);
    list.RemoveValue(0);
    list.Valuate(AITile.GetSlope);
    list.KeepValue(AITile.SLOPE_FLAT);
    list.Valuate(AIMap.DistanceManhattan, AITown.GetLocation(this.actualTown));
    list.Sort(AIList.SORT_BY_VALUE, true);

    // Build a depot
    tile = list.Begin();
    local potentialDepot = null;
    local isConnected = false;
    while (list.IsEnd() == false && isConnected == false) {
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
                    // If we built it but we could not connect it to road
                    AITile.DemolishTile(potentialDepot);
                }
            }
        }
        tile = list.Next();
    }

    if (potentialDepot == null) {
        AILog.Info("Depot failed, aborting");
        AIRoad.RemoveRoadStation(firstStation);
        AIRoad.RemoveRoadStation(secondStation);
        return;
    }


    // Buy our first bus in location
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

    AILog.Info("End of building");
}

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
    while (vehicles.IsEnd() == false) {
        if ((AIVehicle.GetProfitLastYear(vehicle) <= AIVehicle.GetRunningCost(vehicle) * -0.9) && AIOrder.IsCurrentOrderPartOfOrderList(vehicle)) {
            AILog.Info("Sending unprofitable vehicle to be sold: " + vehicle)
            AIVehicle.SendVehicleToDepot(vehicle);
        }
        if (AIVehicle.IsStoppedInDepot(vehicle) && (AIVehicle.GetProfitLastYear(vehicle) <= AIVehicle.GetRunningCost(vehicle) * -0.9)) {
            local depotLocation = AIVehicle.GetLocation(vehicle);
            AILog.Info("Selling unprofitable vehicle " + vehicle);
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
function CoronaAIFix::DeleteUnusedCrap() {
    foreach (obj in this.existing) {
        local firstStationId = AIStation.GetStationID(obj.firstStation);
        local secondStationId = AIStation.GetStationID(obj.secondStation);
        local stationsNotUsed = AIVehicleList_Station(firstStationId).Count() == 0 && AIVehicleList_Station(secondStationId).Count() == 0;
        if (stationsNotUsed) {
            AILog.Info("Deleting unused things from " + AITown.GetName(obj.actualTown));
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
    local vehicles = AIVehicleList();
    local vehicle = vehicles.Begin();
    while (vehicles.IsEnd() == false) {
        // We keep vehicles up to 7 years more than its their official age
        if (AIVehicle.GetAgeLeft(vehicle) <= -30 * 12 * 7 && AIOrder.IsCurrentOrderPartOfOrderList(vehicle)) {
            AIVehicle.SendVehicleToDepot(vehicle);
        }
        if (AIVehicle.IsStoppedInDepot(vehicle) && AIVehicle.GetAgeLeft(vehicle) <= -30 * 12 * 7) {
            local depotLocation = AIVehicle.GetLocation(vehicle);
            local stationId = AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 0));
            local vehiclesInStation = AIVehicleList_Station(stationId);
            // If there is just one vehicle in city, we replace it with new one. Otherwise we just sell it.
            if (vehiclesInStation.Count() == 1) {
                local newBus = AIVehicle.BuildVehicle(depotLocation, this.engines.Begin());
                if (AIVehicle.IsValidVehicle(newBus)) {
                    AILog.Info("Only one vehicle " + vehicle + " in station, replacing");
                    AIOrder.ShareOrders(newBus, vehicle);
                    AIVehicle.StartStopVehicle(newBus);
                    AIVehicle.SellVehicle(vehicle);
                }
            } else {
                AILog.Info("Deleting " + vehicle + " there are " + vehiclesInStation.Count() + " other vehicles");
                AIVehicle.SellVehicle(vehicle);
            }
        }
        vehicle = vehicles.Next();
    }
}

/**
 * Simple pathfinder function to find a path. The pathfinder is set in the constructor to only consider existing roads.
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
        list.AddRectangle(townCenter - AIMap.GetTileIndex(8, 8), townCenter + AIMap.GetTileIndex(8, 8));
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
                    if (AIRoad.AreRoadTilesConnected(nextTile, tile)) {
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
                        AILog.Info("Road vehicle " + vehicle + " stops at both found stations, adding it as the bus for this town");
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
        }

        this.SelectTown();
    }
    AILog.Info("All towns checked");
}