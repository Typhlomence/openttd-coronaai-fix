# CoronaAI Fix (openttd-coronaai-fix)
CoronaAI is a simple AI that attempts to build bus services in all cities on the map. The original version by Libor Vilimek works well enough, but has a few small bugs which I've elected to fix with this fork, without increasing the complexity by too much.

This is my first work on an AI (or any modification for OpenTTD), so there's probably implementation details that can be improved.

Changes from the original CoronaAI:
* When selecting a bus to use, only consider road vehicles that can travel on the default road type. The bus with the highest capacity will also be chosen.
* When building stations and depots, ensure that the company actually built them on the chosen tiles (no matter the road type), as well as checking if a bus was successfully bought.
* When building stations and depots, ensure they are connected to each other by existing roads.
* The AI will not try to build anything if it couldn't find a valid vehicle to buy at the moment.
* Instead of only attempting to build once, it will check through all towns each year and (re)build if there's still nothing it owns in a town (and it can successfully build it).
* While it doesn't store anything in the save file, the AI will check if it's built anything when it starts to avoid rebuilding in already serviced towns.

Limitations:
* Likely not to be compatible with all combinations of road vehicle and road type NewGRFs.

# Original readme of ottd-coronaai
Please increase number of road vehicles per company (in settings -> limitations).
On 1024x1024 map the preffered number is 2500.

 * This is very simple AI that was written while I was ill due to having covid-19.
 * I spent only two partial days working on it, therefore it really is intended to be simple.
 * It will try to spread to all cities with buses alone.
 
 Free to use
