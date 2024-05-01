# CoronaAI Fix (openttd-coronaai-fix)
CoronaAI is a simple AI that attempts to build bus services in all cities on the map. The original version by Libor Vilimek works well enough, but has some bugs which I've elected to fix with this fork, without increasing the complexity by too much.

This is my first work on an AI (or any modification for OpenTTD), so there's probably implementation details that can be improved.

Changes from the original CoronaAI:
* When selecting a bus to use, only consider road vehicles that can travel on the default road type. The bus with the highest capacity will also be chosen.
* When building stations and depots, ensure that the company actually built them on the chosen tiles (no matter the road type), as well as checking if a bus was successfully bought.
* When building stations and depots, ensure they are connected to each other by existing roads.
* The AI will not try to build anything if it couldn't find a valid vehicle to buy at the moment.
* Instead of only attempting to build once, the AI will recheck towns a year after the last check and (re)build if there's still nothing it owns in a town (and it can successfully build it).
* While it doesn't store anything in the save file, the AI will check if it's built anything when it starts to avoid rebuilding in already serviced towns.
* The AI should be able to remove unused infrastructure later if an attempt is unsuccessful due to another company's vehicle being in the way, etc.
* If there's enough spare cash, the AI will repay the loan, and if the AI gets low on cash, it will try to take out a loan if it doesn't have the max loan already.
* When building stations and depots, keep them within the chosen town's local authority radius.

Limitations:
* Likely not to be compatible with all combinations of road vehicle and road type NewGRFs.
* It's possible that, depending on how infrastructure was initially built, the function for detecting existing infrastructure might not get things exactly right. To try to prevent issues when trying to remove unused infrastructure, it checks that both stations it detected are used first.
* It seems like the pathfinder isn't perfect as sometimes it allows stations to be built that aren't properly connected by road, just having a road tile between each end.

# Original readme of ottd-coronaai
Please increase number of road vehicles per company (in settings -> limitations).
On 1024x1024 map the preffered number is 2500.

 * This is very simple AI that was written while I was ill due to having covid-19.
 * I spent only two partial days working on it, therefore it really is intended to be simple.
 * It will try to spread to all cities with buses alone.
 
 Free to use
